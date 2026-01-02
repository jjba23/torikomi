;;; lispy-file-sink 

;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;; lispy-file-sink is free software: you can redistribute it and/or modify
;; it under the terms of the GNU Affero General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; lispy-file-sink is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU Affero General Public License for more details.

;; You should have received a copy of the GNU Affero General Public License
;; along with lispy-file-sink.  If not, see <https://www.gnu.org/licenses/>.

(define-module (lispy-file-sink fetch)
  #:use-module (web uri)
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
  #:use-module (ice-9 textual-ports)
  #:export (fetch-file))

(define* (fetch-file #:key url
                     (timeout-seconds 120)
                     (follow-redirects #t))
  (display (format #f "\nfetching URL: ~a\n" url))
  (let* ((last-url-piece (car (reverse (string-split url #\/))))
         (handle (curl-easy-init))
         ;; We will use a list to accumulate chunks of bytevectors
         (accumulated-data '()))
    
    (curl-easy-setopt handle 'url url)
    (curl-easy-setopt handle 'followlocation follow-redirects)
    (curl-easy-setopt handle 'timeout timeout-seconds)
    (curl-easy-setopt handle 'ssl-verifyhost 0)
    (curl-easy-setopt handle 'ssl-verifypeer 0)

    ;; Correct way: Use a write-function to catch raw bytes
    (curl-easy-setopt handle 'writefunction 
      (lambda (data)
        (set! accumulated-data (cons data accumulated-data))
        (bytevector-length data)))

    (curl-easy-perform handle)
    (curl-easy-cleanup handle)

    (let* ((response-body (u8-list->bytevector (reverse (apply append (map bytevector->u8-list accumulated-data)))))
           (content-type (curl-easy-getinfo handle 'content-type))
           ;; Note: You might want to get the extension via headers properly, 
           ;; but for simplicity, we'll keep your naming logic or use a default.
           (destination-file (format #f "tmp/~a" last-url-piece)))
      
      (display (format #f "The body contains ~a bytes~%" (bytevector-length response-body)))
      
      (call-with-output-file destination-file
        (lambda (port)
          (put-bytevector port response-body))
        #:binary #t)
      
      destination-file)))
