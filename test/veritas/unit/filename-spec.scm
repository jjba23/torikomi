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

;;; Deciding a name, and writing the bytes under it.
;;;
;;; A name arrives from three places -- the reader's form, a server's
;;; `Content-Disposition', the URL -- and none of them is trusted.  The readings
;;; below are of the name that comes out: no traversal, no hidden file, no
;;; 400-character name, an extension that matches the bytes, and a file that is
;;; never written over another.

(define-module (veritas unit filename-spec)
  #:use-module (veritas veritas)
  #:use-module (veritas support temp-dir)
  #:use-module (srfi srfi-1)
  #:use-module (rnrs bytevectors)
  #:use-module (ice-9 binary-ports)
  #:use-module (torikomi torikomi)
  #:use-module (torikomi preferences)
  #:export (spec))

(define (read-all path)
  "The bytes of the file at PATH."
  (call-with-input-file path get-bytevector-all))

(define (directory-entries path)
  "The names of the entries of PATH, `.` and `..' included."
  (let ((directory (opendir path)))
    (let loop ((names '()))
      (let ((name (readdir directory)))
        (if (eof-object? name)
            (begin (closedir directory) (reverse names))
            (loop (cons name names)))))))

(define filename-suite
  (suite "deciding a name"
         #:concurrent? #f
         #:shuffle? #f
         (test "a name cannot escape the sink directory"
               #:shuffle? #f
               (assert-equal #:expect "passwd"
                             #:got (sanitize-filename "../../etc/passwd"))
               (assert-equal #:expect "passwd"
                             #:got (sanitize-filename "..\\..\\etc\\passwd"))
               (assert-equal #:expect "b.png"
                             #:got (sanitize-filename "a/b/../b.png"))
               (assert-equal #:expect "passwd"
                             #:got (sanitize-filename "/etc/passwd")))
         (test "a name cannot be hidden or empty"
               #:shuffle? #f
               (assert-false (sanitize-filename "."))
               (assert-false (sanitize-filename ".."))
               (assert-false (sanitize-filename "  ..  "))
               (assert-false (sanitize-filename ""))
               (assert-false (sanitize-filename #f))
               (assert-equal #:expect "name"
                             #:got (sanitize-filename "..name..")))
         (test "unsafe characters become one dash"
               #:shuffle? #f
               (assert-equal #:expect "a-b.png"
                             #:got (sanitize-filename "a b.png"))
               (assert-equal #:expect "a-b.png"
                             #:got (sanitize-filename "a???b.png"))
               (assert-equal #:expect "h-llo-w-rld.png"
                             #:got (sanitize-filename "héllo wörld.png"))
               (assert-equal #:expect "photo.JPG"
                             #:got (sanitize-filename "photo.JPG"))
               (assert-equal #:expect "a_b-c.txt"
                             #:got (sanitize-filename "a_b  c.txt")))
         (test "a very long name is shortened but keeps its extension"
               #:shuffle? #f
               (parameterize ((filename-max-length 20))
                 (let ((name (sanitize-filename
                              (string-append (make-string 40 #\a) ".png"))))
                   (assert-true (<= (string-length name) 20))
                   (assert-true (string-suffix? ".png" name)))))
         (test "an extension is only letters and digits"
               #:shuffle? #f
               (assert-equal #:expect "png" #:got (sanitize-extension "PNG"))
               (assert-equal #:expect "jpg" #:got (sanitize-extension " jpg "))
               (assert-false (sanitize-extension "p/ng"))
               (assert-false (sanitize-extension "../etc"))
               (assert-false (sanitize-extension ""))
               (assert-false (sanitize-extension "averyveryverylongext"))
               (assert-false (sanitize-extension #f)))
         (test "a known extension is replaced rather than appended"
               #:shuffle? #f
               (assert-equal #:expect "photo.png"
                             #:got (with-extension "photo.JPG" "png"))
               (assert-equal #:expect "archive.tar.gz"
                             #:got (with-extension "archive.tar.gz" "gz"))
               (assert-equal #:expect "v1.2.txt"
                             #:got (with-extension "v1.2" "txt"))
               (assert-equal #:expect "noext.png"
                             #:got (with-extension "noext" "PNG"))
               (assert-equal #:expect "photo.bin"
                             #:got (with-extension "photo" "not an extension!"))
               (assert-equal #:expect "photo.bin"
                             #:got (with-extension "photo" #f)))
         (test "the name a Content-Disposition asks for is understood"
               #:shuffle? #f
               (assert-equal
                #:expect "My File.pdf"
                #:got (content-disposition-filename
                       "HTTP/1.1 200 OK\r\nContent-Disposition: attachment; filename=\"My File.pdf\"\r\n\r\n"))
               (assert-equal
                #:expect "café.png"
                #:got (content-disposition-filename
                       "HTTP/1.1 200 OK\r\nContent-Disposition: inline; filename*=UTF-8''caf%C3%A9.png\r\n\r\n"))
               (assert-equal
                #:expect "a.png"
                #:got (content-disposition-filename
                       "HTTP/1.1 200 OK\r\nContent-Disposition: attachment; filename=a.png\r\n\r\n"))
               (assert-false
                (content-disposition-filename
                 "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\n")))
         (test "a malformed escape is left as it is"
               #:shuffle? #f
               (assert-equal
                #:expect "bad%zz.png"
                #:got (content-disposition-filename
                       "HTTP/1.1 200 OK\r\nContent-Disposition: inline; filename*=UTF-8''bad%zz.png\r\n\r\n")))
         (test "the URL's last segment is a name"
               #:shuffle? #f
               (assert-equal #:expect "pic.png"
                             #:got (basename-from-url
                                    "https://example.org/images/pic.png?size=2"))
               (assert-equal #:expect "a-b.png"
                             #:got (basename-from-url
                                    "https://example.org/a%20b.png"))
               (assert-false (basename-from-url "https://example.org/"))
               (assert-false (basename-from-url "https://example.org")))
         (test "the URL's extension is read but not trusted"
               #:shuffle? #f
               (assert-equal #:expect "gz"
                             #:got (extension-from-url
                                    "https://example.org/archive.tar.gz"))
               (assert-equal #:expect "png"
                             #:got (extension-from-url
                                    "https://example.org/pic.PNG?x=1"))
               (assert-false (extension-from-url "https://example.org/noext"))
               (assert-false (extension-from-url "https://example.org/")))
         (test "the media type decides the extension before the name does"
               #:shuffle? #f
               (let ((headers (string-append
                               "HTTP/1.1 200 OK\r\n"
                               "Content-Type: image/png\r\n"
                               "Content-Disposition: attachment; filename=\"a.jpg\"\r\n"
                               "\r\n")))
                 (assert-equal #:expect "png"
                               #:got (choose-extension
                                      "https://example.org/a.gif" headers))))
         (test "a server that only says octet-stream leaves the name to say it"
               #:shuffle? #f
               (let ((headers (string-append
                               "HTTP/1.1 200 OK\r\n"
                               "Content-Type: application/octet-stream\r\n"
                               "Content-Disposition: attachment; filename=\"a.pdf\"\r\n"
                               "\r\n")))
                 (assert-equal #:expect "pdf"
                               #:got (choose-extension
                                      "https://example.org/a.gif" headers)))
               (let ((headers
                      "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\n\r\n"))
                 (assert-equal #:expect "gif"
                               #:got (choose-extension
                                      "https://example.org/a.gif" headers))))
         (test "the base name comes from the reader, the server or the URL"
               #:shuffle? #f
               (assert-equal #:expect "mine"
                             #:got (choose-basename "https://example.org/a.png"
                                                    "../../mine" ""))
               (assert-equal #:expect "a.png"
                             #:got (choose-basename "https://example.org/a.png"
                                                    #f ""))
               (assert-equal #:expect "suggested.bin"
                             #:got (choose-basename
                                    "https://example.org/a.png" #f
                                    (string-append
                                     "HTTP/1.1 200 OK\r\n"
                                     "Content-Disposition: attachment; filename=\"suggested.bin\"\r\n\r\n")))
               (assert-equal #:expect "torikomi"
                             #:got (choose-basename "https://example.org/" #f
                                                    "")))
         (test "a name already taken is not replaced"
               #:shuffle? #f
               (call-with-temp-directory
                (lambda (directory)
                  (let* ((first (write-download! directory "a.txt"
                                                  (string->utf8 "first")))
                         (second (write-download! directory "a.txt"
                                                  (string->utf8 "second"))))
                    (assert-equal #:expect "a.txt" #:got (car first))
                    (assert-true (string? (car second)))
                    (assert-false (string=? (car first) (car second)))
                    (assert-true (string-suffix? ".txt" (car second)))
                    (assert-equal #:expect (string->utf8 "first")
                                  #:got (read-all (cdr first)))
                    (assert-equal #:expect (string->utf8 "second")
                                  #:got (read-all (cdr second)))))))
         (test "the sink directory is created and left without temporary files"
               #:shuffle? #f
               (call-with-temp-directory
                (lambda (directory)
                  (let* ((nested (string-append directory "/a/b/c"))
                         (saved (write-download! nested "note.txt"
                                                  (string->utf8 "hello"))))
                    (assert-true (file-exists? (cdr saved)))
                    (assert-equal #:expect (string->utf8 "hello")
                                  #:got (read-all (cdr saved)))
                    (assert-equal
                     #:expect '("." ".." "note.txt")
                     #:got (sort (directory-entries nested) string<?))))))
         (test "another name can be asked for without writing"
               #:shuffle? #f
               (call-with-temp-directory
                (lambda (directory)
                  (assert-equal #:expect "a-b.png"
                                #:got (resolve-unique-filename
                                       #:dir directory
                                       #:filename "a b"
                                       #:extension "PNG"))
                  (call-with-output-file (string-append directory "/a-b.png")
                    (lambda (port) (display "" port)))
                  (let ((chosen (resolve-unique-filename #:dir directory
                                                         #:filename "a b"
                                                         #:extension "png")))
                    (assert-false (string=? "a-b.png" chosen))
                    (assert-true (string? chosen))))))))

(define (spec)
  (veritas-run #:concurrent? #f #:shuffle? #f filename-suite))
