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
;; The page is a room with the fog coming in: a handful of oversized, heavily
;; blurred washes of colour are fixed behind everything -- a fog blue, the warm
;; gold of a headland at dusk and a violet that belongs to neither -- and every
;; surface above them is a pane of frosted glass.  That is the whole visual
;; language: the colours are the Golden Gate's, the material is glass, and the
;; rest is typography and restraint.
;;
;; The page is a pure function of what the controller passes it: the
;; translations, what the reader typed and whether the last sink failed.  It
;; reaches for no file, no setting and no network, which is what lets the suite
;; render it and read it as the markup a browser is handed.
;;
;; Two things are deliberate and easy to undo by accident, so they are written
;; here rather than left to be inferred.  `hg-frost' is hygguile's frost layer
;; rather than olive's `backdrop-blur-*' utilities: the latter paint their blur
;; in the element's square box and leave a square patch of frost at every
;; rounded corner, which is exactly what a page of rounded panes cannot have.
;; And the page is serialized by hygguile's SXML writer rather than Artanis'
;; XML shorthand, because the washes behind the hero are childless elements and
;; a browser reading `<div />' takes it for an open tag.
;;
;; The theme is the reader's: a stored preference wins, the system preference is
;; the default, and a small script in the head applies either before the first
;; paint so a dark-theme reader never sees a flash of white.

;;; Code:

(define-module (app views index)
  #:use-module (ice-9 format)
  #:use-module (ice-9 string-fun)
  #:use-module (ice-9 textual-ports)
  #:use-module (hygguile hygguile)
  #:use-module (hygguile sxml)
  #:use-module (torikomi version)
  #:export (torikomi-page html-template render-page javascript-string))

;;; ====== Writing a page ======

(define (render-page page)
  "Serialize PAGE, a whole SXML document, to the HTML a browser is handed.

Hygguile's writer is used rather than Artanis' shorthand for the reason the
`div' that holds a wash has no children: the shorthand writes it as `<div />',
which a browser reading `text/html' never closes, so the rest of the document
becomes its content."
  (call-with-output-string
   (lambda (port) (sxml->xml page port))))

;; A URL is written into a JavaScript string literal, where a quote or a
;; backslash would end the literal early; both are escaped here so a copy button
;; can never be turned into executable code by the address it copies.
(define (javascript-string text)
  "TEXT escaped for use inside a single-quoted JavaScript string."
  (string-replace-substring
   (string-replace-substring (or text "") "\\" "\\\\")
   "'"
   "\\'"))

;; Artanis writes a page with text escaping off -- which is what keeps an
;; embedded stylesheet a stylesheet -- so a string that came from a reader, a
;; remote server or a URL is escaped here, before it becomes a node.  Attribute
;; values are escaped by the writer itself, and are passed unescaped.
(define (escape-html text)
  "TEXT with the characters that would end a text node escaped."
  (let ((text (if (string? text) text (format #f "~a" (or text "")))))
    (string-replace-substring
     (string-replace-substring
      (string-replace-substring
       (string-replace-substring
        (string-replace-substring text "&" "&amp;")
        "<"
        "&lt;")
       ">"
       "&gt;")
      "\""
      "&quot;")
     "'"
     "&#39;")))

;;; ====== The weather behind the glass ======
;;
;; Three colour washes fixed to the viewport, deep under everything and out of
;; the way of a pointer or a reader.  They are the "Golden Gate" of the design:
;; the cold blue of the fog, the gold of the headland at dusk, and a violet that
;; is the colour the two make where they meet.  Nothing frosts them on the way
;; out -- the panes above do the frosting -- so they are plain, heavy blurs.
(define (aurora-backdrop)
  `((div (@ (aria-hidden "true")
            (class ,(mk-class '(pointer-events-none fixed inset-0 z-0
                                                    overflow-hidden)))))
    (div (@ (class ,(mk-class '(absolute top-0 left-0
                                         w-128 h-128
                                         rounded-full blur-3xl
                                         bg-jeans-blue-500/25
                                         dark:bg-jeans-blue-700/25)))))
    (div (@ (class ,(mk-class '(absolute top-48 right-0
                                         w-128 h-128
                                         rounded-full blur-3xl
                                         bg-tawny-500/25
                                         dark:bg-tawny-700/25)))))
    (div (@ (class ,(mk-class '(absolute bottom-0 left-64
                                         w-128 h-128
                                         rounded-full blur-3xl
                                         bg-china-violet-500/25
                                         dark:bg-china-violet-700/25)))))))

;;; ====== Small pieces of the room ======

;; The frosted pill the header and the hero wear around short labels: a pane of
;; its own, rounded all the way, and soft enough that a two-rem pill is not all
;; blur.
(define (frosted-pill content)
  `(span (@ (class ,(mk-class '(hg-frost hg-frost-pill inline-flex
                                items-center rounded-full border-2
                                border-stone-500/25 dark:border-onyx-100/25
                                bg-stone-100/75 dark:bg-onyx-900/75
                                px-3 py-1 text-sm font-medium
                                text-onyx-700 dark:text-stone-300))))
         ,content))

;; The theme control.  It does not name itself in words, so it carries the name
;; for assistive technology and the tooltip a pointer gets; the two glyphs are
;; the whole affordance.  `js-only' is hygguile's contract: with scripting off
;; the button is hidden, because it would be a control that does nothing.
(define (theme-toggle)
  `(button (@ (type "button")
              (onclick "hygguileToggleDarkTheme()")
              (aria-label "switch between the light and dark theme")
              (title "switch between the light and dark theme")
              (class ,(mk-class '(js-only hg-frost hg-frost-pill
                                          cursor-pointer select-none
                                          rounded-full border-2
                                          border-stone-500/25
                                          dark:border-onyx-100/25
                                          bg-stone-100/75 dark:bg-onyx-900/75
                                          shadow-sm px-3 py-1
                                          transition-colors duration-200
                                          focus-visible:outline-2
                                          focus-visible:outline-offset-2
                                          outline-onyx-500))))
     (span (@ (class ,(mk-class '(flex flex-row items-center gap-1))))
           ,(icon #:type 'sun
                  #:icon-css '(text-md text-tawny-700 dark:text-tawny-300))
           ,(icon #:type 'moon
                  #:icon-css '(text-md text-china-violet-700
                               dark:text-china-violet-300)))))

(define (site-header G_)
  "The floating bar: who this is, where the source is, and the theme control."
  (glass-panel
   `((div (@ (class ,(mk-class '(flex flex-row flex-wrap items-center
                                        justify-between gap-3 w-full))))
          (a (@ (href "/")
                (class ,(mk-class '(flex flex-row items-center gap-2
                                            no-underline))))
             ,(icon #:type 'sparkle
                    #:icon-css '(text-xl text-jeans-blue-700
                                 dark:text-jeans-blue-300))
             (span (@ (class ,(mk-class '(font-bold text-lg
                                                   text-onyx-900
                                                   dark:text-stone-100))))
                   "torikomi")
             (span (@ (class ,(mk-class '(text-sm font-light
                                                  text-onyx-500
                                                  dark:text-stone-500))))
                   "取り込み"))
          (div (@ (class ,(mk-class '(flex flex-row items-center gap-2))))
               (a (@ (href ,torikomi-homepage)
                     (target "_blank")
                     (rel "noopener")
                     (class ,(mk-class '(flex flex-row items-center gap-1
                                                 no-underline text-sm
                                                 font-medium
                                                 text-onyx-700
                                                 dark:text-stone-300
                                                 hover:text-jeans-blue-700
                                                 dark:hover:text-jeans-blue-300
                                                 px-2 py-1 rounded-xl
                                                 transition-colors duration-200))))
                  ,(icon #:type 'code #:icon-css '(text-md))
                  (span "source"))
               ,(theme-toggle))))
   #:tag 'header
   #:position '(sticky top-3 z-48)
   #:rounding '(rounded-2xl)
   #:shadow '(shadow-lg)
   #:padding '(px-4 py-2 md:px-5)
   #:classes '(w-full)
   #:content-classes '(w-full)))

;;; ====== The first screen ======

(define (hero-text-column G_)
  "The words of the first screen, kept as its own column."
  `(div (@ (class ,(mk-class '(flex flex-col gap-4 grow min-w-0))))
        (div (@ (class ,(mk-class '(flex flex-row flex-wrap items-center gap-2))))
             ,(frosted-pill (G_ "files · archives · libraries"))
             ,(frosted-pill (G_ "free software")))
        ,(h1 (list "torikomi "
                   `(span (@ (class ,(mk-class '(font-light))))
                          "取り込み"))
             #:color '(hg-gradient-text)
             #:size '(text-4xl md:text-5xl)
             #:weight '(font-black))
        ,(p (G_ "a quiet place to sink files from the web into a directory of your own: give it a URL, and it brings the bytes home with a name and a type that make sense.")
            #:weight '(font-light)
            #:size '(text-md md:text-lg)
            #:color '(text-onyx-500 dark:text-stone-500))
        (div (@ (class ,(mk-class '(flex flex-row flex-wrap gap-4 pt-1))))
             ,(hero-feature G_ 'globe (G_ "any URL"))
             ,(hero-feature G_ 'tag (G_ "a name from the bytes"))
             ,(hero-feature G_ 'brackets-curly (G_ "form and JSON")))))

(define (hero-figure)
  "The mark, in a pane of its own so it reads as an object rather than a logo."
  `(figure (@ (class ,(mk-class '(shrink-0 self-center))))
           (div (@ (class ,(mk-class '(hg-frost hg-frost-soft p-3
                                              rounded-3xl border-2
                                              border-stone-500/25
                                              dark:border-onyx-100/25
                                              bg-stone-100/75
                                              dark:bg-onyx-900/75
                                              shadow-lg))))
                (img (@ (class ,(mk-class '(w-24 h-auto rounded-2xl)))
                        (src "https://jointhefreeworld.org/static-assets/torikomi/torikomi-logo-small.png")
                        (alt "torikomi"))))))

(define (hero-section G_)
  "What torikomi is, on a pane of near-white glass with the fog drifting in it.

The washes are the same three colours as the backdrop, but stronger and moving:
each drifts at its own pace and none of them is in step with the others, so the
glass has something of its own to catch rather than reading as a flat card laid
on a flat page."
  (glass-panel
   `((div (@ (class ,(mk-class '(flex flex-col md:flex-row md:items-center
                                        md:justify-between gap-6))))
          ,(hero-text-column G_)
          ,(hero-figure)))
   #:tint '(bg-stone-100/75 dark:bg-onyx-900/75)
   #:frost 3
   #:rounding '(rounded-3xl)
   #:padding '(p-6 sm:p-10)
   #:drift? #t
   #:washes (list (glass-wash '(bg-jeans-blue-500/50 w-96 h-96 top-0 left-4)
                              #:delay -6
                              #:pace 44
                              #:distance '(3 -2))
                  (glass-wash '(bg-tawny-500/50 w-96 h-96 top-1/2 left-1/3)
                              #:delay -18
                              #:pace 56
                              #:distance '(-2 2))
                  (glass-wash '(bg-china-violet-500/50 w-96 h-96
                                                    bottom-0 right-4)
                              #:delay -30
                              #:pace 38
                              #:distance '(-3 -2)))
   #:content-classes '(flex flex-col gap-5)))


(define (hero-feature G_ icon-name label)
  `(div (@ (class ,(mk-class '(flex flex-row items-center gap-2
                                       text-sm font-light
                                       text-onyx-500 dark:text-stone-500))))
        ,(icon #:type icon-name
               #:icon-css '(text-md text-jeans-blue-700
                            dark:text-jeans-blue-300))
        (span ,label)))

;;; ====== The form ======

(define* (form-section G_ #:key file-url file-name)
  (glass-panel
   `((div (@ (class ,(mk-class '(flex flex-col gap-4))))
          ,(h2 (G_ "sink a file")
               #:size '(text-2xl md:text-3xl)
               #:weight '(font-bold))
          ,(p (G_ "Paste the address of the file you want to keep.  The name is optional: leave it empty and torikomi reads one from the response and the URL.")
              #:weight '(font-light)
              #:size '(text-sm)
              #:color '(text-onyx-500 dark:text-stone-500))
          (form (@ (method POST)
                   (action "/sink-file")
                   (class ,(mk-class '(flex flex-col gap-4 pt-1))))
                ,(input #:label (G_ "File URL (required):")
                        #:placeholder (G_ "Enter the file's URL here")
                        #:type 'url
                        #:required #t
                        #:name 'file-url
                        #:value (or file-url "")
                        #:input-css '(p-4 min-w-64 md:min-w-128
                                          rounded-xl
                                          border-stone-500/25
                                          dark:border-onyx-100/25
                                          dark:text-stone-300
                                          bg-stone-100/75
                                          dark:bg-onyx-900/75
                                          border-2 shadow-md font-sans))
                ,(input #:label (G_ "File name (optional):")
                        #:placeholder
                        (G_ "Enter the file's name to save the file as")
                        #:type 'text
                        #:required #f
                        #:name 'file-name
                        #:value (or file-name "")
                        #:input-css '(p-4 min-w-64 md:min-w-128
                                          rounded-xl
                                          border-stone-500/25
                                          dark:border-onyx-100/25
                                          dark:text-stone-300
                                          bg-stone-100/75
                                          dark:bg-onyx-900/75
                                          border-2 shadow-md font-sans))
                (div (@ (class ,(mk-class '(flex flex-row flex-wrap
                                                    items-center gap-3
                                                    pt-1))))
                     ,(icon-button #:icon 'download-simple
                                   #:content (G_ "sink the file")
                                   #:type 'submit
                                   #:background '(bg-jeans-blue-500/90
                                                  dark:bg-jeans-blue-700/90)
                                   #:hover-background '(hover:bg-jeans-blue-700
                                                        dark:hover:bg-jeans-blue-700)
                                   #:border-color '(border-jeans-blue-500/50
                                                    dark:border-jeans-blue-700/50)
                                   #:color '(text-stone-100)
                                   #:icon-css '(text-stone-100 text-md))
                     (span (@ (class ,(mk-class '(text-sm font-light
                                                          text-onyx-500
                                                          dark:text-stone-500))))
                           ,(G_ "it lands in the sink directory of this deployment"))))))
   #:frost 3
   #:rounding '(rounded-3xl)
   #:padding '(p-6 sm:p-8)
   #:content-classes '(flex flex-col gap-4)))

;;; ====== What happened to the last sink ======

(define* (notice #:key title body tone)
  "A frosted notice: a tinted pane, a coloured glyph and the two lines of text.

It is built here rather than with the framework's `alert' because the colours
that component names (a claret, a coral, a mantis) are not in this project's
palette, and a notice whose classes are missing from the stylesheet is a notice
that reads as a plain box."
  (let ((success? (eq? tone 'success)))
    `(div (@ (role ,(if success? "status" "alert"))
             (class ,(mk-class
                      (append
                       '(hg-frost hg-frost-pill rounded-2xl border-2 p-4
                                  flex flex-row items-start gap-3
                                  shadow-sm)
                       (if success?
                           '(bg-asparagus-500/25 border-asparagus-500/50)
                           '(bg-orange-500/25 border-orange-500/50))))))
          ,(icon #:type (if success? 'check-circle 'warning-octagon)
                 #:icon-css (if success?
                                '(text-xl shrink-0 text-asparagus-700
                                  dark:text-asparagus-300)
                                '(text-xl shrink-0 text-orange-700
                                  dark:text-orange-300)))
          (div (@ (class ,(mk-class '(flex flex-col gap-1 min-w-0))))
               (strong (@ (class ,(mk-class '(text-md font-semibold
                                                       text-onyx-900
                                                       dark:text-stone-100))))
                       ,title)
               ,(p body
                   #:weight '(font-light)
                   #:size '(text-sm)
                   #:color '(text-onyx-700 dark:text-stone-300))))))

(define (copy-button url)
  (icon-button #:content "copy"
               #:icon 'clipboard
               #:on-click (format #f "navigator.clipboard.writeText('~a')"
                                  (javascript-string url))))

(define* (outcome-section G_ #:key error file-url file-name new-url)
  "The result of the last sink, if there was one.

A failure and a success are both panes of glass: the alert colour is in the
border, the tint and the glyph, and the text stays the page's own ink so it is
readable in either theme.  A successful address is a pill of its own with a copy
button, because the one thing a reader does with it is take it somewhere else."
  (if (or error new-url file-url file-name)
      (list
       (glass-panel
        `((div (@ (class ,(mk-class '(flex flex-col gap-4))))
               ,@(if error
                     (list (notice #:title (G_ "could not sink the file")
                                   #:body (escape-html error)
                                   #:tone 'danger))
                     '())
               ,@(if new-url
                     (list
                      (notice #:title (G_ "sunk")
                              #:body (G_ "the file is waiting at the address below")
                              #:tone 'success)
                      `(div (@ (class ,(mk-class '(hg-frost hg-frost-pill
                                                          flex flex-row
                                                          flex-wrap
                                                          items-center gap-3
                                                          rounded-2xl border-2
                                                          border-stone-500/25
                                                          dark:border-onyx-100/25
                                                          bg-stone-100/75
                                                          dark:bg-onyx-900/75
                                                          p-3 shadow-sm))))
                            (span (@ (class ,(mk-class '(text-sm font-medium
                                                                 text-onyx-700
                                                                 dark:text-stone-300))))
                                  ,(G_ "public url"))
                            (span (@ (class ,(mk-class '(min-w-0 break-all))))
                                  ,(mono new-url
                                         #:size '(text-sm)
                                         #:weight '(font-light)
                                         #:color '(text-jeans-blue-700
                                                   dark:text-jeans-blue-300)))
                            ,(copy-button new-url)))
                     '())
               ,@(if file-name
                     (list `(small (@ (class ,(mk-class '(text-sm font-light
                                                                 text-onyx-500
                                                                 dark:text-stone-500))))
                                   ,(format #f "~a ~a"
                                            (G_ "given file-name:")
                                            (escape-html file-name))))
                     '())
               ,@(if file-url
                     (list `(small (@ (class ,(mk-class '(text-sm font-light
                                                                 text-onyx-500
                                                                 dark:text-stone-500))))
                                   ,(format #f "~a ~a"
                                            (G_ "given file-url:")
                                            (escape-html file-url))))
                     '())))
        #:frost 3
        #:rounding '(rounded-3xl)
        #:padding '(p-6 sm:p-8)
        #:content-classes '(flex flex-col gap-4)))
      '()))

;;; ====== The API, for the reader who came to script it ======

(define (api-section G_)
  (glass-panel
   `((div (@ (class ,(mk-class '(flex flex-col gap-3))))
          ,(h3 (G_ "or from a script")
               #:size '(text-lg)
               #:weight '(font-bold))
          ,(p (G_ "The same sink is one POST away.  The API answers JSON, says why a fetch failed in words, and keeps the status it answered with.")
              #:weight '(font-light)
              #:size '(text-sm)
              #:color '(text-onyx-500 dark:text-stone-500))
          (div (@ (class ,(mk-class '(hg-frost hg-frost-pill
                                              rounded-2xl border-2
                                              border-stone-500/25
                                              dark:border-onyx-100/25
                                              bg-stone-100/75
                                              dark:bg-onyx-900/75
                                              p-3 overflow-x-auto
                                              shadow-sm))))
               ,(mono "curl --json '{\"file-url\": \"https://example.org/pic.png\"}' https://this-host/api/v1/sink-file"
                      #:size '(text-sm)
                      #:weight '(font-light)
                      #:color '(text-onyx-700 dark:text-stone-300)
                      #:mono-classes '(font-mono whitespace-nowrap)))
          (a (@ (href "/api/v1/version")
                (class ,(mk-class '(text-sm font-medium no-underline
                                            text-jeans-blue-700
                                            dark:text-jeans-blue-300
                                            hover:text-china-violet-300
                                            transition-colors duration-200))))
             ,(G_ "the API says which version it is"))))
   #:frost 3
   #:rounding '(rounded-3xl)
   #:padding '(p-6 sm:p-8)
   #:content-classes '(flex flex-col gap-3)))

;;; ====== The last pane ======

(define (footer-section G_)
  (glass-panel
   `((div (@ (class ,(mk-class '(flex flex-row flex-wrap items-center
                                        justify-between gap-3))))
          (div (@ (class ,(mk-class '(flex flex-col gap-1))))
               (span (@ (class ,(mk-class '(text-sm font-medium
                                                   text-onyx-700
                                                   dark:text-stone-300))))
                     ,(format #f "torikomi ~a" torikomi-version))
               (span (@ (class ,(mk-class '(text-sm font-light
                                                   text-onyx-500
                                                   dark:text-stone-500))))
                     ,(G_ "λ powered by Lisp (Guile Scheme)")))
          (div (@ (class ,(mk-class '(flex flex-row flex-wrap items-center
                                              gap-3))))
               (a (@ (href ,torikomi-homepage)
                     (target "_blank")
                     (rel "noopener")
                     (class ,(mk-class '(text-sm font-medium no-underline
                                                 text-onyx-700
                                                 dark:text-stone-300
                                                 hover:text-jeans-blue-700
                                                 dark:hover:text-jeans-blue-300
                                                 transition-colors duration-200))))
                  ,(string-replace-substring torikomi-homepage
                                             "https://"
                                             ""))
               ,(mono (get-short-commit-sha)
                      #:size '(text-sm)
                      #:weight '(font-light)
                      #:color '(text-onyx-500 dark:text-stone-500)))))
   #:rounding '(rounded-2xl)
   #:shadow '(shadow-md)
   #:padding '(px-5 py-4)
   #:content-classes '(w-full)))

;;; ====== The whole page ======

(define* (torikomi-page G_
                        #:key file-url file-name new-url error)
  (html-template G_
                 #:body (list (site-header G_)
                              (hero-section G_)
                              (form-section G_
                                            #:file-url file-url
                                            #:file-name file-name)
                              (outcome-section G_
                                               #:error error
                                               #:file-url file-url
                                               #:file-name file-name
                                               #:new-url new-url)
                              (if (or error new-url file-url file-name)
                                  '()
                                  (api-section G_))
                              (footer-section G_))))

;; Applied before the first paint rather than on DOMContentLoaded, so a reader
;; who chose the dark theme never sees the light one flash by.  A stored
;; preference wins; with none, the system preference decides; with neither the
;; page is light, which is the framework's default.
(define theme-bootstrap
  (string-append
   "try{"
   "var t=localStorage.getItem('data-theme');"
   "if(!t&&window.matchMedia&&window.matchMedia('(prefers-color-scheme: dark)').matches){t='dark'}"
   "if(t==='dark'||t==='light'){document.documentElement.setAttribute('data-theme',t)}"
   "}catch(e){}"))

(define* (html-template G_
                        #:key (title "torikomi")
                        (description "torikomi sinks files from the web into a directory of your own.")
                        body)
  (list
   doctype-html
   `(html (@ (lang "en"))
          (head (title ,title)
                ,@(hygguile-recommended-meta)
                (meta (@ (name "description") (content ,description)))
                (meta (@ (name "theme-color")
                         (media "(prefers-color-scheme: light)")
                         (content "#f5f5f4")))
                (meta (@ (name "theme-color")
                         (media "(prefers-color-scheme: dark)")
                         (content "#171717")))
                (meta (@ (property "og:title") (content ,title)))
                (meta (@ (property "og:description") (content ,description)))
                ,@(hygguile-recommended-resources)
                (link (@ (rel "shortcut icon")
                         (href "/favicon.ico")
                         (type "image/x-icon"))
                      "")
                (link (@ (rel "icon")
                         (href "/favicon.ico")
                         (type "image/x-icon"))
                      "")
                (link (@ (rel "stylesheet")
                         (href "/css/torikomi.olive.min.css"))
                      "")
                (script ,theme-bootstrap))
          (body (@ (class ,(mk-class '(min-h-screen
                                       bg-stone-100 dark:bg-onyx-900
                                       font-sans relative
                                       overflow-x-hidden))))
                ,(aurora-backdrop)
                (div (@ (class ,(mk-class '(relative z-10
                                                   flex min-h-screen flex-col))))
                     (div (@ (class ,(mk-class '(w-full max-w-256
                                                        mx-auto
                                                        px-3 md:px-6
                                                        py-6 md:py-8
                                                        flex flex-col
                                                        gap-6))))
                          ,@body))))))
