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

(define-module (torikomi torikomi)
  #:use-module (srfi srfi-1) ;List processing (filter, etc.)
  #:use-module (rnrs bytevectors) ;Bytevector handling
  #:use-module (curl) ;Guile-curl bindings
  #:use-module (uuid generate) ;UUID generation
  #:use-module (ice-9 format) ;String formatting
  #:use-module (ice-9 string-fun) ;String manipulation
  #:use-module (ice-9 binary-ports) ;Binary IO
  #:use-module (torikomi env) ;Environment variables 
  #:export (fetch-file))

;;; ----------------------------------------------------------------------------
;;; Helper Functions
;;; ----------------------------------------------------------------------------

(define (assert-response-ok status-line)
  "Parses the HTTP status line and checks if the status code is 2xx.
   Raises an error if the status is outside the 200-299 range."
  ;; Example status line: "HTTP/1.1 200 OK"
  (let* ((parts (string-split status-line #\space))
         ;; The status code is typically the second element
         (status-code (string->number (cadr parts))))
    
    (unless (and status-code
                 (>= status-code 200)
                 (< status-code 300))
      (error (format #f "Error fetching URL. Unexpected HTTP status code: ~a"
                     (or status-code "unknown"))))))

(define (parse-content-subtype header-value)
  "Extracts the subtype from a Content-Type header value.
   Input: 'image/jpeg; charset=utf-8' -> Output: 'jpeg'.
   Defaults to 'bin' if parsing fails."
  (let* ((mime-type (string-trim-both (car (string-split header-value #\;))))
         (parts (string-split mime-type #\/)))
    (if (>= (length parts) 2)
        (cadr parts) ;Return subtype (e.g., "jpeg")
        "bin")))
 ;; Fallback

(define (find-extension-in-headers raw-headers)
  "Iterates through raw headers to find the Content-Type and derive a file extension.
   Returns 'bin' if no specific type is found."
  ;; Normalize newlines to handles \r\n vs \n consistency
  (let* ((headers-str (string-replace-substring raw-headers "\r\n" "\n"))
         (header-lines (string-split headers-str #\newline))
         ;; Look for the line starting with "content-type:" (case insensitive)
         (ct-line (find (lambda (line)
                          (string-prefix-ci? "content-type:" line))
                        header-lines)))
    
    (if ct-line
        (let ((value-part (cadr (string-split ct-line #\:))))
          (parse-content-subtype value-part)) "bin")))

(define* (resolve-unique-filename #:key dir filename extension)
  "Generates a file path. If the file already exists in 'dir', appends a UUID 
   to ensure uniqueness.
   
   Args:
     dir: Target directory path.
     filename: Base name derived from URL.
     extension: File extension (e.g., 'jpg')."
  (let* ((basename (format #f "~a.~a" filename extension))
         (full-path (format #f "~a/~a" dir basename)))
    
    (if (file-exists? full-path)
        ;; Collision detected: inject UUID
        (let* ((new-uid (generate-string-uuid))
               (new-name (format #f "~a-~a.~a" filename new-uid extension)))
          new-name)
        ;; No collision: use original name
        basename)))

;;; ----------------------------------------------------------------------------
;;; Main Export
;;; ----------------------------------------------------------------------------

(define* (fetch-file #:key url)
  "Downloads a file from the given URL using libcurl.
   
   It automatically determines the file extension based on Content-Type headers,
   handles file name collisions by appending a UUID, and saves the file to
   'torikomi-sink-file-directory'.
   
   Returns: The public URL of the saved file."
  (format #t "~%Fetching URL: ~a~%" url)

  (let ((handle (curl-easy-init)))
    (dynamic-wind
     ;; 1. Setup (noop here as init is done in let)
     (const #f)

     ;; 2. Execution Body
     (lambda ()
       ;; Configure Curl Options
       (curl-easy-setopt handle
                         'header #f)
       (curl-easy-setopt handle
                         'url url)
       (curl-easy-setopt handle
                         'verbose #f)
       (curl-easy-setopt handle
                         'ssl-verifyhost #f) ;TODO make into variable
       (curl-easy-setopt handle
                         'ssl-verifypeer #f) ;TODO make into variable
       (curl-easy-setopt handle
                         'maxredirs 10) ;TODO make into variable
       (curl-easy-setopt handle
                         'http-version 2)
       (curl-easy-setopt handle
                         'followlocation #t)
       (curl-easy-setopt handle
                         'timeout torikomi-curl-timeout-seconds)

       ;; Perform Request
       (let* ((response (curl-easy-perform handle #t #t))
              (headers (car response))
              (body (cadr response)))
         
         ;; Validate Response
         (assert-response-ok headers)

         (let* ((lili (last (string-split url #\/)))
                (last-url-piece (if (equal? "" lili) "torikomi" lili))
                ;; Extract extension from headers (e.g., "png")
                (ext-from-headers (find-extension-in-headers headers))
                ;; Clean the filename (remove existing extension if present in URL piece to avoid img.jpg.jpg)
                (clean-name (first (string-split last-url-piece #\.)))

                ;; Generate unique filename
                (final-filename (resolve-unique-filename #:dir
                                 torikomi-sink-file-directory
                                 #:filename clean-name
                                 #:extension ext-from-headers))

                (dest-path (format #f "~a/~a" torikomi-sink-file-directory
                                   final-filename))
                (public-url (format #f "~a/~a" torikomi-sink-file-base-url
                                    final-filename)))
           
           (format #t "Writing file to: ~a~%" dest-path)

           ;; Write to disk
           (call-with-output-file dest-path
             (lambda (port)
               (put-bytevector port body))
             #:binary #t)

           ;; Return the public URL
           public-url)))

     ;; 3. Cleanup (Guarantees handle is freed even on error)
     (lambda ()
       (curl-easy-cleanup handle)))))
