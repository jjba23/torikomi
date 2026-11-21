;; torikomi
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; The development environment, pinned the way the project's sibling
;;; (~/Hacking/byggsteg) pins its own: the Scheme libraries are defined here,
;;; at the versions this tree is known to build and run against, so that a
;;; checkout is reproducible on any machine and the CI job that runs `maak test'
;;; tests the same code everywhere.
;;;
;;; The command-line tools are not an afterthought: `maak' drives `find',
;;; `fuser', `mkdir', `curl' and `guile' itself, so they are named here rather
;;; than borrowed from whatever the developer's profile happens to hold.

(use-modules (gnu packages)
             (guix packages)
             (gnu)
             (guix utils)
             (guix gexp)
             (guix git-download)
             (guix download)
             (guix build-system gnu)
             (guix build-system guile)
             (gnu packages admin)
             (gnu packages autotools)
             (gnu packages base)
             (gnu packages bash)
             (gnu packages compression)
             (gnu packages curl)
             (gnu packages emacs)
             (gnu packages gnupg)
             (gnu packages guile)
             (gnu packages guile-xyz)
             (gnu packages linux)
             (gnu packages nss)
             (gnu packages perl)
             (gnu packages pkg-config)
             (gnu packages rust-apps)
             (gnu packages texinfo)
             (gnu packages tls)
             (gnu packages vim)
             ((guix licenses)
              #:prefix license:))

;;; ====== The Scheme libraries ======

(define-public guile-uuid
  (package
    (name "guile-uuid")
    (version "0.9.1")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://codeberg.org/elb/guile-uuid.git")
             (commit (string-append "v" version))))
       (file-name (git-file-name name version))
       (sha256
        (base32 "01gza8zsjmazc02p9vm7pgidvfzdi786asc7c4r8cnjxdn3sigvd"))))
    (build-system guile-build-system)
    (native-inputs (list guile-3.0 guile-gcrypt))
    ;; 0.9.1 keeps its Guix recipe in the source tree, and the Guile build
    ;; system would compile it as library code and stop at `(guix gexp)'.
    (arguments
     (list
      #:phases
      #~(modify-phases %standard-phases
          (add-after 'unpack 'drop-packaging-recipe
            (lambda _
              (delete-file "guix.scm"))))))
    (home-page "https://codeberg.org/elb/guile-uuid")
    (synopsis "UUID generation and manipulation library for Guile Scheme")
    (description
     "This package implements RFC 9562 UUIDs, and can generate versions
1 and 3–8 from that specification. It also provides parsing for UUIDs in
standard hex-and-dash format of any variant and version. Simple routines for converting
between binary and hex-and-dash string UUIDs are included.")
    (license license:gpl3+)))

;;; Kracht is what `(kracht prelude)' brings the controllers and views: the
;;; little conveniences the project writes in, kept in one place rather than
;;; copied between files.
(define-public guile-kracht
  (package
    (name "guile-kracht")
    (version "0.3.8")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://codeberg.org/jjba23/kracht.git")
             (commit (string-append "v" version))))
       (file-name (git-file-name name version))
       (sha256
        (base32 "1v2n50hqwlihscl7f5y9hp815aznyrzzpk96whflqaqvjnzyxzb0"))))
    (build-system guile-build-system)
    (native-inputs (list guile-3.0))
    (arguments
     (list
      #:source-directory "src"))
    (home-page "https://codeberg.org/jjba23/kracht")
    (synopsis
     "Good prelude for Guile Scheme, an opt-in enhancement to the standard library")
    (description
     "Good prelude for Guile Scheme, an opt-in enhancement to the standard library. kracht means power/strength in the Dutch language, and is also a recursive acronym which stands for: KRACHT Reliable And Consistent Helper Tools")
    (license license:lgpl3+)))

;;; Hygguile is the component library the page is built from.  It is pinned
;;; here rather than taken from the channel so that the markup a deployment
;;; serves and the markup a test reads are the same markup.
(define-public guile-hygguile
  (package
    (name "guile-hygguile")
    (version "2.8.6")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://github.com/jjba23/hygguile.git")
             (commit (string-append "v" version))))
       (file-name (git-file-name name version))
       (sha256
        (base32 "11vdz9vfhxmsx89m59l2cv8j7gsfdh7yz1pnz639mrzkl8dj2qx4"))))
    (build-system guile-build-system)
    ;; guile-uuid pulls in guile-gcrypt at compile time: the UUID module opens
    ;; `(gcrypt random)' and `(gcrypt hash)' while it is being compiled, so the
    ;; crypt library has to be in the build environment and not only in the
    ;; profile a deployment runs.
    (native-inputs (list guile-uuid guile-gcrypt guile-3.0))
    (arguments
     (list
      #:source-directory "src"))
    (home-page "https://github.com/jjba23/hygguile")
    (synopsis "Web UI component library for Guile Scheme projects")
    (description
     "Hygguile is a library that allows you to create cozy web user-interfaces
using Guile Scheme, by defining an expressive domain-specific language (DSL),
and by leveraging the power of S-expressions, SXML and TailwindCSS.

The project aims to provide reusable, professional-looking and accessible
web components, whose names resemble the HTML counterparts, thus
easing the learning curve, and reducing the cognitive load.")
    (license license:expat)))

;;; Veritas is the test framework `maak test' runs.  Specs are discovered under
;;; test/veritas/unit and their suites are named `(veritas unit ...)', so the
;;; library is part of the development environment as much as it is a run-time
;;; dependency of the test task.
(define-public guile-veritas
  (package
    (name "guile-veritas")
    (version "1.4.5")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://github.com/jjba23/veritas.git")
             (commit (string-append "v" version))))
       (file-name (git-file-name name version))
       (sha256
        (base32 "1abf6vxhrw2q1g8xplqcd7xavn3dv59ir4d77xmpyds1mfijv338"))))
    (build-system guile-build-system)
    (arguments
     (list
      #:source-directory "src"))
    (native-inputs (list guile-3.0))
    (propagated-inputs (list guile-fibers guile-json-4))
    (home-page "https://github.com/jjba23/veritas")
    (synopsis "Testing framework for Guile")
    (description
     "Veritas is a testing framework for Guile with an @acronym{EDSL,
embedded domain specific language} to define test suites.  Emphasis is placed
on legible, maintainable tests.  Veritas shuffles tests and runs them
concurrently by default.")
    (license license:expat)))

;;; ====== The environment ======

(packages->manifest
 (list
  ;; The build and release tooling.
  (specification->package "make")
  (specification->package "gettext")

  ;; The API documentation: `dokgen' writes the chapter out of the modules'
  ;; docstrings, and `texi2any' renders it as one HTML page.  guile-dokgen is
  ;; defined by the jointhefreeworld channel channels.scm pins, so it is
  ;; resolved by name against the channels rather than imported here.
  (specification->package "guile-dokgen")
  texinfo

  ;; Guile and the libraries the source imports.
  guile-3.0-latest
  guile-uuid
  guile-ares-rs
  artanis
  guile-kracht
  guile-curl
  guile-gcrypt
  guile-hygguile
  guile-veritas

  ;; TLS trust anchors.  guile-curl asks libcurl to verify the peer and the
  ;; host by default (see `(torikomi preferences)'), which needs a bundle of
  ;; certificates in the environment; a deployment that only reads http still
  ;; gets the bundle, because the same server usually serves both.
  nss-certs

  ;; The command-line tools `maak' drives: `find' for fmt, `fuser' for
  ;; kill-server, `mkdir'/`rm' for the sink directory, `curl' for the
  ;; stylesheet, and bash to run all of it.
  coreutils
  findutils
  psmisc
  curl
  bash-minimal

  ;; Watching the tree while developing, and the editor `maak fmt' documents.
  watchexec
  emacs-no-x))
