;;; The header section, asserted in llhttp's own trace text.
;;;
;;; These cases render through the SAME adapter the conformance driver uses,
;;; so an expectation here is a block of lines copied out of a fixture rather
;;; than a transliteration of it. Where a case uses an input the corpus does
;;; not carry, the comment says which fixture establishes the shape.
;;;
;;; `headers complete` renders here from M4 on. Its line carries four numbers
;;; -- method, version pair, flags, content length -- and every one is READ OFF
;;; THE PARSER'S OWN FIELDS, never recomputed from the headers this lane fed
;;; in, which is what keeps the adapter a rename (decision 0014).
(import (rnrs)
        (httparse test harness)
        (httparse test adapter)
        (httparse test trace-format)
        (httparse grammar)
        (byte-machine verify)
        (byte-machine interpret)
        (byte-machine runtime))

(define machine
  (make-interpreted-machine (verify-machine (make-request-line-machine))))

;; trace : String -> (Listof String)
(define (trace input)
  (let* ((paused #f)
         (r (make-trace-recorder))
         (p (make-parser machine (trace-recorder-bindings r) #f))
         (bv (string->utf8 input))
         (refused
          (call/cc
           (lambda (k)
             (with-exception-handler
              (lambda (e) (if (adapter-error? e) (k #t) (raise e)))
              (lambda ()
                (let ((res (parser-feed! p bv 0 (bytevector-length bv))))
                  (when (eq? (parser-result-status res) 'error)
                    (trace-recorder-note-error! r (parser-result-error res)))
                  (set! paused (parser-result-status res))
                  #f)))))))
    (append (map utf8->string (trace-format (trace-recorder-events r)))
            (if refused '("(refused)") '())
            (if (eq? paused 'paused) '("(paused)") '()))))

;; The request line every case below shares, so the header lines start at a
;; known offset: `GET / HTTP/1.1` is 14 bytes and its CRLF ends at 16.
(define start-line
  '("off=0 message begin"
    "off=0 len=3 span[method]=\"GET\""
    "off=3 method complete"
    "off=4 len=1 span[url]=\"/\""
    "off=6 url complete"
    "off=6 len=4 span[protocol]=\"HTTP\""
    "off=10 protocol complete"
    "off=11 len=3 span[version]=\"1.1\""
    "off=14 version complete"))

;; `list-tail` is R6RS; its counterpart is not.
(define (list-head xs n)
  (if (or (= n 0) (null? xs)) '() (cons (car xs) (list-head (cdr xs) (- n 1)))))

(define (after-start-line input)
  (let loop ((lines (trace (string-append "GET / HTTP/1.1\r\n" input)))
             (expected start-line))
    (if (null? expected)
        lines
        (begin
          (unless (and (pair? lines) (string=? (car lines) (car expected)))
            (assertion-violation 'after-start-line "the start line moved"
                                 (car expected) (and (pair? lines) (car lines))))
          (loop (cdr lines) (cdr expected))))))

(harness-begin "unit.header-section")

(harness-group "a header, line for line"
  (lambda ()
    (harness-case "request/sample.md#1 reproduces exactly, headers included"
      (lambda ()
        ;; The whole expected block of that fixture, minus its last line --
        ;; `headers complete`, which M3 cannot render.
        (check-equal "trace"
                     (trace "OPTIONS /url HTTP/1.1\r\nHeader1: Value1\r\nHeader2:  Value2\r\n\r\n")
                     '("off=0 message begin"
                       "off=0 len=7 span[method]=\"OPTIONS\""
                       "off=7 method complete"
                       "off=8 len=4 span[url]=\"/url\""
                       "off=13 url complete"
                       "off=13 len=4 span[protocol]=\"HTTP\""
                       "off=17 protocol complete"
                       "off=18 len=3 span[version]=\"1.1\""
                       "off=21 version complete"
                       "off=23 len=7 span[header_field]=\"Header1\""
                       "off=31 header_field complete"
                       "off=32 len=6 span[header_value]=\"Value1\""
                       "off=40 header_value complete"
                       "off=40 len=7 span[header_field]=\"Header2\""
                       "off=48 header_field complete"
                       "off=50 len=6 span[header_value]=\"Value2\""
                       "off=58 header_value complete"
                       "off=60 headers complete method=6 v=1/1 flags=0 content_length=0"
                       "off=60 message complete"))))
    (harness-case "the version pair on the line is the one that was parsed"
      (lambda ()
        ;; request/connection.md, "No restart when keep-alive is off (1.0)":
        ;; its first message is `PUT /url HTTP/1.0` with no headers, and the
        ;; oracle records `off=21 headers complete method=4 v=1/0`. The rest of
        ;; that fixture is a second message and a `Connection: close` error,
        ;; both later milestones', so only its first twelve lines are asserted.
        (check-equal "1.0"
                     (list-tail (trace "PUT /url HTTP/1.0\r\n\r\n") 9)
                     '("off=21 headers complete method=4 v=1/0 flags=0 content_length=0"
                       "off=21 message complete")))
      )
    (harness-case "the field span ends before the colon and the event fires past it"
      (lambda ()
        ;; The `url complete` asymmetry again: the delimiter is consumed and
        ;; then the event fires, so 21 is one past the colon at 20.
        (check-equal "field"
                     (list-head (after-start-line "Host: a\r\n\r\n") 2)
                     '("off=16 len=4 span[header_field]=\"Host\""
                       "off=21 header_field complete"))))
    (harness-case "leading OWS is discarded and is not part of the value"
      (lambda ()
        (check-equal "value"
                     (list-head (list-tail (after-start-line "Host:   a\r\n\r\n") 2) 2)
                     '("off=24 len=1 span[header_value]=\"a\""
                       "off=27 header_value complete"))))
    (harness-case "an empty value is announced as an empty span"
      (lambda ()
        ;; llhttp opens and immediately closes the value span
        ;; (`emptySpan(span.headerValue, ...)`), which is only observable
        ;; because of the upstream empty-span change this project asked for.
        (check-equal "value"
                     (list-head (list-tail (after-start-line "Empty:\r\n\r\n") 2) 2)
                     '("off=24 len=0 span[header_value]=\"\""
                       "off=24 header_value complete"))))))

(harness-group "Content-Length, and the body it measures"
  (lambda ()
    (harness-case "request/content-length.md#1 reproduces exactly, body included"
      (lambda ()
        ;; The whole expected block of that fixture. `flags=20` is
        ;; FLAGS.CONTENT_LENGTH, and the body arrives as a span like any other.
        (check-equal "trace"
                     (trace "PUT /url HTTP/1.1\r\nContent-Length: 003\r\n\r\nabc")
                     '("off=0 message begin"
                       "off=0 len=3 span[method]=\"PUT\""
                       "off=3 method complete"
                       "off=4 len=4 span[url]=\"/url\""
                       "off=9 url complete"
                       "off=9 len=4 span[protocol]=\"HTTP\""
                       "off=13 protocol complete"
                       "off=14 len=3 span[version]=\"1.1\""
                       "off=17 version complete"
                       "off=19 len=14 span[header_field]=\"Content-Length\""
                       "off=34 header_field complete"
                       "off=35 len=3 span[header_value]=\"003\""
                       "off=40 header_value complete"
                       "off=42 headers complete method=4 v=1/1 flags=20 content_length=3"
                       "off=42 len=3 span[body]=\"abc\""
                       "off=45 message complete"))))
    (harness-case "the name table is case-insensitive, as llhttp's transform makes it"
      (lambda ()
        ;; llhttp lowercases the field name before `select(SPECIAL_HEADERS)`.
        ;; The SPAN still carries the bytes as they arrived.
        (check-equal "content_length is still set"
                     (list-tail (trace "PUT /url HTTP/1.1\r\ncOnTeNt-LeNgTh: 5\r\n\r\nabcde") 9)
                     '("off=19 len=14 span[header_field]=\"cOnTeNt-LeNgTh\""
                       "off=34 header_field complete"
                       "off=35 len=1 span[header_value]=\"5\""
                       "off=38 header_value complete"
                       "off=40 headers complete method=4 v=1/1 flags=20 content_length=5"
                       "off=40 len=5 span[body]=\"abcde\""
                       "off=45 message complete"))))
    (harness-case "a longer name that merely starts with a special one is general"
      (lambda ()
        ;; llhttp's own comment: `Connection-Duration` instead of `Connection`.
        ;; The table matches the prefix, the colon check falls through, and the
        ;; general token loop carries on from where the walk stopped.
        (check-equal "no flag, and the whole name in the span"
                     (list-tail (trace "PUT /url HTTP/1.1\r\nContent-Length-Ish: 3\r\n\r\n") 9)
                     '("off=19 len=18 span[header_field]=\"Content-Length-Ish\""
                       "off=38 header_field complete"
                       "off=39 len=1 span[header_value]=\"3\""
                       "off=42 header_value complete"
                       "off=44 headers complete method=4 v=1/1 flags=0 content_length=0"
                       "off=44 message complete"))))
    (harness-case "a space before the colon is a different error on a special name"
      (lambda ()
        ;; request/connection.md, "Invalid whitespace token with `Connection`
        ;; header field": the name completes into a SPAN and the error is at
        ;; 30, one PAST the space at 29, because llhttp peeks the space, ends
        ;; the span, and then `skipTo`s -- and a skip consumes.
        (check-equal "Connection"
                     (list-tail (trace "PUT /url HTTP/1.1\r\nConnection : upgrade\r\n\r\n") 9)
                     '("off=19 len=10 span[header_field]=\"Connection\""
                       "off=30 error code=10 reason=\"Invalid header field char\""))
        ;; The same rule for another name in llhttp's SPECIAL_HEADERS, which
        ;; no fixture exercises: `proxy-connection` is in the table, so it
        ;; takes the same path. This is what makes its presence observable at
        ;; all in this slice -- the connection FLAGS it also selects are the
        ;; next slice's.
        (check-equal "Proxy-Connection"
                     (list-tail (trace "PUT /url HTTP/1.1\r\nProxy-Connection : x\r\n\r\n") 9)
                     '("off=19 len=16 span[header_field]=\"Proxy-Connection\""
                       "off=36 error code=10 reason=\"Invalid header field char\""))
        ;; And the contrast that makes the pair mean something. The same
        ;; sixteen-byte length, so the space is at 35 either way and only the
        ;; RULE moves the number: a name not in the table errors AT the space
        ;; rather than past it, with a different reason, and with the span
        ;; still open so no fragment is delivered at all.
        (check-equal "a general name of the same length"
                     (list-tail (trace "PUT /url HTTP/1.1\r\nProxy-Connexions : x\r\n\r\n") 9)
                     '("off=35 error code=10 reason=\"Invalid header token\""))))
    (harness-case "the accumulator overflows where llhttp's does, one digit late"
      (lambda ()
        ;; request/content-length.md, "Error on `Content-Length` overflow":
        ;; 22 digits in, and the span is 21 of them -- the offending digit is
        ;; CONSUMED before the overflow is reported, so the error is at 56 and
        ;; not at 55. Only the accumulator can produce that span, which is why
        ;; this fixture is this milestone's and not the header section's.
        (check-equal "trace"
                     (list-tail (trace "PUT /url HTTP/1.1\r\nContent-Length: 1000000000000000000000\r\n\r\n") 11)
                     '("off=35 len=21 span[header_value]=\"100000000000000000000\""
                       "off=56 error code=11 reason=\"Content-Length overflow\""))))
    (harness-case "a second Content-Length is a duplicate, checked at the value"
      (lambda ()
        ;; request/content-length.md, "Error on duplicate `Content-Length`":
        ;; the second field name completes and THEN the error fires, because
        ;; the flag is tested where the value starts.
        (check-equal "trace"
                     (list-tail (trace "PUT /url HTTP/1.1\r\nContent-Length: 1\r\nContent-Length: 2\r\n\r\n") 11)
                     '("off=35 len=1 span[header_value]=\"1\""
                       "off=38 header_value complete"
                       "off=38 len=14 span[header_field]=\"Content-Length\""
                       "off=53 header_field complete"
                       "off=54 error code=4 reason=\"Duplicate Content-Length\""))))
    (harness-case "trailing space is inside the value span but not inside the number"
      (lambda ()
        ;; `header_value_content_length_ws` MATCHES spaces, so they are
        ;; consumed and the span ends at the CR past them.
        (check-equal "span keeps the space"
                     (list-tail (trace "PUT /url HTTP/1.1\r\nContent-Length: 4 \r\n\r\nabcd") 11)
                     '("off=35 len=2 span[header_value]=\"4 \""
                       "off=39 header_value complete"
                       "off=41 headers complete method=4 v=1/1 flags=20 content_length=4"
                       "off=41 len=4 span[body]=\"abcd\""
                       "off=45 message complete"))))
    (harness-case "a non-digit in Content-Length is its own reason, at the byte"
      (lambda ()
        ;; `.otherwise` does not consume, so the error is AT the character --
        ;; and the span is ended first, which is why the value still renders.
        (check-equal "trace"
                     (list-tail (trace "PUT /url HTTP/1.1\r\nContent-Length: 4x\r\n\r\n") 11)
                     '("off=35 len=1 span[header_value]=\"4\""
                       "off=36 error code=11 reason=\"Invalid character in Content-Length\""))))
    (harness-case "an empty Content-Length is an error, not an empty span"
      (lambda ()
        ;; `checkEmptyHeaderValue` loads the header state BEFORE the empty
        ;; span is announced, so a general header still gets its empty span
        ;; (asserted above) and this one does not.
        (check-equal "trace"
                     (list-tail (trace "PUT /url HTTP/1.1\r\nContent-Length:\r\n\r\n") 11)
                     '("off=36 error code=11 reason=\"Empty Content-Length\""))))
    (harness-case "Content-Length zero has no body at all"
      (lambda ()
        ;; llhttp's body decision: the flag is set but the length is zero, so
        ;; the answer is 0 -- no body -- and not an empty body span.
        (check-equal "trace"
                     (list-tail (trace "PUT /url HTTP/1.1\r\nContent-Length: 0\r\n\r\n") 13)
                     '("off=40 headers complete method=4 v=1/1 flags=20 content_length=0"
                       "off=40 message complete"))))))

(harness-group "Connection, Transfer-Encoding and Upgrade set the flags"
  (lambda ()
    (harness-case "each Connection token sets its own bit"
      (lambda ()
        ;; request/connection.md, one fixture per bit. The value span is
        ;; untouched by any of it -- the tokens are read for their flags and
        ;; copied through unchanged.
        (check-equal "keep-alive is flags=1"
                     (list-tail (trace "PUT /url HTTP/1.1\r\nConnection: keep-alive\r\n\r\n") 11)
                     '("off=31 len=10 span[header_value]=\"keep-alive\""
                       "off=43 header_value complete"
                       "off=45 headers complete method=4 v=1/1 flags=1 content_length=0"
                       "off=45 message complete"))
        (check-equal "close is flags=2"
                     (list-tail (trace "PUT /url HTTP/1.1\r\nConnection: close\r\n\r\n") 11)
                     '("off=31 len=5 span[header_value]=\"close\""
                       "off=38 header_value complete"
                       "off=40 headers complete method=4 v=1/1 flags=2 content_length=0"
                       "off=40 message complete"))
        ;; "Setting flag on `close` followed by tab": the tab is inside the
        ;; span, because `header_value_connection_ws` MATCHES it.
        (check-equal "a trailing tab stays in the span"
                     (list-tail (trace "PUT /url HTTP/1.1\r\nConnection: close\t\r\n\r\n") 11)
                     '("off=31 len=6 span[header_value]=\"close\t\""
                       "off=39 header_value complete"
                       "off=41 headers complete method=4 v=1/1 flags=2 content_length=0"
                       "off=41 message complete"))))
    (harness-case "a comma-separated list sets every bit it names"
      (lambda ()
        ;; request/connection.md "Sample": three known tokens and two unknown
        ;; ones, giving flags=7 -- and the unknown tokens neither set nor
        ;; clear anything.
        (check-equal "flags=7"
                     (list-tail (trace (string-append
                                        "PUT /url HTTP/1.1\r\n"
                                        "Connection: close, token, upgrade, token, keep-alive\r\n\r\n")) 11)
                     '("off=31 len=40 span[header_value]=\"close, token, upgrade, token, keep-alive\""
                       "off=73 header_value complete"
                       "off=75 headers complete method=4 v=1/1 flags=7 content_length=0"
                       "off=75 message complete"))))
    (harness-case "the value tables are case-folded too, not just the name table"
      (lambda ()
        ;; llhttp lowercases the value before matching, in `header_value_connection`
        ;; and in `header_value_te_chunked`. The corpus shows it at work in the
        ;; "Upgrade GET request" fixture, whose `Connection: Upgrade` -- capital
        ;; U -- contributes CONNECTION_UPGRADE to flags=14. The inputs here are
        ;; the lowercase fixtures with the case flipped and nothing else, so the
        ;; offsets are those fixtures' own and only the case is under test.
        (check-equal "CLOSE is close"
                     (list-tail (trace "PUT /url HTTP/1.1\r\nConnection: CLOSE\r\n\r\n") 13)
                     '("off=40 headers complete method=4 v=1/1 flags=2 content_length=0"
                       "off=40 message complete"))
        ;; A chunked request parks after `headers complete` until there is a
        ;; chunk reader, so this asserts the flag and stops where M4 does.
        (check-equal "CHUNKED is chunked"
                     (list-tail (trace "PUT /url HTTP/1.1\r\nTransfer-Encoding: CHUNKED\r\n\r\n") 13)
                     '("off=49 headers complete method=4 v=1/1 flags=208 content_length=0"))))
    (harness-case "lowercase chunked sets both bits, and the trace stops there"
      (lambda ()
        ;; The pair to the case test above and to `pigeons`: same shape, same
        ;; offsets, and the only difference is that this one IS chunked --
        ;; flags=208 rather than 200, and no `Request has invalid` refusal.
        (check-equal "flags=208"
                     (list-tail (trace "PUT /url HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n") 11)
                     '("off=38 len=7 span[header_value]=\"chunked\""
                       "off=47 header_value complete"
                       "off=49 headers complete method=4 v=1/1 flags=208 content_length=0"))))
    (harness-case "close is not closed, and the table knows the difference"
      (lambda ()
        ;; The `close` / `closed` pair a Gate 0 spike measured, and the reason
        ;; `make-sequence-dispatch-node` could not have been used here: the
        ;; longer token is not a Connection keyword, so no bit is set.
        (check-equal "closed sets nothing"
                     (list-tail (trace "PUT /url HTTP/1.1\r\nConnection: closed\r\n\r\n") 13)
                     '("off=41 headers complete method=4 v=1/1 flags=0 content_length=0"
                       "off=41 message complete"))))
    (harness-case "an Upgrade header sets its own bit, beside Connection's"
      (lambda ()
        ;; request/connection.md, "Upgrade GET request" (the short one): every
        ;; line of that fixture except its last, which is the upgrade PAUSE --
        ;; a later milestone's. flags=15 is UPGRADE | CONNECTION_UPGRADE |
        ;; CONNECTION_KEEP_ALIVE, so all three bits and two headers are pinned
        ;; by one expectation.
        (check-equal "flags=15"
                     (trace (string-append
                             "GET /demo HTTP/1.1\r\n"
                             "Connection: keep-alive, upgrade\r\n"
                             "Upgrade: WebSocket\r\n\r\n"))
                     '("off=0 message begin"
                       "off=0 len=3 span[method]=\"GET\""
                       "off=3 method complete"
                       "off=4 len=5 span[url]=\"/demo\""
                       "off=10 url complete"
                       "off=10 len=4 span[protocol]=\"HTTP\""
                       "off=14 protocol complete"
                       "off=15 len=3 span[version]=\"1.1\""
                       "off=18 version complete"
                       "off=20 len=10 span[header_field]=\"Connection\""
                       "off=31 header_field complete"
                       "off=32 len=19 span[header_value]=\"keep-alive, upgrade\""
                       "off=53 header_value complete"
                       "off=53 len=7 span[header_field]=\"Upgrade\""
                       "off=61 header_field complete"
                       "off=62 len=9 span[header_value]=\"WebSocket\""
                       "off=73 header_value complete"
                       "off=75 headers complete method=1 v=1/1 flags=15 content_length=0"
                       "off=75 message complete"
                       ;; Both upgrade bits and no body, so llhttp's decision
                       ;; answers 1: complete, then pause. The fixture's own
                       ;; last line is `error code=22`, which is the pause
                       ;; rendered -- and the one thing the adapter cannot
                       ;; spell, so the run ends here instead.
                       "(paused)"))))
    (harness-case "a bare Transfer-Encoding is a request error, after the line that reports it"
      (lambda ()
        ;; request/transfer-encoding.md, "Ignoring `pigeons`": the flag is set
        ;; and PRINTED, and only then does the body decision refuse it --
        ;; llhttp's `after_headers_complete` returning 5.
        (check-equal "pigeons"
                     (list-tail (trace "PUT /url HTTP/1.1\r\nTransfer-Encoding: pigeons\r\n\r\n") 11)
                     '("off=38 len=7 span[header_value]=\"pigeons\""
                       "off=47 header_value complete"
                       "off=49 headers complete method=4 v=1/1 flags=200 content_length=0"
                       "off=49 error code=15 reason=\"Request has invalid `Transfer-Encoding`\""))))
    (harness-case "chunkedchunked is not chunked"
      (lambda ()
        ;; request/transfer-encoding.md. The table takes `chunked` whole and
        ;; the next byte continues the token, so the value falls through to
        ;; the token loop and no CHUNKED bit is set -- flags=200, not 208.
        (check-equal "flags=200"
                     (list-tail (trace "PUT /url HTTP/1.1\r\nTransfer-Encoding: chunkedchunked\r\n\r\n") 11)
                     '("off=38 len=14 span[header_value]=\"chunkedchunked\""
                       "off=54 header_value complete"
                       "off=56 headers complete method=4 v=1/1 flags=200 content_length=0"
                       "off=56 error code=15 reason=\"Request has invalid `Transfer-Encoding`\""))))
    (harness-case "Content-Length after Transfer-Encoding is the mirror conflict"
      (lambda ()
        ;; The other half of the pair M4 Slice ① could only build one side of:
        ;; the TRANSFER_ENCODING flag can now be set, so this branch is
        ;; reachable and carries its own reason and its own code.
        (check-equal "trace"
                     (list-tail (trace (string-append
                                        "PUT /url HTTP/1.1\r\n"
                                        "Transfer-Encoding: pigeons\r\nContent-Length: 1\r\n\r\n")) 13)
                     '("off=47 len=14 span[header_field]=\"Content-Length\""
                       "off=62 header_field complete"
                       "off=62 error code=11 reason=\"Content-Length can't be present with Transfer-Encoding\""))))))

(harness-group "the upgrade decision, and the pause it has no words for"
  (lambda ()
    (harness-case "CONNECT does not read the body its own Content-Length declares"
      (lambda ()
        ;; request/method.md, "CONNECT with body". llhttp sets `upgrade` for
        ;; CONNECT before the headers-complete callback, and its body decision
        ;; then answers 1 -- message complete and PAUSE -- so the ten bytes are
        ;; never read. Reading them is what this parser did before the decision
        ;; core was complete, and it is a behaviour bug the trace shows.
        (check-equal "no body span, and a pause the adapter cannot spell"
                     (list-tail (trace (string-append
                                        "CONNECT foo.bar.com:443 HTTP/1.0\r\n"
                                        "User-agent: Mozilla/1.1N\r\n"
                                        "Proxy-authorization: basic aGVsbG86d29ybGQ=\r\n"
                                        "Content-Length: 10\r\n\r\nblarfcicle\"")) 21)
                     '("off=127 headers complete method=5 v=1/0 flags=20 content_length=10"
                       "off=127 message complete"
                       "(paused)"))))
    (harness-case "an upgrade that HAS a body reads it, and pauses afterwards"
      (lambda ()
        ;; request/connection.md, "Emitting part of body and pausing". The
        ;; early exit is `upgrade && (CONNECT || !hasBody)`, and this request
        ;; has a body -- so it is NOT taken, the four declared bytes are read,
        ;; and the pause happens at the END. Without this case nothing
        ;; distinguishes the two upgrade arms, because the fixture that would
        ;; is one of the seven the pause gap blocks.
        (check-equal "body then pause"
                     (list-tail (trace (string-append
                                        "PUT /url HTTP/1.1\r\n"
                                        "Connection: upgrade\r\nContent-Length: 4\r\n"
                                        "Upgrade: ws\r\n\r\nabcdefgh")) 21)
                     '("off=74 headers complete method=4 v=1/1 flags=34 content_length=4"
                       "off=74 len=4 span[body]=\"abcd\""
                       "off=78 message complete"
                       "(paused)"))))
    (harness-case "an ordinary request does not pause"
      (lambda ()
        ;; The contrast: `upgrade` is zero, so the same decision falls through
        ;; to the body arms. Without this the pause could fire for everything
        ;; and both cases above would still pass.
        (check-equal "no pause"
                     (list-tail (trace "PUT /url HTTP/1.1\r\nContent-Length: 3\r\n\r\nabc") 13)
                     '("off=40 headers complete method=4 v=1/1 flags=20 content_length=3"
                       "off=40 len=3 span[body]=\"abc\""
                       "off=43 message complete"))))))

(harness-group "a request may start with a stray CRLF"
  (lambda ()
    (harness-case "request/sample.md, Prefix newline"
      (lambda ()
        ;; llhttp's `start` node matches CR and LF back to itself, so a leading
        ;; line ending is skipped and `message begin` lands at 2 rather than 0.
        (check-equal "trace"
                     (trace "\r\nGET /test HTTP/1.1\r\n\r\n")
                     '("off=2 message begin"
                       "off=2 len=3 span[method]=\"GET\""
                       "off=5 method complete"
                       "off=6 len=5 span[url]=\"/test\""
                       "off=12 url complete"
                       "off=12 len=4 span[protocol]=\"HTTP\""
                       "off=16 protocol complete"
                       "off=17 len=3 span[version]=\"1.1\""
                       "off=20 version complete"
                       "off=24 headers complete method=1 v=1/1 flags=0 content_length=0"
                       "off=24 message complete"))))))

(harness-group "obs-fold is rejected, in both of its places"
  (lambda ()
    (harness-case "a continuation line after a non-empty value"
      (lambda ()
        ;; llhttp PEEKS the whitespace here, so the error is AT it, at 25.
        (check-equal "trace"
                     (list-tail (after-start-line "Host: a\r\n abc\r\n\r\n") 2)
                     '("off=22 len=1 span[header_value]=\"a\""
                       "off=25 error code=10 reason=\"Unexpected whitespace after header value\""))))
    (harness-case "a continuation line after an empty value"
      (lambda ()
        ;; and MATCHES it here, so the error is one PAST it, at 25 for a space
        ;; at 24 -- a different reason and a different offset rule.
        (check-equal "trace"
                     (list-tail (after-start-line "Empty:\r\n abc\r\n\r\n") 2)
                     '("off=25 error code=10 reason=\"Invalid header value char\""))))))

(harness-group "the four ways a header is rejected, each with its own reason"
  (lambda ()
    (harness-case "a space where a field should start"
      (lambda ()
        ;; request/invalid.md#20: the space is consumed before it fails, so
        ;; `off=17` for a space at 16.
        (check-equal "trace" (after-start-line " Host: foo\r\n\r\n")
                     '("off=17 error code=30 reason=\"Unexpected space after start line\""))))
    (harness-case "a non-token byte in the field name"
      (lambda ()
        ;; request/invalid.md#11, `Fo@: Failure`: no `span[header_field]` at
        ;; all, because the span is still open when the error fires.
        (check-equal "trace" (after-start-line "Fo@: Failure\r\n\r\n")
                     '("off=18 error code=10 reason=\"Invalid header token\""))))
    (harness-case "a field name with no colon"
      (lambda ()
        ;; request/invalid.md#15, `name` alone: the error lands on the CR.
        (check-equal "trace" (after-start-line "name\r\n\r\n")
                     '("off=20 error code=10 reason=\"Invalid header token\""))))
    (harness-case "a leading colon"
      (lambda ()
        ;; request/invalid.md#13. Peeked, so the error is AT the colon.
        (check-equal "trace" (after-start-line ": Bar\r\n\r\n")
                     '("off=16 error code=10 reason=\"Invalid header token\""))))
    (harness-case "a bare LF where a field should start"
      (lambda ()
        ;; Matched, so consumed: the error is one past the LF at 16.
        (check-equal "trace" (after-start-line "\nHost: a\r\n\r\n")
                     '("off=17 error code=10 reason=\"Invalid header field char\""))))))

(harness-group "line endings inside the header section are strict"
  (lambda ()
    (harness-case "a bare LF after a value wants its CR"
      (lambda ()
        ;; request/sample.md records this shape: the value span closes and the
        ;; error is AT the LF, unconsumed.
        (check-equal "trace" (list-tail (after-start-line "Host: a\nX: y\r\n\r\n") 2)
                     '("off=22 len=1 span[header_value]=\"a\""
                       "off=23 error code=25 reason=\"Missing expected CR after header value\""))))
    (harness-case "a CR not followed by LF after a value"
      (lambda ()
        (check-equal "trace" (list-tail (after-start-line "Host: a\rX\r\n\r\n") 2)
                     '("off=22 len=1 span[header_value]=\"a\""
                       "off=24 error code=3 reason=\"Missing expected LF after header value\""))))
    (harness-case "a CR not followed by LF after an empty value"
      (lambda ()
        (check-equal "trace" (list-tail (after-start-line "Empty:\rX\r\n\r\n") 2)
                     '("off=23 error code=2 reason=\"Expected LF after CR\""))))
    (harness-case "a CR not followed by LF on the empty line"
      (lambda ()
        (check-equal "trace" (after-start-line "\rX")
                     '("off=17 error code=2 reason=\"Expected LF after headers\""))))))

(harness-finish)
