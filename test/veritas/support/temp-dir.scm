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
;; A throwaway directory for a test that writes files.
;;
;; The suite exercises the sink for real -- a name is reserved, bytes are
;; written, a collision is retried -- and none of that may touch the checkout or
;; another test's files.  Each test that writes asks for a directory of its own
;; and gives it back; the directory is named after a UUID so two concurrent
;; suites cannot meet in it.

;;; Code:

(define-module (veritas support temp-dir)
  #:use-module (ice-9 format)
  #:use-module (uuid generate)
  #:export (make-temp-directory
            delete-directory-tree
            call-with-temp-directory))

(define (make-temp-directory)
  "Create and return a fresh directory under TMPDIR, named after a UUID."
  (let* ((base (or (getenv "TMPDIR") "/tmp"))
         (path (format #f "~a/torikomi-test-~a"
                       (string-trim-right base #\/)
                       (generate-string-uuid))))
    (mkdir path)
    path))

(define (delete-directory-tree path)
  "Delete PATH, recursively when it is a directory, and do nothing if it is gone."
  (define (delete entry)
    (let ((info (lstat entry)))
      (if (eq? (stat:type info) 'directory)
          (begin
            (let ((directory (opendir entry)))
              (let loop ((name (readdir directory)))
                (unless (eof-object? name)
                  (unless (member name '("." ".."))
                    (delete (string-append entry "/" name)))
                  (loop (readdir directory))))
              (closedir directory))
            (rmdir entry))
          (delete-file entry))))
  (when (file-exists? path)
    (delete path)))

(define (call-with-temp-directory procedure)
  "Call PROCEDURE with a fresh directory, removing it however it returns."
  (let ((directory (make-temp-directory)))
    (dynamic-wind
      (lambda () #t)
      (lambda () (procedure directory))
      (lambda () (delete-directory-tree directory)))))
