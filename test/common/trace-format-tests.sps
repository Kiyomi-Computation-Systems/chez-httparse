;;; Tests for (httparse test trace-format): rendering events as llhttp's trace.
;;;
;;; Hand-built events in, exact trace lines out. This is the instrument the
;;; parser is measured with, so it is calibrated without the parser.
(import (rnrs)
        (httparse test harness)
        (httparse test trace-format))

(define (s->bv s) (string->utf8 s))

(define (bv-append . bvs)
  (let* ((total (apply + (map bytevector-length bvs)))
         (out (make-bytevector total)))
    (let loop ((bvs bvs) (at 0))
      (if (null? bvs)
          out
          (begin (bytevector-copy! (car bvs) 0 out at (bytevector-length (car bvs)))
                 (loop (cdr bvs) (+ at (bytevector-length (car bvs)))))))))
(define (lines->strings bvs) (map utf8->string bvs))

(define (fmt . events) (lines->strings (trace-format events)))

(harness-begin "unit.trace-format")

(harness-group "marks"
  (lambda ()
    (harness-case "a mark renders with its offset"
      (lambda ()
        (check-equal "begin" (fmt (make-trace-mark 0 "message begin"))
                     '("off=0 message begin"))))
    (harness-case "a mark's text is passed through untouched"
      (lambda ()
        (check-equal "headers complete"
                     (fmt (make-trace-mark 60 "headers complete method=6 v=1/1 flags=0 content_length=0"))
                     '("off=60 headers complete method=6 v=1/1 flags=0 content_length=0"))))
    (harness-case "a null mark renders off=NULL"
      (lambda ()
        (check-equal "finish" (fmt (make-trace-mark-at-null "finish=2"))
                     '("off=NULL finish=2"))))))

(harness-group "span splitting"
  (lambda ()
    (harness-case "a span with no line break is one quoted line"
      (lambda ()
        (check-equal "GET" (fmt (make-trace-span "method" 0 (s->bv "GET")))
                     '("off=0 len=3 span[method]=\"GET\""))))
    (harness-case "an empty span still prints one empty quoted line"
      (lambda ()
        ;; The C loop's `len != 0 || (lf == NULL && cr == NULL)` guard. Dropping
        ;; the empty line would silently delete a real event.
        (check-equal "empty" (fmt (make-trace-span "body" 7 (s->bv "")))
                     '("off=7 len=0 span[body]=\"\""))))
    (harness-case "a span that is exactly LF prints only the lf line"
      (lambda ()
        (check-equal "lf" (fmt (make-trace-span "body" 4 (s->bv "\n")))
                     '("off=4 len=1 span[body]=lf"))))
    (harness-case "a span that is exactly CR prints only the cr line"
      (lambda ()
        (check-equal "cr" (fmt (make-trace-span "body" 4 (s->bv "\r")))
                     '("off=4 len=1 span[body]=cr"))))
    (harness-case "text before an LF is split off"
      (lambda ()
        (check-equal "ab lf" (fmt (make-trace-span "body" 0 (s->bv "ab\n")))
                     '("off=0 len=2 span[body]=\"ab\""
                       "off=2 len=1 span[body]=lf"))))
    (harness-case "CRLF becomes a cr line then an lf line"
      (lambda ()
        (check-equal "crlf" (fmt (make-trace-span "body" 0 (s->bv "a\r\nb")))
                     '("off=0 len=1 span[body]=\"a\""
                       "off=1 len=1 span[body]=cr"
                       "off=2 len=1 span[body]=lf"
                       "off=3 len=1 span[body]=\"b\""))))
    (harness-case "an LF before a CR is taken first"
      (lambda ()
        ;; memchr finds both; the earlier one wins. Taking CR unconditionally
        ;; would mis-order these two lines.
        (check-equal "lf then cr" (fmt (make-trace-span "body" 0 (s->bv "\n\r")))
                     '("off=0 len=1 span[body]=lf"
                       "off=1 len=1 span[body]=cr"))))
    (harness-case "span bytes are emitted raw, including non-ASCII"
      (lambda ()
        (check-equal "utf8"
                     (trace-format (list (make-trace-span "header_value" 0
                                                          (u8-list->bytevector '(#xC3 #xBF #x41)))))
                     (list (bv-append
                            (string->utf8 "off=0 len=3 span[header_value]=\"")
                            (u8-list->bytevector '(#xC3 #xBF #x41))
                            (string->utf8 "\""))))))))

(harness-group "coalescing"
  (lambda ()
    (harness-case "two contiguous fragments of one span merge"
      (lambda ()
        (check-equal "merge"
                     (fmt (make-trace-span "url" 0 (s->bv "/fo"))
                          (make-trace-span "url" 3 (s->bv "o")))
                     '("off=0 len=4 span[url]=\"/foo\""))))
    (harness-case "non-contiguous fragments do not merge"
      (lambda ()
        (check-equal "gap"
                     (fmt (make-trace-span "url" 0 (s->bv "ab"))
                          (make-trace-span "url" 5 (s->bv "cd")))
                     '("off=0 len=2 span[url]=\"ab\""
                       "off=5 len=2 span[url]=\"cd\""))))
    (harness-case "fragments of different spans do not merge"
      (lambda ()
        (check-equal "two names"
                     (fmt (make-trace-span "url" 0 (s->bv "ab"))
                          (make-trace-span "method" 2 (s->bv "cd")))
                     '("off=0 len=2 span[url]=\"ab\""
                       "off=2 len=2 span[method]=\"cd\""))))
    (harness-case "a merged line MOVES TO THE END, after lines between the fragments"
      (lambda ()
        ;; The reordering in the driver's normalizeSpans: on merge the surviving
        ;; entry is spliced out of its position and pushed. Anything emitted
        ;; between the two fragments therefore ends up BEFORE the merged span.
        ;; A formatter that merged in place would put these two lines the other
        ;; way round and every chunked-body fixture would mismatch.
        (check-equal "reorder"
                     (fmt (make-trace-span "body" 0 (s->bv "ab"))
                          (make-trace-mark 2 "chunk complete")
                          (make-trace-span "body" 2 (s->bv "cd")))
                     '("off=2 chunk complete"
                       "off=0 len=4 span[body]=\"abcd\""))))
    (harness-case "three contiguous fragments merge into one"
      (lambda ()
        (check-equal "three"
                     (fmt (make-trace-span "body" 0 (s->bv "a"))
                          (make-trace-span "body" 1 (s->bv "b"))
                          (make-trace-span "body" 2 (s->bv "c")))
                     '("off=0 len=3 span[body]=\"abc\""))))
    (harness-case "a cr line is never coalesced into a quoted run"
      (lambda ()
        ;; =cr and =lf do not match the quoted shape the driver coalesces, so
        ;; they stay put and break the contiguity of what surrounds them.
        (check-equal "cr breaks"
                     (fmt (make-trace-span "body" 0 (s->bv "a\rb")))
                     '("off=0 len=1 span[body]=\"a\""
                       "off=1 len=1 span[body]=cr"
                       "off=2 len=1 span[body]=\"b\""))))
    (harness-case "a fragment after a cr line still merges if it is contiguous"
      (lambda ()
        ;; "a" is off=0 len=1, "b" is off=2 -- not contiguous, so no merge.
        ;; This pins that the cr line's byte counts toward the offset.
        (check-equal "no merge across cr"
                     (length (fmt (make-trace-span "body" 0 (s->bv "a\rb"))))
                     3)))))

(harness-group "whole traces"
  (lambda ()
    (harness-case "a request-line trace renders in order"
      (lambda ()
        (check-equal "request line"
                     (fmt (make-trace-mark 0 "message begin")
                          (make-trace-span "method" 0 (s->bv "GET"))
                          (make-trace-mark 3 "method complete")
                          (make-trace-span "url" 4 (s->bv "/url"))
                          (make-trace-mark 8 "url complete"))
                     '("off=0 message begin"
                       "off=0 len=3 span[method]=\"GET\""
                       "off=3 method complete"
                       "off=4 len=4 span[url]=\"/url\""
                       "off=8 url complete"))))
    (harness-case "no events render no lines"
      (lambda ()
        (check-equal "empty" (fmt) '())))))

(harness-finish)
