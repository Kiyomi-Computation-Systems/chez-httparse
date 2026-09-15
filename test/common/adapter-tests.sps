;;; Tests for (httparse test adapter): the rename tables, judged alone.
;;;
;;; Decision 0008 item 2 makes this layer a table lookup with no default, so
;;; what is checked here is mostly what it REFUSES. A table that quietly
;;; defaulted would let a parser reporting the wrong thing render a trace that
;;; matches, which is the one failure the corpus cannot catch by itself.
;;;
;;; No parser runs here. The events are hand-built, as decision 0008 item 4
;;; requires of the instrument.
(import (rnrs)
        (httparse test harness)
        (httparse test adapter)
        (httparse test trace-format))

(define (line . events) (map utf8->string (trace-format events)))

(define (refuses? thunk)
  (call/cc (lambda (k)
             (with-exception-handler
              (lambda (e) (k (adapter-error? e)))
              (lambda () (thunk) #f)))))

(harness-begin "unit.adapter")

(harness-group "the callback table"
  (lambda ()
    (harness-case "an event renders as llhttp's own words at its offset"
      (lambda ()
        (check-equal "message begin"
                     (line (adapter-event-for 'on-message-begin 0 #f #f))
                     '("off=0 message begin"))
        (check-equal "method complete"
                     (line (adapter-event-for 'on-method-complete 7 #f #f))
                     '("off=7 method complete"))))
    (harness-case "a span renders as llhttp's span line"
      (lambda ()
        (check-equal "method span"
                     (line (adapter-event-for 'on-method-data 0 (string->utf8 "OPTIONS") #f))
                     '("off=0 len=7 span[method]=\"OPTIONS\""))))
    (harness-case "every declared callback has a row, and the kinds are right"
      (lambda ()
        ;; A callback added to the grammar without a row here raises at the
        ;; first fixture that reaches it rather than being rendered as
        ;; something plausible.
        (check-equal "rows" (length adapter-trace-names) 16)
        (check-equal "spans"
                     (map car (filter (lambda (r) (eq? (cadr r) 'span))
                                      adapter-trace-names))
                     '(on-method-data on-url-data on-protocol-data on-version-data
                       on-header-field-data on-header-value-data on-body-data))))
    (harness-case "an unknown callback is refused, not guessed"
      (lambda ()
        (check "refused"
               (refuses? (lambda () (adapter-event-for 'on-chunk-header 0
                                                       (string->utf8 "X") #f))))))
    (harness-case "a state line renders llhttp's four numbers, and only from fields"
      (lambda ()
        ;; request/sample.md#1's last-but-one line, built here from field
        ;; values rather than from a parser -- the instrument is calibrated
        ;; before it is used (decision 0008 item 4).
        (check-equal "sample.md#1"
                     (line (adapter-event-for 'on-headers-complete 60 #f
                                              '((method . 6) (http-major . 1)
                                                (http-minor . 1) (flags . 0)
                                                (content-length . 0))))
                     '("off=60 headers complete method=6 v=1/1 flags=0 content_length=0"))
        ;; `%x` IS LOWERCASE. Chez's own `number->string` radix 16 is not, and
        ;; the corpus records `flags=20a` for a chunked request that closes.
        (check-equal "flags render in lowercase hex"
                     (line (adapter-event-for 'on-headers-complete 42 #f
                                              '((method . 3) (http-major . 1)
                                                (http-minor . 1) (flags . 522)
                                                (content-length . 0))))
                     '("off=42 headers complete method=3 v=1/1 flags=20a content_length=0"))
        ;; A 21-digit content length is llhttp's `%llu`, not a machine word.
        (check-equal "content_length is arbitrary precision here"
                     (line (adapter-event-for 'on-headers-complete 8 #f
                                              '((method . 4) (http-major . 1)
                                                (http-minor . 0) (flags . 32)
                                                (content-length . 18446744073709551615))))
                     '("off=8 headers complete method=4 v=1/0 flags=20 content_length=18446744073709551615"))))
    (harness-case "a state line with a field missing is refused, not zeroed"
      (lambda ()
        ;; The failure this guards is the worst kind: a default would print
        ;; `flags=0`, which is a line llhttp writes for real messages, so the
        ;; trace would look right for every fixture whose flags happen to be 0.
        (check "no fields at all"
               (refuses? (lambda () (adapter-event-for 'on-headers-complete 60 #f #f))))
        (check "one field missing"
               (refuses? (lambda () (adapter-event-for 'on-headers-complete 60 #f
                                                       '((method . 6) (http-major . 1)
                                                         (http-minor . 1) (flags . 0))))))
        (check "a field that is not a number"
               (refuses? (lambda () (adapter-event-for 'on-headers-complete 60 #f
                                                       '((method . 6) (http-major . 1)
                                                         (http-minor . 1) (flags . 0)
                                                         (content-length . "0"))))))))
    (harness-case "the state fields are llhttp's five, in its print order"
      (lambda ()
        ;; The recorder reads exactly these off the parser. A sixth added to
        ;; the grammar and not to the line, or a reorder, shows up here.
        (check-equal "fields" adapter-state-fields
                     '(method http-major http-minor flags content-length))))
    (harness-case "a span callback with no bytes is refused"
      (lambda ()
        ;; An empty span is `(bytevector)`, which is not #f. Accepting #f here
        ;; would silently turn a missing fragment into an empty one -- the very
        ;; distinction the empty-span work upstream was done to preserve.
        (check "refused" (refuses? (lambda () (adapter-event-for 'on-method-data 0 #f #f))))
        (check-equal "empty is not missing"
                     (line (adapter-event-for 'on-protocol-data 9 (make-bytevector 0) #f))
                     '("off=9 len=0 span[protocol]=\"\""))))
    (harness-case "an event callback handed bytes is refused"
      (lambda ()
        (check "refused"
               (refuses? (lambda () (adapter-event-for 'on-method-complete 7
                                                       (string->utf8 "X") #f))))))))

(harness-group "the error table"
  (lambda ()
    (harness-case "a code renames to llhttp's number and the reason passes through"
      (lambda ()
        ;; request/invalid.md records exactly this line.
        (check-equal "code 8"
                     (line (adapter-error-event 'invalid-constant
                                                "Invalid method for HTTP/x.x request" 32))
                     '("off=32 error code=8 reason=\"Invalid method for HTTP/x.x request\""))))
    (harness-case "the two line-ending codes render as two different numbers"
      (lambda ()
        ;; Decision 0013's collision: one reason, two numbers. A table keyed on
        ;; the reason could not tell these apart.
        (check-equal "no CR"
                     (line (adapter-error-event 'invalid-version
                                                "Expected CRLF after version" 14))
                     '("off=14 error code=9 reason=\"Expected CRLF after version\""))
        (check-equal "CR without LF"
                     (line (adapter-error-event 'strict
                                                "Expected CRLF after version" 15))
                     '("off=15 error code=2 reason=\"Expected CRLF after version\""))))
    (harness-case "every code this table knows is one llhttp number"
      (lambda ()
        (check-equal "codes" adapter-error-codes
                     '((strict . 2) (lf-expected . 3)
                       (unexpected-content-length . 4) (invalid-method . 6)
                       (invalid-url . 7) (invalid-constant . 8)
                       (invalid-version . 9) (invalid-header-token . 10)
                       (invalid-content-length . 11)
                       (invalid-transfer-encoding . 15)
                       (paused-h2-upgrade . 23)
                       (cr-expected . 25) (unexpected-space . 30)))))
    (harness-case "the four header reasons under code 10 all render as 10"
      (lambda ()
        ;; Decision 0013's other direction: one number, several reasons. The
        ;; reason is what tells them apart, and it passes through untouched.
        (check-equal "field char"
                     (line (adapter-error-event 'invalid-header-token
                                                "Invalid header field char" 30))
                     '("off=30 error code=10 reason=\"Invalid header field char\""))
        (check-equal "token"
                     (line (adapter-error-event 'invalid-header-token
                                                "Invalid header token" 18))
                     '("off=18 error code=10 reason=\"Invalid header token\""))))
    (harness-case "an unmapped code is refused, not defaulted"
      (lambda ()
        (check "refused"
               (refuses? (lambda () (adapter-error-event 'invalid-chunk-size "x" 0))))))
    (harness-case "unexpected-eof has no number, deliberately"
      (lambda ()
        ;; llhttp prints nothing at all when input runs out mid-token, so a
        ;; trace can never carry one. Renaming it to some number would invent a
        ;; line the oracle never records.
        (check "refused"
               (refuses? (lambda () (adapter-error-event 'unexpected-eof
                                                         "unexpected end of input" 3))))))))

(harness-finish)
