;;; lispy-file-sink 

;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;; lispy-file-sink is free software: you can redistribute it and/or modify
;; it under the terms of the GNU Affero General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; lispy-file-sink is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU Affero General Public License for more details.

;; You should have received a copy of the GNU Affero General Public License
;; along with lispy-file-sink.  If not, see <https://www.gnu.org/licenses/>.

(define-artanis-controller index)

(import (web uri)
        (ice-9 string-fun)
        (ice-9 binary-ports)
        (kracht prelude)
        (curl)
        (web response)
        (rnrs bytevectors)
        (app views index))

(get "/"
     #:mime 'xml
     #:i18n '(cookie "lang")
     (lambda (rc)
       (response-emit (:mime rc
                             (lispy-file-sink-page (:i18n rc))))))

(define* (fetch-file #:key url
                     (timeout-seconds 120)
                     (follow-redirects #t))
  (display (format #f "\nfetching URL: ~a\n" url))
  (let* ((last-url-piece (car (reverse (string-split url #\/))))
         (handle (curl-easy-init))
         (_ (begin
              (curl-easy-setopt handle
                                'header #t)
              (curl-easy-setopt handle
                                'url url)
              (curl-easy-setopt handle
                                'verbose #t)
              (curl-easy-setopt handle
                                'ssl-verifyhost #f)
              (curl-easy-setopt handle
                                'ssl-verifypeer #f)
              (curl-easy-setopt handle
                                'maxredirs 10)
              (curl-easy-setopt handle
                                'http-version 2)
              (curl-easy-setopt handle
                                'followlocation follow-redirects)
              (curl-easy-setopt handle
                                'timeout timeout-seconds)))
         (response-string (curl-easy-perform handle))
         (response-port (open-input-string response-string))
         (response (read-response response-port))
         (response-content-type (cadr (string-split (format #f "~a" (car (response-content-type
                                                          response))) #\/)))
         (response-body (read-response-body response))
         (destination-file (format #f "tmp/~a.~a" last-url-piece
                                   response-content-type)))
    (display (format #f "The body contains ~a bytes~%"
                     (bytevector-length response-body)))
    (call-with-output-file destination-file
      (lambda (port)
        (put-bytevector port response-body))
      #:binary #t) response-body))

(post "/sink-file"
      #:mime 'xml
      #:i18n '(cookie "lang")
      (lambda (rc)
        (let* ((body (alist-from-url-encoded-body (rc-body rc)))
               (_ (fetch-file #:url (assoc-ref body "file-url"))))
          
          (response-emit (:mime rc
                                (lispy-file-sink-page (:i18n rc)
                                                      #:new-url (assoc-ref
                                                                 body
                                                                 "file-url")))))))

(get "/robots.txt" static-page-emitter)
(get "/favicon.ico" static-page-emitter)
