;;; lispy-file-sink - the free music knowledge encyclopaedia

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
        (kracht prelude)
        (app views index))

(get "/"
     #:mime 'xml
     #:i18n '(cookie "lang")
     (lambda (rc)
       (response-emit (:mime rc
                             (lispy-file-sink-page (:i18n rc))))))

(post "/sink-file"
      #:mime 'xml
      #:i18n '(cookie "lang")
      (lambda (rc)
        (let* ((body (alist-from-url-encoded-body (rc-body rc))))
          (response-emit (:mime rc
                                (lispy-file-sink-page (:i18n rc)
                                                      #:new-url (assoc-ref
                                                                 body
                                                                 "file-url")))))))

(get "/robots.txt" static-page-emitter)
(get "/favicon.ico" static-page-emitter)
