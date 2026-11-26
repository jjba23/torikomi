;; torikomi
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

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
  "0.3.7")

(define torikomi-homepage
  "https://github.com/jjba23/torikomi")

(define torikomi-license
  "MIT")

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
