;; torikomi
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; The REST API.  One endpoint does the work -- `POST /api/v1/sink-file' --
;; and the answers are JSON in the shape `sink-result->alist' describes, so a
;; client reads the same fields whichever way it asked.
;;
;; A request body is read as JSON, and read as a URL-encoded form when it is
;; not JSON: a script that posts with `curl --form' and one that posts with
;; `curl --json' are both reasonable, and neither has to know which this file
;; prefers.  A body that is neither is a 400 with a sentence, not a 500: the
;; client's syntax is the client's business, and telling it so is the answer.
;;
;; `GET /api/v1/version' and `GET /api/v1/health' are here for the same reason
;; a deployment has a smoke test: to answer "which torikomi is this, and is it
;; up?" without asking it to fetch anything.

(define-restful-api v1)

(import (ice-9 exceptions)
        (ice-9 iconv)
        (kracht prelude)
        (json)
        (torikomi torikomi)
        (torikomi version))

(define (emit-json status data)
  "Send DATA as a JSON response with STATUS.

The body is serialized here rather than left to `#:mime', because `:mime'
cannot set a status: a failure would answer 200 and a client would have to read
the body to learn it failed."
  (response-emit (scm->json-string data)
                 #:status status
                 #:headers '((content-type application/json))))

(define (payload-field payload name)
  "The non-empty string NAME has in PAYLOAD, or #f."
  (let ((value (assoc-ref payload name)))
    (and (string? value)
         (let ((value (string-trim-both value)))
           (and (positive? (string-length value)) value)))))

(define (json-payload text)
  "TEXT decoded as a JSON object, or #f when it is not one."
  (let ((decoded (guard (condition (else #f))
                  (json-string->scm text))))
    (and (list? decoded)
         (every pair? decoded)
         decoded)))

(define (form-payload body)
  "BODY decoded as a URL-encoded form, or #f when it does not decode."
  (guard (condition (else #f))
    (alist-from-url-encoded-body body)))

(define (request-payload rc)
  "The request body as an association list, JSON first and a form second."
  (let ((body (rc-body rc)))
    (if (and body (bytevector? body))
        (or (let ((text (guard (condition (else #f))
                            (utf8->string body))))
              (and text (json-payload text)))
            (form-payload body)
            '())
        '())))

(post "/api/v1/sink-file"
      (lambda (rc)
        (let* ((payload (request-payload rc))
               (file-url (payload-field payload "file-url"))
               (file-name (payload-field payload "file-name"))
               (result (sink-file #:url file-url #:name file-name)))
          (emit-json (if (sink-result-ok? result)
                         200
                         (sink-result-status result))
                     ;; The first version of this API echoed the URL it was
                     ;; given; the field is kept for a client that reads it.
                     (append (sink-result->alist result)
                             (if file-url
                                 `((file-url . ,file-url))
                                 '()))))))

(get "/api/v1/version"
     (lambda (rc)
       (emit-json 200
                  `((name . "torikomi")
                    (version . ,torikomi-version)
                    (license . ,torikomi-license)
                    (homepage . ,torikomi-homepage)))))

(get "/api/v1/health"
     (lambda (rc)
       (emit-json 200 `((status . "ok")
                        (version . ,torikomi-version)))))
