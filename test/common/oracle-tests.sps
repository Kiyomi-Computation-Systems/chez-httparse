;;; Tests for (httparse test oracle): reading a live llhttp binary's output.
;;;
;;; THE CALIBRATION IS THE CORPUS, and it needs no llhttp. Upstream's 253
;;; expected blocks are already in the form the checker compares -- raw lines
;;; coalesced by `normalizeSpans` -- so running them through this module must
;;; give them back UNCHANGED. A recogniser that dropped a line into its
;;; catch-all, took the wrong substring, or lost a span's bytes cannot survive
;;; that, and neither can a coalescing step that disagrees with the one the
;;; parser's own traces go through.
;;;
;;; The hand-written cases below are the shapes the corpus does not contain
;;; often enough to rely on, plus every refusal.
(import (rnrs)
        (httparse test harness)
        (httparse test corpus-load)
        (httparse test oracle))

(define (read-text path)
  (utf8->string (call-with-port (open-file-input-port path) get-bytevector-all)))

(define corpus-dir (adapter-environment-variable "HTTPARSE_CORPUS_DIR"))

(define corpus-files
  '("request/connection.md" "request/content-length.md" "request/finish.md"
    "request/invalid.md" "request/lenient-header-value-relaxed.md"
    "request/lenient-headers.md" "request/lenient-version.md" "request/method.md"
    "request/pausing.md" "request/pipelining.md" "request/sample.md"
    "request/transfer-encoding.md" "request/uri.md"
    "response/connection.md" "response/content-length.md" "response/finish.md"
    "response/invalid.md" "response/lenient-version.md" "response/pausing.md"
    "response/pipelining.md" "response/sample.md" "response/transfer-encoding.md"
    "url.md"))

(define (line bv) (utf8->string bv))
(define (bv s) (string->utf8 s))
(define (lines . ss) (map bv ss))
(define (texts bvs) (map line bvs))

(harness-begin "unit.oracle")

(harness-group "a printed line becomes the event it was printed from"
  (lambda ()
    (harness-case "a quoted span"
      (lambda ()
        (check-equal "round trip"
                     (texts (oracle-normalize (lines "off=0 len=7 span[method]=\"OPTIONS\"")))
                     '("off=0 len=7 span[method]=\"OPTIONS\""))))
    (harness-case "an empty span keeps its empty quoted line"
      (lambda ()
        (check-equal "len 0"
                     (texts (oracle-normalize (lines "off=33 len=0 span[header_value]=\"\"")))
                     '("off=33 len=0 span[header_value]=\"\""))))
    (harness-case "a span that is one CR"
      (lambda ()
        (check-equal "cr"
                     (texts (oracle-normalize (lines "off=4 len=1 span[body]=cr")))
                     '("off=4 len=1 span[body]=cr"))))
    (harness-case "a span that is one LF"
      (lambda ()
        (check-equal "lf"
                     (texts (oracle-normalize (lines "off=5 len=1 span[body]=lf")))
                     '("off=5 len=1 span[body]=lf"))))
    (harness-case "a mark"
      (lambda ()
        (check-equal "message begin"
                     (texts (oracle-normalize (lines "off=0 message begin")))
                     '("off=0 message begin"))))
    (harness-case "a mark whose text contains an equals sign and quotes"
      (lambda ()
        (check-equal "error"
                     (texts (oracle-normalize
                             (lines "off=42 error code=10 reason=\"Invalid header token\"")))
                     '("off=42 error code=10 reason=\"Invalid header token\""))))
    (harness-case "a mark at NULL"
      (lambda ()
        (check-equal "finish"
                     (texts (oracle-normalize (lines "off=NULL finish=0")))
                     '("off=NULL finish=0"))))
    (harness-case "a span whose bytes contain a quote"
      (lambda ()
        ;; The recogniser takes the LAST quote, as upstream's greedy pattern
        ;; does; taking the first would silently shorten the span.
        (check-equal "inner quote"
                     (texts (oracle-normalize (lines "off=3 len=3 span[v]=\"a\"b\"")))
                     '("off=3 len=3 span[v]=\"a\"b\""))))))

(harness-group "fragments are coalesced the way the checker coalesces them"
  (lambda ()
    (harness-case "adjacent fragments of one span merge"
      (lambda ()
        (check-equal "two become one"
                     (texts (oracle-normalize
                             (lines "off=0 len=1 span[method]=\"G\""
                                    "off=1 len=2 span[method]=\"ET\"")))
                     '("off=0 len=3 span[method]=\"GET\""))))
    (harness-case "a merged fragment moves to the end"
      (lambda ()
        ;; This reordering is upstream's, and it is observable whenever another
        ;; line falls between the fragments.
        (check-equal "moved"
                     (texts (oracle-normalize
                             (lines "off=0 len=1 span[body]=\"a\""
                                    "off=1 chunk complete"
                                    "off=1 len=1 span[body]=\"b\"")))
                     '("off=1 chunk complete"
                       "off=0 len=2 span[body]=\"ab\""))))
    (harness-case "non-adjacent fragments do not merge"
      (lambda ()
        (check-equal "gap"
                     (texts (oracle-normalize
                             (lines "off=0 len=1 span[x]=\"a\""
                                    "off=5 len=1 span[x]=\"b\"")))
                     '("off=0 len=1 span[x]=\"a\""
                       "off=5 len=1 span[x]=\"b\""))))
    (harness-case "a cr line breaks the adjacency"
      (lambda ()
        (check-equal "cr between"
                     (texts (oracle-normalize
                             (lines "off=0 len=1 span[x]=\"a\""
                                    "off=1 len=1 span[x]=cr"
                                    "off=2 len=1 span[x]=\"b\"")))
                     '("off=0 len=1 span[x]=\"a\""
                       "off=1 len=1 span[x]=cr"
                       "off=2 len=1 span[x]=\"b\""))))))

(harness-group "a line this module cannot place is refused"
  (lambda ()
    (harness-case "a line that does not start with off="
      (lambda ()
        (check-raises "junk" oracle-error?
          (lambda () (oracle-normalize (lines "hello"))))))
    (harness-case "a bare off=N"
      (lambda ()
        ;; `trace-format` renders every mark with text after the space, so
        ;; there is no event this could have come from.
        (check-raises "bare" oracle-error?
          (lambda () (oracle-normalize (lines "off=7"))))))
    (harness-case "a bare off=NULL"
      (lambda ()
        (check-raises "bare null" oracle-error?
          (lambda () (oracle-normalize (lines "off=NULL"))))))
    (harness-case "a span whose declared length disagrees with its bytes"
      (lambda ()
        ;; The cross-check that catches a recogniser taking the wrong slice.
        (check-raises "len lies" oracle-error?
          (lambda () (oracle-normalize (lines "off=0 len=9 span[m]=\"GET\""))))))
    (harness-case "a cr line whose length is not one"
      (lambda ()
        (check-raises "len 2 cr" oracle-error?
          (lambda () (oracle-normalize (lines "off=0 len=2 span[m]=cr"))))))
    (harness-case "a span with no closing quote"
      (lambda ()
        (check-raises "unterminated" oracle-error?
          (lambda () (oracle-normalize (lines "off=0 len=3 span[m]=\"GET"))))))
    (harness-case "a span with an unterminated name"
      (lambda ()
        (check-raises "no bracket" oracle-error?
          (lambda () (oracle-normalize (lines "off=0 len=3 span[m"))))))
    (harness-case "an offset with no space after it"
      (lambda ()
        (check-raises "no space" oracle-error?
          (lambda () (oracle-normalize (lines "off=12x message begin"))))))))

(harness-group "the scan markers split a run's output"
  (lambda ()
    (harness-case "each marker starts a block"
      (lambda ()
        (check-equal "two blocks"
                     (map texts
                          (oracle-split-scans
                           (bv (string-append
                                "===== SCAN 1 START =====\n" "off=0 a\n" "off=1 b\n"
                                "===== SCAN 2 START =====\n" "off=0 a\n"))))
                     '(("off=0 a" "off=1 b") ("off=0 a")))))
    (harness-case "a block with no lines is still a block"
      (lambda ()
        ;; A scan that printed nothing is a real outcome and dropping it would
        ;; shift every later block onto the wrong chunk size.
        (check-equal "empty middle"
                     (map texts
                          (oracle-split-scans
                           (bv (string-append "===== SCAN 1 START =====\n"
                                              "===== SCAN 2 START =====\n" "off=0 a\n"))))
                     '(() ("off=0 a")))))
    (harness-case "output before the first marker is refused"
      (lambda ()
        (check-raises "stray" oracle-error?
          (lambda () (oracle-split-scans (bv "noise\n===== SCAN 1 START =====\n"))))))
    (harness-case "no output at all is no blocks"
      (lambda ()
        (check-equal "empty" (oracle-split-scans (bv "")) '())))))

(harness-group "hex carries arbitrary bytes between the processes"
  (lambda ()
    (harness-case "a round trip returns the bytes"
      (lambda ()
        (let ((b (u8-list->bytevector '(0 1 13 10 127 128 255 65))))
          (check-equal "round trip" (oracle-hex-decode (oracle-hex-encode b)) b))))
    (harness-case "the encoding is lower-case and two digits a byte"
      (lambda ()
        (check-equal "encode"
                     (oracle-hex-encode (u8-list->bytevector '(0 15 16 255)))
                     "000f10ff")))
    (harness-case "upper-case input decodes too"
      (lambda ()
        (check-equal "decode" (oracle-hex-decode "0A0b") (u8-list->bytevector '(10 11)))))
    (harness-case "an empty bytevector round trips"
      (lambda ()
        (check-equal "empty" (oracle-hex-encode (u8-list->bytevector '())) "")))
    (harness-case "an odd-length hex string is refused"
      (lambda ()
        (check-raises "odd" oracle-error? (lambda () (oracle-hex-decode "abc")))))
    (harness-case "a non-hex digit is refused"
      (lambda ()
        (check-raises "zz" oracle-error? (lambda () (oracle-hex-decode "zz")))))))

(harness-group "the corpus calibrates the recogniser"
  (lambda ()
    (harness-case "every expected block survives a round trip unchanged"
      (lambda ()
        ;; 253 recorded traces, already in the form upstream's checker
        ;; compares. This is the check that makes the module an instrument
        ;; rather than a guess, and it needs no llhttp.
        (let loop ((files corpus-files) (bad '()) (blocks 0) (rows 0))
          (if (null? files)
              (begin
                (check-equal "blocks that did not round trip" bad '())
                ;; A run that silently compared nothing would otherwise pass.
                (check "every fixture was read" (> blocks 250))
                (check "and its lines" (> rows 2000)))
              (let inner ((fs (corpus-parse-file
                               (read-text (string-append corpus-dir "/" (car files)))))
                          (i 1) (bad bad) (blocks blocks) (rows rows))
                (if (null? fs)
                    (loop (cdr files) bad blocks rows)
                    (let* ((f (car fs))
                           (expected (fixture-expected f))
                           (id (string-append (car files) "#" (number->string i))))
                      (if (exists expectation-pattern? expected)
                          ;; Two url.md fixtures carry a pattern rather than a
                          ;; line; there is no printed text to reconstruct.
                          (inner (cdr fs) (+ i 1) bad blocks rows)
                          (let* ((texts-in (map expectation-text expected))
                                 (out (guard (e (#t (list (string-append
                                                           "refused: "
                                                           (if (oracle-error? e)
                                                               (oracle-error-detail e)
                                                               "unknown")))))
                                       (map (lambda (b) (utf8->string b))
                                            (oracle-normalize (map string->utf8 texts-in))))))
                            (inner (cdr fs) (+ i 1)
                                   (if (equal? out texts-in) bad (cons id bad))
                                   (+ blocks 1)
                                   (+ rows (length texts-in)))))))))))))) 

(harness-finish)
