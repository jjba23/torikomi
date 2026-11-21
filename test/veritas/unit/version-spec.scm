;; torikomi
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; The version, in one place.
;;;
;;; `maak version' prints it and `maak sync-version' copies it into the files
;;; that cannot read a Scheme module.  The manual is one of those files, so the
;;; suite asks that the two still agree: a release that forgot the README is
;;; the one mistake this split invites.

(define-module (veritas unit version-spec)
  #:use-module (veritas veritas)
  #:use-module (ice-9 format)
  #:use-module (ice-9 textual-ports)
  #:use-module (torikomi version)
  #:export (spec))

(define (read-text path)
  (call-with-input-file path get-string-all))

(define version-suite
  (suite "the version this program is"
         #:concurrent? #f
         #:shuffle? #f
         (test "the version is a release number"
               #:shuffle? #f
               (assert-matches #:pattern "^[0-9]+\\.[0-9]+\\.[0-9]+$"
                               #:got torikomi-version))
         (test "the version banner names the program"
               #:shuffle? #f
               (assert-equal #:expect (format #f "torikomi ~a" torikomi-version)
                             #:got (torikomi-version-string))
               (assert-contains #:expect (torikomi-version-string)
                                #:got torikomi-version))
         (test "printing the version also names the licence and the homepage"
               #:shuffle? #f
               (let ((printed (with-output-to-string
                                (lambda () (print-version)))))
                 (assert-contains #:expect printed #:got torikomi-version)
                 (assert-contains #:expect printed #:got torikomi-license)
                 (assert-contains #:expect printed #:got torikomi-homepage)))
         (test "the homepage is an address"
               #:shuffle? #f
               (assert-matches #:pattern "^https://"
                               #:got torikomi-homepage))
         (test "the manual carries the same version"
               #:shuffle? #f
               (assert-true (file-exists? "README.org"))
               (let ((manual (read-text "README.org")))
                 (assert-contains
                  #:expect manual
                  #:got (format #f "torikomi version ~a" torikomi-version))))))

(define (spec)
  (veritas-run #:concurrent? #f #:shuffle? #f version-suite))
