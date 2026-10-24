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

(define-module (maak)
  #:use-module (maak maak)
  ;; What the release tasks read the tree with: a file that carries a copy of
  ;; the version is rewritten through a regular expression, and `get-string-all'
  ;; is how a file is read whole.  The DSL re-exports neither.
  #:use-module (ice-9 regex)
  #:use-module (ice-9 textual-ports)
  #:declarative? #t)

;; ====== Maak constants ======

;; The TCP port on which the web server will listen.  It is the same port
;; `conf/artanis.conf' names, and `kill-server' uses it to stop whatever is
;; already listening before a new server is started.
(define http-port
  50027)

(define hot-reload-file-types
  '(scm css js))

;; Where a fresh checkout writes the files it sinks, when the deployment has not
;; named a directory of its own.  This mirrors the default in
;; `(torikomi preferences)', which is the code that actually reads it.
(define project-sink-directory
  "pub/tmp")

(define (sink-directory)
  "The sink directory this deployment writes to."
  (let ((named (getenv "TORIKOMI_SINK_DIRECTORY")))
    (if (and named (positive? (string-length named))) named
        project-sink-directory)))

;; ====== Maak tasks ======

(define (repl)
  "Development REPL."
  (time-machine-manifest-shell '("guile -L ./lib -L ."
                                 "-c '((@ (ares server) run-nrepl-server))'")))

(define (default)
  "Default task to be run, list available tasks."
  (list-tasks))

(define (fmt)
  "Format Scheme source code files according to the Guix style guide."
  (run (list "find" "." "-maxdepth" "8" "-name" "*.scm" "-type" "f"
             "-exec" "guix" "style" "-f" "{}" ";")
       #:verbose? #t))

(define (hot-reload)
  "Hot-reloading developer's setup."
  (time-machine-manifest-shell (list "watchexec"
                                     "--clear"
                                     (~ "--exts ~a"
                                        (string-join (map symbol->string
                                                      hot-reload-file-types)
                                                     ","))
                                     "--on-busy-update=restart"
                                     "--shell bash"
                                     "--watch . --"
                                     "maak server")))

(define (hr)
  "Alias to hot-reloading."
  (hot-reload))

(define (dev)
  "Developer's setup."
  (hot-reload))

(define (kill-server)
  "Kill any running HTTP server in the same port.

The short wait afterwards is not politeness: a server that has been signalled
has not necessarily released the port by the time the next one binds it, and
the second bind then fails with an address already in use."
  ($ (list (~ "fuser -k ~a/tcp || true" http-port)))
  (run (list "sleep" "1")))

(define (server)
  "Target to start the torikomi server with the default configuration."
  (kill-server)
  (time-machine-manifest-shell '("art work")))

(define (production-server)
  "Target to start the torikomi server with the production configuration."
  (kill-server)
  (time-machine-manifest-shell '("art work -c conf/production.conf")))

(define (sink-dir)
  "Create the directory sunk files are written to.

The server creates it on the first fetch as well, so this is for a deployment
that wants to set its permissions before anything is sunk, or to check which
directory the configuration names without fetching anything."
  (mkdir-p (sink-directory))
  (log-info "Sink directory ready: ~a" (sink-directory)))

;; ====== The tests ======

(define (test)
  "Run the project's test suite.

The specs live under test/veritas/unit.  That is where the runner looks for
suites -- given the test root ./test, the module prefix `veritas' and the suite
name `unit' -- and it is also what their own `(veritas unit ...)' module names
resolve to on the load path below.

The run names the locale it reads in rather than inheriting one: Guile reads a
page by the locale in force, and this suite reads pages that hold characters
outside ASCII.  `C.UTF-8' is that name for a machine that has never generated a
locale -- a service, a container, and this project's own continuous
integration.  Naming it here is part of what the pinned manifest is for: a run
of the suite reads the same pages wherever the pipeline runs.

The specs are compiled rather than read from a cache.  A compiled spec
outlives the library it was compiled against -- Guile decides a compiled file
is still good by the spec's own text, and not by the macros and procedures that
text was compiled with -- so a spec compiled before `(veritas veritas)' changed
shape is loaded afterwards as if it still had the old one.  Compiling from
source every run costs a few seconds and makes the reading depend on the specs
alone, which is what a suite that is run to judge a change has to do."
  (time-machine-manifest-shell
   (list "guile --fresh-auto-compile -L ./lib -L . -L ./test"
         "-c '(begin (setlocale LC_ALL \"C.UTF-8\") (use-modules (veritas runner)) (run-tests))'")))

;; ====== The version, and its release ======
;;
;; The version is written by hand once, in lib/torikomi/version.scm, which is
;; what `maak version' prints.  Nothing else in the tree may name it: a file
;; that cannot read a Scheme module -- the manual -- goes in `version-sites'
;; below, and `sync-version' writes the version into it.
;;
;; The module is loaded on demand rather than imported at the top of this file.
;; Maak puts the directory the Maak file lives in on the load path and not the
;; `lib' beside it, so an import there would stop this file loading at all --
;; every task with it -- unless each run named `-L ./lib'.  Reading the module
;; out of `./lib' is also what makes the version the checkout's: a task run from
;; a shell whose load path names another torikomi still answers for the tree it
;; was started in.

(define version-source
  "lib/torikomi/version.scm")

;; Each site is a file and a regular expression matching one place in it where
;; the version is written, with the version itself as the first group.  Only
;; that group is replaced, so everything around it -- a sentence's wording, a
;; field's alignment -- stays the file's business rather than this list's.
(define version-sites
  '(("README.org" . "torikomi version ([0-9]+\\.[0-9]+\\.[0-9]+)")))

(define (torikomi-version-library)
  "This checkout's `(torikomi version)' module, loaded on demand.

The load path is extended with the `lib' of the checkout rather than with one
named by the caller, so that the module these tasks read is the one the tree
holds and not one installed elsewhere."
  (unless (file-exists? version-source)
    (error (format #f
                   "no ~a here; run maak from the root of a torikomi checkout"
                   version-source)))
  (unless (member "./lib" %load-path)
    (set! %load-path (cons "./lib" %load-path)))
  (resolve-module '(torikomi version) #:ensure #t))

(define (version)
  "Print the torikomi version this checkout is at."
  ((module-ref (torikomi-version-library)
               'print-version)))

(define* (checkout-version #:optional (directory "."))
  "The version the checkout in DIRECTORY is at, read from its own file.

The file is read as text rather than loaded as a module, which is what makes the
version the checkout's: the task is given a directory to work in, and the
reading has to come from there and not from whatever torikomi a load path
happens to name."
  (let ((file (if (string=? directory ".")
                  version-source
                  (string-append directory "/" version-source))))
    (unless (file-exists? file)
      (error (format #f "no ~a in ~a; name the checkout's root"
                     version-source directory)))
    (let ((found (string-match
                  "torikomi-version[ \t\n]+\"([0-9]+\\.[0-9]+\\.[0-9]+)\""
                  (call-with-input-file file get-string-all))))
      (unless found
        (error (format #f
                       "~a does not define torikomi-version as a version"
                       file)))
      (match:substring found 1))))

(define (git-exit directory . arguments)
  "The exit code git ended with, run in DIRECTORY with ARGUMENTS.

`system*' answers with the wait status rather than the exit code -- a command
that exited 1 reads as 256 -- so it is divided back down here, and a git that
could not be started at all reads as the 127 a shell would report.  The
arguments are a list rather than a command line, so a commit message with
spaces or quotes in it reaches git as one argument and no shell splits it
again."
  (let ((status (apply system* "git" "-C" directory arguments)))
    (if status (quotient status 256) 127)))

(define* (sync-version #:optional (directory "."))
  "Write the version into every file that cannot read it, then release it.

The version is written by hand once, in lib/torikomi/version.scm, which is what
`maak version' prints.  The files in `version-sites' cannot read a Scheme
module, so they carry copies, and this task rewrites them from that file.  Each
copy is found by a regular expression over the file and only the version inside
the match is replaced, so the rest of the file is left exactly as it was.

A release is then the whole ritual in one command: the copies are made to
agree, everything tracked that changed is committed as `chore: Release vX.Y.Z',
and that commit is tagged `vX.Y.Z'.  The commit is `git commit -am', so it takes
every tracked change in the tree rather than only the ones this task made;
commit anything unrelated first if it should not ride along.  A version whose
tag already exists is refused rather than committed again or retagged, and a
tree with nothing left to commit is tagged where it stands.

DIRECTORY is the checkout to work in, the current directory by default.  The
version is read from that checkout's own file rather than from the running
library, so the task releases the tree it was started in."
  (define repo directory)

  (define (path file)
    (if (string=? directory ".")
        file
        (string-append directory "/" file)))

  (define (read-text file)
    (if (file-exists? (path file))
        (call-with-input-file (path file) get-string-all)
        (error (format #f
                       "sync-version: no ~a in ~a; name the checkout's root"
                       file directory))))

  (define (write-text file text)
    (call-with-output-file (path file)
      (lambda (port) (display text port))))

  (define (rewrite text pattern version)
    "Return TEXT with the version PATTERN names replaced by VERSION."
    (regexp-substitute/global
     #f pattern text 'pre
     (lambda (match)
       (regexp-substitute/global #f "[0-9]+\\.[0-9]+\\.[0-9]+"
                                 (match:substring match 0)
                                 'pre version 'post))
     'post))

  (define (sync-copy! site version)
    "Write VERSION into the copy SITE names, and return whether it had to."
    (let* ((file (car site))
           (text (read-text file))
           (rewritten (rewrite text (cdr site) version)))
      (if (string=? text rewritten)
          #f
          (begin (write-text file rewritten) #t))))

  (let* ((version (checkout-version directory))
         (tag (string-append "v" version)))
    ;; A tree that is not a checkout has nothing to commit and nothing to tag,
    ;; and a release that was half made is worse than one that was refused.
    (unless (file-exists? (path ".git"))
      (error (format #f
                     "sync-version: ~a is not a git checkout, so there is nothing to commit or tag"
                     directory)))
    ;; `show-ref --quiet' answers with its exit status and prints nothing, which
    ;; `rev-parse --verify' does not: a release that is refused should say why
    ;; and nothing else.
    (when (zero? (git-exit repo "show-ref" "--verify" "--quiet"
                           (string-append "refs/tags/" tag)))
      (error (format #f
                     "sync-version: ~a is already released as ~a; bump ~a first"
                     version tag version-source)))
    (for-each (lambda (site)
                (when (sync-copy! site version)
                  (log-info "Wrote ~a into ~a." version (car site))))
              version-sites)
    (if (zero? (git-exit repo "diff" "--quiet" "HEAD"))
        (begin
          (unless (zero? (git-exit repo "tag" tag))
            (error (format #f
                           "sync-version: `git tag ~a' failed; nothing was released"
                           tag)))
          (log-info "Nothing to commit; tagged ~a at the current commit."
                    tag))
        (let ((message (format #f "chore: Release v~a" version)))
          (unless (zero? (git-exit repo "commit" "-am" message))
            (error "sync-version: git commit failed, so nothing was tagged"))
          (unless (zero? (git-exit repo "tag" tag))
            (error (format #f
                           "sync-version: `git tag ~a' failed; the release was committed, but not tagged"
                           tag)))
          (log-info "Committed `~a' and tagged ~a." message tag)))))

;; ====== Fetching the project's own resources ======

(define (test-local-api-call)
  "Test out a local REST API call."
  ($ '("http POST localhost:50027/api/v1/sink-file"
       "file-url=https://jointhefreeworld.org/static-assets/torikomi/torikomi-logo-small.png")))

(define (olive-css)
  "Refresh the Olive CSS the page is styled by.

The stylesheet is a *build artifact* of the olive-css project, generated from
its `torikomi-palettes' configuration; it is not edited here.  A page change
that needs a utility the build does not contain -- the frost and the washes use
several -- needs a fresh build in olive-css (`maak build' there) before this
task is run, or the classes it asks for simply will not exist.

`--fail' is what makes a 404 an error rather than a saved error page, and
`--location' follows the redirect a raw branch URL answers with; without either,
a broken download would be written over the stylesheet."
  ($ '("curl --fail --silent --show-error --location"
       "--output \"./pub/css/torikomi.olive.min.css\""
       "\"https://codeberg.org/jjba23/olive-css/raw/branch/trunk/resources/css/torikomi.olive.min.css\"")))
