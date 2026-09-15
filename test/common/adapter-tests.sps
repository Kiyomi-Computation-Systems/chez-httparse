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
                     '("off=0 len=7 span[method]=\"OPTIONS\""))
        ;; `response/invalid.md`'s extra-space case. llhttp prints the reason
        ;; phrase under the name of the FIELD, `status`, and the leading space
        ;; is part of it.
        (check-equal "status span"
                     (line (adapter-event-for 'on-status-data 13 (string->utf8 " OK") #f))
                     '("off=13 len=3 span[status]=\" OK\""))
        (check-equal "status complete"
                     (line (adapter-event-for 'on-status-complete 17 #f #f))
                     '("off=17 status complete"))))
    (harness-case "every declared callback has a row, and the kinds are right"
      (lambda ()
        ;; A callback added to the grammar without a row here raises at the
        ;; first fixture that reaches it rather than being rendered as
        ;; something plausible.
        (check-equal "rows" (length adapter-trace-names) 25)
        (check-equal "spans"
                     (map car (filter (lambda (r) (eq? (cadr r) 'span))
                                      adapter-trace-names))
                     '(on-method-data on-url-data on-protocol-data on-version-data
                       on-status-data
                       on-header-field-data on-header-value-data on-body-data
                       on-chunk-extension-name-data
                       on-chunk-extension-value-data))
        ;; THE DECISION CALLBACK IS NOT A ROW, and that is the point: llhttp's
        ;; harness sets `s->type` in an init hook that prints nothing, so a
        ;; trace name for it would be a line the oracle never writes.
        (check "the message type has no trace row"
               (not (assq adapter-message-type-callback adapter-trace-names)))))
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
                                              '((type . 1) (method . 6) (status-code . 0)
                                                (http-major . 1)
                                                (http-minor . 1) (flags . 0)
                                                (content-length . 0))))
                     '("off=60 headers complete method=6 v=1/1 flags=0 content_length=0"))
        ;; `%x` IS LOWERCASE. Chez's own `number->string` radix 16 is not, and
        ;; the corpus records `flags=20a` for a chunked request that closes.
        (check-equal "flags render in lowercase hex"
                     (line (adapter-event-for 'on-headers-complete 42 #f
                                              '((type . 1) (method . 3) (status-code . 0)
                                                (http-major . 1)
                                                (http-minor . 1) (flags . 522)
                                                (content-length . 0))))
                     '("off=42 headers complete method=3 v=1/1 flags=20a content_length=0"))
        ;; A 21-digit content length is llhttp's `%llu`, not a machine word.
        (check-equal "content_length is arbitrary precision here"
                     (line (adapter-event-for 'on-headers-complete 8 #f
                                              '((type . 1) (method . 4) (status-code . 0)
                                                (http-major . 1)
                                                (http-minor . 0) (flags . 32)
                                                (content-length . 18446744073709551615))))
                     '("off=8 headers complete method=4 v=1/0 flags=20 content_length=18446744073709551615"))))
    (harness-case "the same line is `status=` when the type says response"
      (lambda ()
        ;; THE TYPE CHOOSES THE FIELD, exactly as llhttp's own callback does.
        ;; The two lines below are `response/sample.md#1` and
        ;; `response/content-length.md#2`, and the fields they do NOT print
        ;; are supplied with the values a real parser would carry -- a method
        ;; of 0 on a response, a status of 0 on a request -- so the check is
        ;; that the type picks, not that the other field happened to be empty.
        (check-equal "response/sample.md#1"
                     (line (adapter-event-for 'on-headers-complete 73 #f
                                              '((type . 2) (method . 0) (status-code . 200)
                                                (http-major . 1)
                                                (http-minor . 1) (flags . 32)
                                                (content-length . 0))))
                     '("off=73 headers complete status=200 v=1/1 flags=20 content_length=0"))
        (check-equal "a chunked response"
                     (line (adapter-event-for 'on-headers-complete 68 #f
                                              '((type . 2) (method . 0) (status-code . 200)
                                                (http-major . 1)
                                                (http-minor . 1) (flags . 520)
                                                (content-length . 0))))
                     '("off=68 headers complete status=200 v=1/1 flags=208 content_length=0"))
        ;; The SAME numbers under the other type print the other field, which
        ;; is what makes this a choice rather than two unrelated renderers.
        (check-equal "and the same fields as a request"
                     (line (adapter-event-for 'on-headers-complete 73 #f
                                              '((type . 1) (method . 0) (status-code . 200)
                                                (http-major . 1)
                                                (http-minor . 1) (flags . 32)
                                                (content-length . 0))))
                     '("off=73 headers complete method=0 v=1/1 flags=20 content_length=0"))))
    (harness-case "a state line with no message type is refused, not rendered"
      (lambda ()
        ;; llhttp's third arm prints `invalid headers complete`, which no
        ;; fixture records -- and which this parser cannot reach, because the
        ;; branches of `switch-type` are the only writers of the field. So it
        ;; is an assertion here rather than an untested rendering.
        (check "type BOTH"
               (refuses? (lambda () (adapter-event-for 'on-headers-complete 73 #f
                                                       '((type . 0) (method . 0)
                                                         (status-code . 200)
                                                         (http-major . 1)
                                                         (http-minor . 1) (flags . 32)
                                                         (content-length . 0))))))
        (check "a type llhttp does not have"
               (refuses? (lambda () (adapter-event-for 'on-headers-complete 73 #f
                                                       '((type . 3) (method . 0)
                                                         (status-code . 200)
                                                         (http-major . 1)
                                                         (http-minor . 1) (flags . 32)
                                                         (content-length . 0))))))))
    (harness-case "a state line with a field missing is refused, not zeroed"
      (lambda ()
        ;; The failure this guards is the worst kind: a default would print
        ;; `flags=0`, which is a line llhttp writes for real messages, so the
        ;; trace would look right for every fixture whose flags happen to be 0.
        (check "no fields at all"
               (refuses? (lambda () (adapter-event-for 'on-headers-complete 60 #f #f))))
        (check "one field missing"
               (refuses? (lambda () (adapter-event-for 'on-headers-complete 60 #f
                                                       '((type . 1) (method . 6)
                                                         (status-code . 0) (http-major . 1)
                                                         (http-minor . 1) (flags . 0))))))
        (check "a field that is not a number"
               (refuses? (lambda () (adapter-event-for 'on-headers-complete 60 #f
                                                       '((type . 1) (method . 6)
                                                         (status-code . 0) (http-major . 1)
                                                         (http-minor . 1) (flags . 0)
                                                         (content-length . "0"))))))
        ;; The field a RESPONSE prints is one a request's line does not read,
        ;; so a missing `status-code` is invisible until the type asks for it.
        (check "the status is missing on a response"
               (refuses? (lambda () (adapter-event-for 'on-headers-complete 73 #f
                                                       '((type . 2) (method . 0)
                                                         (http-major . 1)
                                                         (http-minor . 1) (flags . 32)
                                                         (content-length . 0))))))))
    (harness-case "a count line renders llhttp's one number"
      (lambda ()
        ;; request/transfer-encoding.md#3's first chunk header, built from a
        ;; field value rather than from a parser.
        (check-equal "chunk header"
                     (line (adapter-event-for 'on-chunk-header 52 #f
                                              '((content-length . 10))))
                     '("off=52 chunk header len=10"))
        ;; The zero chunk. `len=0` is a line llhttp writes for real messages,
        ;; which is exactly why the field may not be defaulted.
        (check-equal "the zero chunk"
                     (line (adapter-event-for 'on-chunk-header 67 #f
                                              '((content-length . 0))))
                     '("off=67 chunk header len=0"))))
    (harness-case "a count line with its field missing is refused, not zeroed"
      (lambda ()
        (check "no fields at all"
               (refuses? (lambda () (adapter-event-for 'on-chunk-header 52 #f #f))))
        (check "the wrong field"
               (refuses? (lambda () (adapter-event-for 'on-chunk-header 52 #f
                                                       '((method . 3))))))))
    (harness-case "the count field is the one the chunk size accumulates into"
      (lambda ()
        ;; llhttp reuses `content_length` for the chunk size rather than
        ;; adding a field, and its callback prints that one. A second field
        ;; here would mean this layer had chosen a name of its own.
        (check-equal "field" adapter-count-field 'content-length)))
    (harness-case "the state fields are the six llhttp's callback reads"
      (lambda ()
        ;; The recorder reads exactly these off the parser. One added to the
        ;; grammar and not to the line, or a reorder, shows up here. SEVEN
        ;; NAMES FOR FIVE PRINTED NUMBERS: `type` chooses and is never
        ;; printed, and one of `method` / `status-code` is dropped by the
        ;; choice.
        (check-equal "fields" adapter-state-fields
                     '(type method status-code
                       http-major http-minor flags content-length))))
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

;; The shell half. No parser runs here either: what a binding list IS can be
;; judged directly, and the one binding that answers rather than reports is
;; the only one whose VALUE is decided by the caller.
(harness-group "the binding list"
  (lambda ()
    (harness-case "every declared callback is bound, and the type is bound too"
      (lambda ()
        (let ((bs (trace-recorder-bindings (make-trace-recorder) 'request #f)))
          (check-equal "one per row, plus the decision"
                       (length bs) (+ 1 (length adapter-trace-names)))
          (check "the message type is bound"
                 (and (assq adapter-message-type-callback bs) #t)))))
    (harness-case "the bound type is the one the caller asked for"
      (lambda ()
        ;; A REQUIRED ARGUMENT, because llhttp's harness cannot build a parser
        ;; without saying what it is parsing. A default here would silently
        ;; make every response a request, and the `headers complete` line
        ;; would print `method=0` for all 66 of them.
        (for-each
         (lambda (want)
           (let* ((bs (trace-recorder-bindings (make-trace-recorder) want #f))
                  (f (cadr (assq adapter-message-type-callback bs))))
             (check-equal (symbol->string want) (f #f #f) want)))
         adapter-message-types)))
    (harness-case "a kind that is neither is refused, not assumed"
      (lambda ()
        (check "url" (refuses? (lambda () (trace-recorder-bindings
                                           (make-trace-recorder) 'url #f))))
        (check "none" (refuses? (lambda () (trace-recorder-bindings
                                            (make-trace-recorder) 'none #f))))
        (check "a string" (refuses? (lambda () (trace-recorder-bindings
                                                (make-trace-recorder) "request" #f))))))))

;;; THE HARNESS MODE IS THE THIRD REQUIRED ARGUMENT, and it is ONE argument
;;; rather than two because upstream makes the two exclusive in the C
;;; preprocessor: `test/fixtures/extra.c` guards `on_headers_complete` with
;;; `#ifdef ..._PAUSE_ON_HEADERS_COMPLETE / #elif defined(..._SKIP_BODY)`, so a
;;; build is never both. Modelling it as two booleans would make a combination
;;; representable that no oracle binary can be.
;;;
;;; THE MODE CARRIES LLHTTP'S OWN SPELLING, because renaming it is this layer's
;;; job and not the driver's. The two are not the same word: upstream's
;;; `pause: "on_chunk_extension_name"` arms the macro inside
;;; `llhttp__on_chunk_extension_name_COMPLETE`, so a mechanical
;;; underscore-to-hyphen fold would arm the span callback instead -- a callback
;;; upstream never pauses in.
(harness-group "the pause points, as a rename"
  (lambda ()
    (harness-case "every point upstream declares has a row"
      (lambda ()
        ;; Read out of `test/fixtures/extra.c` by listing the function each
        ;; `#ifdef LLHTTP__TEST_PAUSE_*` sits inside, at v9.4.3-1-gee51043.
        (check-equal "points" (length adapter-pause-points) 15)
        (check-equal "the two that are not a fold"
                     (list (cdr (assoc "on_chunk_extension_name" adapter-pause-points))
                           (cdr (assoc "on_chunk_extension_value" adapter-pause-points)))
                     '(on-chunk-extension-name-complete
                       on-chunk-extension-value-complete))))
    (harness-case "every row names a callback this adapter binds"
      (lambda ()
        ;; A row naming a callback with no binding would arm nothing.
        (check-equal "rows with no callback"
                     (filter (lambda (row)
                               (not (assq (cdr row) adapter-trace-names)))
                             adapter-pause-points)
                     '())))
    (harness-case "no row names a span callback"
      (lambda ()
        ;; Upstream's span callbacks are `llparse__print_span` and return its
        ;; value; none carries a pause macro. A row that named one would pause
        ;; somewhere no fixture can record.
        (check-equal "span rows"
                     (filter (lambda (row)
                               (eq? 'span (cadr (assq (cdr row) adapter-trace-names))))
                             adapter-pause-points)
                     '())))))

(harness-group "the harness mode, as a check on its shape"
  (lambda ()
    ;; What the mode DOES is checked where a parser exists; what it REFUSES is
    ;; checked here, with the rest of the no-default discipline.
    (harness-case "a mode naming a point upstream has no macro for is refused"
      (lambda ()
        ;; A typo would otherwise arm nothing and produce a clean unpaused
        ;; trace for a fixture that must pause.
        (check "not a point"
               (refuses? (lambda () (trace-recorder-bindings
                                     (make-trace-recorder) 'request
                                     '(pause "on_nothing_at_all")))))
        (check "a span, which upstream never pauses in"
               (refuses? (lambda () (trace-recorder-bindings
                                     (make-trace-recorder) 'request
                                     '(pause "on_method")))))
        (check "our spelling, which is not upstream's"
               (refuses? (lambda () (trace-recorder-bindings
                                     (make-trace-recorder) 'request
                                     '(pause "on-message-begin")))))))
    (harness-case "a mode that is neither shape is refused"
      (lambda ()
        (check "a bare symbol" (refuses? (lambda ()
                                           (trace-recorder-bindings
                                            (make-trace-recorder) 'request 'pause))))
        (check "true" (refuses? (lambda () (trace-recorder-bindings
                                            (make-trace-recorder) 'request #t))))
        (check "an unknown word" (refuses? (lambda ()
                                             (trace-recorder-bindings
                                              (make-trace-recorder) 'request
                                              '(lenient)))))
        (check "a pause naming nothing"
               (refuses? (lambda () (trace-recorder-bindings
                                     (make-trace-recorder) 'request '(pause)))))
        (check "a pause naming two"
               (refuses? (lambda () (trace-recorder-bindings
                                     (make-trace-recorder) 'request
                                     '(pause "on_message_begin" "on_reset")))))))))

;;; THE EMBEDDER'S PAUSE AND THE MACHINE'S ARE DIFFERENT LINES, and the
;;; discriminator is measured rather than assumed: a callback that returns
;;; `callback-pause` leaves the result's pause slot EMPTY, because a pause
;;; reason is declared on a NODE and this project's event nodes declare none.
;;; A pause that carries a reason is the machine's own and prints as llhttp's
;;; error line; a pause with no reason is one this harness asked for.
(harness-group "a requested pause"
  (lambda ()
    (harness-case "it renders as the bare word, at the offset given"
      (lambda ()
        (let ((r (make-trace-recorder)))
          (trace-recorder-bindings r 'request '(pause "on_message_begin"))
          (trace-recorder-note-requested-pause! r 32)
          (check-equal "the line"
                       (map utf8->string (trace-format (trace-recorder-events r)))
                       '("off=32 pause")))))
    (harness-case "a pause nobody asked for is still refused"
      (lambda ()
        ;; This is the check that keeps the new line honest. Without it, any
        ;; reasonless pause anywhere would print `pause` and a parser stopping
        ;; where llhttp does not would render a trace that looks deliberate.
        (let ((r (make-trace-recorder)))
          (trace-recorder-bindings r 'request #f)
          (check "unarmed"
                 (refuses? (lambda () (trace-recorder-note-requested-pause! r 0)))))))
    (harness-case "a recorder that was never bound is refused too"
      (lambda ()
        ;; A recorder with no bindings has armed nothing, and `#f` is not a
        ;; mode it was told -- it is a mode it was never asked about.
        (check "unbound"
               (refuses? (lambda ()
                           (trace-recorder-note-requested-pause!
                            (make-trace-recorder) 0))))))))

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
                       (unexpected-content-length . 4) (closed-connection . 5)
                       (invalid-method . 6)
                       (invalid-url . 7) (invalid-constant . 8)
                       (invalid-version . 9) (invalid-header-token . 10)
                       (invalid-content-length . 11)
                       (invalid-chunk-size . 12)
                       (invalid-status . 13)
                       (invalid-transfer-encoding . 15)
                       (paused-upgrade . 22) (paused-h2-upgrade . 23)
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
    (harness-case "the finish line is off=NULL, and its number is a field"
      (lambda ()
        ;; NOT A CALLBACK AND NOT AN OUTCOME. llhttp's fixture harness prints
        ;; `s->finish` once the input runs out, with a NULL position -- so
        ;; there is no offset to render and the number is a parser field like
        ;; any other (decision 0014).
        (check-equal "a complete message"
                     (line (adapter-finish-event 0))
                     '("off=NULL finish=0"))
        (check-equal "stopping here would lose data"
                     (line (adapter-finish-event 2))
                     '("off=NULL finish=2"))))
    (harness-case "a finish value that is not a state is refused"
      (lambda ()
        ;; llhttp has three, and a fourth would be a field this layer cannot
        ;; spell -- `abort()` is what its own `llhttp_finish` does with one.
        (check "three" (refuses? (lambda () (adapter-finish-event 3))))
        (check "not a number" (refuses? (lambda () (adapter-finish-event "0"))))))
    (harness-case "an unmapped code is refused, not defaulted"
      (lambda ()
        ;; `paused` is llhttp's plain PAUSED, code 21, which belongs to the
        ;; deferred pausing milestone. The example here has to be a code no
        ;; milestone has reached yet, so it moves as the table grows -- it was
        ;; `invalid-chunk-size` until M5 and `invalid-status` until M7.
        (check "refused"
               (refuses? (lambda () (adapter-error-event 'paused "x" 0))))))
    (harness-case "the message type a parser was never told has no number either"
      (lambda ()
        ;; A SECOND CODE THAT WILL NEVER GET ONE. llhttp reads its type from a
        ;; field an embedder wrote and so cannot reach this state at all;
        ;; giving the refusal a number would let a parser that answered
        ;; neither branch render a line the oracle has no word for.
        (check "refused"
               (refuses? (lambda () (adapter-error-event 'unexpected-message-type
                                                         "x" 0))))))
    (harness-case "unexpected-eof has no number, deliberately"
      (lambda ()
        ;; llhttp prints nothing at all when input runs out mid-token, so a
        ;; trace can never carry one. Renaming it to some number would invent a
        ;; line the oracle never records.
        (check "refused"
               (refuses? (lambda () (adapter-error-event 'unexpected-eof
                                                         "unexpected end of input" 3))))))))

(harness-finish)
