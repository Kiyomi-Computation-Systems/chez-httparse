;;; (httparse test ratchet): which vendored fixtures this parser claims to pass.
;;;
;;; Decision 0008 item 6 requires a TWO-WAY gate. A manifest that only fails
;;; when a passing fixture breaks is a TODO list: it lets a fixture start
;;; passing unnoticed, which is how a milestone's exit criterion stops being
;;; falsifiable. So a `passing` entry that fails is an error AND a `not-yet`
;;; entry that passes is an error.
;;;
;;; THE STATUS CLASS IS DERIVED, NOT WRITTEN DOWN TWICE. Decision 0009 puts
;;; lenient modes and the URL sub-parser outside v0.1 -- pausing and skipBody
;;; were there too until M9 brought them in, which is two lines removed from
;;; the predicate below and 26 rows re-classed in one reviewed diff. Rather
;;; than trusting the manifest to say so, the class is computed from each
;;; fixture's own meta and the manifest must agree. A refresh that adds a
;;; lenient fixture therefore cannot be silently marked `not-yet` and counted
;;; against v0.1's bar.
(library (httparse test ratchet)
  (export ratchet-parse
          ratchet-entry? ratchet-entry-status ratchet-entry-id ratchet-entry-note
          ratchet-fixture-id ratchet-fixture-class
          ratchet-implemented-lenient
          ratchet-error? ratchet-error-detail)
  (import (rnrs) (httparse test corpus-load))

  (define-condition-type &ratchet &error
    make-ratchet-error ratchet-error? (detail ratchet-error-detail))

  (define (ratchet-refuse detail)
    (raise (condition (make-ratchet-error detail)
                      (make-who-condition 'ratchet-parse)
                      (make-message-condition detail))))

  (define-record-type ratchet-entry (fields status id note))

  ;; ratchet-fixture-id : String Nat -> String
  ;; A fixture's identity: its file and its 1-based ordinal within that file.
  (define (ratchet-fixture-id relative-path ordinal)
    (string-append relative-path "#" (number->string ordinal)))

  ;; ratchet-fixture-class : Fixture -> Symbol
  ;; 'deferred when decision 0009 puts the fixture outside v0.1, else 'in-scope.
  ;; THE LENIENT FLAGS THIS PARSER IMPLEMENTS. M10 lands them a slice at a
  ;; time, and a fixture is in scope exactly when the flag its init hook sets
  ;; is on this list -- so a slice is one name added here and its fixtures
  ;; re-classed in the same reviewed diff, and no fixture can drift in ahead
  ;; of the behaviour it needs. `all` is the hook that sets nine at once, so
  ;; it arrives only when all nine do.
  (define ratchet-implemented-lenient '(version headers optional-lf-after-cr optional-crlf-after-chunk
      header-value-relaxed keep-alive chunked-length transfer-encoding
      data-after-close spaces-after-chunk-size optional-cr-before-lf))

  (define (ratchet-fixture-class f)
    (if (or (eq? (fixture-kind f) 'url)
            (not (for-all (lambda (flag) (memq flag ratchet-implemented-lenient))
                          (fixture-lenient-flags f))))
        'deferred
        'in-scope))

  (define (whitespace? c)
    (or (char=? c #\space) (char=? c #\tab) (char=? c #\return) (char=? c #\linefeed)))

  (define (split-fields line)
    (let ((n (string-length line)))
      (let loop ((i 0) (start #f) (acc '()))
        (cond
         ((>= i n) (reverse (if start (cons (substring line start n) acc) acc)))
         ((whitespace? (string-ref line i))
          (loop (+ i 1) #f (if start (cons (substring line start i) acc) acc)))
         (else (loop (+ i 1) (or start i) acc))))))

  (define (split-lines s)
    (let ((n (string-length s)))
      (let loop ((i 0) (start 0) (acc '()))
        (cond ((>= i n) (reverse (cons (substring s start n) acc)))
              ((char=? (string-ref s i) #\linefeed)
               (loop (+ i 1) (+ i 1) (cons (substring s start i) acc)))
              (else (loop (+ i 1) start acc))))))

  ;; ratchet-parse : String -> (Listof RatchetEntry)
  (define (ratchet-parse text)
    (let loop ((lines (split-lines text)) (lineno 1) (acc '()) (seen '()))
      (if (null? lines)
          (reverse acc)
          (let* ((line (car lines))
                 (fields (split-fields line)))
            (cond
             ((or (null? fields) (char=? (string-ref (car fields) 0) #\#))
              (loop (cdr lines) (+ lineno 1) acc seen))
             ((< (length fields) 2)
              (ratchet-refuse (string-append "ratchet line " (number->string lineno)
                                             " has no fixture id: " line)))
             (else
              (let ((status (car fields)) (id (cadr fields)))
                (unless (member status '("passing" "not-yet" "deferred"))
                  (ratchet-refuse
                   (string-append "ratchet line " (number->string lineno)
                                  " has an unknown status '" status
                                  "' (expected passing, not-yet or deferred)")))
                (when (member id seen)
                  (ratchet-refuse
                   (string-append "ratchet line " (number->string lineno)
                                  " repeats fixture " id)))
                (loop (cdr lines) (+ lineno 1)
                      (cons (make-ratchet-entry (string->symbol status) id
                                                (if (> (length fields) 2) (caddr fields) ""))
                            acc)
                      (cons id seen)))))))))
  )
