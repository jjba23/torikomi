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

;;; Commentary:
;;
;; The HTML controller: one page, and the form that asks torikomi to sink a
;; file.  What it does is read what the reader typed, hand it to
;; `(torikomi torikomi)' and draw the answer; every decision about a URL, a
;; name and a failure is made there, so this file has no policy to get wrong.
;;
;; A failure is answered with the same page and the status the sink decided --
;; 400 for a URL that is not one, 413 for a body over the limit, 502 for a
;; remote that refused -- and the reader's URL and name are still in the form.
;; That is friendlier than a redirect (the reader keeps what they typed) and
;; more honest than answering 200 for a fetch that did not happen.

(define-artanis-controller index)

(import (ice-9 exceptions)
        (ice-9 binary-ports)
        (kracht prelude)
        (torikomi torikomi)
        (app views index))

(define* (emit-page rc page #:key (status 200))
  "Send PAGE as an HTML response with STATUS.

The page is serialized by hygguile's writer (see `render-page'), not by
Artanis' XML shorthand: the shorthand writes a childless element as `<div />',
and a browser reading `text/html' never closes that, which would turn the
frosted washes behind the hero into the rest of the document."
  (response-emit (render-page page)
                 #:status status
                 #:headers '((content-type text/html))))

(define (submitted-form rc)
  "The submitted form as an association list, or '() when there is none.

A body that is not a bytevector, or a form that does not decode, is an empty
form rather than a 500: a malformed request must not take the page down."
  (let ((body (rc-body rc)))
    (if (and body (bytevector? body))
        (guard (condition (else '()))
          (alist-from-url-encoded-body body))
        '())))

(define (field form name)
  "The non-empty value NAME has in FORM, or #f."
  (let ((value (assoc-ref form name)))
    (and (string? value)
         (let ((value (string-trim-both value)))
           (and (positive? (string-length value)) value)))))

(get "/"
     #:mime 'xml
     #:i18n '(cookie "lang")
     (lambda (rc)
       (emit-page rc (torikomi-page (:i18n rc)))))

(post "/sink-file"
      #:mime 'xml
      #:i18n '(cookie "lang")
      (lambda (rc)
        (let* ((form (submitted-form rc))
               (file-url (field form "file-url"))
               (file-name (field form "file-name"))
               (result (sink-file #:url file-url #:name file-name)))
          (emit-page rc
                     (torikomi-page (:i18n rc)
                                    #:file-url file-url
                                    #:file-name file-name
                                    #:new-url (and (sink-result-ok? result)
                                                   (sink-result-public-url
                                                    result))
                                    #:error (and (not (sink-result-ok? result))
                                                 (sink-result-message result)))
                     #:status (if (sink-result-ok? result)
                                  200
                                  (sink-result-status result))))))

(get "/robots.txt" static-page-emitter)
(get "/favicon.ico" static-page-emitter)
