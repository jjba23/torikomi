;;; torikomi

;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;; torikomi is free software: you can redistribute it and/or modify
;; it under the terms of the GNU Affero General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; torikomi is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU Affero General Public License for more details.

;; You should have received a copy of the GNU Affero General Public License
;; along with torikomi.  If not, see <https://www.gnu.org/licenses/>.

;;; Sinking a file, end to end.
;;;
;;; A real HTTP server on localhost serves the responses torikomi has to cope
;;; with -- a redirect, a 404, a gateway that fails twice, a body over the
;;; limit -- and a real directory receives the bytes.  Nothing here is mocked:
;;; the test is of libcurl, of `write-download!' and of the policy between them,
;;; which is exactly where the earlier version's bugs lived.

(define-module (veritas unit sink-spec)
  #:use-module (veritas veritas)
  #:use-module (veritas support temp-dir)
  #:use-module (veritas support http-server)
  #:use-module (ice-9 exceptions)
  #:use-module (rnrs bytevectors)
  #:use-module (ice-9 binary-ports)
  #:use-module (torikomi torikomi)
  #:use-module (torikomi preferences)
  #:export (spec))

;; How many times the flaky route has been asked.  The handler runs in the
;; server's own process, so this counts that process's requests and not the
;; suite's.
(define flaky-attempts 0)

(define (handler method path headers)
  "The responses the suite fetches, by path."
  (let ((path (car (string-split path #\?))))
    (cond
     ((string=? path "/text")
      (response #:content-type "text/plain; charset=utf-8"
                #:body "hello torikomi"))
     ((string=? path "/png")
      (response #:content-type "image/png"
                #:body (u8-list->bytevector '(137 80 78 71))))
     ((string=? path "/none")
      (response #:content-type #f #:body "no type at all"))
     ((string=? path "/disposition")
      (response #:content-type "application/octet-stream"
                #:headers
                (list (cons "Content-Disposition"
                            "attachment; filename=\"My Report.pdf\""))
                #:body "report"))
     ((string=? path "/redirect")
      (redirect "/png"))
     ((string=? path "/missing")
      (response #:status 404 #:body "gone"))
     ((string=? path "/error")
      (response #:status 500 #:body "boom"))
     ((string=? path "/flaky")
      (set! flaky-attempts (1+ flaky-attempts))
      (if (<= flaky-attempts 2)
          (response #:status 503 #:body "wait")
          (response #:content-type "text/plain" #:body "finally")))
     ((string=? path "/big")
      (response #:content-type "application/octet-stream"
                #:body (make-bytevector (* 1024 1024) 120)))
     (else
      (response #:status 404 #:body "not found")))))

(define server #f)

(define (read-all path)
  (call-with-input-file path get-bytevector-all))

(define (directory-entries path)
  "The names of the entries of PATH, `.` and `..' included."
  (let ((directory (opendir path)))
    (let loop ((names '()))
      (let ((name (readdir directory)))
        (if (eof-object? name)
            (begin (closedir directory) (reverse names))
            (loop (cons name names)))))))

(define (caught thunk)
  "The condition THUNK raises, or #f when it returns."
  (guard (condition (else condition))
    (thunk)
    #f))

;; Every fetch in this suite is made against its own directory, with retries
;; that do not sleep: the readings are of what is written, not of how long a
;; backoff waited.
(define (with-sink-directory directory thunk)
  (parameterize ((sink-directory directory)
                 (public-base-url "https://files.example/sunk")
                 (curl-retries 0)
                 (curl-retry-delay-seconds 0))
    (thunk)))

(define sink-suite
  (suite "sinking a file"
         #:concurrent? #f
         #:shuffle? #f
         #:before-all (lambda (vc)
                        (set! server (make-test-server! handler)))
         #:after-all (lambda (vc)
                       (when server (stop-test-server! server)))
         (test "a file is written under the URL's name"
               #:shuffle? #f
               (call-with-temp-directory
                (lambda (directory)
                  (with-sink-directory
                   directory
                   (lambda ()
                     (let* ((result (sink-file
                                     #:url (test-server-url server "/text")))
                            (alist (sink-result->alist result))
                            (path (sink-result-path result)))
                       (assert-true (sink-result-ok? result))
                       (assert-equal #:expect "text.txt"
                                     #:got (sink-result-file-name result))
                       (assert-equal #:expect "https://files.example/sunk/text.txt"
                                     #:got (sink-result-public-url result))
                       (assert-equal #:expect 14
                                     #:got (sink-result-bytes result))
                       (assert-equal #:expect 200
                                     #:got (sink-result-status result))
                       ;; Only read a path that exists: a failure above must
                       ;; leave a readable report, not abort the suite.
                       (when (string? path)
                         (assert-equal
                          #:expect (string->utf8 "hello torikomi")
                          #:got (read-all path)))
                       ;; The address has two names in the JSON shape: `url',
                       ;; and `new-url' from the first version of the API.
                       (assert-equal
                        #:expect "https://files.example/sunk/text.txt"
                        #:got (assoc-ref alist 'new-url))
                       (assert-equal #:expect (assoc-ref alist 'url)
                                     #:got (assoc-ref alist 'new-url))))))))

         (test "the reader's name wins and is made safe"
               #:shuffle? #f
               (call-with-temp-directory
                (lambda (directory)
                  (with-sink-directory
                   directory
                   (lambda ()
                     (let ((result (sink-file
                                    #:url (test-server-url server "/png")
                                    #:name "../../My Photo.JPG")))
                       (assert-true (sink-result-ok? result))
                       (assert-equal #:expect "My-Photo.png"
                                     #:got (sink-result-file-name result))
                       (assert-not-contains #:expect
                                            (sink-result-file-name result)
                                            #:got "/")
                       (assert-true
                        (and (sink-result-path result)
                             (string-prefix?
                              (string-append directory "/")
                              (sink-result-path result))))))))))
         (test "the server's suggested name is used"
               #:shuffle? #f
               (call-with-temp-directory
                (lambda (directory)
                  (with-sink-directory
                   directory
                   (lambda ()
                     (let ((result (sink-file
                                    #:url (test-server-url server
                                                           "/disposition"))))
                       (assert-true (sink-result-ok? result))
                       (assert-equal #:expect "My-Report.pdf"
                                     #:got (sink-result-file-name result))
                       (assert-equal #:expect 6
                                     #:got (sink-result-bytes result))))))))
         (test "a response without a type still gets an extension"
               #:shuffle? #f
               (call-with-temp-directory
                (lambda (directory)
                  (with-sink-directory
                   directory
                   (lambda ()
                     (let ((result (sink-file
                                    #:url (test-server-url server "/none"))))
                       (assert-true (sink-result-ok? result))
                       (assert-equal #:expect "none.bin"
                                     #:got (sink-result-file-name result))))))))
         (test "a redirect is followed and the body of the last response is kept"
               #:shuffle? #f
               (call-with-temp-directory
                (lambda (directory)
                  (with-sink-directory
                   directory
                   (lambda ()
                     (let ((result (sink-file
                                    #:url (test-server-url server
                                                           "/redirect"))))
                       (assert-true (sink-result-ok? result))
                       (assert-equal #:expect "redirect.png"
                                     #:got (sink-result-file-name result))
                       (assert-equal #:expect 4
                                     #:got (sink-result-bytes result))))))))
         (test "the same URL twice does not overwrite the first file"
               #:shuffle? #f
               (call-with-temp-directory
                (lambda (directory)
                  (with-sink-directory
                   directory
                   (lambda ()
                     (let* ((url (test-server-url server "/text"))
                            (first (sink-file #:url url))
                            (second (sink-file #:url url)))
                       (assert-true (sink-result-ok? first))
                       (assert-true (sink-result-ok? second))
                       (assert-false (string=? (sink-result-file-name first)
                                               (sink-result-file-name second)))
                       (assert-true (file-exists? (sink-result-path first)))
                       (assert-true (file-exists? (sink-result-path second)))))))))
         (test "a 404 is a failure with the remote's status"
               #:shuffle? #f
               (call-with-temp-directory
                (lambda (directory)
                  (with-sink-directory
                   directory
                   (lambda ()
                     (let ((result (sink-file
                                    #:url (test-server-url server
                                                           "/missing"))))
                       (assert-false (sink-result-ok? result))
                       (assert-equal #:expect 502
                                     #:got (sink-result-status result))
                       (assert-equal #:expect 404
                                     #:got (sink-result-upstream-status result))
                       (assert-contains #:expect (sink-result-message result)
                                        #:got "404")
                       ;; Nothing was written for a failure.
                       (assert-equal #:expect '()
                                     #:got (filter (lambda (name)
                                                     (not (member name
                                                                  '("." ".."))))
                                                   (directory-entries
                                                    directory)))))))))
         (test "a transient failure is retried"
               #:shuffle? #f
               (call-with-temp-directory
                (lambda (directory)
                  (parameterize ((sink-directory directory)
                                 (public-base-url "https://files.example/sunk")
                                 (curl-retries 2)
                                 (curl-retry-delay-seconds 0))
                    (let ((result (sink-file
                                   #:url (test-server-url server "/flaky"))))
                      (assert-true (sink-result-ok? result))
                      (assert-equal #:expect 7
                                    #:got (sink-result-bytes result))
                      (let ((path (sink-result-path result)))
                        (when (string? path)
                          (assert-equal #:expect (string->utf8 "finally")
                                        #:got (read-all path)))))))))
         (test "a body larger than the limit is refused"
               #:shuffle? #f
               (call-with-temp-directory
                (lambda (directory)
                  (parameterize ((sink-directory directory)
                                 (public-base-url "https://files.example/sunk")
                                 (max-file-bytes 1024)
                                 (curl-retries 0))
                    (let ((result (sink-file
                                   #:url (test-server-url server "/big"))))
                      (assert-false (sink-result-ok? result))
                      (assert-equal #:expect 413
                                    #:got (sink-result-status result))
                      (assert-equal #:expect '()
                                    #:got (filter (lambda (name)
                                                    (not (member name
                                                                 '("." ".."))))
                                                  (directory-entries
                                                   directory))))))))
         (test "a URL that is not one is a 400"
               #:shuffle? #f
               (call-with-temp-directory
                (lambda (directory)
                  (with-sink-directory
                   directory
                   (lambda ()
                     (let ((missing (sink-file #:url #f))
                           (scheme (sink-file #:url "file:///etc/passwd"))
                           (nonsense (sink-file #:url "not a url")))
                       (assert-equal #:expect 400
                                     #:got (sink-result-status missing))
                       (assert-equal #:expect 400
                                     #:got (sink-result-status scheme))
                       (assert-equal #:expect 400
                                     #:got (sink-result-status nonsense))))))))
         (test "fetch-file keeps the older contract"
               #:shuffle? #f
               (call-with-temp-directory
                (lambda (directory)
                  (with-sink-directory
                   directory
                   (lambda ()
                     (assert-equal
                      #:expect "https://files.example/sunk/text.txt"
                      #:got (fetch-file #:url (test-server-url server "/text")))
                     (let ((condition
                            (caught (lambda ()
                                      (fetch-file
                                       #:url (test-server-url server
                                                              "/missing"))))))
                       (assert-true (sink-error? condition))
                       (assert-equal #:expect 502
                                     #:got (sink-error-status condition))
                       (assert-equal #:expect 404
                                     #:got (sink-error-upstream-status
                                            condition))))))))
         (test "the sink directory is created on the first fetch"
               #:shuffle? #f
               (call-with-temp-directory
                (lambda (directory)
                  (let ((nested (string-append directory "/not/yet/there")))
                    (with-sink-directory
                     nested
                     (lambda ()
                       (let ((result (sink-file
                                      #:url (test-server-url server "/text"))))
                         (assert-true (sink-result-ok? result))
                         (let ((path (sink-result-path result)))
                           (assert-true (and path (file-exists? path)))
                           (assert-true
                            (and path
                                 (string-prefix? (string-append nested "/")
                                                 path)))))))))))))

(define (spec)
  (veritas-run #:concurrent? #f #:shuffle? #f sink-suite))
