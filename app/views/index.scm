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
  `((section (@ (class ,(mk-class '(py-6 md:py-8 px-3 md:px-6))))
             (h1 (a (@ (class ,(mk-class '(overline text-lg font-bold
                                           text-jeans-blue-700
                                           dark:text-jeans-blue-100
                                           hover:text-china-violet-300)))
                       (href "/")) "torikomi: 取り込み"))
             (p (@ (class ,(mk-class '(py-4 text-onyx-500
                                            dark:text-stone-500
                                            font-light
                                            max-w-72
                                            text-justify
                                            leading-6))))
              "simple interface to sink/download files from a remote URL directly into a directory on your server."))))

(define* (url-show-section #:key file-url new-url)
  `((section (@(class ,(mk-class '(px-6 md:px-16)))) ,(if new-url
                  `((p (@ (class ,(mk-class '(text-md text-onyx-500
                                                      dark:text-stone-500))))
                       ,(format #f "new-url: ~a" new-url))) "")
             ,(if file-url
                  `((small (@ (class ,(mk-class '(pt-4 text-sm text-onyx-300
                                                          dark:text-stone-900))))
                           ,(format #f "given file-url: ~a" file-url))) ""))))

(define (footer-section)
  `((footer (@ (class ,(mk-class '(py-12 flex
                                         flex-wrap
                                         gap-8
                                         justify-center
                                         align-center
                                         items-center))))

            (section ,(ui-mode-button #:size '(text-sm)
                                      #:extra-classes '(py-1 px-2 max-w-prose
                                                             cursor-pointer)))
            (section (@ (class ,(mk-class '(flex flex-col gap-3 justify-center
                                                 align-center items-center))))
                     (small (em (@ (class ,(mk-class '(italic text-sm
                                                       text-onyx-500
                                                       dark:text-stone-500))))
                                "λ powered by Lisp (Guile Scheme)"))
                     (small (em (@ (class ,(mk-class '(text-md text-onyx-500
                                                       dark:text-stone-500))))
                                "find the source code for this program here:"))
                     (a (@ (class ,(mk-class '(underline text-md
                                               text-jeans-blue-700
                                               dark:text-jeans-blue-100
                                               hover:text-china-violet-300)))
                           (href "https://codeberg.org/jjba23/torikomi"))
                        "codeberg.org/jjba23/torikomi")))))

(define (file-form-section)
  `((section (@ (class ,(mk-class '(flex flex-col-reverse
                                         md:flex-row
                                         flex-wrap
                                         justify-center
                                         items-center
                                         align-center
                                         md:justify-between
                                         gap-8
                                         px-6
                                         md:px-16))))

             (section (form (@ (method POST)
                               (action "/sink-file")
                               (class ,(mk-class '(py-4))))

                            ,(input #:label "File URL:"
                                    #:placeholder "Enter the file's URL here"
                                    #:type 'url
                                    #:required #t
                                    #:name 'file-url
                                    #:input-css '(p-4 min-w-64
                                                      md:min-w-128
                                                      rounded-xl
                                                      border-stone-700
                                                      dark:border-onyx-100
                                                      dark:text-stone-300
                                                      bg-stone-300/75
                                                      dark:bg-onyx-700/75
                                                      border-2
                                                      shadow-md
                                                      font-sans))
                            ,(submit-button "download")))
             ,(project-logo-section))))

(define (project-logo-section)
  `((section (figure (img (@ (class ,(mk-class '(w-24 h-auto rounded-xl
                                                      shadow-lg)))
                             (src
                              "https://jointhefreeworld.org/static-assets/torikomi/torikomi-logo-small.png"))
                          "")))))

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
                            (body (@ (class ,(mk-class '(bg-stone-300
                                                         dark:bg-onyx-900
                                                         font-sans))))
                                  (div (@ (class ,(mk-class '())))
                                       ,body)))))
