;;; Lenient modes: the bitset the embedder writes before the first byte.
;;;
;;; Upstream decides these before the first byte. `test/md-test.ts` turns a
;;; fixture's type into `-DLLPARSE__TEST_INIT=llhttp__test_init_<type>`, and
;;; that hook writes both halves at once:
;;;
;;;   void llhttp__test_init_request_lenient_version(llparse_t* s) {
;;;     llhttp__test_init_request(s);
;;;     s->lenient_flags |= LENIENT_VERSION;
;;;   }
;;;
;;; SO DOES THIS PARSER: `lenient-flags` is a settable field and
;;; `make-parser`'s fourth argument writes it, which is the same one-integer
;;; surface llhttp has.
;;;
;;; THE MODE IS SET ONCE PER PARSER, NOT ONCE PER MESSAGE, and that is
;;; structural: a field initial is written at CONSTRUCTION, so there is
;;; nothing for a restart to re-enter or skip. The restart stores zero over
;;; `flags` and `lenient-flags` is a separate field, which is why the mode
;;; survives it. No fixture pipelines a lenient message, so the case that says
;;; so is here rather than in the corpus.
(import (rnrs)
        (httparse test harness)
        (httparse test adapter)
        (httparse test drive)
        (httparse test trace-format)
        (httparse grammar)
        (httparse modes)
        (byte-machine verify)
        (byte-machine interpret)
        (byte-machine runtime))

(define machine
  (make-interpreted-machine (verify-machine (make-message-machine))))

;; trace : Init String -> (Listof String)
(define (trace init input)
  (let* ((r (make-trace-recorder))
         (p (make-parser machine (trace-recorder-bindings r init #f) #f
                         (adapter-parser-inits init)))
         (bv (string->utf8 input))
         (refused
          (call/cc
           (lambda (k)
             (with-exception-handler
              (lambda (e) (if (adapter-error? e) (k #t) (raise e)))
              (lambda ()
                (let ((res (drive-feed! r p bv 0 (bytevector-length bv))))
                  (when (eq? (parser-result-status res) 'error)
                    (trace-recorder-note-error! r (parser-result-error res)))
                  #f)))))))
    (append (map utf8->string (trace-format (trace-recorder-events r)))
            (if refused '("(refused)") '()))))

(harness-begin "unit.lenient")

(harness-group "the same bytes, strict and lenient"
  (lambda ()
    (harness-case "a version no pair accepts is an error when strict"
      (lambda ()
        ;; request/invalid.md, "Invalid HTTP version", copied entire. The
        ;; span is delivered and the error lands PAST the minor digit.
        (check-equal "the fixture's own trace"
                     (trace '(request) "GET / HTTP/5.6\r\n")
                     '("off=0 message begin"
                       "off=0 len=3 span[method]=\"GET\""
                       "off=3 method complete"
                       "off=4 len=1 span[url]=\"/\""
                       "off=6 url complete"
                       "off=6 len=4 span[protocol]=\"HTTP\""
                       "off=10 protocol complete"
                       "off=11 len=3 span[version]=\"5.6\""
                       "off=14 error code=9 reason=\"Invalid HTTP version\""))))
    (harness-case "and is parsed, and PRINTED, when the flag is on"
      (lambda ()
        ;; request/lenient-version.md, copied entire. `v=5/6` is the half a
        ;; store-then-check version subgraph exists for: a digit belonging to
        ;; no accepted pair still has to reach the headers-complete line.
        (check-equal "the fixture's own trace"
                     (trace '(request version) "GET / HTTP/5.6\r\n\r\n")
                     '("off=0 message begin"
                       "off=0 len=3 span[method]=\"GET\""
                       "off=3 method complete"
                       "off=4 len=1 span[url]=\"/\""
                       "off=6 url complete"
                       "off=6 len=4 span[protocol]=\"HTTP\""
                       "off=10 protocol complete"
                       "off=11 len=3 span[version]=\"5.6\""
                       "off=14 version complete"
                       "off=18 headers complete method=1 v=5/6 flags=0 content_length=0"
                       "off=18 message complete"))))
    (harness-case "a response reads the same flag"
      (lambda ()
        ;; response/lenient-version.md. One version subgraph serves both
        ;; start lines, so one flag test serves both too.
        (check-equal "status=200 v=5/6"
                     (list-tail (trace '(response version) "HTTP/5.6 200 OK\r\n\r\n") 7)
                     '("off=19 headers complete status=200 v=5/6 flags=0 content_length=0"))))
    (harness-case "another flag does not turn this one on"
      (lambda ()
        ;; THE CASE THAT STOPS ONE FLAG ANSWERING FOR ALL ELEVEN. An initial
        ;; that set every bit, or a test that read the wrong one, would pass
        ;; both cases above.
        (check-equal "still the strict error"
                     (list-tail (trace '(request headers) "GET / HTTP/5.6\r\n") 8)
                     '("off=14 error code=9 reason=\"Invalid HTTP version\""))))))

(harness-group "the mode is written once, before everything"
  (lambda ()
    (harness-case "the flag survives the restart between two messages"
      (lambda ()
        ;; NO FIXTURE PIPELINES A LENIENT MESSAGE. If the flag lived in
        ;; `flags` the restart would store zero over it and the SECOND message
        ;; would be strict; this is what says it is not.
        (let ((ls (trace '(request version)
                         (string-append "GET / HTTP/5.6\r\n\r\n"
                                        "GET / HTTP/5.6\r\n\r\n"))))
          (check-equal "both messages complete"
                       (length (filter (lambda (l) (string=? l "off=18 message complete"))
                                       ls))
                       1)
          (check-equal "the second is lenient too"
                       (list-tail ls (- (length ls) 2))
                       '("off=36 headers complete method=1 v=5/6 flags=0 content_length=0"
                         "off=36 message complete")))))
    (harness-case "the mode outlives every restart on one parser"
      (lambda ()
        ;; Read straight off the field: three messages on one parser, two
        ;; restarts between them, and the bitset the embedder wrote is still
        ;; there at the end.
        ;;
        ;; The restart stores zero over `flags`, and
        ;; `lenient-flags` is a SEPARATE field for exactly this reason; a
        ;; grammar that folded the two together would clear the mode on the
        ;; first restart and this case is what would say so.
        (let* ((r (make-trace-recorder))
               (p (make-parser machine (trace-recorder-bindings r '(request) #f) #f
                               (adapter-parser-inits '(request version))))
               (bv (string->utf8 (string-append "GET / HTTP/5.6\r\n\r\n"
                                                "GET / HTTP/5.6\r\n\r\n"
                                                "GET / HTTP/5.6\r\n\r\n"))))
          (check-equal "set before a byte is read" (parser-field-ref p 'lenient-flags) 16)
          (parser-feed! p bv 0 (bytevector-length bv))
          (check-equal "three messages parsed"
                       (length (filter (lambda (l)
                                         (and (> (string-length l) 16)
                                              (string=? (substring l (- (string-length l) 16)
                                                                   (string-length l))
                                                        "message complete")))
                                       (map utf8->string
                                            (trace-format (trace-recorder-events r)))))
                       3)
          (check-equal "and still set after two restarts"
                       (parser-field-ref p 'lenient-flags) 16))))
    (harness-case "no lenient bits is the strict parser"
      (lambda ()
        ;; The default path, named. Every one of the 216 strict fixtures runs
        ;; with a zero bitset, and an embedder reaches the same parser by
        ;; omitting the row entirely -- so both spellings are checked, because
        ;; "strict" has two of them.
        (let* ((r (make-trace-recorder))
               (p (make-parser machine (trace-recorder-bindings r '(request) #f) #f
                               (list (cons 'type (httparse-message-type-value 'request)))))
               (bv (string->utf8 "GET / HTTP/5.6\r\n")))
          (check-equal "an omitted row is zero" (parser-field-ref p 'lenient-flags) 0)
          (let ((res (parser-feed! p bv 0 (bytevector-length bv))))
            (check-equal "and strict" (parser-error-reason (parser-result-error res))
                         "Invalid HTTP version")))
        (check-equal "an explicit empty bitset is the same parser"
                     (list-tail (trace '(request) "GET / HTTP/5.6\r\n") 8)
                     '("off=14 error code=9 reason=\"Invalid HTTP version\""))))
    (harness-case "and a parser told nothing at all refuses at the first byte"
      (lambda ()
        ;; A field initial cannot be made mandatory, so a parser built with
        ;; no `type` starts at the declared TYPE-BOTH -- llhttp's HTTP_BOTH,
        ;; whose `start_req_or_res` arm this parser does not implement -- and
        ;; refuses at offset 0, with the reason string llhttp's `type` gap
        ;; produces here. The refusal comes at the first feed rather than at
        ;; construction, and it is still a refusal rather than a guess.
        (let* ((r (make-trace-recorder))
               (p (make-parser machine (trace-recorder-bindings r '(request) #f) #f))
               (bv (string->utf8 "GET / HTTP/1.1\r\n\r\n")))
          (check-equal "constructed without complaint" (parser-field-ref p 'type) 0)
          (let ((res (parser-feed! p bv 0 (bytevector-length bv))))
            (check-equal "status" (parser-result-status res) 'error)
            (check-equal "code" (parser-error-code (parser-result-error res))
                         'unexpected-message-type)
            (check-equal "at the first byte"
                         (parser-error-offset (parser-result-error res)) 0)))))))

(harness-group "LENIENT_HEADERS, at the one site only lenient-all reaches"
  (lambda ()
    ;; FIVE OF THE SIX SITES ARE REACHED BY A SINGLE-FLAG FIXTURE, as
    ;; disabling each in turn shows. The sixth is reached only by
    ;; request/invalid.md#22, "Spaces before headers", which is typed
    ;; `request-lenient-all` and so sets nine flags at once. Both halves below
    ;; isolate the one flag, measured against a LIVE llhttp at
    ;; `v9.4.3-1-gee51043`: the strict one from the plain
    ;; `http-request-c`, the lenient one from a binary built with
    ;; `-DLLPARSE__TEST_INIT=llhttp__test_init_request_lenient_headers`, both
    ;; at scan size 28.
    (harness-case "a space before the first header is an error when strict"
      (lambda ()
        (check-equal "the oracle's last line"
                     (list-tail (trace '(request) "GET / HTTP/1.1\r\n Host: x\r\n\r\n") 9)
                     '("off=17 error code=30 reason=\"Unexpected space after start line\""))))
    (harness-case "and is consumed, not skipped, when the flag is on"
      (lambda ()
        ;; THE SPACE IS EATEN EITHER WAY -- llhttp `.match`es it INTO the
        ;; flag test, and a match consumes. So the field span starts at 17
        ;; and not at 16, which is the half a peek-based implementation would
        ;; get wrong while still accepting the message.
        (check-equal "the oracle's own trace"
                     (trace '(request headers) "GET / HTTP/1.1\r\n Host: x\r\n\r\n")
                     '("off=0 message begin"
                       "off=0 len=3 span[method]=\"GET\""
                       "off=3 method complete"
                       "off=4 len=1 span[url]=\"/\""
                       "off=6 url complete"
                       "off=6 len=4 span[protocol]=\"HTTP\""
                       "off=10 protocol complete"
                       "off=11 len=3 span[version]=\"1.1\""
                       "off=14 version complete"
                       "off=17 len=4 span[header_field]=\"Host\""
                       "off=22 header_field complete"
                       "off=23 len=1 span[header_value]=\"x\""
                       "off=26 header_value complete"
                       "off=28 headers complete method=1 v=1/1 flags=0 content_length=0"
                       "off=28 message complete"))))))

(harness-group "OPTIONAL_CR_BEFORE_LF, at the one site no fixture reaches"
  (lambda ()
    ;; Ten sites, and the same disable sweep separates this one: each of the
    ;; other nine breaks two lanes when disabled, and this breaks nothing.
    ;; Measured against a live llhttp at `v9.4.3-1-gee51043` -- the
    ;; strict half from the plain `http-request-c`, the lenient half from a
    ;; build carrying
    ;; `-DLLPARSE__TEST_INIT=llhttp__test_init_request_lenient_optional_cr_before_lf`
    ;; -- both at scan size 24.
    (harness-case "a bare LF where a value would start is an error when strict"
      (lambda ()
        (check-equal "the oracle's last line"
                     (list-tail (trace '(request) "GET / HTTP/1.1\r\nHost:\n\r\n") 11)
                     '("off=22 error code=10 reason=\"Invalid header value char\""))))
    (harness-case "and ends an EMPTY value when the flag is on"
      (lambda ()
        ;; The value is announced as an empty span, not skipped -- which is
        ;; `checkEmptyHeaderValue`'s doing and not this flag's, and is the
        ;; part a fork pointed at the wrong target would lose.
        (check-equal "the oracle's own trace"
                     (list-tail (trace '(request optional-cr-before-lf)
                                       "GET / HTTP/1.1\r\nHost:\n\r\n") 9)
                     '("off=16 len=4 span[header_field]=\"Host\""
                       "off=21 header_field complete"
                       "off=22 len=0 span[header_value]=\"\""
                       "off=22 header_value complete"
                       "off=24 headers complete method=1 v=1/1 flags=0 content_length=0"
                       "off=24 message complete"))))))

;;; This one is not about a trace. A settable field reads the embedder's value
;;; before any byte arrives and still reads it after a reset: it is never
;;; unset and never cleared.
(harness-group "a reset restores the embedder's mode, not the declared one"
  (lambda ()
    (harness-case "the mode is there before the first byte and after a reset"
      (lambda ()
        ;; `parser-reset!` restores each field to the initial the PARSER was
        ;; built with -- the embedder's where one was given, the machine's
        ;; otherwise. This is the case that would catch a reset restoring the
        ;; machine's declared initial instead.
        (let* ((r (make-trace-recorder))
               (p (make-parser machine
                               (trace-recorder-bindings r '(request) #f) #f
                               (adapter-parser-inits '(request version))))
               (bv (string->utf8 "GET / HTTP/5.6\r\n\r\n"))
               (read-flags (lambda () (parser-field-ref p 'lenient-flags))))
          (check-equal "set at construction, before any byte" (read-flags) 16)
          (parser-feed! p bv 0 (bytevector-length bv))
          (check-equal "unchanged by a parse" (read-flags) 16)
          (parser-reset! p)
          (check-equal "and the reset restores it, not zero" (read-flags) 16)
          (let ((res (parser-feed! p bv 0 (bytevector-length bv))))
            ;; The half that matters to an embedder: the second parse is
            ;; still lenient, so `HTTP/5.6` does not become an error.
            (check "the reset parser is still lenient"
                   (not (eq? (parser-result-status res) 'error)))))))))

;;; A BARE LF AFTER THE VERSION NEEDS TWO FLAGS, AND ONE OF THEM ALONE MOVES
;;; ONLY THE ERROR CODE. The live differential's lenient kind reaches it, and
;;; no fixture upstream ships does: the corpus tests one flag at a time, where
;;; this needs a pair, and its only combination fixtures are
;;; `*-lenient-all`, which set both.
;;;
;;; Upstream's two nodes, and the whole of the behaviour:
;;;
;;;     n('req_http_complete')
;;;       .match('\r', n('req_http_complete_crlf'))
;;;       .match('\n', checkIfAllowLFWithoutCR(       // OPTIONAL_CR_BEFORE_LF
;;;         n('req_http_complete_crlf'),
;;;         p.error(ERROR.INVALID_VERSION, 'Expected CRLF after version')))
;;;       .otherwise(p.error(ERROR.INVALID_VERSION, ...));
;;;
;;;     n('req_http_complete_crlf')
;;;       .match('\n', n('headers_start'))
;;;       .otherwise(testLenientFlags(OPTIONAL_LF_AFTER_CR, {
;;;         1: n('headers_start'),
;;;       }, p.error(ERROR.STRICT, 'Expected CRLF after version')));
;;;
;;; `.match('\n')` CONSUMES, so the lenient arm arrives at a node that wants
;;; an LF the input has already spent. With `optional-cr-before-lf` alone the
;;; parse still fails -- at the SAME OFFSET and with the SAME REASON as
;;; strict, and a different code. Reading the reason alone cannot tell the
;;; two apart; only the code does.
;;;
;;; THIS IS ONE OF THREE CROSS-FLAG INTERACTIONS. A bare LF after a chunk size
;;; needs the same two flags, and a request's invalid Transfer-Encoding is
;;; accepted under EITHER of LENIENT_CHUNKED_LENGTH and
;;; LENIENT_TRANSFER_ENCODING -- a condition stated in llhttp's hand-written C,
;;; not its grammar.
(define (after-version flags input)
  ;; The last two lines: the version event and what follows it. The nine
  ;; before are the same in every case here and say nothing.
  (let ((lines (trace (cons 'request flags) input)))
    (reverse (harness-take (reverse lines) 2))))

(harness-group "a bare LF after the version, one flag at a time"
  (lambda ()
    (harness-case "strict refuses it as an invalid version"
      (lambda ()
        (check-equal "no flags"
                     (after-version '() "PUT / HTTP/1.1\nX")
                     '("off=14 version complete"
                       "off=15 error code=9 reason=\"Expected CRLF after version\""))))
    (harness-case "OPTIONAL_LF_AFTER_CR alone changes nothing"
      (lambda ()
        ;; It governs the byte after a CR, and there is no CR here.
        (check-equal "lf-after-cr"
                     (after-version '(optional-lf-after-cr) "PUT / HTTP/1.1\nX")
                     '("off=14 version complete"
                       "off=15 error code=9 reason=\"Expected CRLF after version\""))))
    (harness-case "OPTIONAL_CR_BEFORE_LF alone still refuses, with a DIFFERENT CODE"
      (lambda ()
        ;; Same offset, same reason, code 9 -> 2. The lenient arm reaches
        ;; `req_http_complete_crlf`, which wants an LF that `.match` has
        ;; already consumed, and falls through to the other flag's strict arm.
        (check-equal "cr-before-lf"
                     (after-version '(optional-cr-before-lf) "PUT / HTTP/1.1\nX")
                     '("off=14 version complete"
                       "off=15 error code=2 reason=\"Expected CRLF after version\""))))
    (harness-case "and only both together let the message through"
      (lambda ()
        (check-equal "both"
                     (after-version '(optional-cr-before-lf optional-lf-after-cr)
                                   "PUT / HTTP/1.1\nHost: x\n\n")
                     '("off=24 headers complete method=4 v=1/1 flags=0 content_length=0"
                       "off=24 message complete"))))))

;;; AND A STATUS LINE WITH NO REASON PHRASE HAS A LENIENT SITE OF ITS OWN.
;;; A disable sweep cannot find it, because it counts the forks that exist.
;;; Upstream's `res_status_code_otherwise` has an LF arm gated on
;;; OPTIONAL_CR_BEFORE_LF:
;;;
;;;     n('res_status_code_otherwise')
;;;       .match(' ', n('res_status_start'))
;;;       .match('\r', n('res_line_almost_done'))
;;;       .match('\n', checkIfAllowLFWithoutCR(        // OPTIONAL_CR_BEFORE_LF
;;;         onStatusComplete,
;;;         p.error(ERROR.INVALID_STATUS, 'Invalid response status')))
;;;       .otherwise(p.error(ERROR.INVALID_STATUS, ...));
;;;
;;; NO FIXTURE UPSTREAM SHIPS REACHES IT: `Invalid response status` appears
;;; nowhere in the 274, which `corpus-load-tests.sps` already pins, and a
;;; response whose status line has NO REASON PHRASE and ends in a BARE LF is
;;; two unusual things at once. The live differential's lenient kind reaches
;;; it.
;;;
;;; UNLIKE THE REQUEST SIDE ABOVE, ONE FLAG IS ENOUGH -- upstream's lenient
;;; arm here goes straight to `onStatusComplete` rather than to a node that
;;; wants the LF again. The two sites read alike and behave differently,
;;; which is why both are written down.
(define (status-line flags input)
  (let ((lines (trace (cons 'response flags) input)))
    (reverse (harness-take (reverse lines) 2))))

(harness-group "a status line with no reason phrase, ending in a bare LF"
  (lambda ()
    (harness-case "strict refuses it as an invalid status"
      (lambda ()
        (check-equal "no flags"
                     (status-line '() "HTTP/1.1 200\nA: b\n\n")
                     '("off=8 version complete"
                       "off=13 error code=13 reason=\"Invalid response status\""))))
    (harness-case "OPTIONAL_LF_AFTER_CR alone changes nothing"
      (lambda ()
        ;; There is no CR, so the other flag has nothing to govern -- the
        ;; check that this site belongs to the flag it is forked on.
        (check-equal "lf-after-cr"
                     (status-line '(optional-lf-after-cr) "HTTP/1.1 200\nA: b\n\n")
                     '("off=8 version complete"
                       "off=13 error code=13 reason=\"Invalid response status\""))))
    (harness-case "OPTIONAL_CR_BEFORE_LF alone completes the status line"
      (lambda ()
        ;; `status complete` at 13, one past the LF, and the header section
        ;; begins there. One flag, where the request side needs two.
        (check-equal "cr-before-lf"
                     (trace (cons 'response '(optional-cr-before-lf))
                            "HTTP/1.1 200\nA: b\n\n")
                     '("off=0 message begin"
                       "off=0 len=4 span[protocol]=\"HTTP\""
                       "off=4 protocol complete"
                       "off=5 len=3 span[version]=\"1.1\""
                       "off=8 version complete"
                       "off=13 status complete"
                       "off=13 len=1 span[header_field]=\"A\""
                       "off=15 header_field complete"
                       "off=16 len=1 span[header_value]=\"b\""
                       "off=18 header_value complete"
                       ;; NO `message complete`. A response with neither a
                       ;; Content-Length nor a Transfer-Encoding is read to
                       ;; end of connection, so the message ends at a finish
                       ;; this trace never asks for.
                       "off=19 headers complete status=200 v=1/1 flags=0 content_length=0"))))
    (harness-case "and there is no span[status] at all, because there was none"
      (lambda ()
        ;; The span opens only on the SPACE arm, so a status line with no
        ;; reason phrase records none -- and this is the arm that skips it.
        (check "no status span"
               (not (exists (lambda (l) (harness-string-contains? l "span[status]"))
                            (trace (cons 'response '(optional-cr-before-lf))
                                   "HTTP/1.1 200\nA: b\n\n"))))))))

(harness-finish)
