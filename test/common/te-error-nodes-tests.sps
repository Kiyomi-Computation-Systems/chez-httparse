;;; The node names docs/api.org gives for `invalid-transfer-encoding`.
;;;
;;; `docs/api.org` tells an embedder that a request refused with code
;;; `invalid-transfer-encoding` fails in one of four ways, and that
;;; `parser-error-node-name` tells the four apart. The code and reason are
;;; llhttp's, and the conformance lane already holds them to the corpus. The
;;; node names are OURS, so no trace line prints them and no conformance lane
;;; can see one renamed. This lane is their only witness.
;;;
;;; TWO QUESTIONS, BECAUSE A CORPUS SWEEP ANSWERS ONLY ONE. The sweep asks
;;; whether every refusal the corpus records stops at the node the document
;;; names for llhttp's reason -- keyed by the ORACLE's reason text, so the
;;; expectation never comes from this parser. But it can only see reasons some
;;; fixture reaches, so "four" would survive a fifth declaration no fixture
;;; exercises. The committed parser's own error table answers that one: the
;;; reasons it declares under this code must be exactly the document's four.
(import (rnrs)
        (only (chezscheme) directory-list)
        (httparse test harness)
        (httparse test corpus-load)
        (httparse test corpus-decode)
        (httparse test adapter)
        (httparse test drive)
        (generated httparse-message)
        (byte-machine runtime))

(define (read-text path)
  (utf8->string (call-with-port (open-file-input-port path) get-bytevector-all)))

(define corpus-dir (adapter-environment-variable "HTTPARSE_CORPUS_DIR"))
(define artifact-path (adapter-environment-variable "HTTPARSE_GENERATED_PARSER"))

;; documented-nodes : (Listof (Pair String Symbol))
;; llhttp's reason text -> the node docs/api.org names for it. The four rows
;; of the document's table, in its order.
(define documented-nodes
  '(("Empty Transfer-Encoding" . e-empty-transfer-encoding)
    ("Invalid `Transfer-Encoding` header value" . e-bad-te-value)
    ("Request has invalid `Transfer-Encoding`" . e-request-invalid-te)
    ("Transfer-Encoding can't be present with Content-Length"
     . e-te-with-content-length)))

;; The number llhttp prints for the code, from the adapter's own table rather
;; than restated here.
(define code-number
  (cdr (assq 'invalid-transfer-encoding adapter-error-codes)))

;; --- the corpus -------------------------------------------------------------

(define (string-suffix? suffix s)
  (let ((n (string-length s)) (m (string-length suffix)))
    (and (>= n m) (string=? (substring s (- n m) n) suffix))))

;; request-files : (Listof String)
;; Every `.md` under the corpus's `request/`, read from the directory rather
;; than listed, so a corpus refresh that adds a file cannot leave it unswept.
(define request-files
  (map (lambda (name) (string-append "request/" name))
       (list-sort string<?
                  (filter (lambda (name) (string-suffix? ".md" name))
                          (directory-list (string-append corpus-dir "/request"))))))

;; strict-requests : (Listof (Pair String Fixture))
;; Every fixture whose `type` meta is exactly "request", keyed by `file#n`.
;; Exactly, because the document is about the strict parser `make-parser`
;; gives an embedder; a lenient flag turns some of these refusals off.
(define strict-requests
  (apply append
         (map (lambda (rel)
                (let loop ((fs (corpus-parse-file
                                (read-text (string-append corpus-dir "/" rel))))
                           (i 1) (acc '()))
                  (cond ((null? fs) (reverse acc))
                        ((equal? (fixture-meta-ref (car fs) 'type #f) "request")
                         (loop (cdr fs) (+ i 1)
                               (cons (cons (string-append rel "#" (number->string i))
                                           (car fs))
                                     acc)))
                        (else (loop (cdr fs) (+ i 1) acc)))))
              request-files)))

;; index-of : String String -> (Option Nat)
(define (index-of s sub)
  (let ((n (string-length s)) (m (string-length sub)))
    (let loop ((i 0))
      (cond ((> (+ i m) n) #f)
            ((string=? (substring s i (+ i m)) sub) i)
            (else (loop (+ i 1)))))))

;; refusal-reason : Fixture -> (Option String)
;; The reason on the fixture's error line for this code, or #f if it has none.
;; llhttp prints the reason last on the line, in double quotes.
(define (refusal-reason f)
  (let ((marker (string-append " error code=" (number->string code-number)
                               " reason=\"")))
    (let loop ((es (fixture-expected f)))
      (if (null? es)
          #f
          (let* ((line (expectation-text (car es)))
                 (at (index-of line marker)))
            (if (and at (not (expectation-pattern? (car es))))
                (substring line (+ at (string-length marker))
                           (- (string-length line) 1))
                (loop (cdr es))))))))

;; --- the committed parser ---------------------------------------------------

;; refusal : Fixture Nat -> (Option (List Symbol Symbol))
;; `(code node-name)` for the error the fixture's input ends in, or #f.
(define (refusal f size)
  (let* ((bv (corpus-decode-input (fixture-input-text f)))
         (r (drive-result httparse-message-machine (drive-init 'request '()) bv
                          (if (zero? size) (max 1 (bytevector-length bv)) size)))
         (e (and r (parser-result-error r))))
    (and e
         (eq? (parser-result-status r) 'error)
         (list (parser-error-code e) (parser-error-node-name e)))))

;; declared-reasons : Symbol -> (Listof String)
;; The reasons the committed artifact declares under `code`, read from the
;; error table it carries as data -- the `(define errs (quote #(...)))` whose
;; entries are `#(code reason)`. Refuses rather than answering '() when the
;; table is not found, so a change to the artifact's shape cannot read as a
;; parser with no errors.
(define (declared-reasons code)
  (define (find-table d)
    (cond ((and (pair? d) (eq? (car d) 'define) (pair? (cdr d))
                (eq? (cadr d) 'errs) (pair? (cddr d))
                (pair? (caddr d)) (eq? (car (caddr d)) 'quote))
           (cadr (caddr d)))
          ((pair? d) (or (find-table (car d)) (find-table (cdr d))))
          (else #f)))
  (let ((table (find-table (call-with-port (open-input-file artifact-path) get-datum))))
    (unless (vector? table)
      (assertion-violation 'declared-reasons
                           "no `errs` table in the committed artifact" artifact-path))
    (map (lambda (entry) (vector-ref entry 1))
         (filter (lambda (entry) (eq? (vector-ref entry 0) code))
                 (vector->list table)))))

;; --- the sweep --------------------------------------------------------------

;; refused : (Listof (List String String Fixture))
;; `(id reason fixture)` for each strict request fixture that ends in the code.
(define refused
  (fold-right (lambda (entry acc)
                (let ((reason (refusal-reason (cdr entry))))
                  (if reason (cons (list (car entry) reason (cdr entry)) acc) acc)))
              '() strict-requests))

;; mismatches : Nat -> (Listof String)
;; The id of every refused fixture whose reason the document does not list, or
;; whose parse does not end at the node the document names for that reason.
(define (mismatches size)
  (fold-right
   (lambda (r acc)
     (let ((row (assoc (cadr r) documented-nodes)))
       (if (and row
                (equal? (refusal (caddr r) size)
                        (list 'invalid-transfer-encoding (cdr row))))
           acc
           (cons (car r) acc))))
   '() refused))

(harness-begin "unit.te-error-nodes")

(harness-group "invalid-transfer-encoding node names are the documented ones"
  (lambda ()
    (display (string-append
              "httparse-harness: te-error-nodes files="
              (number->string (length request-files))
              " refused=" (number->string (length refused))
              (apply string-append
                     (map (lambda (row)
                            (string-append
                             " " (symbol->string (cdr row)) ":"
                             (number->string
                              (length (filter (lambda (r) (equal? (cadr r) (car row)))
                                              refused)))))
                          documented-nodes))
              "\n"))

    (harness-case "the committed parser declares exactly the documented reasons"
      (lambda ()
        (check-equal "reasons under invalid-transfer-encoding"
                     (list-sort string<? (declared-reasons 'invalid-transfer-encoding))
                     (list-sort string<? (map car documented-nodes)))))

    (harness-case "every refused request fixture ends at its documented node"
      (lambda ()
        (check-equal "whole buffer" (mismatches 0) '())
        (check-equal "one byte per feed" (mismatches 1) '())))

    ;; Vacuity: the sweep says nothing about a row no fixture reaches, so each
    ;; of the document's four rows must be reached by at least one.
    (harness-case "the corpus reaches every documented row"
      (lambda ()
        (for-each
         (lambda (row)
           (check (string-append "reached: " (symbol->string (cdr row)))
                  (exists (lambda (r) (equal? (cadr r) (car row))) refused)))
         documented-nodes)))))

(harness-finish)
