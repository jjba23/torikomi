;; torikomi
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

(define-module (maak)
  #:use-module (maak maak)
  #:use-module ((ice-9 rdelim) #:select (read-line))
  ;; What the release tasks read the tree with: a file that carries a copy of
  ;; the version is rewritten through a regular expression.  The DSL
  ;; re-exports the file helpers, but not the regexp one.
  #:use-module (ice-9 regex)
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
  (time-machine-manifest-shell
   (list "guile" "-L" "./lib" "-L" "."
         "-c" "'((@ (ares server) run-nrepl-server))'")))

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
                                     "--exts"
                                     (string-join (map symbol->string
                                                       hot-reload-file-types)
                                                  ",")
                                     "--on-busy-update=restart"
                                     "--shell" "bash"
                                     "--watch" "." "--"
                                     "maak" "server")))

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
  ;; Nothing listening is not a failure, so the command is allowed to say so
  ;; instead of the task dying on `fuser''s non-zero exit.
  (run (list "fuser" "-k" (~ "~a/tcp" http-port))
       #:allow-failure? #t)
  (run (list "sleep" "1")))

(define (server)
  "Target to start the torikomi server with the default configuration."
  (kill-server)
  (time-machine-manifest-shell (list "art" "work")))

(define (production-server)
  "Target to start the torikomi server with the production configuration."
  (kill-server)
  (time-machine-manifest-shell (list "art" "work"
                                     "-c" "conf/production.conf")))

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
   (list "guile" "--fresh-auto-compile"
         "-L" "./lib" "-L" "." "-L" "./test"
         "-c"
         "'(begin (setlocale LC_ALL \"C.UTF-8\") (use-modules (veritas runner)) (run-tests))'")))

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
  '(("README.org" . "torikomi version ([0-9]+\\.[0-9]+\\.[0-9]+)")
    ("VISION.md" . "on Guile Scheme, at ([0-9]+\\.[0-9]+\\.[0-9]+)")))

(define (torikomi-version-library)
  "This checkout's `(torikomi version)' module, loaded on demand.

The load path is extended with the `lib' of the checkout rather than with one
named by the caller, so that the module these tasks read is the one the tree
holds and not one installed elsewhere."
  (unless (file-exists? version-source)
    (task-error "no ~a here" #:args (list version-source)
                #:hint "Run maak from the root of a torikomi checkout."))
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
                  (~ "~a/~a" directory version-source))))
    (unless (file-exists? file)
      (task-error "no ~a in ~a" #:args (list version-source directory)
                  #:hint "Name the checkout's root as DIRECTORY."))
    (let ((found (string-match
                  "torikomi-version[ \t\n]+\"([0-9]+\\.[0-9]+\\.[0-9]+)\""
                  (read-file file))))
      (unless found
        (task-error "~a does not define torikomi-version as a version"
                    #:args (list file)
                    #:hint "Write the version there as a string, `X.Y.Z'."))
      (match:substring found 1))))

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
        (~ "~a/~a" directory file)))

  (define (read-text file)
    (let ((full (path file)))
      (if (file-exists? full)
          (read-file full)
          (task-error "sync-version: no ~a in ~a"
                      #:args (list file directory)
                      #:hint "Name the checkout's root as DIRECTORY."))))

  (define (write-text file text)
    (write-file (path file) text))

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

  ;; ---- The commit and the tag --------------------------------------------
  ;;
  ;; The git wrappers take `#:directory', so a release of another checkout
  ;; commits there rather than wherever maak was started from.

  (define (changes-to-commit?)
    "Return whether anything tracked differs from the last commit."
    (not (string=? ""
                   (string-trim-both
                    (git-output (list "diff" "--name-only" "HEAD")
                                #:directory repo)))))

  (define (commit-release message)
    "Commit every tracked change as the release MESSAGE."
    (unless (git (list "commit" "--all" "-m" message)
                 #:directory repo #:allow-failure? #t)
      (task-error "sync-version: git commit failed, so nothing was tagged"
                  #:hint "Resolve what git refused in the checkout, then run the task again.")))

  (define (tag-release version)
    "Tag the current commit as the release VERSION."
    (unless (git (list "tag" (~ "v~a" version))
                 #:directory repo #:allow-failure? #t)
      (task-error "sync-version: `git tag v~a' failed; the release was committed, but not tagged"
                  #:args (list version)
                  #:hint "Tag the commit by hand, or remove it and run the task again.")))

  (let* ((version (checkout-version directory))
         (tag (~ "v~a" version)))
    ;; A tree that is not a checkout has nothing to commit and nothing to tag,
    ;; and a release that was half made is worse than one that was refused.
    (unless (file-exists? (path ".git"))
      (task-error "sync-version: ~a is not a git checkout, so there is nothing to commit or tag"
                  #:args (list directory)
                  #:hint "Run the task in a checkout, or name one as DIRECTORY."))
    ;; The tag is looked for among the checkout's tags rather than asked for
    ;; with `show-ref --verify', so a refusal can name the release that is
    ;; already there and nothing else.
    (when (member tag (git-tags #:directory repo))
      (task-error "sync-version: ~a is already released as ~a; bump ~a first"
                  #:args (list version tag version-source)
                  #:hint "Raise the version in the version file, then run the task again."))
    (for-each (lambda (site)
                (when (sync-copy! site version)
                  (log-info "Wrote ~a into ~a." version (car site))))
              version-sites)
    (if (changes-to-commit?)
        (let ((message (~ "chore: Release v~a" version)))
          (commit-release message)
          (tag-release version)
          (log-info "Committed `~a' and tagged ~a." message tag))
        (begin
          (tag-release version)
          (log-info "Nothing to commit; tagged ~a at the current commit."
                    tag)))))

;; ====== Fetching the project's own resources ======

(define (test-local-api-call)
  "Test out a local REST API call."
  ;; `file-url=...' comes after the program, so it is one argument to `http'
  ;; rather than a shell assignment: no shell is needed, and none is used.
  (run (list "http" "POST" "localhost:50027/api/v1/sink-file"
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
  (curl-download
   "https://raw.githubusercontent.com/jjba23/olive-css/trunk/resources/css/torikomi.olive.min.css"
   #:output "./pub/css/torikomi.olive.min.css"))

;; ====== Agent skills ======

;; AGENTS.md is generated, never edited by hand.  The section has two halves:
;; the data below, which is this project's, and the task itself, which is not.
;; Another repository copies the whole section and replaces the data - the
;; header, the pinned skills (repository, commit, path, licence) and the
;; practices - and `maak agents' writes its own AGENTS.md.  Regeneration is
;; deterministic: the same pins and the same text produce the same file, byte
;; for byte, and it needs nothing but curl.  The skill URLs assume GitHub, so a
;; skill hosted elsewhere needs a URL of its own.

(define ponytail-commit
  "96608e078b2d5ea607c5c3b8b5a54d1c1fba6846")

(define tdd-commit
  "22f0b463e7a5e579904dd6211a520321035526f7")

;; Name, repository, commit, the path the repository keeps the skill at and the
;; licence.  A skill arrives whole: trimming it means scanning for headings, and
;; such a scan cannot tell a heading from a `##' line inside a code fence.
(define agent-skills
  (list (list "ponytail"
              "DietrichGebert/ponytail"
              ponytail-commit
              "skills/ponytail/SKILL.md"
              "MIT")
        (list "test-driven-development"
              "obra/superpowers"
              tdd-commit
              "skills/test-driven-development/SKILL.md"
              "MIT")))

(define agent-skills-dir
  "reports/agent-skills")

(define agents-header
  "# AGENTS.md

Generated by `maak agents` from the pinned skills and the practices in
`maak.scm`; edit that task, never this file.  The pins and the text are the whole
input, so regenerating gives the same document.  The repository's own rules win
over general advice, and the narrowest rule here wins over the broadest.
")

;; Practices this project keeps.  They are short on purpose: a rule a reader
;; checks in a second is a rule that gets followed.  The pinned skills are the
;; long form of the same habits.
(define agent-practices
  (list
   "## Documentation

- Every user-visible change reaches the documentation: the page that owns the
  feature, the manual page for a flag or an environment variable, and the
  release notes under the unreleased heading.
- Keep the table of contents in step with the headings.  A section with no entry
  is a section nobody finds.
- The guide is Org: one `*` heading per page, `**` for sections, `#+TITLE` and
  `#+EMAIL` at the top, a `CUSTOM_ID` on anything linked from elsewhere, and
  `file:` links between pages.
- Explain why and when, never what: the code already says what.  A docstring's
  first line works as a summary on its own.
- Spell an identifier the way the code spells it - the exact name, not a
  description of it.
- An example must run as written, copied from a real invocation.
- No promises about the future and no changelog in the guide; history lives in
  the release notes.
"
   "## Security

- No secrets in the tree.  Tokens, keys and passwords arrive through the
  environment, and no recipe, workflow or example embeds one.
- Validate at the edge: anything from a file, a report, a path or a subprocess
  is untrusted until it has been checked.
- Never build a shell string out of data.  Tasks pass argument lists, and Guile
  calls `(system \"program\" \"arg\")` or `open-pipe*`, never a command
  assembled with `string-append`.
- Do not `eval` or `read` input you did not write; parse with `(json)` or a
  reader built for the format.
- Escape what leaves the process: a name that came from input is escaped when
  it is written to XML, HTML or a data file.
- Fail closed.  A file that cannot be read is an error, not an empty result.
- Input never chooses the path of a written file; writes stay inside the
  directory reserved for them.
- A dependency is a security decision: it must be needed, MIT compatible and
  pinned.
- Report a vulnerability privately, not in a public issue.
"
   "## Performance

- Measure first.  A before and after belongs in the benchmark, and a speedup
  claimed without a number is not a speedup.
- Prefer not doing the work: cache it, skip it, batch it, or delete the call,
  before making the call faster.
- Then the algorithm, then the data structure (hash table, vector), then the
  micro-optimisation.  In that order, for that reason.
- Guile specifics: keep module resolution and long `assoc` chains out of loops,
  use `#:declarative?` modules and compiled `.go` files at startup, and reach
  for `statprof` instead of guessing where the time goes.
- A shortcut that buys speed costs clarity; it gets a measurement and a
  `shortcut:` comment saying what it costs and when to revisit it.
- Coverage instrumentation is slow by design: iterate without it, and measure
  before finishing.
"
   "## Architecture decisions

- A decision that is expensive to reverse gets a short record: the context, the
  decision, the consequences, and the alternatives that lost.  A small decision
  belongs in the commit body instead.
- Two paragraphs beat a design document; record the choice while it is still a
  choice, not after it has become a fact.
- An accepted record is not rewritten.  Supersede it with a new one and link the
  two directions.
- The record lives next to its subject: the documentation for anything a user
  would notice, the release notes for the release-level result.
- Changes to the public API, a file format, the pipeline or the licence get this
  treatment at a minimum in the commit body.
"
   "## Semantic versioning

- The project follows SemVer 2.0.0 for its public API: the exported functions,
  the CLI flags and environment variables, and the shape of its file formats.
- A breaking change bumps MAJOR, a new feature MINOR, a fix PATCH.  A new export
  is MINOR; removing or changing one is MAJOR.
- One version string, named everywhere it appears: the source, the build
  recipes, the manual page and the packaging.
- A release is a dated release-notes section, an annotated `vX.Y.Z` tag on the
  release commit, and a packaging checksum updated afterwards from the published
  archive.
"
   "## Conventional commits

- `type(scope): summary`, imperative, lower case, no full stop, about seventy
  characters.
- Types in use: `feat`, `fix`, `perf`, `refactor`, `test`, `docs`, `build`, `ci`,
  `chore`.  A `!` after the type or a `BREAKING CHANGE:` footer marks a MAJOR
  change, and says what breaks.
- The subject says what changed.  The body says why, and what was rejected.
- One logical change per commit: a refactor and a fix travel apart, so either
  can be reverted alone.
- Run the full validation task before committing, and never commit a red suite
  without saying so in the message.
- Reference the issue in the footer - `Closes #12` - not in the subject.
"
   "## Functional programming and immutability

- Pure functions in the core, effects at the edges.  Whatever touches the file
  system or the clock sits at the edge; the core does not.
- Prefer `let` and new values to `set!`.  Build results with `map`, `filter`,
  `fold` and named `let`, not with index loops that push into a list.
- A record is a value: construct a new one instead of mutating a shared one, and
  pass configuration as arguments or parameters rather than as globals.
- Handle an exception at the boundary: catch it there, turn it into a result
  record, and let the caller decide what it means.
- A function that both computes and prints is two functions.
- Temporary effects - a changed directory, a bound environment variable - go
  through `dynamic-wind`.
- Prefer the expression style: `if` and `cond` that return a value, not a branch
  that assigns one.
"
   "## Do not reinvent the wheel

- Guile's standard library first: `(ice-9 ...)` for the runtime, `(srfi srfi-1)`
  for lists, `(srfi srfi-9)` for records, `(srfi srfi-13)` for strings, `(json)`
  for JSON.  The project already depends on all of them.
- Then this codebase: read the existing modules before writing a helper, and use
  the one that is nearly right instead of adding a second one.
- A new dependency needs a reason the standard library cannot meet, a licence
  the project can carry, and a paragraph in the commit body.
- Prefer deleting a special case to writing code that handles it.
- The best diff removes lines and keeps the behaviour; the second best is a
  small diff that is obvious a year later.
"))

(define (slurp path)
  "Return the whole of @var{path} as a string."
  (call-with-input-file path
    (lambda (port)
      (let loop ((lines '())
                 (line (read-line port)))
        (if (eof-object? line)
            (string-concatenate-reverse lines)
            (loop (cons (string-append line "\n") lines)
                  (read-line port)))))))

(define (fetch-skill name repository commit path)
  "Download one skill pinned at @var{commit}, into the reports tree.

  Returns the skill's text."
  (let ((target (~ "~a/~a.md" agent-skills-dir name))
        (url (~ "https://raw.githubusercontent.com/~a/~a/~a"
                repository commit path)))
    (run (list "curl" "--fail" "--silent" "--show-error" "--location"
               "--output" target url)
         #:verbose? #t)
    (slurp target)))

(define (agents)
  "Regenerate AGENTS.md from the pinned skills and the practices."
  (run (list "mkdir" "-p" agent-skills-dir))
  ;; Every download happens before the file is opened, so a fetch that fails
  ;; leaves the previous AGENTS.md in place rather than a half-written one.
  (let ((skills (map (lambda (skill)
                       (append skill
                               (list (fetch-skill (list-ref skill 0)
                                                  (list-ref skill 1)
                                                  (list-ref skill 2)
                                                  (list-ref skill 3)))))
                     agent-skills)))
    (call-with-output-file "AGENTS.md"
      (lambda (port)
        (display agents-header port)
        (for-each (lambda (skill)
                    (format port
                            "~%## ~a~%~%`~a` at `~a`, `~a`, ~a licensed.~%~%"
                            (list-ref skill 0)
                            (list-ref skill 1)
                            (list-ref skill 2)
                            (list-ref skill 3)
                            (list-ref skill 4))
                    (display (list-ref skill 5) port))
                  skills)
        (for-each (lambda (practice)
                    (newline port)
                    (display practice port))
                  agent-practices)))))
