;;; Tests for (httparse test conformance): the scan schedule and comparator.
(import (rnrs)
        (httparse test harness)
        (httparse test corpus-load)
        (httparse test conformance))

;; Expectations are built through the loader so these tests exercise the same
;; record the real lanes will hand the comparator.
(define (expectations-of . texts)
  (fixture-expected
   (car (corpus-parse-file
         (apply string-append
                (append (list "```http\n" "A\n" "```\n" "```log\n")
                        (map (lambda (t) (string-append t "\n")) texts)
                        (list "```\n")))))))

(define (bvs . texts) (map string->utf8 texts))

(define (bv-append . bvs)
  (let* ((total (apply + (map bytevector-length bvs)))
         (out (make-bytevector total)))
    (let loop ((bs bvs) (at 0))
      (if (null? bs)
          out
          (begin (bytevector-copy! (car bs) 0 out at (bytevector-length (car bs)))
                 (loop (cdr bs) (+ at (bytevector-length (car bs)))))))))

(harness-begin "unit.conformance")

(harness-group "the scan schedule"
  (lambda ()
    (harness-case "a full scan runs every chunk size from 1 to the length"
      (lambda ()
        (check-equal "full 5" (corpus-scan-sizes 5 #f 'full) '(1 2 3 4 5))))
    (harness-case "the extremes selection runs size 1 and the whole buffer"
      (lambda ()
        (check-equal "extremes 5" (corpus-scan-sizes 5 #f 'extremes) '(1 5))))
    (harness-case "a noScan fixture is whole-buffer only under a full scan"
      (lambda ()
        (check-equal "noScan full" (corpus-scan-sizes 5 #t 'full) '(5))))
    (harness-case "a noScan fixture is whole-buffer only under the extremes too"
      (lambda ()
        (check-equal "noScan extremes" (corpus-scan-sizes 5 #t 'extremes) '(5))))
    (harness-case "a one-byte fixture has a single size, not a duplicated one"
      (lambda ()
        (check-equal "len 1" (corpus-scan-sizes 1 #f 'extremes) '(1))))
    (harness-case "a zero-length fixture still gets one run"
      (lambda ()
        ;; Skipping it would let an empty fixture pass by never executing.
        (check-equal "len 0" (corpus-scan-sizes 0 #f 'full) '(1))))))

(harness-group "chunk bounds"
  (lambda ()
    (harness-case "size 1 yields one slice per byte"
      (lambda ()
        (check-equal "1 of 3" (corpus-chunk-bounds 3 1) '((0 . 1) (1 . 2) (2 . 3)))))
    (harness-case "the whole buffer is one slice"
      (lambda ()
        (check-equal "3 of 3" (corpus-chunk-bounds 3 3) '((0 . 3)))))
    (harness-case "a final short chunk is clamped to the length"
      (lambda ()
        (check-equal "2 of 5" (corpus-chunk-bounds 5 2) '((0 . 2) (2 . 4) (4 . 5)))))
    (harness-case "a chunk larger than the input is one clamped slice"
      (lambda ()
        (check-equal "9 of 3" (corpus-chunk-bounds 3 9) '((0 . 3)))))
    (harness-case "a zero-length input yields no slices"
      (lambda ()
        (check-equal "0" (corpus-chunk-bounds 0 4) '())))
    (harness-case "the slices exactly tile the input with no gap or overlap"
      (lambda ()
        (let* ((bounds (corpus-chunk-bounds 7 3))
               (covered (apply + (map (lambda (b) (- (cdr b) (car b))) bounds))))
          (check-equal "total covered" covered 7)
          (check-equal "starts where the last ended"
                       (map car (cdr bounds)) (map cdr (reverse (cdr (reverse bounds))))))))
    (harness-case "a chunk size below one is refused"
      (lambda ()
        (check-raises "zero" conformance-error?
          (lambda () (corpus-chunk-bounds 3 0)))))))

(harness-group "the comparator"
  (lambda ()
    (harness-case "an exact match reports no mismatch"
      (lambda ()
        (check-equal "match"
                     (trace-compare (expectations-of "off=0 message begin")
                                    (bvs "off=0 message begin"))
                     #f)))
    (harness-case "a differing line is reported with its index"
      (lambda ()
        (let ((m (trace-compare (expectations-of "off=0 a" "off=1 b")
                                (bvs "off=0 a" "off=9 b"))))
          (check "a mismatch is returned" (mismatch? m))
          (check-equal "index" (mismatch-index m) 1)
          (check-equal "expected" (mismatch-expected m) "off=1 b")
          (check-equal "actual" (mismatch-actual m) "off=9 b")
          (check-equal "reason" (mismatch-reason m) 'line-differs))))
    (harness-case "a missing trailing line is a mismatch, not a pass"
      (lambda ()
        (let ((m (trace-compare (expectations-of "off=0 a" "off=1 b")
                                (bvs "off=0 a"))))
          (check-equal "reason" (mismatch-reason m) 'missing-line)
          (check-equal "index" (mismatch-index m) 1))))
    (harness-case "an extra trailing line is a mismatch, not a pass"
      (lambda ()
        ;; A prefix match must not count: a parser that stops early would
        ;; otherwise pass every fixture whose trace it began correctly.
        (let ((m (trace-compare (expectations-of "off=0 a")
                                (bvs "off=0 a" "off=1 b"))))
          (check-equal "reason" (mismatch-reason m) 'unexpected-extra-line)
          (check-equal "index" (mismatch-index m) 1))))
    (harness-case "both empty is a match"
      (lambda ()
        (check-equal "empty" (trace-compare '() '()) #f)))
    (harness-case "comparison is by bytes, not by decoded text"
      (lambda ()
        (check-equal "utf8 span"
                     (trace-compare (expectations-of "off=0 len=2 span[v]=\"\xff;\"")
                                    (list (bv-append (string->utf8 "off=0 len=2 span[v]=\"")
                                                     (u8-list->bytevector '(#xC3 #xBF))
                                                     (string->utf8 "\""))))
                     #f)))
    (harness-case "a trailing-whitespace difference is a mismatch"
      (lambda ()
        ;; Bit-exact means bit-exact; no trimming.
        (check "space differs"
               (mismatch? (trace-compare (expectations-of "off=0 a")
                                         (bvs "off=0 a "))))))))

(harness-finish)
