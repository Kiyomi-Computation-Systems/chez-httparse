;;; Properties of the parser over inputs nobody wrote down.
;;;
;;; The corpus is replayed at every chunk size and compared bit-exactly, so
;;; what it cannot cover is an input it does not contain. This lane takes the
;;; two properties the corpus establishes for its own 190 inputs and asks them
;;; of generated ones instead. It needs no llhttp: both sides of every
;;; comparison here are ours.
;;;
;;; 1. FRAGMENTATION INVARIANCE, FOR A PARSE THAT REACHES NO ERROR. Upstream's
;;;    scan exists because a resumable parser must produce the same trace
;;;    however the bytes arrive. The qualifier was MEASURED, not assumed: over
;;;    240 generated inputs, every one of the 71 that parsed without an error
;;;    was invariant across chunk sizes, and 13 of the 169 that errored were
;;;    not. The exception has its own group below and llhttp shares it exactly,
;;;    so the unqualified property would have been a false one -- and the
;;;    corpus could not have said so, because upstream chose fixtures it holds
;;;    for.
;;;
;;; 2. THE TWO EXECUTORS AGREE. The committed artifact is what ships and the
;;;    interpreter is what the grammar means. The conformance lane compares
;;;    them on corpus inputs; this compares them where no expectation exists,
;;;    which is the only place a compiler bug could hide from that lane.
;;;
;;; A REFUSAL IS A FINDING, NOT A CRASH. The adapter has no row for an outcome
;;; llhttp never prints, and a generated input is the likeliest way to reach
;;; one. Reported here as a failing case naming the seed and the origin, so it
;;; replays exactly.
(import (rnrs)
        (httparse test harness)
        (httparse test corpus-load)
        (httparse test corpus-decode)
        (httparse test generate)
        (httparse test drive)
        (httparse test adapter)
        (httparse grammar)
        (generated httparse-message)
        (byte-machine verify)
        (byte-machine interpret))

(define (read-text path)
  (utf8->string (call-with-port (open-file-input-port path) get-bytevector-all)))

(define corpus-dir (adapter-environment-variable "HTTPARSE_CORPUS_DIR"))

(define seed
  (let ((v (adapter-environment-variable "HTTPARSE_PROPERTY_SEED")))
    (or (and (string? v) (string->number v)) 20260915)))

(define case-count
  (let ((v (adapter-environment-variable "HTTPARSE_PROPERTY_CASES")))
    (or (and (string? v) (string->number v)) 120)))

(define generated httparse-message-machine)
(define interpreted
  (make-interpreted-machine (verify-machine (make-message-machine))))

;; --- bases -------------------------------------------------------------
;;
;; A mutant of a real message lands in the neighbourhood where the grammar's
;; arms are densest, so the corpus supplies the bases. The six fixtures
;; carrying a non-ASCII byte are excluded HERE rather than inside the
;; generator, which refuses them: an unsafe base is a caller's mistake, and
;; silently dropping one inside the generator is how a run gets shorter with
;; nothing to show for it.
(define base-files
  '("request/sample.md" "request/connection.md" "request/content-length.md"
    "request/transfer-encoding.md" "request/method.md" "request/uri.md"
    "response/sample.md" "response/connection.md" "response/content-length.md"
    "response/transfer-encoding.md"))

(define (first-word s)
  (let loop ((i 0))
    (cond ((= i (string-length s)) s)
          ((char=? (string-ref s i) #\-) (substring s 0 i))
          (else (loop (+ i 1))))))

(define (message-kind f)
  (let ((type (fixture-meta-ref f 'type #f)))
    (and (string? type) (string->symbol (first-word type)))))

(define bases
  (let loop ((files base-files) (acc '()))
    (if (null? files)
        (reverse acc)
        (let inner ((fs (corpus-parse-file (read-text (string-append corpus-dir "/" (car files)))))
                    (i 1) (acc acc))
          (if (null? fs)
              (loop (cdr files) acc)
              (let* ((f (car fs))
                     (kind (message-kind f))
                     (bv (corpus-decode-input (fixture-input-text f))))
                (inner (cdr fs) (+ i 1)
                       (if (and (memq kind '(request response))
                                (generate-safe-bytes? bv))
                           (cons (cons kind
                                       (cons (string-append (car files) "#" (number->string i))
                                             bv))
                                 acc)
                           acc))))))))

(define cases
  (append (generate-structured seed case-count)
          (generate-mutants seed case-count bases)))

(define (trace-text lines)
  (harness-join (map utf8->string lines) "\n"))

(define (describe c) (gen-case-origin c))

(harness-begin "property.generated-input")

(harness-group "the parser produces a trace for every generated input"
  (lambda ()
    (harness-case "no generated input reaches an outcome the adapter cannot name"
      (lambda ()
        (let loop ((cs cases) (refused '()))
          (cond
           ((null? cs)
            (check-equal "refusals" refused '()))
           (else
            (let ((t (drive-trace generated (gen-case-kind (car cs))
                                  (gen-case-bytes (car cs))
                                  (max 1 (bytevector-length (gen-case-bytes (car cs)))))))
              (loop (cdr cs)
                    (if (drive-refusal? t)
                        (cons (string-append (describe (car cs)) " :: "
                                             (drive-refusal-detail t))
                              refused)
                        refused))))))))))

(define (has-error? lines)
  (exists (lambda (l) (harness-string-contains? (utf8->string l) "error code="))
          lines))

(harness-group "a parse that reaches no error does not depend on how the bytes arrive"
  (lambda ()
    (harness-case "every chunk size yields the trace the whole buffer does"
      (lambda ()
        (let loop ((cs cases) (bad '()) (clean 0))
          (cond
           ((null? cs)
            (check-equal "divergences" bad '())
            ;; Without a floor this passes by selecting nothing: a generator
            ;; that only ever produced errors would leave it green.
            (check "enough error-free inputs to be a property"
                   (> clean 20)))
           (else
            (let* ((c (car cs))
                   (bv (gen-case-bytes c))
                   (len (bytevector-length bv))
                   (whole (drive-trace generated (gen-case-kind c) bv (max 1 len))))
              (if (or (drive-refusal? whole) (has-error? whole))
                  (loop (cdr cs) bad clean)
                  (let ((ref (trace-text whole)))
                    (let inner ((ss (drive-chunk-ladder len)) (bad bad))
                      (if (null? ss)
                          (loop (cdr cs) bad (+ clean 1))
                          (let ((t (drive-trace generated (gen-case-kind c) bv (car ss))))
                            (inner (cdr ss)
                                   (if (and (not (drive-refusal? t))
                                            (string=? (trace-text t) ref))
                                       bad
                                       (cons (string-append
                                              (describe c) " at chunk size "
                                              (number->string (car ss)))
                                             bad)))))))))))))))) 

;; --- the exception, measured against a live llhttp ------------------------
;;
;; A span the parse never closed is printed only for the bytes a chunk
;; boundary already flushed, so the same input traces differently at
;; different chunk sizes. BOTH TRACES BELOW ARE llhttp'S OWN OUTPUT, taken
;; from its fixture binary at v9.4.3-1-gee51043 -- the whole-buffer one
;; verbatim, the one-byte one through the same coalescing upstream's checker
;; applies. They are not this parser's output written down.
;;
;; The input is a generated one: a header name with a space before its colon,
;; which is a token error. At 52 bytes the name span is open when the error
;; fires and llhttp prints nothing for it; at one byte at a time the boundary
;; flushes have already printed all seven bytes, which coalesce into one line.
(define unclosed-span-input
  (string->utf8 "ICE/2.0 102 OK\r\nUpgrade:websocket\r\nTrailer : X-T\r\n\r\n"))

(define (trace-of size)
  (let ((t (drive-trace generated 'response unclosed-span-input size)))
    (if (drive-refusal? t)
        (list (string-append "refused: " (drive-refusal-detail t)))
        (map utf8->string t))))

(define unclosed-span-prefix
  '("off=0 message begin"
    "off=0 len=3 span[protocol]=\"ICE\""
    "off=3 protocol complete"
    "off=4 len=3 span[version]=\"2.0\""
    "off=7 version complete"
    "off=12 len=2 span[status]=\"OK\""
    "off=16 status complete"
    "off=16 len=7 span[header_field]=\"Upgrade\""
    "off=24 header_field complete"
    "off=24 len=9 span[header_value]=\"websocket\""
    "off=35 header_value complete"))

(harness-group "a span still open when the parse fails"
  (lambda ()
    (harness-case "the whole buffer never prints it"
      (lambda ()
        (check-equal "52 bytes at once"
                     (trace-of 52)
                     (append unclosed-span-prefix
                             '("off=42 error code=10 reason=\"Invalid header token\"")))))
    (harness-case "one byte at a time prints what the boundaries flushed"
      (lambda ()
        (check-equal "size 1"
                     (trace-of 1)
                     (append unclosed-span-prefix
                             '("off=35 len=7 span[header_field]=\"Trailer\""
                               "off=42 error code=10 reason=\"Invalid header token\"")))))
    (harness-case "so the two differ, which is the whole point of the case"
      (lambda ()
        ;; Stated as a check because the two cases above would both pass if
        ;; someone made them the same by accident.
        (check-not-equal "52 vs 1" (trace-of 52) (trace-of 1))))))

(harness-group "the shipped artifact and the grammar agree"
  (lambda ()
    (harness-case "both executors produce the same trace for every generated input"
      (lambda ()
        ;; The conformance lane makes this comparison over the corpus. Here it
        ;; is made where nothing recorded the answer, which is the only place
        ;; an emitter bug could survive that lane.
        (let loop ((cs cases) (bad '()) (checked 0))
          (cond
           ((null? cs)
            (check-equal "divergences" bad '())
            (check "some comparisons happened" (> checked 0)))
           (else
            (let* ((c (car cs))
                   (bv (gen-case-bytes c))
                   (size (max 1 (bytevector-length bv)))
                   (a (drive-trace generated (gen-case-kind c) bv size))
                   (b (drive-trace interpreted (gen-case-kind c) bv size))
                   (same (cond ((and (drive-refusal? a) (drive-refusal? b))
                                (string=? (drive-refusal-detail a)
                                          (drive-refusal-detail b)))
                               ((or (drive-refusal? a) (drive-refusal? b)) #f)
                               (else (string=? (trace-text a) (trace-text b))))))
              (loop (cdr cs)
                    (if same bad (cons (describe c) bad))
                    (+ checked 1))))))))))

(harness-finish)
