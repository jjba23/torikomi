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

(define-module (app views index)
  #:use-module (artanis artanis)
  #:use-module (artanis i18n)
  #:use-module (artanis i18n sxml)
  #:use-module (artanis i18n locale)
  #:use-module (ice-9 i18n)
  #:use-module (ice-9 textual-ports)
  #:use-module (ice-9 string-fun)
  #:export (lispy-file-sink-page))

(define* (lispy-file-sink-page G_ #:key new-url)
  (html-template G_
                 #:body `((section (h1 "lispy-file-sink")
                                   (p
                                    "simple interface to sink/download files from a remote URL directly into a directory on your server."))
                          ,(if new-url `((p ,(format #f "new-url: ~a" new-url))) "")
                          (section (form (@ (method POST)
                                            (action "/sink-file"))
                                         (label (@ (for "file-url"))
                                                "File URL:")
                                         (input (@ (placeholder
                                                    "Enter the file's URL here")
                                                   (type url)
                                                   (required "")
                                                   (name "file-url")) "")
                                         (button (@ (type submit)) "Submit"))))))

(define* (html-template G_
                        #:key (title "lispy-file-sink") body)
  
  `("<!DOCTYPE html>" (html (head (title ,title)
                                  (link (@ (rel "shortcut icon")
                                           (href "/favicon.ico")
                                           (type "image/x-icon")) "")
                                  (link (@ (rel "icon")
                                           (href "/favicon.ico")
                                           (type "image/x-icon")) ""))
                            (body ,body))))
