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

(define-module (torikomi fetch)
  #:use-module (torikomi env)
  #:use-module (web uri)
  #:use-module (web response)
  #:use-module (rnrs bytevectors)
  #:use-module (json)
  #:use-module (curl)
  #:use-module (ice-9 popen)
  #:use-module (ice-9 textual-ports)
  #:use-module (ice-9 time)
  #:use-module (ice-9 format)
  #:use-module (ice-9 string-fun)
  #:use-module (ice-9 iconv)
  #:use-module (ice-9 hash-table)
  #:use-module (ice-9 threads)
  #:use-module (kracht prelude)
  #:use-module (srfi srfi-19)
  #:use-module (ice-9 binary-ports)
  #:export (fetch-file))

(define (find-content-type-in-headers raw-headers)
  (let* ((headers (string-split (string-replace-substring raw-headers "\r\n"
                                                          "\n") #\newline))
         (maybe-content-type-line (filter (lambda (h)
                                            (string-prefix-ci? "content-type:"
                                             h)) headers)))
    
    (if (eq? 1
             (length maybe-content-type-line))
        (let* ((full-line (car maybe-content-type-line))
               (value-part (string-trim-both (cadr (string-split full-line #\:))))
               (mime-only (string-trim-both (car (string-split value-part #\;))))
               (parts (string-split mime-only #\/)))
          (if (>= (length parts) 2)
              (cadr parts) "bin")) "bin")))

(define* (fetch-file #:key url
                     (timeout-seconds 60)
                     (follow-redirects #t))
  (display (format #f "\nfetching URL: ~a\n" url))
  (let* ((sink-file-directory torikomi-sink-file-directory)
         (sink-file-base-url torikomi-sink-file-base-url)
         (last-url-piece (car (reverse (string-split url #\/))))
         (handle (curl-easy-init))
         (_ (begin
              (curl-easy-setopt handle
                                'header #f)
              (curl-easy-setopt handle
                                'url url)
              (curl-easy-setopt handle
                                'verbose #f)
              (curl-easy-setopt handle
                                'ssl-verifyhost #f)
              (curl-easy-setopt handle
                                'ssl-verifypeer #f)
              (curl-easy-setopt handle
                                'maxredirs 10)
              (curl-easy-setopt handle
                                'http-version 2)
              (curl-easy-setopt handle
                                'followlocation follow-redirects)
              (curl-easy-setopt handle
                                'timeout timeout-seconds)))
         (headers-and-bts (curl-easy-perform handle #t #t))
         (heads (car headers-and-bts))
         (bts (cadr headers-and-bts))
         (response-content-type (find-content-type-in-headers (car
                                                               headers-and-bts)))
         (extension (string-append "." response-content-type))
         (new-file-name (if (string-suffix-ci? extension last-url-piece)
                            (format #f "~a" last-url-piece) 
                            (format #f "~a.~a" last-url-piece
                                    response-content-type)))
         (destination-file (format #f "~a/~a" sink-file-directory
                                   new-file-name))
         (new-url (format #f "~a/~a" sink-file-base-url new-file-name)))
    (display (format #f "\nwriting file to ~a\n" destination-file))
    (call-with-output-file destination-file
      (lambda (port)
        (put-bytevector port bts))
      #:binary #t) new-url))

