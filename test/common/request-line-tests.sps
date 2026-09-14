;;; Tests for (httparse grammar)'s request line.
;;;
;;; Every expectation is an event name and a byte offset, taken from the
;;; vendored corpus's own recorded traces rather than from what the grammar
;;; happens to do. `request/sample.md` records, for `OPTIONS /url HTTP/1.1`:
;;;
;;;   off=0 message begin / off=0 len=7 span[method]="OPTIONS" /
;;;   off=7 method complete / off=8 len=4 span[url]="/url" / off=13 url complete /
;;;   off=13 len=4 span[protocol]="HTTP" / off=17 protocol complete /
;;;   off=18 len=3 span[version]="1.1" / off=21 version complete
;;;
;;; The grammar runs here through the REFERENCE INTERPRETER. The generated lane
;;; and the conformance driver arrive with the slice that emits the parser.
(import (rnrs)
        (httparse test harness)
        (httparse grammar)
        (byte-machine verify)
        (byte-machine interpret)
        (byte-machine runtime))

(define compiled (make-interpreted-machine (verify-machine (make-request-line-machine))))

;; Runs `input` and returns (values status events), where an event is
;;   (name offset)                       an event callback
;;   (name start length text)            a span fragment, `start` ABSOLUTE
;; A span fragment's absolute start is the stream offset minus its length: the
;; callback fires having already advanced past the bytes it is handed.
(define (run-with input feed!)
  (let ((events '()))
    (define (ev name)
      (lambda (p ctx)
        (set! events (cons (list name (parser-stream-offset p)) events))
        callback-continue))
    (define (span name)
      (lambda (p ctx bv from to)
        (let ((text (let ((b (make-bytevector (- to from))))
                      (bytevector-copy! bv from b 0 (- to from))
                      (utf8->string b))))
          (set! events (cons (list name (- (parser-stream-offset p) (- to from))
                                   (- to from) text)
                             events)))
        callback-continue))
    (let* ((p (make-parser compiled
                           (list (list 'on-message-begin (ev 'message-begin))
                                 (list 'on-method-data (span 'method))
                                 (list 'on-method-complete (ev 'method-complete))
                                 (list 'on-url-data (span 'url))
                                 (list 'on-url-complete (ev 'url-complete))
                                 (list 'on-protocol-data (span 'protocol))
                                 (list 'on-protocol-complete (ev 'protocol-complete))
                                 (list 'on-version-data (span 'version))
                                 (list 'on-version-complete (ev 'version-complete))
                                 (list 'on-header-field-data (span 'header-field))
                                 (list 'on-header-field-complete (ev 'header-field-complete))
                                 (list 'on-header-value-data (span 'header-value))
                                 (list 'on-header-value-complete (ev 'header-value-complete))
                                 (list 'on-headers-complete (ev 'headers-complete)))
                           #f))
           (bv (string->utf8 input))
           (r (feed! p bv)))
      (values r (reverse events)))))

(define (run input)
  (run-with input (lambda (p bv) (parser-feed! p bv 0 (bytevector-length bv)))))

;; The same run fed in fixed-size chunks of `n` bytes -- the shape upstream's
;; `llparse__run_scan` uses and decision 0008 adopts. Feeding stops at the first
;; result that is not `need-input`. Span text is per FRAGMENT, so a span that
;; crosses a chunk boundary arrives here as several events; rejoining them is
;; the trace formatter's job, not this runner's.
(define (run/chunked input n)
  (run-with input
    (lambda (p bv)
      (let ((len (bytevector-length bv)))
        (let loop ((i 0))
          (let* ((end (if (< (+ i n) len) (+ i n) len))
                 (r (parser-feed! p bv i end)))
            (if (and (< end len) (eq? (parser-result-status r) 'need-input))
                (loop end)
                r)))))))

(define (events-of input) (let-values (((r e) (run input))) e))
(define (events-of/chunked input n) (let-values (((r e) (run/chunked input n))) e))

;; Every callback is declared `required?`, so a parser must bind all of them
;; even when a case ignores what they report. (Learned from the parser
;; refusing an empty binding list, which is the declaration doing its job.)
(define (ignoring-bindings)
  (define (ignore-event p ctx) callback-continue)
  (define (ignore-span p ctx bv from to) callback-continue)
  (list (list 'on-message-begin ignore-event)
        (list 'on-method-data ignore-span)
        (list 'on-method-complete ignore-event)
        (list 'on-url-data ignore-span)
        (list 'on-url-complete ignore-event)
        (list 'on-protocol-data ignore-span)
        (list 'on-protocol-complete ignore-event)
        (list 'on-version-data ignore-span)
        (list 'on-version-complete ignore-event)
        (list 'on-header-field-data ignore-span)
        (list 'on-header-field-complete ignore-event)
        (list 'on-header-value-data ignore-span)
        (list 'on-header-value-complete ignore-event)
        (list 'on-headers-complete ignore-event)))
;; Since M3 the request line no longer terminates the parse -- it runs on into
;; the header section -- so a well-formed line leaves the parser wanting more
;; input rather than stopped. What these cases claim is that the line was
;; ACCEPTED, and that is "no error".
(define (status-of input) (let-values (((r e) (run input))) (parser-result-status r)))
(define (accepted? input) (not (eq? (status-of input) 'error)))
(define (error-code-of input)
  (let-values (((r e) (run input)))
    (and (eq? (parser-result-status r) 'error)
         (parser-error-code (parser-result-error r)))))
(define (error-offset-of input)
  (let-values (((r e) (run input)))
    (and (eq? (parser-result-status r) 'error)
         (parser-error-offset (parser-result-error r)))))
;; The reason is half an error's identity, not decoration: llhttp puts two
;; distinct errors behind the same reason text under different numbers, and
;; several distinct reasons behind one number. The corpus records both, so both
;; are checked.
(define (error-reason-of input)
  (let-values (((r e) (run input)))
    (and (eq? (parser-result-status r) 'error)
         (parser-error-reason (parser-result-error r)))))
;; (code reason offset), the three things a corpus error line carries.
(define (error-of input)
  (list (error-code-of input) (error-reason-of input) (error-offset-of input)))
(define (only kinds input)
  (filter (lambda (e) (memq (car e) kinds)) (events-of input)))

(harness-begin "unit.request-line")

(harness-group "the machine itself"
  (lambda ()
    (harness-case "it verifies"
      (lambda ()
        (check "verify-machine returns" (verify-machine (make-request-line-machine)))))))

(harness-group "a complete request line, at the corpus's own offsets"
  (lambda ()
    (harness-case "OPTIONS /url HTTP/1.1 produces exactly the recorded events"
      (lambda ()
        (check-equal "events"
                     (events-of "OPTIONS /url HTTP/1.1\r\n")
                     '((message-begin 0)
                       (method 0 7 "OPTIONS")
                       (method-complete 7)
                       (url 8 4 "/url")
                       (url-complete 13)
                       (protocol 13 4 "HTTP")
                       (protocol-complete 17)
                       (version 18 3 "1.1")
                       (version-complete 21)))))
    (harness-case "HEAD /url HTTP/1.1 produces exactly the recorded events"
      (lambda ()
        ;; request/sample.md, "Request with method starting with `H`".
        (check-equal "events"
                     (events-of "HEAD /url HTTP/1.1\r\n")
                     '((message-begin 0)
                       (method 0 4 "HEAD")
                       (method-complete 4)
                       (url 5 4 "/url")
                       (url-complete 10)
                       (protocol 10 4 "HTTP")
                       (protocol-complete 14)
                       (version 15 3 "1.1")
                       (version-complete 18)))))
    (harness-case "the request line consumes exactly its own bytes"
      (lambda ()
        ;; 16 is past the CRLF. The parser then wants the header section, so
        ;; the status is `need-input` rather than a terminal one.
        (let-values (((r e) (run "GET / HTTP/1.1\r\n")))
          (check-equal "status" (parser-result-status r) 'need-input)
          (check-equal "next" (parser-result-next r) 16))))))

(harness-group "the offsets are asymmetric, deliberately"
  (lambda ()
    (harness-case "method complete fires AT its space, which is unconsumed"
      (lambda ()
        ;; "GET / HTTP/1.1": G=0 E=1 T=2, SP=3.
        (check-equal "at the space"
                     (cadr (assq 'method-complete (events-of "GET / HTTP/1.1\r\n")))
                     3)))
    (harness-case "url complete fires one byte PAST its space, which is consumed"
      (lambda ()
        ;; url span is 4..4 ("/"), its SP is at 5, and the event lands at 6.
        ;; Making this uniform with the other three would shift every url
        ;; offset in the corpus by one.
        (check-equal "past the space"
                     (cadr (assq 'url-complete (events-of "GET / HTTP/1.1\r\n")))
                     6)))
    (harness-case "protocol complete fires AT its slash, which is unconsumed"
      (lambda ()
        (check-equal "at the slash"
                     (cadr (assq 'protocol-complete (events-of "GET / HTTP/1.1\r\n")))
                     10)))
    (harness-case "version complete fires AT the CR, which is unconsumed"
      (lambda ()
        (check-equal "at the CR"
                     (cadr (assq 'version-complete (events-of "GET / HTTP/1.1\r\n")))
                     14)))))

(harness-group "spans end before their delimiter"
  (lambda ()
    (harness-case "the method span excludes its space"
      (lambda ()
        (check-equal "method" (assq 'method (events-of "POST / HTTP/1.1\r\n"))
                     '(method 0 4 "POST"))))
    (harness-case "the url span excludes its space"
      (lambda ()
        (check-equal "url" (assq 'url (events-of "GET /abc HTTP/1.1\r\n"))
                     '(url 4 4 "/abc"))))
    (harness-case "the version span excludes the CR"
      (lambda ()
        (check-equal "version" (assq 'version (events-of "GET / HTTP/1.0\r\n"))
                     '(version 11 3 "1.0"))))))

(harness-group "an empty span is announced, not omitted"
  (lambda ()
    ;; request/uri.md#11 records, for `GET /foo bar/ HTTP/1.1`:
    ;;
    ;;   off=9 url complete
    ;;   off=9 len=0 span[protocol]=""
    ;;   off=9 error code=8 reason="Expected HTTP/, RTSP/ or ICE/"
    ;;
    ;; The protocol span opens at 9 and closes at 9 having delivered nothing,
    ;; and llhttp announces it anyway. A generator that suppressed the empty
    ;; fragment would leave a consumer unable to tell "present and empty" from
    ;; "never opened" -- which is the distinction the recorded trace draws, so
    ;; it is checked here rather than assumed.
    (harness-case "the protocol span delivers one empty fragment at its offset"
      (lambda ()
        (check-equal "events"
                     (events-of "GET /foo bar/ HTTP/1.1\r\n")
                     '((message-begin 0)
                       (method 0 3 "GET")
                       (method-complete 3)
                       (url 4 4 "/foo")
                       (url-complete 9)
                       (protocol 9 0 "")))))
    (harness-case "the error is the recorded one, at the recorded offset"
      (lambda ()
        (check-equal "code" (error-code-of "GET /foo bar/ HTTP/1.1\r\n") 'invalid-constant)
        (check-equal "offset" (error-offset-of "GET /foo bar/ HTTP/1.1\r\n") 9)))
    (harness-case "an empty fragment survives byte-at-a-time feeding"
      (lambda ()
        ;; At one byte per feed the span's mark is set in the feed that
        ;; consumes the space at 8 and the span closes in the next one, so a
        ;; feed boundary falls inside an empty span. Exactly one fragment is
        ;; the whole claim: none means the close was suppressed, two means the
        ;; boundary flush announced the same emptiness a second time.
        (check-equal "protocol fragments"
                     (filter (lambda (e) (eq? (car e) 'protocol))
                             (events-of/chunked "GET /foo bar/ HTTP/1.1\r\n" 1))
                     '((protocol 9 0 "")))))))

(harness-group "rejections"
  (lambda ()
    (harness-case "an empty method is rejected before any span opens"
      (lambda ()
        ;; `method = 1*tchar`. The leading space is not a tchar, so `start`
        ;; rejects at offset 0 and no method span is ever opened.
        (check-equal "code" (error-code-of " / HTTP/1.1\r\n") 'invalid-method)
        (check-equal "offset" (error-offset-of " / HTTP/1.1\r\n") 0)
        (check-equal "no events" (events-of " / HTTP/1.1\r\n") '())))
    (harness-case "a method not followed by a space is rejected at that byte"
      (lambda ()
        ;; The method span closes, `method complete` fires, and the dispatch
        ;; then reads a byte that is not SP.
        (check-equal "code" (error-code-of "GET\t/ HTTP/1.1\r\n") 'invalid-method)
        (check-equal "offset" (error-offset-of "GET\t/ HTTP/1.1\r\n") 3)))
    (harness-case "a bare LF after the version is code 9, not the strict code"
      (lambda ()
        ;; llhttp splits the two line-ending failures across two error numbers
        ;; with the SAME reason text: no CR at all is INVALID_VERSION (9), and
        ;; a CR not followed by LF is STRICT (2). A single line-ending code
        ;; cannot render both.
        (check-equal "code" (error-code-of "GET / HTTP/1.1\n") 'invalid-version)
        ;; 15, not 14: the LF is CONSUMED and then refused, because llhttp
        ;; matches it into a lenient test strict mode fails. An unrelated byte
        ;; is not consumed, so the two land one apart --
        ;; request/invalid.md#21 records the LF side at one past the version.
        (check-equal "offset" (error-offset-of "GET / HTTP/1.1\n") 15)
        (check-equal "an unrelated byte is not consumed"
                     (error-offset-of "GET / HTTP/1.1X") 14)))
    (harness-case "a CR not followed by LF is the strict code"
      (lambda ()
        (check-equal "code" (error-code-of "GET / HTTP/1.1\rX") 'strict)
        (check-equal "offset" (error-offset-of "GET / HTTP/1.1\rX") 15)))
    (harness-case "a protocol not followed by a slash is rejected"
      (lambda ()
        (check-equal "code" (error-code-of "GET / HTTP 1.1\r\n") 'invalid-constant)))
    (harness-case "end of input inside the method is unexpected-eof"
      (lambda ()
        (let* ((bv (string->utf8 "GE"))
               (p (make-parser compiled (ignoring-bindings) #f)))
          (parser-feed! p bv 0 2)
          (check-equal "code" (parser-error-code (parser-result-error (parser-finish! p)))
                       'unexpected-eof))))
    (harness-case "end of input before any byte finishes cleanly"
      (lambda ()
        ;; Between messages, clean end of input is `finished`, not an error --
        ;; which is what lets the message loop terminate in a later milestone.
        (check-equal "status"
                     (parser-result-status
                      (parser-finish! (make-parser compiled (ignoring-bindings) #f)))
                     'finished)))))

(harness-group "the result does not depend on how the input is split"
  (lambda ()
    (harness-case "byte-at-a-time feeding produces the same events"
      (lambda ()
        ;; The corpus replays every fixture at every chunk size; this is the
        ;; same property on one input, before the conformance driver exists.
        (let ((input "OPTIONS /url HTTP/1.1\r\n")
              (events '()))
          (define (ev name)
            (lambda (p ctx)
              (set! events (cons (list name (parser-stream-offset p)) events))
              callback-continue))
          (define (span name)
            (lambda (p ctx bv from to)
              (set! events (cons (list name (- (parser-stream-offset p) (- to from))
                                       (- to from))
                                 events))
              callback-continue))
          (let* ((bv (string->utf8 input))
                 (p (make-parser compiled
                                 (list (list 'on-message-begin (ev 'message-begin))
                                       (list 'on-method-data (span 'method))
                                       (list 'on-method-complete (ev 'method-complete))
                                       (list 'on-url-data (span 'url))
                                       (list 'on-url-complete (ev 'url-complete))
                                       (list 'on-protocol-data (span 'protocol))
                                       (list 'on-protocol-complete (ev 'protocol-complete))
                                       (list 'on-version-data (span 'version))
                                       (list 'on-version-complete (ev 'version-complete))
                                       (list 'on-header-field-data (span 'header-field))
                                       (list 'on-header-field-complete (ev 'header-field-complete))
                                       (list 'on-header-value-data (span 'header-value))
                                       (list 'on-header-value-complete (ev 'header-value-complete))
                                       (list 'on-headers-complete (ev 'headers-complete)))
                                 #f)))
            (let loop ((i 0))
              (when (< i (bytevector-length bv))
                (parser-feed! p bv i (+ i 1))
                (loop (+ i 1))))
            ;; Fragmented feeding splits each span into one fragment per byte,
            ;; so the events are compared by their non-span members: the
            ;; coalescing that rejoins fragments is the trace formatter's job.
            (check-equal "event offsets"
                         (map (lambda (e) (list (car e) (cadr e)))
                              (filter (lambda (e) (= (length e) 2)) (reverse events)))
                         '((message-begin 0) (method-complete 7) (url-complete 13)
                           (protocol-complete 17) (version-complete 21)))))))))

(harness-group "the protocol constants"
  (lambda ()
    (harness-case "each of the three matches and completes at its own length"
      (lambda ()
        ;; request/method.md: `SOURCE /music/sweet/music ICE/1.0` records
        ;; `off=26 len=3 span[protocol]="ICE"` and `off=29 protocol complete`;
        ;; the RTSP and HTTP rows come from the same file.
        (check-equal "ICE"
                     (only '(protocol protocol-complete)
                           "SOURCE /music/sweet/music ICE/1.0\r\n")
                     '((protocol 26 3 "ICE") (protocol-complete 29)))
        (check-equal "RTSP"
                     (only '(protocol protocol-complete)
                           "OPTIONS /music/sweet/music RTSP/1.0\r\n")
                     '((protocol 27 4 "RTSP") (protocol-complete 31)))
        (check-equal "HTTP"
                     (only '(protocol protocol-complete) "GET / HTTP/1.1\r\n")
                     '((protocol 6 4 "HTTP") (protocol-complete 10)))))
    (harness-case "a partial match closes the span over what it consumed"
      (lambda ()
        ;; request/invalid.md, "ICE protocol, but not really":
        ;;   off=23 len=1 span[protocol]="I"
        ;;   off=24 error code=8 reason="Expected HTTP/, RTSP/ or ICE/"
        ;; No `protocol complete` -- llhttp fires it only on a full match.
        (check-equal "events"
                     (only '(protocol protocol-complete)
                           "GET /music/sweet/music IHTTP/1.0\r\n")
                     '((protocol 23 1 "I")))
        (check-equal "error"
                     (error-of "GET /music/sweet/music IHTTP/1.0\r\n")
                     '(invalid-constant "Expected HTTP/, RTSP/ or ICE/" 24))))
    (harness-case "no match at all closes the span empty, at the same offset"
      (lambda ()
        ;; request/uri.md#11, the empty-span fixture.
        (check-equal "events"
                     (only '(protocol protocol-complete) "GET /foo bar/ HTTP/1.1\r\n")
                     '((protocol 9 0 "")))
        (check-equal "error"
                     (error-of "GET /foo bar/ HTTP/1.1\r\n")
                     '(invalid-constant "Expected HTTP/, RTSP/ or ICE/" 9))))
    (harness-case "a full match missing its slash completes and then fails"
      (lambda ()
        ;; The same shape response/sample.md records for `HTTPER/1.1`:
        ;; span, `protocol complete`, then the error at the same offset.
        (check-equal "events"
                     (only '(protocol protocol-complete) "GET / HTTPER/1.1\r\n")
                     '((protocol 6 4 "HTTP") (protocol-complete 10)))
        (check-equal "error"
                     (error-of "GET / HTTPER/1.1\r\n")
                     '(invalid-constant "Expected HTTP/, RTSP/ or ICE/" 10))))
    (harness-case "a run of capitals is not a protocol"
      (lambda ()
        ;; The A-Z loop this replaced accepted `HTTX/1.1` outright, version and
        ;; all, because it had no notion of a constant.
        (check-equal "status" (status-of "GET / HTTX/1.1\r\n") 'error)
        (check-equal "events"
                     (only '(protocol protocol-complete) "GET / HTTX/1.1\r\n")
                     '((protocol 6 3 "HTT")))))))

(harness-group "the method-versus-protocol matrix"
  (lambda ()
    ;; llhttp checks the method against the protocol AT the protocol, before
    ;; the version is read, with a different reason per protocol -- the four
    ;; distinct reasons under error code 8. All six rows below are corpus
    ;; fixtures: the three rejections from request/invalid.md and the three
    ;; acceptances from request/method.md.
    (harness-case "GET with ICE wants SOURCE"
      (lambda ()
        (check-equal "error" (error-of "GET /music/sweet/music ICE/1.0\r\n")
                     '(invalid-constant "Expected SOURCE method for ICE/x.x request" 26))))
    (harness-case "PUT with RTSP is not an RTSP method"
      (lambda ()
        (check-equal "error" (error-of "PUT /music/sweet/music RTSP/1.0\r\n")
                     '(invalid-constant "Invalid method for RTSP/x.x request" 27))))
    (harness-case "ANNOUNCE with HTTP is not an HTTP method"
      (lambda ()
        (check-equal "error" (error-of "ANNOUNCE /music/sweet/music HTTP/1.0\r\n")
                     '(invalid-constant "Invalid method for HTTP/x.x request" 32))))
    (harness-case "the rejection fires before the version is read"
      (lambda ()
        ;; `off=32 protocol complete` then `off=32 error` -- no version span
        ;; and no version complete, though `1.0` follows and is valid.
        (check-equal "no version events"
                     (only '(version version-complete)
                           "ANNOUNCE /music/sweet/music HTTP/1.0\r\n")
                     '())))
    (harness-case "SOURCE is accepted by both ICE and HTTP"
      (lambda ()
        (check "ICE" (accepted? "SOURCE /music/sweet/music ICE/1.0\r\n"))
        (check "HTTP" (accepted? "SOURCE /music/sweet/music HTTP/1.1\r\n"))))
    (harness-case "an RTSP-only method is accepted by RTSP"
      (lambda ()
        (check "accepted" (accepted? "ANNOUNCE /music/sweet/music RTSP/1.0\r\n"))))
    (harness-case "a method in both is accepted by both"
      (lambda ()
        (check "RTSP" (accepted? "OPTIONS /music/sweet/music RTSP/1.0\r\n"))
        (check "HTTP" (accepted? "OPTIONS / HTTP/1.1\r\n"))))
    (harness-case "every method is accepted by at least one protocol"
      (lambda ()
        ;; A method that fell out of all three lists would still parse its own
        ;; name and then be rejected by whichever protocol followed. This walks
        ;; the table rather than trusting the lists to partition it.
        (check-equal "methods no protocol accepts"
                     (filter (lambda (name)
                               (not (or (member name httparse-http-methods)
                                        (member name httparse-rtsp-methods)
                                        (member name httparse-ice-methods))))
                             httparse-method-names)
                     '())))
    (harness-case "the three lists are llhttp's, by shape"
      (lambda ()
        ;; Counts and overlaps read off llhttp's own METHODS_HTTP /
        ;; METHODS_RTSP / METHODS_ICECAST.
        (check-equal "http" (length httparse-http-methods) 36)
        (check-equal "rtsp" (length httparse-rtsp-methods) 14)
        (check-equal "ice" httparse-ice-methods '("SOURCE"))
        (check-equal "in both"
                     (filter (lambda (n) (member n httparse-rtsp-methods))
                             httparse-http-methods)
                     '("GET" "OPTIONS" "POST"))
        (check-equal "ice is also http"
                     (filter (lambda (n) (not (member n httparse-http-methods)))
                             httparse-ice-methods)
                     '())))))

(harness-group "the version is a pair, not a digit soup"
  (lambda ()
    (harness-case "the four accepted pairs parse"
      (lambda ()
        ;; llhttp's `checkVersion` in strict mode admits exactly these.
        (check-equal "versions that did not parse"
                     (filter (lambda (v)
                               (not (accepted? (string-append "GET / HTTP/" v "\r\n"))))
                             '("0.9" "1.0" "1.1" "2.0"))
                     '())))
    (harness-case "a well-formed pair llhttp rejects is Invalid HTTP version"
      (lambda ()
        ;; request/invalid.md, "Invalid HTTP version", `GET / HTTP/5.6`:
        ;;   off=11 len=3 span[version]="5.6"
        ;;   off=14 error code=9 reason="Invalid HTTP version"
        ;; The span covers the whole pair and the error lands past it, because
        ;; the digit is consumed before the pair is judged.
        (check-equal "span" (only '(version) "GET / HTTP/5.6\r\n")
                     '((version 11 3 "5.6")))
        (check-equal "error" (error-of "GET / HTTP/5.6\r\n")
                     '(invalid-version "Invalid HTTP version" 14))
        (check-equal "1.2" (error-of "GET / HTTP/1.2\r\n")
                     '(invalid-version "Invalid HTTP version" 14))
        (check-equal "2.1" (error-of "GET / HTTP/2.1\r\n")
                     '(invalid-version "Invalid HTTP version" 14))))
    (harness-case "a second major digit is Expected dot"
      (lambda ()
        ;; response/invalid.md records this shape for `HTTP/01.1`: the span
        ;; covers the one digit read, and the error is at the byte after it.
        (check-equal "span" (only '(version) "GET / HTTP/01.1\r\n")
                     '((version 11 1 "0")))
        (check-equal "error" (error-of "GET / HTTP/01.1\r\n")
                     '(invalid-version "Expected dot" 12))))
    (harness-case "a non-digit minor is Invalid minor version, before the byte"
      (lambda ()
        ;; The span covers major and dot and stops: the offending byte is not
        ;; consumed, which is what separates this from Invalid HTTP version.
        (check-equal "span" (only '(version) "GET / HTTP/1.x\r\n")
                     '((version 11 2 "1.")))
        (check-equal "error" (error-of "GET / HTTP/1.x\r\n")
                     '(invalid-version "Invalid minor version" 13))))
    (harness-case "a non-digit major is Invalid major version, on an empty span"
      (lambda ()
        (check-equal "span" (only '(version) "GET / HTTP/x.1\r\n")
                     '((version 11 0 "")))
        (check-equal "error" (error-of "GET / HTTP/x.1\r\n")
                     '(invalid-version "Invalid major version" 11))))
    (harness-case "a third component is not part of the version"
      (lambda ()
        ;; The digits-and-dot loop this replaced took `1.1.1` whole.
        (check-equal "span" (only '(version) "GET / HTTP/1.1.1\r\n")
                     '((version 11 3 "1.1")))
        (check-equal "error" (error-of "GET / HTTP/1.1.1\r\n")
                     '(invalid-version "Expected CRLF after version" 14))))))

(harness-group "the method table"
  (lambda ()
    (harness-case "every method in the table parses as itself"
      (lambda ()
        ;; 47 names, each fed as a complete request line. A table that dropped or
        ;; mis-wired one name would show up here rather than in whichever
        ;; fixture happened to use it.
        (check-equal "methods that did not round-trip"
                     (filter
                      (lambda (name)
                        (let ((events (events-of (string-append name " / HTTP/1.1\r\n"))))
                          (not (equal? (assq 'method events)
                                       (list 'method 0 (string-length name) name)))))
                      httparse-method-names)
                     '())))
    (harness-case "the table is the one llhttp knows"
      (lambda ()
        (check-equal "count" (length httparse-method-names) 47)))
    (harness-case "MKCOLA matches MKCOL and then rejects the A"
      (lambda ()
        ;; request/invalid.md: `off=0 len=5 span[method]="MKCOL"`,
        ;; `off=5 method complete`, `off=5 error`. A tchar loop would take
        ;; MKCOLA whole and accept it, which is the point of the table.
        (check-equal "events"
                     (events-of "MKCOLA / HTTP/1.1\r\n")
                     '((message-begin 0)
                       (method 0 5 "MKCOL")
                       (method-complete 5)))
        (check-equal "status" (status-of "MKCOLA / HTTP/1.1\r\n") 'error)
        (check-equal "offset" (error-offset-of "MKCOLA / HTTP/1.1\r\n") 5)))
    (harness-case "GET-PARAMETER matches whole, though GET is a proper prefix of it"
      (lambda ()
        ;; This pair is why the table cannot be `make-sequence-dispatch-node`,
        ;; which rejects a case list where one entry is a proper prefix of
        ;; another. A keyword table tolerates the pair and takes the longer
        ;; name when the input reaches it.
        (check-equal "method" (assq 'method (events-of "GET-PARAMETER / HTTP/1.1\r\n"))
                     '(method 0 13 "GET-PARAMETER"))))
    (harness-case "GET followed by a space matches GET, not the longer name"
      (lambda ()
        (check-equal "method" (assq 'method (events-of "GET / HTTP/1.1\r\n"))
                     '(method 0 3 "GET"))))
    (harness-case "a hyphenated method matches"
      (lambda ()
        (check-equal "method" (assq 'method (events-of "M-SEARCH * HTTP/1.1\r\n"))
                     '(method 0 8 "M-SEARCH"))))
    (harness-case "an unknown method is rejected inside the table walk"
      (lambda ()
        ;; `F` begins FLUSH, so the walk advances one byte and then finds no
        ;; continuation for `O`. The error lands on that byte, and the span is
        ;; still open when it fires, so no fragment is delivered.
        (check-equal "status" (status-of "FOO / HTTP/1.1\r\n") 'error)
        (check-equal "offset" (error-offset-of "FOO / HTTP/1.1\r\n") 1)
        (check-equal "no method span"
                     (filter (lambda (e) (eq? (car e) 'method))
                             (events-of "FOO / HTTP/1.1\r\n"))
                     '())))
    (harness-case "a method that is only a prefix of a real one is rejected"
      (lambda ()
        ;; `MKCO` is a prefix of MKCOL but is not itself a method, so the walk
        ;; consumes all four bytes and then fails on the space at 4. No fragment
        ;; is delivered -- and the corpus agrees: `span[method]` never precedes
        ;; an error in any of the 253 fixtures.
        (check-equal "status" (status-of "MKCO / HTTP/1.1\r\n") 'error)
        (check-equal "offset" (error-offset-of "MKCO / HTTP/1.1\r\n") 4)
        (check-equal "no method span"
                     (filter (lambda (e) (eq? (car e) 'method))
                             (events-of "MKCO / HTTP/1.1\r\n"))
                     '())))))

(harness-finish)
