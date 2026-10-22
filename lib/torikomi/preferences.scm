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
;; Everything a deployment can decide about torikomi, in one place.
;;
;; The settings used to live in a hand-written `env.scm' at the root of the
;; checkout: the module `(torikomi env)' was imported by the code that fetched
;; files, and a checkout without that file could not load at all.  That is a
;; fragile way to run a service -- the file is not in the repository (it holds
;; deployment addresses), so a fresh clone, a test run and the CI job all
;; failed until somebody wrote one.
;;
;; Each setting is now a parameter with the value a fresh checkout should get,
;; read once from the deployment's environment when the module is loaded.  A
;; deployment that still has an `env.scm' keeps working: the bindings this
;; module knows about are read as defaults, so an existing installation only
;; needs to be restarted, not rewritten.  The environment variable always wins,
;; which is what makes a single command able to point a test at its own
;; temporary directory.
;;
;; Every number and flag is validated.  A deployment that writes
;; `TORIKOMI_CURL_TIMEOUT_SECONDS=soon' or `TORIKOMI_CURL_RETRIES=-1' gets the
;; project's value rather than a server that hangs or a loop that never ends:
;; a setting that does not mean anything cannot be allowed to mean anything.

;;; Code:

(define-module (torikomi preferences)
  #:use-module (ice-9 exceptions)
  #:use-module (ice-9 format)
  #:use-module (srfi srfi-1)
  #:use-module (torikomi version)
  #:export (deployment-setting
            deployment-number-setting
            deployment-boolean-setting
            deployment-size-setting
            parse-size
            legacy-binding
            sink-directory
            public-base-url
            public-url
            curl-timeout-seconds
            curl-connect-timeout-seconds
            curl-max-redirects
            curl-retries
            curl-retry-delay-seconds
            curl-verify-tls
            curl-ca-bundle
            curl-user-agent
            max-file-bytes
            filename-max-length
            allowed-url-schemes))

;;; ====== Reading a deployment's settings ======

(define (non-empty-string? value)
  "Whether VALUE is a string with something other than whitespace in it."
  (and (string? value)
       (positive? (string-length (string-trim-both value)))))

(define (setting-value value)
  "VALUE as a setting, or #f when it says nothing.

An empty value is read as no value at all: `TORIKOMI_BASE_URL=' in a unit file
means the deployment did not say, not that it wants an address of nothing."
  (cond
   ((not value) #f)
   ((string? value) (and (non-empty-string? value) (string-trim-both value)))
   (else value)))

(define (legacy-binding name)
  "The value the checkout's own `env.scm' binds NAME to, if that module is loaded.

The module is looked up rather than imported: it usually does not exist, and a
checkout without one is the normal case now.  `resolve-module' with `#:ensure
#f' answers #f instead of raising, and the whole lookup is guarded so that a
broken legacy file cannot stop the service from starting."
  (guard (condition (else #f))
    (let ((module (resolve-module '(torikomi env) #:ensure #f)))
      (and module
           (module-bound? module name)
           (let ((value (module-ref module name)))
             (if (procedure? value) (value) value))))))

(define* (deployment-setting variable #:optional legacy-name (default #f))
  "DEFAULT, or what the deployment set VARIABLE to -- or LEGACY-NAME's binding.

The environment variable is the deployment's word and wins; the legacy binding
is read only when it says nothing.  LEGACY-NAME is a symbol naming the old
`(torikomi env)' binding, if the project ever had one for this setting."
  (or (setting-value (getenv variable))
      (setting-value (and legacy-name (legacy-binding legacy-name)))
      default))

(define* (deployment-number-setting variable
                                    #:optional legacy-name
                                    (default #f)
                                    #:key (minimum 0) (maximum #f))
  "DEFAULT, or the whole number the deployment set VARIABLE to.

A value that is not a whole number in [MINIMUM, MAXIMUM] is not a setting at
all, so the project's own value is kept rather than a timeout of `soon' or a
retry count of minus one."
  (let* ((raw (deployment-setting variable legacy-name #f))
         (number (cond ((number? raw) raw)
                       ((string? raw) (string->number raw))
                       (else #f))))
    (if (and number
             (integer? number)
             (exact? number)
             (>= number minimum)
             (or (not maximum) (<= number maximum)))
        number default)))

(define (false-string? value)
  "Whether VALUE is a way a person writes `no'."
  (member (string-downcase (string-trim-both value))
          '("0" "false" "no" "off" "nil" "none" "disable" "disabled")))

(define* (deployment-boolean-setting variable
                                     #:optional legacy-name
                                     (default #f))
  "DEFAULT, or the flag the deployment set VARIABLE to.

`0', `false', `no', `off' and `disable' are false; every other non-empty value
is true.  An unreadable value is left as DEFAULT rather than guessed at.

A sentinel separates `the deployment said nothing' from `the deployment said
#f': the former keeps DEFAULT, which may itself be #t."
  (let ((raw (deployment-setting variable legacy-name 'unset)))
    (cond
     ((eq? raw 'unset) default)
     ((boolean? raw) raw)
     ((non-empty-string? raw) (not (false-string? raw)))
     (else default))))

(define* (deployment-size-setting variable
                                  #:optional legacy-name
                                  (default 0))
  "DEFAULT bytes, or the size the deployment set VARIABLE to.

A size may be written plainly (`1048576') or with a K, M, G or T suffix
(`256M'), which is how the value is documented.  A number that is not a
positive whole number of bytes is not a size, and DEFAULT is kept."
  (let ((raw (deployment-setting variable legacy-name #f)))
    (or (and raw (parse-size raw)) default)))

(define* (parse-size text #:optional (default #f))
  "TEXT as a whole number of bytes, with an optional K, M, G or T suffix."
  (let* ((text (and (string? text) (string-trim-both text)))
         (length (and text (string-length text))))
    (if (or (not length) (zero? length))
        default
        (let* ((last-char (string-ref text (- length 1)))
               (multiplier (case (char-upcase last-char)
                             ((#\K) 1024)
                             ((#\M) (expt 1024 2))
                             ((#\G) (expt 1024 3))
                             ((#\T) (expt 1024 4))
                             (else 1)))
               (number-text (if (= multiplier 1)
                                text
                                (substring text 0 (- length 1))))
               (number (string->number (string-trim-both number-text))))
          (if (and number
                   (integer? number)
                   (exact? number)
                   (positive? number))
              (* number multiplier)
              default)))))

;;; ====== Where a sunk file goes, and where it is served from ======

;; The directory a fetched file is written to, and the address a public URL
;; starts with.  `maak sink-dir' creates the former; `(torikomi torikomi)'
;; creates it too, the first time a file is sunk into it.
(define sink-directory
  (make-parameter (deployment-setting "TORIKOMI_SINK_DIRECTORY"
                                     'torikomi-sink-file-directory
                                     "pub/tmp")))

(define public-base-url
  (make-parameter (deployment-setting "TORIKOMI_BASE_URL"
                                     'torikomi-sink-file-base-url
                                     "http://localhost:50027/tmp")))

(define (public-url file-name)
  "FILE-NAME as the address a reader fetches it from."
  (string-append (string-trim-right (public-base-url) #\/)
                 "/"
                 file-name))

;;; ====== How a fetch is made ======

(define curl-timeout-seconds
  (make-parameter (deployment-number-setting "TORIKOMI_CURL_TIMEOUT_SECONDS"
                                             'torikomi-curl-timeout-seconds
                                             60
                                             #:minimum 1)))

;; A request that connects and then stalls would otherwise sit until the whole
;; timeout expires before anything could retry it.
(define curl-connect-timeout-seconds
  (make-parameter (deployment-number-setting "TORIKOMI_CURL_CONNECT_TIMEOUT_SECONDS"
                                             #f
                                             15
                                             #:minimum 1)))

(define curl-max-redirects
  (make-parameter (deployment-number-setting "TORIKOMI_CURL_MAX_REDIRECTS"
                                             #f
                                             10
                                             #:minimum 0
                                             #:maximum 50)))

;; A transient failure -- a refused connection, a gateway that is still
;; starting, a rate limit -- is retried, with a delay that doubles each time.
;; `0' turns retrying off.
(define curl-retries
  (make-parameter (deployment-number-setting "TORIKOMI_CURL_RETRIES"
                                             #f
                                             2
                                             #:minimum 0
                                             #:maximum 10)))

(define curl-retry-delay-seconds
  (make-parameter (deployment-number-setting "TORIKOMI_CURL_RETRY_DELAY_SECONDS"
                                             #f
                                             1
                                             #:minimum 0
                                             #:maximum 60)))

;; Certificates are checked by default.  A deployment that fetches from a host
;; with a self-signed certificate has to say so explicitly, with
;; `TORIKOMI_CURL_VERIFY_TLS=0', rather than have every deployment of this
;; software quietly accept any certificate.
(define curl-verify-tls
  (make-parameter (deployment-boolean-setting "TORIKOMI_CURL_VERIFY_TLS"
                                              #f
                                              #t)))

;; The bundle guile-curl hands to libcurl.  `nss-certs' sets `SSL_CERT_FILE'
;; in the environment, so a Guix deployment usually needs nothing here; the
;; explicit variable is for a deployment that keeps its bundle elsewhere.
(define curl-ca-bundle
  (make-parameter (or (setting-value (getenv "TORIKOMI_CA_BUNDLE"))
                      (setting-value (getenv "SSL_CERT_FILE"))
                      (setting-value (getenv "CURL_CA_BUNDLE")))))

(define curl-user-agent
  (make-parameter (deployment-setting "TORIKOMI_USER_AGENT"
                                     #f
                                     (format #f "torikomi/~a"
                                             torikomi-version))))

;; The largest body torikomi will keep.  libcurl aborts a transfer whose
;; `Content-Length' is larger, and the body is checked again when it arrives,
;; so a chunked response without a length cannot fill the disk either.
(define max-file-bytes
  (make-parameter (deployment-size-setting "TORIKOMI_MAX_FILE_BYTES"
                                           #f
                                           (* 256 1024 1024))))

;; Names are shortened rather than rejected: a name is a hint, and a file with
;; a 300-character name cannot be written on every filesystem the service may
;; run on.
(define filename-max-length
  (make-parameter (deployment-number-setting "TORIKOMI_FILENAME_MAX_LENGTH"
                                             #f
                                             120
                                             #:minimum 16
                                             #:maximum 200)))

;; Only http and https are ever fetched.  A list that names nothing else is
;; still checked here, and the curl handle is restricted to the two protocols
;; as well, so a redirect to `file://' cannot be followed either.
(define allowed-url-schemes
  (make-parameter
   (let* ((named (deployment-setting "TORIKOMI_URL_SCHEMES" #f "http,https"))
          (wanted (filter (lambda (scheme)
                            (member scheme '("http" "https")))
                          (map (lambda (scheme)
                                 (string-downcase (string-trim-both scheme)))
                               (string-split named #\,)))))
     (if (null? wanted) '("http" "https") wanted))))
