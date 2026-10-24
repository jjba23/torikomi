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
;; The one place torikomi's version is written by hand, together with the
;; handful of facts the program reports about itself.  `maak version' prints
;; it, and a release is one edit here rather than a search of the tree: the
;; copies that cannot read a Scheme module are rewritten from this file by
;; `maak sync-version', which reads the checkout's own file rather than the
;; library it happens to be running under.
;;
;; The version is the release the tree is at, and it is bumped when a release
;; is cut rather than when work starts.

;;; Code:

(define-module (torikomi version)
  ;; Deliberately not declarative.  A declarative module lets Guile inline its
  ;; bindings into the modules that use them, and the version is the one value
  ;; here that changes between builds: inlined, it would be baked into a
  ;; consumer's compiled file while that file's source stayed the same, so a
  ;; bump would leave the program answering with the version it was compiled
  ;; against.
  #:declarative? #f
  #:export (torikomi-version
            torikomi-homepage
            torikomi-license
            torikomi-version-string
            print-version))

(define torikomi-version
  "0.1.1")

(define torikomi-homepage
  "https://codeberg.org/jjba23/torikomi")

(define torikomi-license
  "AGPL-3.0-or-later")

(define (torikomi-version-string)
  "The one-line version banner: the program's name and the release it is."
  (format #f "torikomi ~a" torikomi-version))

(define* (print-version #:optional (port (current-output-port)))
  "Print the version banner, and the program's licence and homepage, to PORT.

The homepage is printed with it because a version on its own is a number a
reader cannot act on: what they do with it is find out what it is."
  (format port "~a~%~a~%~a~%"
          (torikomi-version-string)
          (format #f "License: ~a" torikomi-license)
          (format #f "Homepage: ~a" torikomi-homepage)))
