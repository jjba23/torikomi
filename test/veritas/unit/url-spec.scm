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

;;; What a URL is allowed to be.
;;;
;;; torikomi fetches a URL that a stranger typed, from inside a server that can
;;; reach whatever the server can reach.  The least it owes is to fetch only the
;;; two protocols it says it fetches -- a `file://' URL would read the server's
;;; disk, and an `ftp://' or `gopher://' one is not what this service is for --
;;; and to say why a URL was refused in words a reader can act on.

(define-module (veritas unit url-spec)
  #:use-module (veritas veritas)
  #:use-module (ice-9 exceptions)
  #:use-module (web uri)
  #:use-module (torikomi torikomi)
  #:export (spec))

(define (caught thunk)
  "The condition THUNK raises, or #f when it returns."
  (guard (condition (else condition))
    (thunk)
    #f))

(define url-suite
  (suite "what a URL may be"
         #:concurrent? #f
         #:shuffle? #f
         (test "http and https are the protocols torikomi fetches"
               #:shuffle? #f
               (assert-true (valid-url? "https://example.org/a.png"))
               (assert-true (valid-url? "http://example.org"))
               (assert-true (valid-url? "http://127.0.0.1:8080/a?b=1"))
               (assert-true (valid-url? "https://user:secret@example.org/a"))
               (assert-true (valid-url? "  https://example.org/a  ")))
         (test "every other protocol is refused"
               #:shuffle? #f
               (assert-false (valid-url? "file:///etc/passwd"))
               (assert-false (valid-url? "ftp://example.org/a"))
               (assert-false (valid-url? "gopher://example.org/"))
               (assert-false (valid-url? "data:text/plain,hello"))
               (assert-false (valid-url? "javascript:alert(1)")))
         (test "a URL without a host is not a URL to fetch"
               #:shuffle? #f
               (assert-false (valid-url? ""))
               (assert-false (valid-url? "   "))
               (assert-false (valid-url? #f))
               (assert-false (valid-url? "not a url"))
               (assert-false (valid-url? "/just/a/path"))
               (assert-false (valid-url? "http://"))
               (assert-false (valid-url? "https:///path")))
         (test "a valid URL is answered as a URI"
               #:shuffle? #f
               (let ((uri (validate-url "https://example.org:8443/a/b.png?x=1")))
                 (assert-equal #:expect 'https #:got (uri-scheme uri))
                 (assert-equal #:expect "example.org" #:got (uri-host uri))
                 (assert-equal #:expect 8443 #:got (uri-port uri))
                 (assert-equal #:expect "/a/b.png" #:got (uri-path uri))))
         (test "a missing URL is a 400 that says so"
               #:shuffle? #f
               (let ((condition (caught (lambda () (validate-url #f)))))
                 (assert-true (sink-error? condition))
                 (assert-equal #:expect 400 #:got (sink-error-status condition))
                 (assert-equal #:expect 'missing-url
                               #:got (sink-error-reason condition))
                 (assert-true (string? (sink-error-message condition))))
               (let ((condition (caught (lambda () (validate-url "")))))
                 (assert-equal #:expect 'missing-url
                               #:got (sink-error-reason condition))))
         (test "a refused protocol is a 400 that names the alternatives"
               #:shuffle? #f
               (let ((condition (caught (lambda ()
                                          (validate-url "file:///etc/passwd")))))
                 (assert-true (sink-error? condition))
                 (assert-equal #:expect 400 #:got (sink-error-status condition))
                 (assert-equal #:expect 'unsupported-scheme
                               #:got (sink-error-reason condition))
                 (assert-contains #:expect (sink-error-message condition)
                                  #:got "http")))
         (test "a malformed URL is a 400 and not a crash"
               #:shuffle? #f
               (let ((condition (caught (lambda () (validate-url "not a url")))))
                 (assert-true (sink-error? condition))
                 (assert-equal #:expect 400 #:got (sink-error-status condition))
                 (assert-equal #:expect 'invalid-url
                               #:got (sink-error-reason condition))))))

(define (spec)
  (veritas-run #:concurrent? #f #:shuffle? #f url-suite))
