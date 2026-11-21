;; torikomi
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Putting a file from a URL into a directory sounds like one call to curl, and
;; the first version of this module nearly was: it asked curl for the body,
;; read a few headers, and wrote the bytes under the name it guessed.  What
;; that misses is everything that happens when the network is not perfect and
;; the URL is not friendly:
;;
;;   * the response may not be a 200, and the status line may not be the first
;;     one -- a redirect leaves one block of headers per hop;
;;   * the name may arrive in a `Content-Disposition' header, may contain
;;     slashes, NULs or 400 characters, and two requests may race for it;
;;   * the transfer may fail halfway, and a partial file is worse than none;
;;   * the remote may be briefly unreachable, or a gateway may be starting;
;;   * the body may be larger than the disk the service runs on.
;;
;; Each of those is handled here rather than in a controller, and the result is
;; a `sink-result' record -- a success carrying the name, path, address and
;; size, or a failure carrying an HTTP status and a sentence a reader can act
;; on.  `fetch-file' is kept for callers that want the old contract: it returns
;; the public URL and raises on failure.
;;
;; The helpers are exported on purpose.  They are where the decisions are, and
;; the suite under test/veritas/unit reads them directly instead of standing up
;; a server to observe a filename.

;;; Code:

(define-module (torikomi torikomi)
  #:use-module (srfi srfi-1)            ;List processing
  #:use-module (srfi srfi-9)            ;Records
  #:use-module (ice-9 exceptions)       ;Conditions and raising them
  #:use-module (rnrs bytevectors)       ;Bytevector handling
  #:use-module (ice-9 format)           ;String formatting
  #:use-module (ice-9 iconv)            ;Header decoding
  #:use-module (ice-9 regex)            ;Content-Disposition
  #:use-module (ice-9 time)             ;Timestamps in the log
  #:use-module (ice-9 string-fun)       ;String manipulation
  #:use-module (ice-9 binary-ports)     ;Binary IO
  #:use-module (web uri)                ;URL parsing
  #:use-module (curl)                   ;Guile-curl bindings
  #:use-module (uuid generate)          ;UUID generation
  #:use-module (torikomi preferences)   ;Deployment settings
  #:use-module (torikomi version)       ;What this program is
  #:export (;; The failures.
            &sink-error make-sink-error sink-error? sink-error-status
            sink-error-reason sink-error-message sink-error-upstream-status
            ;; What a sink attempt answers with.
            <sink-result> sink-result? sink-result-ok? sink-result-status
            sink-result-message sink-result-file-name sink-result-path
            sink-result-public-url sink-result-bytes
            sink-result-upstream-status sink-result->alist
            ;; The entry points.
            sink-file fetch-file
            ;; URLs.
            valid-url? validate-url parse-uri
            ;; Responses.
            http-status-line http-status-code http-ok? header-value
            content-type-of parse-content-subtype extension-from-content-type
            find-extension-in-headers extension-from-url
            content-disposition-filename
            ;; Names.
            sanitize-filename sanitize-extension with-extension
            basename-from-url choose-basename choose-extension
            resolve-unique-filename write-download!
            ;; Retrying.
            retryable-status? retryable-error? retry-delay))

;;; ====== Logging ======

(define (log level format-string . arguments)
  "Write one line to the error port, stamped with the time and LEVEL.

The standard output of an Artanis worker is not a place to look for a
diagnosis: the server's own chatter goes there, and a log line written to it is
lost among startup messages.  The error port is what a service manager
captures, so everything torikomi has to say about a fetch goes there."
  (format (current-error-port)
          "~a torikomi ~a: ~a~%"
          (strftime "%Y-%m-%dT%H:%M:%S%z" (localtime (current-time)))
          level
          (apply format #f format-string arguments)))

(define (log-info format-string . arguments)
  (apply log "info" format-string arguments))

(define (log-warning format-string . arguments)
  (apply log "warning" format-string arguments))

;;; ====== Failures ======

;; A sink failure carries the status the HTTP caller should see, a reason a
;; caller or a test can branch on, a message a person can read, and the upstream
;; status when the failure was the remote server's answer.
(define-exception-type &sink-error &error
  make-sink-error
  sink-error?
  (status sink-error-status)
  (reason sink-error-reason)
  (message sink-error-message)
  (upstream-status sink-error-upstream-status))

(define-record-type <sink-result>
  (make-sink-result ok? status message file-name path public-url bytes
                    upstream-status)
  sink-result?
  (ok? sink-result-ok?)
  (status sink-result-status)
  (message sink-result-message)
  (file-name sink-result-file-name)
  (path sink-result-path)
  (public-url sink-result-public-url)
  (bytes sink-result-bytes)
  (upstream-status sink-result-upstream-status))

(define (sink-result->alist result)
  "RESULT as an association list a JSON writer can serialize.

`url' is the address the file was sunk to.  `new-url' is the same address under
the name the first version of the API used, and is kept so that a client
written against it does not have to change."
  (if (sink-result-ok? result)
      `((ok . #t)
        (file-name . ,(sink-result-file-name result))
        (url . ,(sink-result-public-url result))
        (new-url . ,(sink-result-public-url result))
        (bytes . ,(sink-result-bytes result)))
      `((ok . #f)
        (error . ,(sink-result-message result))
        ,@(let ((upstream (sink-result-upstream-status result)))
            (if upstream
                `((upstream-status . ,upstream))
                '())))))

;;; ====== Reading a response ======

(define (header-lines headers)
  "HEADERS, the header block libcurl returned, split into non-empty lines."
  (if (or (not headers) (string-null? headers))
      '()
      (filter (lambda (line)
                (positive? (string-length (string-trim-both line))))
              (string-split (string-replace-substring headers "\r\n" "\n")
                            #\newline))))

(define (http-status-line headers)
  "The last HTTP status line in HEADERS, or #f.

libcurl is asked for the headers of the transfer and returns one block per
response when it follows a redirect, so the first status line is the redirect
and the last one is the response whose body arrived.  Reading the first would
accept a `301' whose file then failed to download, or reject a redirect chain
that ended in a `200'."
  (let loop ((lines (header-lines headers)) (found #f))
    (cond ((null? lines) found)
          ((string-prefix-ci? "HTTP/" (car lines))
           (loop (cdr lines) (car lines)))
          (else (loop (cdr lines) found)))))

(define (http-status-code status-line)
  "The numeric status code of STATUS-LINE, or #f.

Only a whole number is a status: `HTTP/1.1' has no code, and a version number
that happens to parse as `1.1' is not one either."
  (and status-line
       (let ((parts (string-split (string-trim-both status-line) #\space)))
         (and (>= (length parts) 2)
              (let ((code (string->number (cadr parts))))
                (and code (integer? code) (exact? code) code))))))

(define (http-ok? status)
  "Whether STATUS is a 2xx code."
  (and (integer? status) (>= status 200) (< status 300)))

(define (final-header-lines headers)
  "The header lines of the response that ended the transfer.

Everything after the last status line: the headers of earlier redirects are
dropped, so a `Content-Type' of a redirect page cannot be mistaken for the one
of the file.  Without a status line at all every line is returned, which is
what lets `header-value' still find a header in a hand-written block."
  (let loop ((lines (header-lines headers)) (current '()))
    (cond ((null? lines) (reverse current))
          ((string-prefix-ci? "HTTP/" (car lines))
           (loop (cdr lines) '()))
          (else (loop (cdr lines) (cons (car lines) current))))))

(define (header-value headers name)
  "The value of header NAME in the final response, or #f."
  (let ((prefix (string-append (string-downcase name) ":")))
    (let loop ((lines (final-header-lines headers)))
      (cond ((null? lines) #f)
            ((string-prefix-ci? prefix (car lines))
             (string-trim-both (substring (car lines) (string-length prefix))))
            (else (loop (cdr lines)))))))

(define (content-type-of headers)
  "The `Content-Type' of the final response, or #f."
  (header-value headers "content-type"))

;;; ====== Deciding an extension ======

(define (parse-uri url)
  "URL as a URI, or #f when it is not one.

`string->uri' signals a malformed URL by throwing, and a URL that a caller
typed is not trusted input; every caller here wants the same answer -- no URI
-- rather than an exception in the middle of naming a file."
  (guard (condition (else #f))
    (string->uri url)))

(define (ascii-alphanumeric? character)
  "Whether CHARACTER is an ASCII letter or digit."
  (or (char-numeric? character)
      (and (char>=? character #\a) (char<=? character #\z))
      (and (char>=? character #\A) (char<=? character #\Z))))

(define (sanitize-extension extension)
  "EXTENSION as a safe file extension, or #f when it is not one.

An extension is only ever appended to a name, so it is held to letters and
digits and a short length: no dots, slashes, spaces, or anything a filesystem
might read as more than an extension."
  (let ((extension (and extension
                        (string-downcase (string-trim-both extension)))))
    (and extension
         (positive? (string-length extension))
         (<= (string-length extension) 10)
         (every ascii-alphanumeric? (string->list extension))
         extension)))

;; The media types worth naming exactly.  Everything else falls back to its
;; subtype (`image/webp' -> `webp'), which is right often enough and is then
;; sanitized.
(define content-type-extensions
  '(("application/atom+xml" . "atom")
    ("application/epub+zip" . "epub")
    ("application/gzip" . "gz")
    ("application/javascript" . "js")
    ("application/json" . "json")
    ("application/ld+json" . "jsonld")
    ("application/msword" . "doc")
    ("application/octet-stream" . "bin")
    ("application/ogg" . "ogg")
    ("application/pdf" . "pdf")
    ("application/rss+xml" . "rss")
    ("application/rtf" . "rtf")
    ("application/vnd.ms-excel" . "xls")
    ("application/vnd.ms-powerpoint" . "ppt")
    ("application/vnd.oasis.opendocument.spreadsheet" . "ods")
    ("application/vnd.oasis.opendocument.text" . "odt")
    ("application/vnd.openxmlformats-officedocument.presentationml.presentation"
     . "pptx")
    ("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
     . "xlsx")
    ("application/vnd.openxmlformats-officedocument.wordprocessingml.document"
     . "docx")
    ("application/wasm" . "wasm")
    ("application/x-7z-compressed" . "7z")
    ("application/x-bzip2" . "bz2")
    ("application/x-rar-compressed" . "rar")
    ("application/x-tar" . "tar")
    ("application/xhtml+xml" . "xhtml")
    ("application/xml" . "xml")
    ("application/zip" . "zip")
    ("audio/flac" . "flac")
    ("audio/mpeg" . "mp3")
    ("audio/ogg" . "ogg")
    ("audio/wav" . "wav")
    ("audio/webm" . "weba")
    ("audio/x-wav" . "wav")
    ("font/otf" . "otf")
    ("font/ttf" . "ttf")
    ("font/woff" . "woff")
    ("font/woff2" . "woff2")
    ("image/avif" . "avif")
    ("image/bmp" . "bmp")
    ("image/gif" . "gif")
    ("image/heic" . "heic")
    ("image/jpeg" . "jpg")
    ("image/png" . "png")
    ("image/svg+xml" . "svg")
    ("image/tiff" . "tiff")
    ("image/vnd.microsoft.icon" . "ico")
    ("image/webp" . "webp")
    ("image/x-icon" . "ico")
    ("text/css" . "css")
    ("text/csv" . "csv")
    ("text/html" . "html")
    ("text/markdown" . "md")
    ("text/plain" . "txt")
    ("text/tab-separated-values" . "tsv")
    ("text/xml" . "xml")
    ("video/mp4" . "mp4")
    ("video/mpeg" . "mpeg")
    ("video/ogg" . "ogv")
    ("video/quicktime" . "mov")
    ("video/webm" . "webm")
    ("video/x-matroska" . "mkv")
    ("video/x-msvideo" . "avi")))

(define (parse-content-subtype value)
  "The subtype of a Content-Type VALUE, or #f.

`image/jpeg; charset=utf-8' -> `jpeg'.  A value without a slash, or with an
empty subtype, is not a media type and has no subtype."
  (and value
       (let* ((media (string-downcase
                      (string-trim-both (car (string-split value #\;)))))
              (parts (string-split media #\/)))
         (and (= (length parts) 2)
              (positive? (string-length (cadr parts)))
              (cadr parts)))))

(define (extension-from-content-type value)
  "The file extension a Content-Type VALUE names, or #f.

The exact media type is looked up first, then its subtype; a subtype is
stripped of the `x-' prefix older servers use and of a `+xml'-style suffix, so
`image/svg+xml' is `svg' even if it were not in the table."
  (let ((media (and value
                    (string-downcase
                     (string-trim-both (car (string-split value #\;))))))
        (subtype (parse-content-subtype value)))
    (and media
         subtype
         (or (assoc-ref content-type-extensions media)
             (let* ((subtype (if (string-prefix? "x-" subtype)
                                 (substring subtype 2)
                                 subtype))
                    (plus (string-contains subtype "+"))
                    (subtype (if plus (substring subtype 0 plus) subtype)))
               (sanitize-extension subtype))))))

(define (find-extension-in-headers headers)
  "The extension the response headers name, or \"bin\"."
  (or (extension-from-content-type (content-type-of headers)) "bin"))

(define (extension-from-url url)
  "The extension URL itself ends in, or #f."
  (let* ((uri (parse-uri url))
         (path (and uri (uri-path uri)))
         (segment (and path (basename path)))
         (dot (and segment (string-rindex segment #\.))))
    (and dot
         (> dot 0)
         (< dot (- (string-length segment) 1))
         (sanitize-extension (substring segment (1+ dot))))))

;;; ====== Deciding a name ======

(define content-disposition-extended-pattern
  (make-regexp "filename\\*[ \t]*=[ \t]*([^;]+)" regexp/icase))

(define content-disposition-plain-pattern
  (make-regexp "filename[ \t]*=[ \t]*(\"[^\"]*\"|[^;]*)" regexp/icase))

(define (unquoted-value text)
  "TEXT without the quotes and whitespace a header may wrap it in."
  (let* ((text (string-trim-both (or text "")))
         (length (string-length text)))
    (if (and (>= length 2)
             (char=? (string-ref text 0) #\")
             (char=? (string-ref text (- length 1)) #\"))
        (substring text 1 (- length 1))
        text)))

(define (percent-decode text)
  "TEXT with its percent escapes decoded, or TEXT when they are malformed.

A header is not trusted input: a broken escape must not raise inside the
request that is merely trying to name a file."
  (guard (condition (else text))
    (uri-decode text)))

(define (extended-disposition-filename value)
  "The `filename*=' name of a Content-Disposition VALUE, or #f.

The value is `charset'lang'percent-encoded-name' (RFC 5987).  The name is
percent-decoded; the charset is not converted, which is right for the UTF-8 and
US-ASCII a server actually sends."
  (let ((match (regexp-exec content-disposition-extended-pattern value)))
    (and match
         (let* ((raw (string-trim-both (match:substring match 1)))
                (parts (string-split raw #\'))
                (encoded (if (>= (length parts) 3)
                             (string-join (list-tail parts 2) "'")
                             raw)))
           (and (positive? (string-length encoded))
                (percent-decode encoded))))))

(define (plain-disposition-filename value)
  "The plain `filename=' name of a Content-Disposition VALUE, or #f."
  (let ((match (regexp-exec content-disposition-plain-pattern value)))
    (and match
         (let ((name (unquoted-value (match:substring match 1))))
           (and (positive? (string-length name)) name)))))

(define (content-disposition-filename headers)
  "The file name a `Content-Disposition' header asks for, or #f.

Both forms are understood: the quoted `filename=\"name.png\"' and the RFC 5987
`filename*=UTF-8''name.png' a server sends for a name that is not ASCII."
  (let ((value (header-value headers "content-disposition")))
    (and value
         (or (extended-disposition-filename value)
             (plain-disposition-filename value)))))

(define (truncate-filename name)
  "NAME shortened to `filename-max-length', keeping its extension if it has one."
  (let ((limit (filename-max-length)))
    (if (<= (string-length name) limit)
        name
        (let* ((dot (string-rindex name #\.))
               (extension (and dot
                               (> dot 0)
                               (< (- (string-length name) dot) 16)
                               (substring name dot)))
               (base (if extension (substring name 0 dot) name))
               (room (- limit (if extension (string-length extension) 0))))
          (if (<= room 0)
              (substring name 0 limit)
              (string-append (substring base 0
                                        (min (string-length base) room))
                             (or extension "")))))))

(define (sanitize-filename name)
  "NAME as a safe base file name, or #f when nothing is left of it.

The last path component is taken whatever separators a caller sent, every
character that is not an ASCII letter, digit, dot, dash or underscore becomes a
dash, runs of dashes collapse, and leading and trailing dots and dashes are
dropped -- so no name can be `.`, `..', a hidden file, or a path that escapes
the sink directory.  A name longer than `filename-max-length' is shortened but
keeps its extension."
  (define (clean characters)
    (let loop ((rest characters) (out '()))
      (cond ((null? rest) (list->string (reverse out)))
            ((or (ascii-alphanumeric? (car rest))
                 (memv (car rest) '(#\. #\_)))
             (loop (cdr rest) (cons (car rest) out)))
            (else
             ;; Every other character, a dash included, becomes one dash.
             (loop (cdr rest)
                   (if (and (pair? out) (eqv? (car out) #\-))
                       out
                       (cons #\- out)))))))
  (let* ((last (and (string? name)
                    (basename (string-replace-substring name "\\" "/"))))
         (cleaned (and last (clean (string->list last))))
         (trimmed (and cleaned
                       (string-trim-both
                        cleaned
                        (lambda (character)
                          (or (char=? character #\.)
                              (char=? character #\-)))))))
    (and trimmed
         (positive? (string-length trimmed))
         (truncate-filename trimmed))))

(define (basename-from-url url)
  "The last path segment of URL as a safe base name, or #f."
  (let* ((uri (parse-uri url))
         (path (and uri (uri-path uri)))
         (segment (and path (basename path))))
    (and segment (sanitize-filename (percent-decode segment)))))

(define (extension-from-content-disposition headers)
  "The extension of the name a `Content-Disposition' header asks for, or #f."
  (let* ((name (content-disposition-filename headers))
         (dot (and name (string-rindex name #\.))))
    (and dot (> dot 0)
         (sanitize-extension (substring name (1+ dot))))))

;; The extensions a name is allowed to end in before a new one is appended:
;; `photo.jpg' saved as a PNG is `photo.png', not `photo.jpg.png'.
(define known-extensions
  '("7z" "atom" "avi" "avif" "bin" "bmp" "bz2" "css" "csv" "doc" "docx"
    "epub" "flac" "gif" "gz" "heic" "html" "ico" "jpeg" "jpg" "js" "json"
    "jsonld" "md" "mkv" "mov" "mp3" "mp4" "mpeg" "ods" "odt" "ogg" "ogv"
    "otf" "pdf" "png" "ppt" "pptx" "rar" "rss" "rtf" "svg" "tar" "tiff"
    "tsv" "ttf" "txt" "wasm" "wav" "weba" "webm" "webp" "woff" "woff2"
    "xhtml" "xls" "xlsx" "xml" "zip"))

(define (with-extension basename extension)
  "BASENAME with EXTENSION, replacing an extension it already ends in."
  (let* ((extension (or (sanitize-extension extension) "bin"))
         (dot (string-rindex basename #\.))
         (current (and dot
                       (> dot 0)
                       (string-downcase (substring basename (1+ dot))))))
    (if (and current (member current known-extensions))
        (string-append (substring basename 0 dot) "." extension)
        (string-append basename "." extension))))

(define (choose-basename url name headers)
  "The base name to save URL as: the caller's NAME, the response's suggestion,
the URL's own last segment, or `torikomi'."
  (or (sanitize-filename name)
      (sanitize-filename (content-disposition-filename headers))
      (basename-from-url url)
      "torikomi"))

(define (choose-extension url headers)
  "The extension to save URL with.

The media type is the server's statement about the bytes and wins; when it only
says `application/octet-stream' the header's own filename, then the URL, then
`bin' is used."
  (or (let ((extension (extension-from-content-type (content-type-of headers))))
        (and extension (not (string=? extension "bin")) extension))
      (extension-from-content-disposition headers)
      (extension-from-url url)
      "bin"))

;;; ====== Writing a file ======

(define (ensure-directory! path)
  "Create PATH and any of its parents that are missing."
  (unless (file-exists? path)
    (let ((parent (dirname path)))
      (unless (or (string=? parent path)
                  (string=? parent ".")
                  (string=? parent "")
                  (file-exists? parent))
        (ensure-directory! parent)))
    (catch 'system-error
      (lambda () (mkdir path))
      (lambda (key . arguments)
        (let ((errno (system-error-errno (cons key arguments))))
          ;; Another request may have created it between the check and the
          ;; mkdir; that is success, not failure.
          (unless (and (= errno EEXIST) (file-exists? path))
            (apply throw key arguments)))))))

(define (reserve-file! path)
  "Create PATH exclusively, returning whether the reservation was made.

O_EXCL is what makes two requests racing for one name fail rather than both
write it: the file a request reserved is the file only it will write."
  (let ((descriptor
         (catch 'system-error
           (lambda ()
             (open-fdes path (logior O_WRONLY O_CREAT O_EXCL) #o644))
           (lambda (key . arguments)
             (let ((errno (system-error-errno (cons key arguments))))
               (if (= errno EEXIST) #f (apply throw key arguments)))))))
    (if descriptor
        (begin (close-fdes descriptor) #t)
        #f)))

(define (uuid-suffixed name)
  "NAME with a UUID before its extension."
  (let ((dot (string-rindex name #\.)))
    (if (and dot (> dot 0))
        (format #f "~a-~a~a" (substring name 0 dot)
                (generate-string-uuid) (substring name dot))
        (format #f "~a-~a" name (generate-string-uuid)))))

(define (write-file-atomically! path body)
  "Write BODY to PATH through a temporary file in the same directory.

The temporary file is renamed over PATH once it is complete, so a reader never
sees a half-written file, and a failed write leaves neither a partial file nor
a temporary one behind."
  (let ((temporary (format #f "~a.part-~a" path (generate-string-uuid))))
    (dynamic-wind
      (lambda () #t)
      (lambda ()
        (call-with-output-file temporary
          (lambda (port) (put-bytevector port body))
          #:binary #t)
        (rename-file temporary path))
      (lambda ()
        (when (file-exists? temporary)
          (delete-file temporary))))))

(define (write-download! directory file-name body)
  "Write BODY into DIRECTORY as FILE-NAME, never replacing an existing file.

The name is reserved with O_EXCL, so two requests racing for one name cannot
both pick it, and a name already taken is retried with a UUID suffix.  A
reservation this call made is removed again if the write fails, so a failed
download does not leave an empty file for the next one to collide with.
Returns `(saved-name . path)'."
  (ensure-directory! directory)
  (let loop ((candidate file-name) (attempts 0))
    (if (>= attempts 100)
        (raise-exception
         (make-sink-error 500 'write-failed
                          "Could not find a free file name to save to."
                          #f))
        (let ((path (string-append (string-trim-right directory #\/)
                                   "/" candidate)))
          (if (reserve-file! path)
              (begin
                (guard (condition
                        (else
                         (when (file-exists? path) (delete-file path))
                         (raise-exception condition)))
                  (write-file-atomically! path body))
                (cons candidate path))
              (loop (uuid-suffixed file-name) (1+ attempts)))))))

(define* (resolve-unique-filename #:key dir filename extension)
  "A name in DIR for FILENAME.EXTENSION that is not taken yet.

The name is checked rather than reserved, so it is a hint for a caller that
writes immediately afterwards; `write-download!' is what a fetch uses, and it
reserves the name it returns."
  (let* ((extension (or (sanitize-extension extension) "bin"))
         (basename (with-extension (or (sanitize-filename filename)
                                       "torikomi")
                                   extension)))
    (let loop ((candidate basename))
      (if (file-exists? (string-append (string-trim-right dir #\/)
                                       "/" candidate))
          (loop (uuid-suffixed basename))
          candidate))))

;;; ====== Talking to the remote ======

(define (valid-url? url)
  "Whether URL is an http(s) URL with a host."
  (and (string? url)
       (let ((url (string-trim-both url)))
         (and (positive? (string-length url))
              (let ((uri (parse-uri url)))
                (and uri
                     (let ((scheme (uri-scheme uri)))
                       (and scheme
                            (member (symbol->string scheme)
                                    (allowed-url-schemes))
                            #t))
                     (let ((host (uri-host uri)))
                       (and host
                            (string? host)
                            (positive? (string-length host))))))))))

(define (validate-url url)
  "URL as a URI, or raise a 400 sink error saying why it cannot be fetched."
  (let ((url (and (string? url) (string-trim-both url))))
    (cond
     ((not (and url (positive? (string-length url))))
      (raise-exception (make-sink-error 400 'missing-url
                                        "A file URL is required."
                                        #f)))
     (else
      (let ((uri (parse-uri url)))
        (cond
         ((not uri)
          (raise-exception (make-sink-error 400 'invalid-url
                                            (format #f "~s is not a URL." url)
                                            #f)))
         ((not (let ((scheme (uri-scheme uri)))
                 (and scheme
                      (member (symbol->string scheme) (allowed-url-schemes)))))
          (raise-exception
           (make-sink-error
            400 'unsupported-scheme
            (format #f "Only ~a URLs can be sunk; ~s is not one."
                    (string-join (allowed-url-schemes) " and ")
                    url)
            #f)))
         ((not (let ((host (uri-host uri)))
                 (and host (string? host) (positive? (string-length host)))))
          (raise-exception (make-sink-error 400 'invalid-url
                                            (format #f "~s names no host." url)
                                            #f)))
         (else uri)))))))

(define (header-bytes->string headers)
  "HEADERS as a string, whatever guile-curl returned it as."
  (cond ((string? headers) headers)
        ((bytevector? headers) (bytevector->string headers "ISO-8859-1"))
        (else "")))

(define (transport-sink-error url)
  "The failure of a transfer that libcurl could not complete."
  (let* ((code (curl-error-code))
         (message (or (curl-error-string) "unknown error"))
         (too-large? (and (integer? code)
                          (= code CURLE_FILESIZE_EXCEEDED))))
    (make-sink-error (if too-large? 413 502)
                     (if too-large? 'too-large 'transport)
                     (format #f "Could not fetch ~a: ~a" url message)
                     #f)))

(define (configure-curl! handle url)
  "Point HANDLE at URL with the policy this deployment configured."
  (define (set option value)
    (curl-easy-setopt handle option value))
  (set 'url url)
  ;; The body is the body: libcurl's own `header' option would prepend the
  ;; response headers to it, while `perform' already returns them separately
  ;; (its third argument), which is what the parsing below reads.
  (set 'header #f)
  (set 'verbose #f)
  ;; A remote that closes the connection while libcurl writes must not raise
  ;; SIGPIPE and take the whole server process down with it.
  (set 'nosignal #t)
  ;; Only http and https, for the request and for every redirect it follows:
  ;; a redirect to `file:///etc/passwd' is refused by libcurl itself.
  (set 'protocols (logior CURLPROTO_HTTP CURLPROTO_HTTPS))
  (set 'redir-protocols (logior CURLPROTO_HTTP CURLPROTO_HTTPS))
  (set 'followlocation #t)
  (set 'maxredirs (curl-max-redirects))
  (set 'http-version 2)
  (set 'timeout (curl-timeout-seconds))
  (set 'connecttimeout (curl-connect-timeout-seconds))
  ;; libcurl refuses a response whose Content-Length is larger than this; a
  ;; chunked response has no length to refuse, which is why the body is
  ;; measured again when it arrives.
  (set 'maxfilesize (max-file-bytes))
  (set 'useragent (curl-user-agent))
  (set 'ssl-verifypeer (curl-verify-tls))
  (set 'ssl-verifyhost (curl-verify-tls))
  (when (curl-ca-bundle)
    (set 'cainfo (curl-ca-bundle))))

(define (perform-request url)
  "GET URL, returning `(headers body)'.

A transfer that libcurl could not complete raises a sink error: `perform' says
so by answering #f, and the reason has to be read before the handle is freed."
  (let ((handle (curl-easy-init)))
    (dynamic-wind
      (lambda () #t)
      (lambda ()
        (configure-curl! handle url)
        (let ((response (curl-easy-perform handle #t #t)))
          (if response
              (list (header-bytes->string (car response))
                    (cadr response))
              (raise-exception (transport-sink-error url)))))
      (lambda () (curl-easy-cleanup handle)))))

(define retryable-statuses
  '(408                              ;request timeout
    425                              ;too early
    429                              ;too many requests
    500 502 503 504))                ;the gateway's own failures

(define (retryable-status? status)
  "Whether a response with STATUS is worth asking for again."
  (and (integer? status)
       (if (memv status retryable-statuses) #t #f)))

(define (retryable-error? error)
  "Whether ERROR is a failure that another attempt may not repeat.

A refused connection, a timeout and a gateway that is still starting are
transient; a 404, a refused certificate and a body that is too large are not."
  (and (sink-error? error)
       (case (sink-error-reason error)
         ((transport bad-response) #t)
         ((http-status) (retryable-status?
                         (sink-error-upstream-status error)))
         (else #f))))

(define (retry-delay attempt)
  "The number of seconds to wait after failed ATTEMPT, which is 0-based."
  (min 60 (* (curl-retry-delay-seconds) (expt 2 attempt))))

(define (attempt-download url)
  "One attempt at fetching URL.

Returns `('ok headers body status)' or `('error . condition)'; failures are
values here so that the retry loop can look at them and decide."
  (guard (condition
          ((sink-error? condition) (cons 'error condition))
          (else (cons 'error (make-sink-error
                              502 'transport
                              (format #f "Could not fetch ~a: ~s" url
                                      condition)
                              #f))))
    (let* ((headers-and-body (perform-request url))
           (headers (car headers-and-body))
           (body (cadr headers-and-body))
           (status (http-status-code (http-status-line headers))))
      (cond
       ((not status)
        (cons 'error (make-sink-error
                      502 'bad-response
                      (format #f "~a answered without an HTTP status." url)
                      #f)))
       ((not (http-ok? status))
        (cons 'error (make-sink-error
                      502 'http-status
                      (format #f "~a answered with HTTP ~a." url status)
                      status)))
       ((> (bytevector-length body) (max-file-bytes))
        (cons 'error (make-sink-error
                      413 'too-large
                      (format #f "~a is larger than the ~a byte limit."
                              url (max-file-bytes))
                      status)))
       (else (list 'ok headers body status))))))

(define (download url)
  "Fetch URL, retrying transient failures; return `(headers body status)'."
  (let loop ((attempt 0))
    (let* ((outcome (attempt-download url))
           (kind (car outcome)))
      (if (eq? kind 'ok)
          (cdr outcome)
          (let ((error (cdr outcome)))
            (if (and (< attempt (curl-retries))
                     (retryable-error? error))
                (let ((delay (retry-delay attempt)))
                  (log-warning "~a; retrying in ~a second(s) (~a of ~a)"
                               (sink-error-message error)
                               delay
                               (1+ attempt)
                               (curl-retries))
                  (when (positive? delay) (sleep delay))
                  (loop (1+ attempt)))
                (raise-exception error)))))))

;;; ====== The entry points ======

(define* (sink-file #:key url name)
  "Download URL into the sink directory and answer with a `sink-result'.

Nothing about a failed fetch is raised to the caller: a bad URL, a refused
connection, a 404 from the remote, a body that is too large and a disk that
cannot be written are all ordinary outcomes of this service, and each is
described by the status and the message of the result.  The only failures that
escape are bugs."
  (guard (condition
          ((sink-error? condition)
           (log-warning "~a" (sink-error-message condition))
           (make-sink-result #f
                             (sink-error-status condition)
                             (sink-error-message condition)
                             #f #f #f #f
                             (sink-error-upstream-status condition)))
          (else
           (let ((message (format #f "torikomi could not sink the file: ~s"
                                  condition)))
             (log-warning "~a" message)
             (make-sink-result #f 500 message #f #f #f #f #f))))
    (let* ((uri (validate-url url))
           (url (uri->string uri)))
      (log-info "fetching ~a" url)
      (let* ((downloaded (download url))
             (headers (car downloaded))
             (body (cadr downloaded))
             (status (caddr downloaded))
             (basename (choose-basename url name headers))
             (extension (choose-extension url headers))
             (file-name (with-extension basename extension))
             (saved (write-download! (sink-directory) file-name body))
             (saved-name (car saved)))
        (log-info "sunk ~a (~a bytes) as ~a" url
                  (bytevector-length body) saved-name)
        (make-sink-result #t 200 #f saved-name (cdr saved)
                          (public-url saved-name)
                          (bytevector-length body) status)))))

(define* (fetch-file #:key url name)
  "Download URL into the sink directory and return its public URL.

The older contract, kept for callers that prefer an exception to a record: a
failure is raised as a sink error carrying the same status and message the
result would have carried."
  (let ((result (sink-file #:url url #:name name)))
    (unless (sink-result-ok? result)
      (raise-exception (make-sink-error (sink-result-status result)
                                        'sink
                                        (sink-result-message result)
                                        (sink-result-upstream-status result))))
    (sink-result-public-url result)))
