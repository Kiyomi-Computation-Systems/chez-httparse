;;; (httparse test conformance): the scan schedule and the trace comparator.
;;;
;;; THE SCAN SCHEDULE. Upstream replays each fixture at every chunk size from 1
;;; to the input length, feeding fixed-size chunks (llparse__run_scan), and
;;; `noScan` collapses that to the single whole-buffer feed. So resumability
;;; is not an extra suite; it is the corpus, replayed. The pr/release split
;;; lives here too: `pr` runs the two extremes, `release` runs every size.
;;;
;;; THE COMPARATOR. Conformance is bit-exact equality, with an adapter that
;;; may rename but never compute, so this compares bytes and reports the
;;; first difference. It does NOT normalise, reorder, or match loosely.
;;;
;;; WHY LINE LISTS RATHER THAN ONE BLOB. Upstream joins its trace with newlines,
;;; appends one, splits again, then pads the shorter side -- actual with empty
;;; strings, expected with a never-matching pattern that nonetheless matches the
;;; empty string. The net effect is element-wise equality over the meaningful
;;; lines with the counts required to agree. Producing and comparing line lists
;;; directly is the same relation without the round trip through a blob.
(library (httparse test conformance)
  (export corpus-scan-sizes corpus-chunk-bounds
          trace-compare
          mismatch? mismatch-index mismatch-expected mismatch-actual mismatch-reason
          conformance-error? conformance-error-detail)
  (import (rnrs) (httparse test corpus-load))

  (define-condition-type &conformance &error
    make-conformance-error conformance-error? (detail conformance-error-detail))

  (define-record-type mismatch (fields index expected actual reason))

  ;; corpus-scan-sizes : Nat Boolean Symbol -> (Listof Nat)
  ;; The chunk sizes a fixture is replayed at. `selection` is 'full (every size,
  ;; the release preset) or 'extremes (size 1 and the whole buffer, the pr
  ;; preset). A noScan fixture is whole-buffer only in both, as upstream
  ;; specifies. A zero-length input still gets one run: skipping it would make
  ;; an empty fixture pass by never executing.
  (define (corpus-scan-sizes length no-scan? selection)
    (cond
     ((or no-scan? (<= length 1)) (list (max length 1)))
     ((eq? selection 'full)
      (let loop ((i length) (acc '()))
        (if (< i 1) acc (loop (- i 1) (cons i acc)))))
     ((eq? selection 'extremes)
      (list 1 length))
     (else (raise (condition (make-conformance-error
                              "scan selection must be 'full or 'extremes")
                             (make-who-condition 'corpus-scan-sizes)
                             (make-message-condition "unknown scan selection"))))))

  ;; corpus-chunk-bounds : Nat Nat -> (Listof (Pair Nat Nat))
  ;; The [start,end) slices a run of `size`-byte chunks feeds, in order.
  (define (corpus-chunk-bounds length size)
    (when (< size 1)
      (raise (condition (make-conformance-error "chunk size must be at least 1")
                        (make-who-condition 'corpus-chunk-bounds)
                        (make-message-condition "chunk size must be at least 1"))))
    (let loop ((at 0) (acc '()))
      (if (>= at length)
          (reverse acc)
          (let ((end (min (+ at size) length)))
            (loop end (cons (cons at end) acc))))))

  ;; trace-compare : (Listof Expectation) (Listof Bytevector) -> Mismatch or #f
  ;; #f means the trace matches exactly. Otherwise the first difference.
  (define (trace-compare expected actual)
    (let loop ((e expected) (a actual) (i 0))
      (cond
       ((and (null? e) (null? a)) #f)
       ((null? e)
        (make-mismatch i "" (utf8->string (car a)) 'unexpected-extra-line))
       ((null? a)
        (make-mismatch i (expectation-text (car e)) "" 'missing-line))
       (else
        (let ((exp (car e)) (act (car a)))
          (when (expectation-pattern? exp)
            ;; No fixture in the vendored corpus carries one. Comparing a
            ;; pattern as literal text would pass for the wrong reason, so this
            ;; refuses rather than guessing.
            (raise (condition
                    (make-conformance-error
                     (string-append "expectation is a pattern, which the comparator "
                                    "cannot evaluate: " (expectation-text exp)))
                    (make-who-condition 'trace-compare)
                    (make-message-condition "pattern expectation"))))
          (if (bytevector=? (string->utf8 (expectation-text exp)) act)
              (loop (cdr e) (cdr a) (+ i 1))
              (make-mismatch i (expectation-text exp) (utf8->string act)
                             'line-differs))))))))
