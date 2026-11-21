;; torikomi
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; The settings a deployment may give.
;;;
;;; The point of these readings is not that the default is 60: it is that a
;;; deployment which writes `soon' where a number belongs, or a negative retry
;;; count, gets the project's value instead of a server that hangs or a loop
;;; that never ends.  A setting that means nothing cannot be allowed to mean
;;; anything.

(define-module (veritas unit preferences-spec)
  #:use-module (veritas veritas)
  #:use-module (torikomi preferences)
  #:export (spec))

(define (with-setting variable value thunk)
  "Call THUNK with VARIABLE set to VALUE, restoring the environment after."
  (let ((previous (getenv variable)))
    (dynamic-wind
      (lambda () (setenv variable value))
      thunk
      (lambda ()
        (if previous
            (setenv variable previous)
            (unsetenv variable))))))

(define preferences-suite
  (suite "the settings a deployment may give"
         #:concurrent? #f
         #:shuffle? #f
         (test "the environment is the deployment's word"
               #:shuffle? #f
               (with-setting "TORIKOMI_TEST_SETTING" "from-the-environment"
                 (lambda ()
                   (assert-equal #:expect "from-the-environment"
                                 #:got (deployment-setting
                                        "TORIKOMI_TEST_SETTING" #f "default"))))
               (with-setting "TORIKOMI_TEST_SETTING" "  padded  "
                 (lambda ()
                   (assert-equal #:expect "padded"
                                 #:got (deployment-setting
                                        "TORIKOMI_TEST_SETTING" #f "default"))))
               (with-setting "TORIKOMI_TEST_SETTING" ""
                 (lambda ()
                   (assert-equal #:expect "default"
                                 #:got (deployment-setting
                                        "TORIKOMI_TEST_SETTING" #f "default"))))
               (unsetenv "TORIKOMI_TEST_SETTING")
               (assert-equal #:expect "default"
                             #:got (deployment-setting
                                    "TORIKOMI_TEST_SETTING" #f "default")))
         (test "a number is a whole number in range, or the default"
               #:shuffle? #f
               (with-setting "TORIKOMI_TEST_NUMBER" "42"
                 (lambda ()
                   (assert-equal #:expect 42
                                 #:got (deployment-number-setting
                                        "TORIKOMI_TEST_NUMBER" #f 7))))
               (with-setting "TORIKOMI_TEST_NUMBER" "soon"
                 (lambda ()
                   (assert-equal #:expect 7
                                 #:got (deployment-number-setting
                                        "TORIKOMI_TEST_NUMBER" #f 7))))
               (with-setting "TORIKOMI_TEST_NUMBER" "-1"
                 (lambda ()
                   (assert-equal #:expect 7
                                 #:got (deployment-number-setting
                                        "TORIKOMI_TEST_NUMBER" #f 7))))
               (with-setting "TORIKOMI_TEST_NUMBER" "1.5"
                 (lambda ()
                   (assert-equal #:expect 7
                                 #:got (deployment-number-setting
                                        "TORIKOMI_TEST_NUMBER" #f 7))))
               (with-setting "TORIKOMI_TEST_NUMBER" "3"
                 (lambda ()
                   (assert-equal #:expect 3
                                 #:got (deployment-number-setting
                                        "TORIKOMI_TEST_NUMBER" #f 7
                                        #:minimum 1 #:maximum 5))
                   (assert-equal #:expect 7
                                 #:got (deployment-number-setting
                                        "TORIKOMI_TEST_NUMBER" #f 7
                                        #:minimum 4 #:maximum 5)))))
         (test "a flag is true unless it is one of the ways of writing no"
               #:shuffle? #f
               (for-each
                (lambda (value)
                  (with-setting "TORIKOMI_TEST_FLAG" value
                    (lambda ()
                      (assert-false (deployment-boolean-setting
                                     "TORIKOMI_TEST_FLAG" #f #t)))))
                '("0" "false" "FALSE" "no" "off" "disable" "disabled"))
               (for-each
                (lambda (value)
                  (with-setting "TORIKOMI_TEST_FLAG" value
                    (lambda ()
                      (assert-true (deployment-boolean-setting
                                    "TORIKOMI_TEST_FLAG" #f #f)))))
                '("1" "true" "yes" "on" "whatever"))
               (unsetenv "TORIKOMI_TEST_FLAG")
               (assert-true (deployment-boolean-setting
                             "TORIKOMI_TEST_FLAG" #f #t)))
         (test "a size may be written with a suffix"
               #:shuffle? #f
               (assert-equal #:expect 1024 #:got (parse-size "1024"))
               (assert-equal #:expect 1024 #:got (parse-size "1K"))
               (assert-equal #:expect (* 2 1024 1024) #:got (parse-size "2M"))
               (assert-equal #:expect (* 3 1024 1024 1024)
                             #:got (parse-size "3G"))
               (assert-equal #:expect (* 1024 1024 1024 1024)
                             #:got (parse-size "1T"))
               (assert-equal #:expect (* 10 1024 1024)
                             #:got (parse-size " 10m "))
               (assert-false (parse-size "abc"))
               (assert-false (parse-size "0"))
               (assert-false (parse-size "-1M"))
               (assert-false (parse-size "1.5M"))
               (assert-equal #:expect 9 #:got (parse-size "abc" 9)))
         (test "a public URL joins the base and the name without doubling slashes"
               #:shuffle? #f
               (parameterize ((public-base-url "https://files.example/base/"))
                 (assert-equal #:expect "https://files.example/base/a.png"
                               #:got (public-url "a.png")))
               (parameterize ((public-base-url "https://files.example"))
                 (assert-equal #:expect "https://files.example/a.png"
                               #:got (public-url "a.png"))))
         (test "the project's settings are the shapes the code expects"
               #:shuffle? #f
               (assert-true (string? (sink-directory)))
               (assert-true (positive? (string-length (sink-directory))))
               (assert-true (string? (public-base-url)))
               (assert-true (and (integer? (curl-timeout-seconds))
                                 (positive? (curl-timeout-seconds))))
               (assert-true (and (integer? (curl-connect-timeout-seconds))
                                 (positive? (curl-connect-timeout-seconds))))
               (assert-true (and (integer? (curl-max-redirects))
                                 (>= (curl-max-redirects) 0)))
               (assert-true (and (integer? (curl-retries))
                                 (>= (curl-retries) 0)))
               (assert-true (boolean? (curl-verify-tls)))
               (assert-true (and (integer? (max-file-bytes))
                                 (positive? (max-file-bytes))))
               (assert-true (and (integer? (filename-max-length))
                                 (positive? (filename-max-length))))
               (assert-true (list? (allowed-url-schemes)))
               (assert-true (if (member "https" (allowed-url-schemes)) #t #f))
               (assert-true (string? (curl-user-agent))))))

(define (spec)
  (veritas-run #:concurrent? #f #:shuffle? #f preferences-suite))
