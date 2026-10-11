;;; (httparse test oracle): read a live llhttp fixture binary's output back
;;; into the same trace the parser is measured against.
;;;
;;; WHY THIS EXISTS. A live llhttp sits behind a local, opt-in lane whose job
;;; is generated input. Upstream's binary prints RAW trace lines; upstream's
;;; JavaScript checker then coalesces adjacent span fragments before comparing
;;; (`normalizeSpans`), which is why a corpus fixture matches at every chunk
;;; size. Our side already reproduces that step -- `trace-format` does it --
;;; so the whole job here is turning a printed line back into the EVENT it was
;;; printed from, and letting the existing renderer do the rest.
;;; Reimplementing the coalescing beside it would be a second copy of a subtle
;;; rule.
;;;
;;; THE RECOGNISER IS THE PART THAT CAN FAIL SILENTLY, by matching less than
;;; it should and dropping a line into the catch-all. Two things guard it.
;;; First, a quoted span line carries its own length, so the parse is checked
;;; against `len=` and a disagreement is a refusal rather than a shorter
;;; comparison. Second, the corpus's expected blocks are already normalised:
;;; running them through this module must give them back unchanged, which is
;;; a check that needs no llhttp and runs on every pull request.
;;;
;;; AN UNRECOGNISED LINE IS REFUSED, NOT PASSED THROUGH. A line this module
;;; cannot place is a line the differential would compare as opaque text,
;;; which is how a real divergence becomes a match.
(library (httparse test oracle)
  (export oracle-line->event oracle-normalize
          oracle-split-scans
          oracle-hex-encode oracle-hex-decode
          oracle-error? oracle-error-detail)
  (import (rnrs) (httparse test trace-format))

  (define-condition-type &oracle &error
    make-oracle-error oracle-error? (detail oracle-error-detail))

  (define (refuse detail)
    (raise (condition (make-oracle-error detail)
                      (make-who-condition 'oracle)
                      (make-message-condition detail))))

  (define (bv-slice bv from to)
    (let ((out (make-bytevector (- to from))))
      (bytevector-copy! bv from out 0 (- to from))
      out))

  ;; starts-with? : Bytevector Nat String -> Boolean
  (define (starts-with? bv at s)
    (let ((n (string-length s)) (len (bytevector-length bv)))
      (and (<= (+ at n) len)
           (let loop ((i 0))
             (or (= i n)
                 (and (= (bytevector-u8-ref bv (+ at i))
                         (char->integer (string-ref s i)))
                      (loop (+ i 1))))))))

  (define (digit-at bv i)
    (and (< i (bytevector-length bv))
         (let ((b (bytevector-u8-ref bv i)))
           (and (>= b 48) (<= b 57) (- b 48)))))

  ;; read-nat : Bytevector Nat -> (values Nat Nat) -- value and the index after
  (define (read-nat bv at)
    (let loop ((i at) (acc 0) (any #f))
      (let ((d (digit-at bv i)))
        (cond (d (loop (+ i 1) (+ (* acc 10) d) #t))
              (any (values acc i))
              (else (refuse "expected a number"))))))

  (define (byte-at bv i)
    (and (< i (bytevector-length bv)) (bytevector-u8-ref bv i)))

  ;; oracle-line->event : Bytevector -> Event
  ;; One printed line, as the event `trace-format` would have rendered it
  ;; from. A `=cr` or `=lf` line is a one-byte span, which is exactly what
  ;; `trace-expand-span` turns back into that same line.
  (define (oracle-line->event line)
    (unless (starts-with? line 0 "off=")
      (refuse (string-append "line does not begin with off=: "
                             (bytes->text line))))
    (if (starts-with? line 4 "NULL")
        (cond
         ((= (bytevector-length line) 8)
          (refuse (string-append "a bare off=NULL carries no text: " (bytes->text line))))
         ((= (byte-at line 8) 32)
          (make-trace-mark-at-null (bytes->text (bv-slice line 9 (bytevector-length line)))))
         (else (refuse (string-append "unparsable off=NULL line: " (bytes->text line)))))
        (let-values (((off after) (read-nat line 4)))
          (cond
           ((= after (bytevector-length line))
            ;; `trace-format` renders every mark with a space and some text, so
            ;; a bare `off=N` is a line this module has no event for.
            (refuse (string-append "a bare off=N carries no text: " (bytes->text line))))
           ((not (= (byte-at line after) 32))
            (refuse (string-append "expected a space after the offset: "
                                   (bytes->text line))))
           ((starts-with? line (+ after 1) "len=")
            (span-event line off (+ after 5)))
           (else
            (make-trace-mark off (bytes->text
                                  (bv-slice line (+ after 1)
                                            (bytevector-length line)))))))))

  ;; span-event : Bytevector Nat Nat -> Event
  ;; `at` is just past "len=". The declared length is CHECKED against the
  ;; bytes recovered, so a recogniser that took the wrong substring fails
  ;; here instead of producing a plausible shorter span.
  (define (span-event line off at)
    (let*-values (((len after) (read-nat line at)))
      (unless (starts-with? line after " span[")
        (refuse (string-append "expected span[ after len=: " (bytes->text line))))
      (let ((name-start (+ after 6)))
        (let loop ((i name-start))
          (cond
           ((>= i (bytevector-length line))
            (refuse (string-append "unterminated span name: " (bytes->text line))))
           ((= (bytevector-u8-ref line i) (char->integer #\]))
            (let ((name (bytes->text (bv-slice line name-start i))))
              (unless (starts-with? line (+ i 1) "=")
                (refuse (string-append "expected ]= : " (bytes->text line))))
              (let ((rest (+ i 2)) (end (bytevector-length line)))
                (cond
                 ((and (= (- end rest) 2) (starts-with? line rest "cr"))
                  (check-len len 1 line)
                  (make-trace-span name off (u8-list->bytevector '(13))))
                 ((and (= (- end rest) 2) (starts-with? line rest "lf"))
                  (check-len len 1 line)
                  (make-trace-span name off (u8-list->bytevector '(10))))
                 ((and (>= (- end rest) 2)
                       (= (byte-at line rest) (char->integer #\"))
                       (= (byte-at line (- end 1)) (char->integer #\")))
                  (let ((bytes (bv-slice line (+ rest 1) (- end 1))))
                    (check-len len (bytevector-length bytes) line)
                    (make-trace-span name off bytes)))
                 (else
                  (refuse (string-append "unparsable span body: "
                                         (bytes->text line))))))))
           (else (loop (+ i 1))))))))

  (define (check-len declared actual line)
    (unless (= declared actual)
      (refuse (string-append "len=" (number->string declared)
                             " but recovered " (number->string actual)
                             " bytes: " (bytes->text line)))))

  ;; A diagnostic rendering only. Trace content is raw input bytes and a
  ;; generated input is ASCII by construction, but a refusal must never fail
  ;; while describing what it refused.
  (define (bytes->text bv)
    (let loop ((i 0) (acc '()))
      (if (= i (bytevector-length bv))
          (list->string (reverse acc))
          (let ((b (bytevector-u8-ref bv i)))
            (loop (+ i 1)
                  (cons (if (and (>= b 32) (< b 127)) (integer->char b) #\?) acc))))))

  ;; oracle-normalize : (Listof Bytevector) -> (Listof Bytevector)
  ;; Raw printed lines in, the trace the comparison expects out.
  (define (oracle-normalize lines)
    (trace-format (map oracle-line->event lines)))

  ;; oracle-split-scans : Bytevector -> (Listof (Listof Bytevector))
  ;; The binary prints `===== SCAN n START =====` before each run's output.
  ;; Everything before the first marker is refused rather than dropped: it
  ;; would be output nobody asked for.
  (define (oracle-split-scans out)
    (let* ((lines (split-lines out))
           (marker "===== SCAN "))
      (let loop ((ls lines) (current #f) (acc '()))
        (cond
         ((null? ls)
          (reverse (if current (cons (reverse current) acc) acc)))
         ((starts-with? (car ls) 0 marker)
          (loop (cdr ls) '() (if current (cons (reverse current) acc) acc)))
         ((not current)
          (refuse (string-append "output before the first scan marker: "
                                 (bytes->text (car ls)))))
         (else (loop (cdr ls) (cons (car ls) current) acc))))))

  (define (split-lines bv)
    (let ((n (bytevector-length bv)))
      (let loop ((start 0) (i 0) (acc '()))
        (cond
         ((= i n)
          (reverse (if (> i start) (cons (bv-slice bv start i) acc) acc)))
         ((= (bytevector-u8-ref bv i) 10)
          (loop (+ i 1) (+ i 1) (cons (bv-slice bv start i) acc)))
         (else (loop start (+ i 1) acc))))))

  ;; --- the wire format between this lane and its runner ---------------------
  ;;
  ;; Inputs and traces are arbitrary bytes, and the runner is a separate
  ;; process, so both cross as hex. It is twice the size and it cannot be
  ;; corrupted by a newline, a quote, or a shell.

  (define hex-digits "0123456789abcdef")

  ;; R6RS keeps `string-set!` out of the base library, so this builds the
  ;; characters and converts once rather than importing a mutable-string
  ;; library for one loop.
  (define (oracle-hex-encode bv)
    (let loop ((i (- (bytevector-length bv) 1)) (acc '()))
      (if (< i 0)
          (list->string acc)
          (let ((b (bytevector-u8-ref bv i)))
            (loop (- i 1)
                  (cons (string-ref hex-digits (div b 16))
                        (cons (string-ref hex-digits (mod b 16)) acc)))))))

  (define (hex-value ch)
    (cond ((and (char>=? ch #\0) (char<=? ch #\9)) (- (char->integer ch) 48))
          ((and (char>=? ch #\a) (char<=? ch #\f)) (+ 10 (- (char->integer ch) 97)))
          ((and (char>=? ch #\A) (char<=? ch #\F)) (+ 10 (- (char->integer ch) 65)))
          (else (refuse (string (integer->char 91) ch (integer->char 93))))))

  (define (oracle-hex-decode s)
    (let ((n (string-length s)))
      (when (odd? n) (refuse "a hex string must have an even length"))
      (let* ((out (make-bytevector (div n 2))))
        (let loop ((i 0))
          (if (= i (div n 2))
              out
              (begin
                (bytevector-u8-set! out i (+ (* 16 (hex-value (string-ref s (* 2 i))))
                                             (hex-value (string-ref s (+ (* 2 i) 1)))))
                (loop (+ i 1))))))))
)
