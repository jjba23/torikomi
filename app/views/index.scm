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

(define-module (app views index)
  #:use-module (artanis artanis)
  #:use-module (artanis i18n)
  #:use-module (artanis i18n sxml)
  #:use-module (artanis i18n locale)
  #:use-module (ice-9 i18n)
  #:use-module (ice-9 textual-ports)
  #:use-module (ice-9 string-fun)
  #:use-module (torikomi html)
  #:use-module (hygguile hygguile)
  #:export (torikomi-page))

(define (intro-section)
  `((section (@ (class ,(mk-class '(py-4 px-2))))
             (h1 (a (@ (class ,(mk-class '(overline text-lg font-bold)))
                       (href "/")) "torikomi: 取り込み"))
             (p (@ (class ,(mk-class '(py-4))))
              "simple interface to sink/download files from a remote URL directly into a directory on your server."))))

(define* (url-show-section #:key file-url new-url)
  `((section ,(if new-url
                  `((p ,(format #f "new-url: ~a" new-url))) "")
             ,(if file-url
                  `((small ,(format #f "file-url: ~a" file-url))) ""))))

(define (footer-section)
  `((footer (@ (class ,(mk-class '(py-12 flex flex-col gap-3 justify-center align-center items-center))))
                         (small (em (@(class ,(mk-class '(italic text-sm)))) "λ powered by Lisp (Guile Scheme)"))
            (small (em (@(class ,(mk-class '(text-sm)))) "find the source code for this program here:"))
            (a (@ (class ,(mk-class '(underline text-sm)))
                  (href "https://codeberg.org/jjba23/torikomi"))
               "codeberg.org/jjba23/torikomi"))))

(define (file-form-section)
  `((section (@ (class ,(mk-class '(flex flex-row flex-wrap justify-between
                                         gap-8))))

             (section (form (@ (method POST)
                               (action "/sink-file")
                               (class ,(mk-class '(py-4))))

                            (label (@ (for "file-url")) "File URL:")
                            (input (@ (placeholder "Enter the file's URL here")
                                      (type url)
                                      (required "")
                                      (id file-url)
                                      (name file-url)) "")
                            (button (@ (type submit)) "Submit")))
             (section (figure (img (@ (class ,(mk-class '(w-24 h-auto
                                                               rounded-xl)))
                                      (src
                                       "https://jointhefreeworld.org/static-assets/torikomi/torikomi-logo-small.png"))
                                   ""))))))

(define* (torikomi-page G_
                        #:key file-url new-url)
  (html-template G_
                 #:body `(,(intro-section) ,(url-show-section #:file-url
                                                              file-url
                                                              #:new-url
                                                              new-url)
                          ,(file-form-section)
                          ,(footer-section))))

(define* (html-template G_
                        #:key (title "torikomi") body)
  
  `("<!DOCTYPE html>" (html (head (title ,title)
                                  (style ,(assoc-ref asset-library
                                           "pub/css/torikomi.olive.min.css"))
                                  ,(hygguile-recommended-meta)
                                  ,(hygguile-recommended-resources)
                                  (link (@ (rel "shortcut icon")
                                           (href "/favicon.ico")
                                           (type "image/x-icon")) "")
                                  (link (@ (rel "icon")
                                           (href "/favicon.ico")
                                           (type "image/x-icon")) ""))
                            (body (div (@ (class ,(mk-class '(font-sans))))
                                       ,body)))))
