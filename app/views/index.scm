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
  #:use-module (hygguile hygguile)
  #:use-module (ice-9 i18n)
  #:use-module (ice-9 textual-ports)
  #:use-module (ice-9 string-fun)
  #:export (lispy-file-sink-page))

(define* (lispy-file-sink-page G_)
  (html-template G_
                 #:body `(div (div (@ (class ,(mk-class '(p-2))))
                                   (div (@ (class ,(mk-class '(flex flex-row
                                                               flex-wrap
                                                               gap-5
                                                               px-3
                                                               align-center
                                                               items-center
                                                               justify-center
                                                               py-6))))
                                        ,(lispy-file-sink-explain G_))))))

(define* (html-template G_
                        #:key (title "Lispy-File-Sink") body
                        (is-logged-in #f))
  
  `(,doctype-html (html (head (title ,title)
                              ,(hygguile-recommended-meta)
                              ,(hygguile-recommended-resources)
                              (link (@ (rel "shortcut icon")
                                       (href "/favicon.ico")
                                       (type "image/x-icon")) "")
                              (link (@ (rel "icon")
                                       (href "/favicon.ico")
                                       (type "image/x-icon")) "")
                              (link (@ (rel stylesheet)
                                       (href "/css/olive.min.css"))
                                    "")

                              )
                        (body (@ (class ,(mk-class '(bg-stone-100
                                                     dark:bg-onyx-900))))
                              ((div (@ (class ,(mk-class '(flex flex-col
                                                           justify-between
                                                           min-h-96))))
                                    (div (@ (class ,(mk-class '(flex flex-col
                                                                gap-8
                                                                justify-start))))
                                         ,body)))))))
