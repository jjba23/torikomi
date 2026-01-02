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

(define-restful-api v1)

(import (web uri)
        (ice-9 string-fun)
        (ice-9 binary-ports)
        (kracht prelude)
        (torikomi env)
        (torikomi torikomi)
        (curl)
        (json)
        (web response)
        (rnrs bytevectors)
        (app views index))

(post "/api/v1/sink-file"
      #:mime 'json
      (lambda (rc)
        (let* ((body (json-string->scm (utf8->string (rc-body rc))))
               (new-url (fetch-file #:url (assoc-ref body "file-url")
                                    #:timeout-seconds torikomi-curl-timeout-seconds)))
          (:mime rc
                 `((file-url unquote (assoc-ref body "file-url"))
                   (new-url unquote new-url))))))

