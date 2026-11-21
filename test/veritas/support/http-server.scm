;; torikomi
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; A very small HTTP server for the suite, run in a child process.
;;
;; The interesting half of torikomi is what it does with a remote that is not
;; perfect: a redirect, a 404, a gateway that fails twice and then answers, a
;; body larger than the limit.  Those cannot be tested against the internet --
;; a suite that needs the network fails for reasons that have nothing to do
;; with the change it was run to judge -- so this serves them from localhost.
;;
;; It is deliberately not a framework: a request line, a header block, and a
;; response the test composes.  The server binds port 0, so the kernel picks a
;; free port and two test runs can happen at once; the child inherits the
;; listening socket from `fork', which is why the parent closes its copy and the
;; server survives the test process's exit only until `stop-test-server!'.
;;
;; The handler runs in the child, so state it keeps -- the number of times a
;; flaky route was asked, say -- is the server's own and not the suite's.

;;; Code:

(define-module (veritas support http-server)
  #:use-module (ice-9 exceptions)
  #:use-module (ice-9 format)
  #:use-module (ice-9 rdelim)          ;read-line, which textual-ports lacks
  #:use-module (ice-9 binary-ports)    ;put-bytevector
  #:use-module (rnrs bytevectors)
  #:export (make-test-server!
            stop-test-server!
            test-server-port
            test-server-url
            response
            redirect))

(define (reason-phrase status)
  "The reason phrase a response with STATUS is written with."
  (case status
    ((200) "OK")
    ((201) "Created")
    ((204) "No Content")
    ((301) "Moved Permanently")
    ((302) "Found")
    ((304) "Not Modified")
    ((400) "Bad Request")
    ((401) "Unauthorized")
    ((403) "Forbidden")
    ((404) "Not Found")
    ((408) "Request Timeout")
    ((413) "Payload Too Large")
    ((429) "Too Many Requests")
    ((500) "Internal Server Error")
    ((502) "Bad Gateway")
    ((503) "Service Unavailable")
    ((504) "Gateway Timeout")
    (else "Unknown")))

(define* (response #:key (status 200) (content-type "text/plain")
                   (headers '()) (body ""))
  "A response the test server can write: STATUS, type, headers and BODY.

BODY is a string or a bytevector; a header is a pair of strings, written as
`Name: value'."
  (list status content-type headers body))

(define* (redirect location #:key (status 302))
  "A redirect to LOCATION."
  (response #:status status
            #:headers (list (cons "Location" location))
            #:body ""))

(define (read-request-headers port)
  "The header lines of a request, up to the blank line."
  (let loop ((lines '()))
    (let ((line (read-line port)))
      (cond ((eof-object? line) (reverse lines))
            ((string-null? (string-trim-both line #\return))
             (reverse lines))
            (else (loop (cons (string-trim-both line #\return) lines)))))))

(define (request-line-parts line)
  "The method, path and version of a request line, or '() when it is malformed."
  (and line
       (let ((parts (string-split (string-trim-both line) #\space)))
         (if (= (length parts) 3) parts '()))))

(define (write-response port response)
  "Write RESPONSE to PORT and flush it."
  (let* ((status (list-ref response 0))
         (content-type (list-ref response 1))
         (headers (list-ref response 2))
         (body (list-ref response 3))
         (body (if (string? body) (string->utf8 body) body)))
    (format port "HTTP/1.1 ~a ~a\r\n" status (reason-phrase status))
    (when content-type
      (format port "Content-Type: ~a\r\n" content-type))
    (format port "Content-Length: ~a\r\n" (bytevector-length body))
    (format port "Connection: close\r\n")
    (for-each (lambda (header)
                (format port "~a: ~a\r\n" (car header) (cdr header)))
              headers)
    (format port "\r\n")
    (put-bytevector port body)
    (force-output port)))

(define (serve-client client handler)
  "Read one request from CLIENT, ask HANDLER, and write the answer."
  (dynamic-wind
    (lambda () #t)
    (lambda ()
      (let* ((parts (request-line-parts (read-line client)))
             (method (and (pair? parts) (car parts)))
             (path (and (pair? parts) (cadr parts)))
             (headers (read-request-headers client)))
        (write-response
         client
         (if (and method path)
             (guard (condition (else (response #:status 500
                                               #:body "handler failed")))
               (handler method path headers))
             (response #:status 400 #:body "bad request")))))
    (lambda ()
      (catch #t (lambda () (close client)) (lambda arguments #f)))))

(define (accepted-socket accepted)
  "The connected socket of what `accept' returned.

Guile's `accept' answers with a pair of the socket and the peer's address on
some versions and with the socket alone on others; this is the one place the
difference is read."
  (if (pair? accepted) (car accepted) accepted))

(define (serve-forever socket handler)
  "Accept and answer connections until the process is killed.

One request that goes wrong is answered as a 500 (or dropped) and the loop
carries on: a test server that dies on the first unexpected request would make
every later test fail for a reason that is not the code's."
  (let loop ()
    (let ((client (accepted-socket (accept socket))))
      (catch #t
        (lambda () (serve-client client handler))
        (lambda (key . arguments)
          ;; The child's error port is the suite's, so a broken request is
          ;; visible when the suite is run by hand rather than lost.
          (catch #t
            (lambda ()
              (format (current-error-port)
                      "torikomi test server: request failed: ~s~%"
                      (cons key arguments)))
            (lambda rest #f))
          (catch #t (lambda () (close client)) (lambda rest #f))))
      (loop))))

(define (make-test-server! handler)
  "Start a test server running HANDLER in a child process.

HANDLER is called as `(handler method path headers)' and returns a response
made with `response' or `redirect'.  The returned value answers
`test-server-url' and is what `stop-test-server!' needs."
  (let* ((socket (socket AF_INET SOCK_STREAM 0)))
    (setsockopt socket SOL_SOCKET SO_REUSEADDR 1)
    (bind socket AF_INET INADDR_LOOPBACK 0)
    (let* ((address (getsockname socket))
           (port (vector-ref address 2)))
      (listen socket 16)
      ;; Nothing buffered in the parent may be written twice by the child.
      (flush-all-ports)
      (let ((pid (primitive-fork)))
        (if (zero? pid)
            (begin
              ;; A word to the suite's own error port is what makes a server
              ;; that cannot answer look like one, instead of a fetch that hangs
              ;; until its timeout.
              (catch #t
                (lambda ()
                  (format (current-error-port)
                          "torikomi test server: serving on port ~a~%" port))
                (lambda rest #f))
              (serve-forever socket handler)
              (primitive-exit 0))
            (begin
              ;; The child keeps the listening socket; the parent's copy would
              ;; keep the port bound after the child is gone.
              (catch #t (lambda () (close socket)) (lambda arguments #f))
              (list 'test-server port pid)))))))

(define (test-server-port server)
  "The TCP port SERVER listens on."
  (cadr server))

(define (test-server-url server path)
  "PATH as an absolute URL on SERVER."
  (format #f "http://127.0.0.1:~a~a" (test-server-port server) path))

(define (stop-test-server! server)
  "Stop SERVER, if it is still running."
  (let ((pid (caddr server)))
    (catch #t (lambda () (kill pid SIGTERM)) (lambda arguments #f))
    (catch #t (lambda () (waitpid pid)) (lambda arguments #f))))
