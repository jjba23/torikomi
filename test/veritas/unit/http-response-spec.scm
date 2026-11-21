;; torikomi
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Reading a response.
;;;
;;; libcurl is asked for the headers and returns one block per response when it
;;; follows a redirect.  Every decision torikomi makes -- is this a success?
;;; what type is the body? -- is made from that text, so the readings below are
;;; of the text: a redirect whose first status was 301 and whose last was 200, a
;;; header repeated by a redirect, a `Content-Type' with a charset, and the
;;; retry policy that decides whether asking again could help.

(define-module (veritas unit http-response-spec)
  #:use-module (veritas veritas)
  #:use-module (torikomi torikomi)
  #:use-module (torikomi preferences)
  #:export (spec))

(define ok
  "HTTP/1.1 200 OK\r\nContent-Type: image/png\r\nContent-Length: 4\r\n\r\n")

(define redirected
  (string-append "HTTP/1.1 301 Moved Permanently\r\n"
                 "Location: /pic.png\r\n"
                 "Content-Type: text/html\r\n"
                 "\r\n"
                 "HTTP/2 200\r\n"
                 "Content-Type: image/png\r\n"
                 "Content-Disposition: attachment; filename=\"a.png\"\r\n"
                 "\r\n"))

(define without-status "Content-Type: text/plain\r\n\r\n")

(define http-response-suite
  (suite "reading a response"
         #:concurrent? #f
         #:shuffle? #f
         (test "the status line is the last one libcurl returned"
               #:shuffle? #f
               (assert-equal #:expect "HTTP/2 200"
                             #:got (http-status-line redirected))
               (assert-equal #:expect "HTTP/1.1 200 OK"
                             #:got (http-status-line ok))
               (assert-false (http-status-line without-status)))
         (test "the status code is the number in the status line"
               #:shuffle? #f
               (assert-equal #:expect 200
                             #:got (http-status-code "HTTP/1.1 200 OK"))
               (assert-equal #:expect 404
                             #:got (http-status-code "HTTP/2 404"))
               (assert-equal #:expect 503
                             #:got (http-status-code "HTTP/1.1 503 Service Unavailable"))
               (assert-false (http-status-code "HTTP/1.1"))
               (assert-false (http-status-code #f)))
         (test "only 2xx is a success"
               #:shuffle? #f
               (assert-true (http-ok? 200))
               (assert-true (http-ok? 204))
               (assert-true (http-ok? 299))
               (assert-false (http-ok? 199))
               (assert-false (http-ok? 301))
               (assert-false (http-ok? 404))
               (assert-false (http-ok? #f)))
         (test "the headers read are the ones of the final response"
               #:shuffle? #f
               (assert-equal #:expect "image/png"
                             #:got (content-type-of redirected))
               ;; A header of the redirect itself is not the file's: reading it
               ;; would take the redirect's `Location' or `Content-Type' for the
               ;; answer, which is what the old version did.
               (assert-false (header-value redirected "location"))
               (assert-equal #:expect "/pic.png"
                             #:got (header-value
                                    "HTTP/1.1 302 Found\r\nLocation: /pic.png\r\n\r\n"
                                    "location"))
               (assert-equal #:expect "attachment; filename=\"a.png\""
                             #:got (header-value redirected
                                                "content-disposition"))
               (assert-false (header-value redirected "x-not-there")))
         (test "a Content-Type is split into its media type and subtype"
               #:shuffle? #f
               (assert-equal #:expect "jpeg"
                             #:got (parse-content-subtype "image/jpeg; charset=utf-8"))
               (assert-equal #:expect "plain"
                             #:got (parse-content-subtype "TEXT/PLAIN"))
               (assert-equal #:expect "plain"
                             #:got (parse-content-subtype " text/plain ; charset=utf-8"))
               (assert-false (parse-content-subtype "plain"))
               (assert-false (parse-content-subtype "text/")))
         (test "a media type names the extension of the file"
               #:shuffle? #f
               (assert-equal #:expect "jpg"
                             #:got (extension-from-content-type
                                    "image/jpeg; charset=utf-8"))
               (assert-equal #:expect "png"
                             #:got (extension-from-content-type "image/png"))
               (assert-equal #:expect "svg"
                             #:got (extension-from-content-type "image/svg+xml"))
               (assert-equal #:expect "txt"
                             #:got (extension-from-content-type "text/plain"))
               (assert-equal #:expect "bin"
                             #:got (extension-from-content-type
                                    "application/octet-stream"))
               (assert-equal #:expect "weba"
                             #:got (extension-from-content-type "audio/webm"))
               (assert-false (extension-from-content-type #f))
               (assert-false (extension-from-content-type "nonsense")))
         (test "an unknown subtype still names an extension"
               #:shuffle? #f
               (assert-equal #:expect "foo"
                             #:got (extension-from-content-type
                                    "application/x-foo"))
               (assert-equal #:expect "widget"
                             #:got (extension-from-content-type
                                    "application/widget+xml"))
               ;; A subtype that cannot be a file extension is not guessed at.
               (assert-equal #:expect "bin"
                             #:got (find-extension-in-headers
                                    "HTTP/1.1 200 OK\r\nContent-Type: text/\r\n\r\n"))
               (assert-equal #:expect "png"
                             #:got (find-extension-in-headers ok)))
         (test "the retry policy only retries what may be transient"
               #:shuffle? #f
               (assert-true (retryable-status? 408))
               (assert-true (retryable-status? 429))
               (assert-true (retryable-status? 500))
               (assert-true (retryable-status? 502))
               (assert-true (retryable-status? 503))
               (assert-true (retryable-status? 504))
               (assert-false (retryable-status? 404))
               (assert-false (retryable-status? 413))
               (assert-false (retryable-status? #f)))
         (test "a transport failure and a bad gateway are retryable, a large body is not"
               #:shuffle? #f
               (assert-true (retryable-error?
                             (make-sink-error 502 'transport "no route" #f)))
               (assert-true (retryable-error?
                             (make-sink-error 502 'http-status "busy" 503)))
               (assert-false (retryable-error?
                              (make-sink-error 502 'http-status "gone" 404)))
               (assert-false (retryable-error?
                              (make-sink-error 413 'too-large "big" 200)))
               (assert-false (retryable-error? #f)))
         (test "the wait between attempts doubles and is capped"
               #:shuffle? #f
               (parameterize ((curl-retry-delay-seconds 1))
                 (assert-equal #:expect 1 #:got (retry-delay 0))
                 (assert-equal #:expect 2 #:got (retry-delay 1))
                 (assert-equal #:expect 4 #:got (retry-delay 2))
                 (assert-equal #:expect 8 #:got (retry-delay 3))
                 (assert-equal #:expect 60 #:got (retry-delay 20)))
               (parameterize ((curl-retry-delay-seconds 0))
                 (assert-equal #:expect 0 #:got (retry-delay 0))))))

(define (spec)
  (veritas-run #:concurrent? #f #:shuffle? #f http-response-suite))
