;;; A throughput baseline.
;;;
;;; THE NUMBERS ARE PRINTED, NOT ASSERTED. A measured rate moves with the
;;; machine, the build and whatever else is running, so writing one into a
;;; check would produce a lane that fails for reasons that are not about this
;;; code -- and then gets its number edited, which is worse than not measuring.
;;; What IS asserted is a floor so loose that only a change of kind can cross
;;; it: an accidental quadratic, a per-byte allocation, a rescan of consumed
;;; input. Anything subtler belongs in a comparison between two runs, not in
;;; a pass or a fail.
;;;
;;; AND THE PARSE MUST BE A REAL ONE. A benchmark that measures a parser
;;; erroring on the first byte is fast and meaningless, so each case checks
;;; that the message actually completed before it reports a rate.
;;;
;;; This lane carries the `benchmark` label, which the pull-request preset
;;; does not select; it runs in the release selection. It is registered in
;;; both execution modes, and they agree: Chez compiles on load, so a
;;; `.chez.source` run and a `.chez.aot` run execute the same native code and
;;; ahead-of-time compilation buys startup rather than throughput. Every
;;; figure below prints its mode so the two runs can be told apart in one log.
;;; test/CMakeLists.txt records the measurement behind that claim.
(import (rnrs)
        (httparse test harness)
        (generated httparse-message)
        (httparse modes)
        (byte-machine runtime))

(define completed 0)

(define (bindings)
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
        (list 'on-message-complete
              (lambda (p ctx) (set! completed (+ completed 1)) callback-continue))))

;; A request with the header section a real client sends, because the header
;; loop is where nearly all the bytes of a real message go.
(define request
  (string->utf8
   (string-append
    "GET /wiki/Special:Random HTTP/1.1\r\n"
    "Host: en.wikipedia.org\r\n"
    "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)\r\n"
    "Accept: text/html,application/xhtml+xml,application/xml;q=0.9\r\n"
    "Accept-Language: en-GB,en;q=0.5\r\n"
    "Accept-Encoding: gzip, deflate, br\r\n"
    "Connection: keep-alive\r\n"
    "Upgrade-Insecure-Requests: 1\r\n"
    "\r\n")))

(define response
  (string->utf8
   (string-append
    "HTTP/1.1 200 OK\r\n"
    "Date: Mon, 15 Sep 2026 12:00:00 GMT\r\n"
    "Content-Type: text/html; charset=UTF-8\r\n"
    "Content-Length: 1024\r\n"
    "Connection: keep-alive\r\n"
    "\r\n"
    (let loop ((i 0) (acc '()))
      (if (= i 1024) (apply string-append acc) (loop (+ i 1) (cons "x" acc)))))))

;; parse-n : Bytevector Symbol Nat Nat -> Nat
;; Parse `bv` `reps` times in `chunk`-byte feeds; returns elapsed milliseconds.
(define (parse-n bv kind chunk reps)
  (let ((len (bytevector-length bv)))
    (define (one)
      (let ((p (make-parser httparse-message-machine (bindings) #f
                            (list (cons 'type (httparse-message-type-value kind))))))
        (let loop ((at 0))
          (when (< at len)
            (let* ((end (min (+ at chunk) len))
                   (r (parser-feed! p bv at end)))
              (when (eq? (parser-result-status r) 'need-input)
                (loop end)))))))
    (one)
    ;; Only the timed repetitions are counted, so the calibration below can
    ;; parse as many times as it likes without the completion check having to
    ;; know how many attempts it took.
    (set! completed 0)
    (let ((start (adapter-real-time)))
      (let loop ((i 0)) (when (< i reps) (one) (loop (+ i 1))))
      ;; The RAW reading, zero included. Guarding against dividing by it is
      ;; `report`'s job, so that the case can see what the clock actually
      ;; said rather than a floor standing in for it.
      (- (adapter-real-time) start))))

;; A RATE COMPUTED OVER AN INTERVAL THE CLOCK CANNOT RESOLVE IS A FABRICATED
;; NUMBER, and a fabricated number sails over every floor in this file --
;; the smaller the interval, the larger the rate. `adapter-real-time` reads
;; milliseconds, so a region that finishes in a handful of them is mostly
;; quantisation.
;;
;; THE REPETITION COUNT IS CALIBRATED, NOT CHOSEN. A literal count is right
;; for one parser on one machine: when the parser gets faster, the same count
;; measures a shorter region, until it lands on the floor below. A number that
;; has to be re-tuned whenever the code gets faster is a number that will be
;; re-tuned late, and the symptom of re-tuning it late is a flattering rate
;; rather than a red lane. So each case doubles its repetitions until the
;; region is worth timing, and reports the count it arrived at.
(define target-ms 50)
(define calibration-cap 4000000)

;; measure : Bytevector Symbol Nat -> (values Nat Nat)
;; Repetitions and elapsed milliseconds, doubled until the region clears
;; `target-ms` or the cap refuses to keep going.
(define (measure bv kind chunk)
  (let loop ((reps 100))
    (let ((ms (parse-n bv kind chunk reps)))
      (if (or (>= ms target-ms) (>= reps calibration-cap))
          (values reps ms)
          (loop (* reps 2))))))

;; The floor is not a statement about a chosen count -- it is what fires if
;; calibration hit its cap without ever clearing the clock, which is the one
;; way this lane can still print a fabricated rate.
(define minimum-measurable-ms 10)

(define (check-measurable label ms)
  (check (string-append "the " label " region outlasts the clock's resolution"
                        " (measured " (number->string ms) "ms, floor "
                        (number->string minimum-measurable-ms) "ms)")
         (>= ms minimum-measurable-ms)))

;; Every figure carries the execution mode, because this lane is registered in
;; BOTH and one release log holds both runs' lines. Without it the six lines
;; below are six plausible numbers with no way to tell which run printed
;; which.
(define (report label bytes reps raw-ms)
  (let* ((ms (max 1 raw-ms))
         (per-sec (div (* 1000 reps) ms))
         (mb-per-sec (div (* 1000 bytes reps) (* ms 1048576))))
    (display (string-append "httparse-benchmark: " (adapter-execution-mode)
                            " " label
                            " " (number->string bytes) "B x" (number->string reps)
                            " in " (number->string ms) "ms = "
                            (number->string per-sec) " msg/s, "
                            (number->string mb-per-sec) " MB/s\n"))
    (adapter-flush-output)
    mb-per-sec))

(harness-begin "benchmark.throughput")

(harness-group "whole-buffer throughput"
  (lambda ()
    (harness-case "a request with a real header section"
      (lambda ()
        (let*-values (((reps ms) (measure request 'request (bytevector-length request))))
          (let ((rate (report "request/whole" (bytevector-length request) reps ms)))
            (check-equal "every repetition completed a message" completed reps)
            (check-measurable "request/whole" ms)
            ;; The floor is a change of KIND, not a regression threshold.
            (check (string-append "above 1 MB/s (measured " (number->string rate) ")")
                   (>= rate 1))))))
    (harness-case "a response with a kilobyte body"
      (lambda ()
        (let*-values (((reps ms) (measure response 'response (bytevector-length response))))
          (let ((rate (report "response/whole" (bytevector-length response) reps ms)))
            (check-equal "every repetition completed a message" completed reps)
            (check-measurable "response/whole" ms)
            (check (string-append "above 1 MB/s (measured " (number->string rate) ")")
                   (>= rate 1))))))))

(harness-group "the cost of arriving in pieces"
  (lambda ()
    (harness-case "the same request one byte at a time"
      (lambda ()
        ;; The worst case a resumable parser can be asked for, and the figure
        ;; an embedder reading from a socket a byte at a time would see.
        (let*-values (((reps ms) (measure request 'request 1)))
          (let ((rate (report "request/1-byte-feeds" (bytevector-length request) reps ms)))
            (check-equal "every repetition completed a message" completed reps)
            (check-measurable "request/1-byte-feeds" ms)
            (check (string-append "above 0.1 MB/s (measured " (number->string rate) ")")
                   (>= (* 10 rate) 1))))))))

(harness-finish)
