;; torikomi
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; The page a reader meets.
;;;
;;; The page is read as the markup a browser is handed -- rendered through the
;;; same writer the controller uses, with an identity translation -- rather than
;;; as the expression that builds it.  What is asked of it is what a reader is
;;; owed: that a failure is announced rather than silent, that the URL and name
;;; they typed come back, that a URL is escaped before it is handed to a script,
;;; that the version and stylesheet are where they belong, and that the frosted
;;; glass the page is built out of is really in the markup and really has a
;;; light and a dark face.

(define-module (veritas unit page-spec)
  #:use-module (veritas veritas)
  #:use-module (app views index)
  #:use-module (torikomi version)
  #:export (spec))

;; The identity translation: a page is read here for what it is built of, and a
;; string left as it was written is what a reader whose language has no
;; translation yet is handed.
(define (G_ text)
  text)

(define (markup page)
  "PAGE serialized the way the server hands it to a browser."
  (render-page page))

(define success-page
  (markup (torikomi-page G_
                         #:file-url "https://example.org/pic.png"
                         #:file-name "holiday"
                         #:new-url "https://files.example/pic.png")))

(define failure-page
  (markup (torikomi-page G_
                         #:file-url "https://example.org/missing.png"
                         #:file-name "holiday"
                         #:error "the remote answered with HTTP 404.")))

(define landing-page
  (markup (torikomi-page G_)))

(define head-of-success-page
  (let ((end (string-contains success-page "</head>")))
    (if end (substring success-page 0 end) "")))

(define page-suite
  (suite "the page a reader meets"
         #:concurrent? #f
         #:shuffle? #f
         (test "the page is a document of this program"
               #:shuffle? #f
               (assert-contains #:expect success-page #:got "<!DOCTYPE html>")
               (assert-contains #:expect success-page #:got "lang=\"en\"")
               (assert-contains #:expect success-page #:got "torikomi")
               (assert-contains #:expect success-page #:got torikomi-version)
               (assert-contains #:expect head-of-success-page
                                #:got "torikomi.olive.min.css")
               (assert-contains #:expect success-page #:got "favicon.ico"))
         (test "the page is built out of frosted glass"
               #:shuffle? #f
               ;; The frost layer, rather than a plain backdrop blur: it is what
               ;; survives a rounded corner.
               (assert-contains #:expect success-page #:got "hg-frost")
               (assert-contains #:expect success-page #:got "hg-frost-pill")
               ;; The hero's washes drift behind its glass, and the pane clips
               ;; them to its own radius.
               (assert-contains #:expect success-page #:got "hg-blob")
               (assert-contains #:expect success-page #:got "hg-glass-layer")
               ;; The "Golden Gate" behind the page: fog blue, gold and violet,
               ;; fixed to the viewport and hidden from assistive technology.
               (assert-contains #:expect success-page #:got "fixed inset-0")
               (assert-contains #:expect success-page
                                #:got "bg-jeans-blue-500/25")
               (assert-contains #:expect success-page
                                #:got "bg-tawny-500/25")
               (assert-contains #:expect success-page
                                #:got "bg-china-violet-500/25")
               (assert-contains #:expect success-page
                                #:got "aria-hidden=\"true\""))
         (test "the theme is the reader's, and is applied before the first paint"
               #:shuffle? #f
               (assert-contains #:expect success-page #:got "data-theme")
               (assert-contains #:expect success-page
                                #:got "prefers-color-scheme: dark")
               (assert-contains #:expect success-page
                                #:got "hygguileToggleDarkTheme()")
               (assert-contains #:expect success-page
                                #:got "switch between the light and dark theme")
               ;; Both faces of every surface are in the markup: the light one
               ;; and the dark one.
               (assert-contains #:expect success-page #:got "bg-stone-100")
               (assert-contains #:expect success-page
                                #:got "dark:bg-onyx-900"))
         (test "a success says where the file is"
               #:shuffle? #f
               (assert-contains #:expect success-page #:got "public url")
               (assert-contains #:expect success-page
                                #:got "https://files.example/pic.png")
               ;; A success is announced too, as a status rather than an alert.
               (assert-contains #:expect success-page #:got "role=\"status\"")
               (assert-not-contains #:expect success-page #:got "role=\"alert\""))
         (test "a failure is announced, not silent"
               #:shuffle? #f
               (assert-contains #:expect failure-page #:got "role=\"alert\"")
               (assert-contains #:expect failure-page
                                #:got "the remote answered with HTTP 404.")
               (assert-contains #:expect failure-page
                                #:got "could not sink the file"))
         (test "what the reader typed comes back"
               #:shuffle? #f
               (assert-contains #:expect failure-page
                                #:got "https://example.org/missing.png")
               (assert-contains #:expect failure-page #:got "value=\"holiday\"")
               (assert-contains #:expect failure-page #:got "given file-name:")
               (assert-contains #:expect failure-page #:got "given file-url:"))
         (test "a failure message is escaped"
               #:shuffle? #f
               (let ((page (markup (torikomi-page G_
                                                  #:error "<script>alert(1)</script>"))))
                 (assert-not-contains #:expect page
                                      #:got "<script>alert(1)</script>")
                 (assert-contains #:expect page #:got "&lt;script&gt;")))
         (test "a URL handed to a script cannot end the string early"
               #:shuffle? #f
               (assert-equal #:expect "a\\'b"
                             #:got (javascript-string "a'b"))
               (assert-equal #:expect "a\\\\b"
                             #:got (javascript-string "a\\b"))
               (let ((page (markup (torikomi-page G_
                                                  #:new-url "https://x/a'b.png"))))
                 (assert-contains #:expect page
                                  #:got (javascript-string "a'b.png"))))
         (test "the form posts where the controller listens"
               #:shuffle? #f
               (assert-contains #:expect success-page #:got "action=\"/sink-file\"")
               (assert-contains #:expect success-page #:got "name=\"file-url\"")
               (assert-contains #:expect success-page #:got "name=\"file-name\""))
         (test "a first visit is offered the API instead of an old result"
               #:shuffle? #f
               (assert-contains #:expect landing-page #:got "or from a script")
               (assert-contains #:expect landing-page #:got "/api/v1/sink-file")
               (assert-not-contains #:expect landing-page #:got "role=\"alert\""))
         (test "a result replaces the API card"
               #:shuffle? #f
               (assert-not-contains #:expect success-page
                                    #:got "or from a script")
               (assert-not-contains #:expect failure-page
                                    #:got "or from a script"))))

(define (spec)
  (veritas-run #:concurrent? #f #:shuffle? #f page-suite))
