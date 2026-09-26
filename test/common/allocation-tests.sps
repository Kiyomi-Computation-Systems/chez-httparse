;;; What parsing costs in allocation.
;;;
;;; THE CLAIM IS A SHAPE, NOT A NUMBER. An absolute byte count read off this
;;; parser and written into a test is a snapshot: it passes until someone
;;; changes anything, and then it is edited rather than thought about. What is
;;; worth asserting is the property an embedder depends on -- that feeding a
;;; megabyte does not allocate a megabyte -- and that is a statement about how
;;; the cost SCALES, which no amount of tuning can satisfy by accident.
;;;
;;; SPANS ARE HANDED OUT AS BOUNDS INTO THE CALLER'S BUFFER. A span callback
;;; receives `(bv from to)` and copies nothing; the trace recorder copies
;;; because a trace is text, which is exactly why the recorder is not what is
;;; measured here. These bindings do nothing at all, so what is left is the
;;; parser.
;;;
;;; THE READING IS A DIFFERENCE, AND IT HAD BETTER BE A CUMULATIVE ONE.
;;; `adapter-bytes-allocated` counts everything since startup, so only a
;;; before-and-after pair means anything, and the region runs repeatedly so
;;; that one-off costs -- the parser record, the first feed's internal growth
;;; -- are divided away. The first version of this lane read a LIVE-HEAP
;;; counter instead and reported a region as allocating -33122 bytes, which
;;; is what a collection inside the region looks like; the case at the bottom
;;; is there so that a counter which stopped counting could not pass.
(import (rnrs)
        (httparse test harness)
        (generated httparse-message)
        (httparse modes)
        (byte-machine runtime))

;; Every callback is `required?`, so all of them are bound; none of them does
;; anything, which is the point. The message TYPE is not among them -- it is a
;; settable field, written at construction, so it costs no callback and no
;; allocation.
(define (silent-bindings)
  (define (event p ctx) callback-continue)
  (define (span p ctx bv from to) callback-continue)
  (list (list 'on-reset event)
        (list 'on-message-begin event)
        (list 'on-method-data span)
        (list 'on-method-complete event)
        (list 'on-url-data span)
        (list 'on-url-complete event)
        (list 'on-protocol-data span)
        (list 'on-protocol-complete event)
        (list 'on-version-data span)
        (list 'on-version-complete event)
        (list 'on-status-data span)
        (list 'on-status-complete event)
        (list 'on-header-field-data span)
        (list 'on-header-field-complete event)
        (list 'on-header-value-data span)
        (list 'on-header-value-complete event)
        (list 'on-headers-complete event)
        (list 'on-body-data span)
        (list 'on-chunk-header event)
        (list 'on-chunk-extension-name-data span)
        (list 'on-chunk-extension-name-complete event)
        (list 'on-chunk-extension-value-data span)
        (list 'on-chunk-extension-value-complete event)
        (list 'on-chunk-complete event)
        (list 'on-message-complete event)))

(define (message-with-body n)
  (string->utf8
   (string-append "POST /u HTTP/1.1\r\nContent-Length: " (number->string n)
                  "\r\n\r\n"
                  (let loop ((i 0) (acc '()))
                    (if (= i n) (apply string-append acc) (loop (+ i 1) (cons "x" acc)))))))

;; allocated-per-parse : Bytevector Nat Nat -> Nat
;; Bytes allocated per whole parse of `bv`, fed in `chunk`-byte pieces,
;; averaged over `reps`.
(define (allocated-per-parse bv chunk reps)
  (let ((len (bytevector-length bv)))
    (define (one)
      (let ((p (make-parser httparse-message-machine (silent-bindings) #f
                            (list (cons 'type (httparse-message-type-value 'request))))))
        (let loop ((at 0))
          (if (>= at len)
              #t
              (let* ((end (min (+ at chunk) len))
                     (r (parser-feed! p bv at end)))
                (if (eq? (parser-result-status r) 'need-input)
                    (loop end)
                    #t))))))
    ;; One untimed pass first: the very first parse pays for whatever the
    ;; runtime lazily builds, and charging that to the average would make a
    ;; small `reps` read high.
    (one)
    (let ((before (adapter-bytes-allocated)))
      (let loop ((i 0)) (when (< i reps) (one) (loop (+ i 1))))
      (div (- (adapter-bytes-allocated) before) reps))))

(define small (message-with-body 10))
(define large (message-with-body 10000))

(harness-begin "property.allocation")

(harness-group "parsing does not allocate in proportion to the input"
  (lambda ()
    (harness-case "a body a thousand times longer costs about the same"
      (lambda ()
        ;; The property an embedder depends on: a span is a pair of bounds
        ;; into the caller's buffer, so a large body is not copied anywhere.
        ;; A parser that COPIED would show a thousandfold difference here; the
        ;; factor of four allows for the arithmetic a longer content-length
        ;; and a longer loop genuinely do, without allowing a copy.
        (let ((s (allocated-per-parse small (bytevector-length small) 200))
              (l (allocated-per-parse large (bytevector-length large) 200)))
          (display (string-append "httparse-allocation: " (adapter-execution-mode)
                                  " whole-buffer small="
                                  (number->string s) "B large="
                                  (number->string l) "B ratio="
                                  (number->string (div (* 100 (max l 1)) (max s 1)))
                                  "%\n"))
          (adapter-flush-output)
          (check "the small parse allocates at all" (> s 0))
          (check (string-append "large " (number->string l)
                                " is within 4x of small " (number->string s))
                 (<= l (* 4 s)))
          ;; And the absolute cost is not per byte: 10000 body bytes at even
          ;; one byte each would be 10000.
          (check "well under one byte allocated per body byte"
                 (< l 10000)))))
    (harness-case "a feed costs the same whatever has been fed before it"
      (lambda ()
        ;; Each `parser-feed!` returns a result, so a chunked parse allocates
        ;; in proportion to the NUMBER OF FEEDS -- that much is by design and
        ;; the figure is printed rather than asserted. What must not happen is
        ;; a per-feed cost that GROWS as the parse goes on, which is what
        ;; re-scanning or re-copying consumed input would look like.
        (let* ((sn (bytevector-length small))
               (ln (bytevector-length large))
               (s-whole (allocated-per-parse small sn 200))
               (l-whole (allocated-per-parse large ln 20))
               (s-per (div (- (allocated-per-parse small 1 200) s-whole) sn))
               (l-per (div (- (allocated-per-parse large 1 20) l-whole) ln)))
          (display (string-append "httparse-allocation: per-feed "
                                  (number->string sn) "B message=" (number->string s-per)
                                  "B  " (number->string ln) "B message="
                                  (number->string l-per) "B\n"))
          (adapter-flush-output)
          (check "a feed costs something" (> s-per 0))
          ;; A message two hundred times longer, fed a byte at a time, pays
          ;; the same per feed. A parser accumulating anything across feeds
          ;; would show the long one costing more.
          (check (string-append "long " (number->string l-per)
                                "B per feed is within half of short "
                                (number->string s-per) "B")
                 (and (<= (* 2 l-per) (* 3 s-per))
                      (>= (* 2 l-per) s-per))))))))

;; A request carrying one 17-byte field name whose first k bytes are
;; `Transfer-Encoding` and whose rest is `x`. Below 17 it is an ordinary field,
;; so every k parses the same way; only how far the header-name keyword table
;; walks before it misses changes.
(define (request-with-near-miss k)
  (string->utf8
   (string-append "GET / HTTP/1.1\r\nHost: a\r\n"
                  (substring "Transfer-Encoding" 0 k) (make-string (- 17 k) #\x)
                  ": v\r\n\r\n")))

(harness-group "a header name costs the same however much of a keyword it matches"
  (lambda ()
    (harness-case "a near-miss of transfer-encoding allocates what an ordinary name does"
      (lambda ()
        ;; The generator's keyword walk once copied the prefix it had matched on
        ;; every byte (upstream issue #139), so this parse cost 16 bytes more
        ;; for each matched byte than the one before: about 2,900 more at k=16
        ;; than at k=0, and a client repeating the field multiplied it. The
        ;; claim is the shape: the per-parse figure does not depend on k. Within
        ;; 32 bytes rather than exactly: at the old pin this average read 4 bytes
        ;; apart between the source and AOT lanes for the same k, and 32 is half
        ;; of what ONE matched byte cost under the defect, so k=1 still fails it.
        (let* ((ks '(0 1 2 4 8 12 16))
               (costs (map (lambda (k)
                             (let ((bv (request-with-near-miss k)))
                               (cons k (allocated-per-parse bv (bytevector-length bv) 200))))
                           ks))
               (base (cdr (car costs)))
               (grew (filter (lambda (c) (> (abs (- (cdr c) base)) 32)) costs)))
          (display (string-append "httparse-allocation: near-miss k=0 "
                                  (number->string base) "B k=16 "
                                  (number->string (cdr (assv 16 costs))) "B\n"))
          (adapter-flush-output)
          (check-equal "every k was measured" (length costs) (length ks))
          (check-equal "no k cost more than 32 bytes beyond k=0 (k . bytes per parse)"
                       (map (lambda (c) (cons (car c) (- (cdr c) base))) grew)
                       '()))))))

(harness-group "the reading is a difference, not a total"
  (lambda ()
    (harness-case "the counter moves when something allocates"
      (lambda ()
        ;; Calibration: an instrument that always reported zero would make
        ;; every claim above pass.
        (let* ((before (adapter-bytes-allocated))
               (junk (make-bytevector 100000 0))
               (after (adapter-bytes-allocated)))
          (check "a 100000-byte bytevector is visible"
                 (>= (- after before) 100000))
          (check "and the bytevector is real" (= (bytevector-length junk) 100000)))))
    (harness-case "and it does not move on its own"
      (lambda ()
        (let* ((a (adapter-bytes-allocated))
               (b (adapter-bytes-allocated)))
          ;; Not zero necessarily -- the call itself may allocate -- but small.
          (check "two readings in a row are close" (< (- b a) 4096)))))
    (harness-case "and it never goes backwards"
      (lambda ()
        ;; A live-heap counter falls when memory is reclaimed, which turns
        ;; every measurement above into noise and some of them negative.
        (let loop ((i 0) (last (adapter-bytes-allocated)) (worst 0))
          (if (= i 40)
              (check "no reading was lower than the one before it"
                     (= worst 0))
              (let ((junk (make-bytevector 50000 0)))
                (let ((now (adapter-bytes-allocated)))
                  (loop (+ i 1) now
                        (if (< now last) (- last now) worst))))))))))

(harness-finish)
