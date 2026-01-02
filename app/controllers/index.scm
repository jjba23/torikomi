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

(define-artanis-controller index)

(import (web uri)
        (ice-9 string-fun)
        (ice-9 binary-ports)
        (kracht prelude)
        (torikomi fetch)
        (curl)
        (web response)
        (rnrs bytevectors)
        (app views index))

(get "/"
     #:mime 'xml
     #:i18n '(cookie "lang")
     (lambda (rc)
       (response-emit (:mime rc
                             (torikomi-page (:i18n rc))))))

(post "/sink-file"
      #:mime 'xml
      #:i18n '(cookie "lang")
      (lambda (rc)
        (let* ((body (alist-from-url-encoded-body (rc-body rc)))
               (new-file-path (fetch-file #:url (assoc-ref body "file-url"))))
          
          (response-emit (:mime rc
                                (torikomi-page (:i18n rc)
                                                      #:new-url new-file-path))))))

(get "/robots.txt" static-page-emitter)
(get "/favicon.ico" static-page-emitter)
