;;; What a response's framing decides, in llhttp's own trace text.
;;;
;;; These cases render through the SAME adapter the conformance driver uses,
;;; so an expectation here is a block of lines copied out of a fixture rather
;;; than a transliteration of it.
;;;
;;; A REQUEST'S BODY IS ALWAYS COUNTED AND A RESPONSE'S NEED NOT BE. That is
;;; the whole of what this lane is about. llhttp's `message_needs_eof` returns
;;; 0 unconditionally for a request, so through M6 the body decision had only
;;; two answers -- a count, or nothing. A response adds a third: read until
;;; the connection closes. The function that decides is asked from two places
;;; and both are here, because the same answer decides whether there is a body
;;; AND whether there is a next message.
;;;
;;; THE SHARPEST PAIR IS THE FIRST TWO, and they differ in three bytes. Under
;;; a 200, `HTTP/1.1 200 OK\r\n\r\nHTTP/1.1 200 OK` is one message whose body
;;; is the second line; under a 204 the same shape is TWO messages. Nothing
;;; else in either input differs.
(import (rnrs)
        (httparse test harness)
        (httparse test adapter)
        (httparse test trace-format)
        (httparse grammar)
        (byte-machine verify)
        (byte-machine interpret)
        (byte-machine runtime))

(define machine
  (make-interpreted-machine (verify-machine (make-message-machine))))

;; trace : String -> (Listof String)
(define (trace input)
  (let* ((r (make-trace-recorder))
         (p (make-parser machine (trace-recorder-bindings r '(response) #f) #f
                         (adapter-parser-inits '(response))))
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
                  (when (eq? (parser-result-status res) 'paused)
                    (trace-recorder-note-paused! r (parser-result-pause res)))
                  #f)))))))
    (append (map utf8->string (trace-format (trace-recorder-events r)))
            (if refused '("(refused)") '()))))

(harness-begin "unit.response-framing")

(harness-group "a body the connection ends"
  (lambda ()
    (harness-case "response/connection.md#4"
      (lambda ()
        (check-equal "trace"
                     (trace "HTTP/1.1 200 OK\r\n\r\nHTTP/1.1 200 OK")
                     '("off=0 message begin"
                       "off=0 len=4 span[protocol]=\"HTTP\""
                       "off=4 protocol complete"
                       "off=5 len=3 span[version]=\"1.1\""
                       "off=8 version complete"
                       "off=13 len=2 span[status]=\"OK\""
                       "off=17 status complete"
                       "off=19 headers complete status=200 v=1/1 flags=0 content_length=0"
                       "off=19 len=15 span[body]=\"HTTP/1.1 200 OK\""))))
    (harness-case "response/connection.md#5"
      (lambda ()
        (check-equal "trace"
                     (trace "HTTP/1.1 204 No content\r\n\r\nHTTP/1.1 200 OK")
                     '("off=0 message begin"
                       "off=0 len=4 span[protocol]=\"HTTP\""
                       "off=4 protocol complete"
                       "off=5 len=3 span[version]=\"1.1\""
                       "off=8 version complete"
                       "off=13 len=10 span[status]=\"No content\""
                       "off=25 status complete"
                       "off=27 headers complete status=204 v=1/1 flags=0 content_length=0"
                       "off=27 message complete"
                       "off=27 reset"
                       "off=27 message begin"
                       "off=27 len=4 span[protocol]=\"HTTP\""
                       "off=31 protocol complete"
                       "off=32 len=3 span[version]=\"1.1\""
                       "off=35 version complete"
                       "off=40 len=2 span[status]=\"OK\""))))
    (harness-case "response/connection.md#6"
      (lambda ()
        (check-equal "trace"
                     (trace "HTTP/1.1 204 No content\r\nConnection: close\r\n\r\nHTTP/1.1 200 OK")
                     '("off=0 message begin"
                       "off=0 len=4 span[protocol]=\"HTTP\""
                       "off=4 protocol complete"
                       "off=5 len=3 span[version]=\"1.1\""
                       "off=8 version complete"
                       "off=13 len=10 span[status]=\"No content\""
                       "off=25 status complete"
                       "off=25 len=10 span[header_field]=\"Connection\""
                       "off=36 header_field complete"
                       "off=37 len=5 span[header_value]=\"close\""
                       "off=44 header_value complete"
                       "off=46 headers complete status=204 v=1/1 flags=2 content_length=0"
                       "off=46 message complete"
                       "off=47 error code=5 reason=\"Data after `Connection: close`\""))))))

(harness-group "the status codes that have no body"
  (lambda ()
    ;; 304 IGNORES ITS OWN FRAMING HEADERS, which is what the first two show:
    ;; a `Content-Length: 10` and a `Transfer-Encoding: chunked` are both read,
    ;; both reach the `headers complete` line, and neither is obeyed. 100 and
    ;; 103 are the two informational codes the corpus carries, and llhttp's
    ;; 102 has no fixture -- the `range` in `message_needs_eof` covers all of
    ;; 1xx, the body decision names four codes exactly, and only these two of
    ;; the four can be judged here.
    (harness-case "response/connection.md#15"
      (lambda ()
        (check-equal "trace"
                     (trace "HTTP/1.1 304 Not Modified\r\nContent-Length: 10\r\n\r\n\r\nHTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nhello")
                     '("off=0 message begin"
                       "off=0 len=4 span[protocol]=\"HTTP\""
                       "off=4 protocol complete"
                       "off=5 len=3 span[version]=\"1.1\""
                       "off=8 version complete"
                       "off=13 len=12 span[status]=\"Not Modified\""
                       "off=27 status complete"
                       "off=27 len=14 span[header_field]=\"Content-Length\""
                       "off=42 header_field complete"
                       "off=43 len=2 span[header_value]=\"10\""
                       "off=47 header_value complete"
                       "off=49 headers complete status=304 v=1/1 flags=20 content_length=10"
                       "off=49 message complete"
                       "off=51 reset"
                       "off=51 message begin"
                       "off=51 len=4 span[protocol]=\"HTTP\""
                       "off=55 protocol complete"
                       "off=56 len=3 span[version]=\"1.1\""
                       "off=59 version complete"
                       "off=64 len=2 span[status]=\"OK\""
                       "off=68 status complete"
                       "off=68 len=14 span[header_field]=\"Content-Length\""
                       "off=83 header_field complete"
                       "off=84 len=1 span[header_value]=\"5\""
                       "off=87 header_value complete"
                       "off=89 headers complete status=200 v=1/1 flags=20 content_length=5"
                       "off=89 len=5 span[body]=\"hello\""
                       "off=94 message complete"))))
    (harness-case "response/connection.md#16"
      (lambda ()
        (check-equal "trace"
                     (trace "HTTP/1.1 304 Not Modified\r\nTransfer-Encoding: chunked\r\n\r\nHTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n0\r\n")
                     '("off=0 message begin"
                       "off=0 len=4 span[protocol]=\"HTTP\""
                       "off=4 protocol complete"
                       "off=5 len=3 span[version]=\"1.1\""
                       "off=8 version complete"
                       "off=13 len=12 span[status]=\"Not Modified\""
                       "off=27 status complete"
                       "off=27 len=17 span[header_field]=\"Transfer-Encoding\""
                       "off=45 header_field complete"
                       "off=46 len=7 span[header_value]=\"chunked\""
                       "off=55 header_value complete"
                       "off=57 headers complete status=304 v=1/1 flags=208 content_length=0"
                       "off=57 message complete"
                       "off=57 reset"
                       "off=57 message begin"
                       "off=57 len=4 span[protocol]=\"HTTP\""
                       "off=61 protocol complete"
                       "off=62 len=3 span[version]=\"1.1\""
                       "off=65 version complete"
                       "off=70 len=2 span[status]=\"OK\""
                       "off=74 status complete"
                       "off=74 len=17 span[header_field]=\"Transfer-Encoding\""
                       "off=92 header_field complete"
                       "off=93 len=7 span[header_value]=\"chunked\""
                       "off=102 header_value complete"
                       "off=104 headers complete status=200 v=1/1 flags=208 content_length=0"
                       "off=107 chunk header len=5"
                       "off=107 len=5 span[body]=\"hello\""
                       "off=114 chunk complete"
                       "off=117 chunk header len=0"))))
    (harness-case "response/connection.md#17"
      (lambda ()
        (check-equal "trace"
                     (trace "HTTP/1.1 100 Continue\r\n\r\n\r\nHTTP/1.1 404 Not Found\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: 14\r\nDate: Fri, 15 Sep 2023 19:47:23 GMT\r\nServer: Python/3.10 aiohttp/4.0.0a2.dev0\r\n\r\n404: Not Found")
                     '("off=0 message begin"
                       "off=0 len=4 span[protocol]=\"HTTP\""
                       "off=4 protocol complete"
                       "off=5 len=3 span[version]=\"1.1\""
                       "off=8 version complete"
                       "off=13 len=8 span[status]=\"Continue\""
                       "off=23 status complete"
                       "off=25 headers complete status=100 v=1/1 flags=0 content_length=0"
                       "off=25 message complete"
                       "off=27 reset"
                       "off=27 message begin"
                       "off=27 len=4 span[protocol]=\"HTTP\""
                       "off=31 protocol complete"
                       "off=32 len=3 span[version]=\"1.1\""
                       "off=35 version complete"
                       "off=40 len=9 span[status]=\"Not Found\""
                       "off=51 status complete"
                       "off=51 len=12 span[header_field]=\"Content-Type\""
                       "off=64 header_field complete"
                       "off=65 len=25 span[header_value]=\"text/plain; charset=utf-8\""
                       "off=92 header_value complete"
                       "off=92 len=14 span[header_field]=\"Content-Length\""
                       "off=107 header_field complete"
                       "off=108 len=2 span[header_value]=\"14\""
                       "off=112 header_value complete"
                       "off=112 len=4 span[header_field]=\"Date\""
                       "off=117 header_field complete"
                       "off=118 len=29 span[header_value]=\"Fri, 15 Sep 2023 19:47:23 GMT\""
                       "off=149 header_value complete"
                       "off=149 len=6 span[header_field]=\"Server\""
                       "off=156 header_field complete"
                       "off=157 len=32 span[header_value]=\"Python/3.10 aiohttp/4.0.0a2.dev0\""
                       "off=191 header_value complete"
                       "off=193 headers complete status=404 v=1/1 flags=20 content_length=14"
                       "off=193 len=14 span[body]=\"404: Not Found\""
                       "off=207 message complete"))))
    (harness-case "response/connection.md#18"
      (lambda ()
        (check-equal "trace"
                     (trace "HTTP/1.1 103 Early Hints\r\nLink: </styles.css>; rel=preload; as=style\r\n\r\nHTTP/1.1 200 OK\r\nDate: Wed, 13 Sep 2023 11:09:41 GMT\r\nConnection: keep-alive\r\nKeep-Alive: timeout=5\r\nContent-Length: 17\r\n\r\nresponse content")
                     '("off=0 message begin"
                       "off=0 len=4 span[protocol]=\"HTTP\""
                       "off=4 protocol complete"
                       "off=5 len=3 span[version]=\"1.1\""
                       "off=8 version complete"
                       "off=13 len=11 span[status]=\"Early Hints\""
                       "off=26 status complete"
                       "off=26 len=4 span[header_field]=\"Link\""
                       "off=31 header_field complete"
                       "off=32 len=36 span[header_value]=\"</styles.css>; rel=preload; as=style\""
                       "off=70 header_value complete"
                       "off=72 headers complete status=103 v=1/1 flags=0 content_length=0"
                       "off=72 message complete"
                       "off=72 reset"
                       "off=72 message begin"
                       "off=72 len=4 span[protocol]=\"HTTP\""
                       "off=76 protocol complete"
                       "off=77 len=3 span[version]=\"1.1\""
                       "off=80 version complete"
                       "off=85 len=2 span[status]=\"OK\""
                       "off=89 status complete"
                       "off=89 len=4 span[header_field]=\"Date\""
                       "off=94 header_field complete"
                       "off=95 len=29 span[header_value]=\"Wed, 13 Sep 2023 11:09:41 GMT\""
                       "off=126 header_value complete"
                       "off=126 len=10 span[header_field]=\"Connection\""
                       "off=137 header_field complete"
                       "off=138 len=10 span[header_value]=\"keep-alive\""
                       "off=150 header_value complete"
                       "off=150 len=10 span[header_field]=\"Keep-Alive\""
                       "off=161 header_field complete"
                       "off=162 len=9 span[header_value]=\"timeout=5\""
                       "off=173 header_value complete"
                       "off=173 len=14 span[header_field]=\"Content-Length\""
                       "off=188 header_field complete"
                       "off=189 len=2 span[header_value]=\"17\""
                       "off=193 header_value complete"
                       "off=195 headers complete status=200 v=1/1 flags=21 content_length=17"
                       "off=195 len=16 span[body]=\"response content\""))))))

(harness-group "an upgrade a response is entitled to, and one it is not"
  (lambda ()
    ;; `Connection: upgrade` and `Upgrade: h2c` are IDENTICAL in these two.
    ;; The status is not, and llhttp's own comment says why: on a response the
    ;; pair is mandatory only for a 101 and otherwise merely announces support.
    ;; So the first pauses after its body and the second reads to end of input
    ;; and never completes at all.
    (harness-case "response/connection.md#10"
      (lambda ()
        (check-equal "trace"
                     (trace "HTTP/1.1 101 Switching Protocols\r\nConnection: upgrade\r\nUpgrade: h2c\r\nContent-Length: 4\r\n\r\nbodyproto")
                     '("off=0 message begin"
                       "off=0 len=4 span[protocol]=\"HTTP\""
                       "off=4 protocol complete"
                       "off=5 len=3 span[version]=\"1.1\""
                       "off=8 version complete"
                       "off=13 len=19 span[status]=\"Switching Protocols\""
                       "off=34 status complete"
                       "off=34 len=10 span[header_field]=\"Connection\""
                       "off=45 header_field complete"
                       "off=46 len=7 span[header_value]=\"upgrade\""
                       "off=55 header_value complete"
                       "off=55 len=7 span[header_field]=\"Upgrade\""
                       "off=63 header_field complete"
                       "off=64 len=3 span[header_value]=\"h2c\""
                       "off=69 header_value complete"
                       "off=69 len=14 span[header_field]=\"Content-Length\""
                       "off=84 header_field complete"
                       "off=85 len=1 span[header_value]=\"4\""
                       "off=88 header_value complete"
                       "off=90 headers complete status=101 v=1/1 flags=34 content_length=4"
                       "off=90 message complete"
                       "off=90 error code=22 reason=\"Pause on CONNECT/Upgrade\""))))
    (harness-case "response/connection.md#12"
      (lambda ()
        (check-equal "trace"
                     (trace "HTTP/1.1 200 OK\r\nConnection: upgrade\r\nUpgrade: h2c\r\n\r\nbody")
                     '("off=0 message begin"
                       "off=0 len=4 span[protocol]=\"HTTP\""
                       "off=4 protocol complete"
                       "off=5 len=3 span[version]=\"1.1\""
                       "off=8 version complete"
                       "off=13 len=2 span[status]=\"OK\""
                       "off=17 status complete"
                       "off=17 len=10 span[header_field]=\"Connection\""
                       "off=28 header_field complete"
                       "off=29 len=7 span[header_value]=\"upgrade\""
                       "off=38 header_value complete"
                       "off=38 len=7 span[header_field]=\"Upgrade\""
                       "off=46 header_field complete"
                       "off=47 len=3 span[header_value]=\"h2c\""
                       "off=52 header_value complete"
                       "off=54 headers complete status=200 v=1/1 flags=14 content_length=0"
                       "off=54 len=4 span[body]=\"body\""))))))

(harness-group "a coding after `chunked`, which a response may have"
  (lambda ()
    ;; RFC 7230 3.3.3 gives the two kinds opposite remedies, and llhttp's
    ;; `forbidAfterChunkedInRequest` is the name of the difference. The same
    ;; three inputs under `'request` are all `Invalid `Transfer-Encoding`
    ;; header value`; here every one of them parses, `flags=200` says the
    ;; CHUNKED bit was cleared, and the body runs to end of connection.
    ;;
    ;; THE SECOND IS THE ONLY FIXTURE THAT REACHES `te-unset-chunked` WITH THE
    ;; BIT SET. Until it did, that clear ran only when the bit was already
    ;; clear and the mutation removing it survived both lanes.
    (harness-case "response/transfer-encoding.md#3"
      (lambda ()
        (check-equal "trace"
                     (trace "HTTP/1.1 200 OK\r\nAccept: */*\r\nTransfer-Encoding: chunked, deflate\r\n\r\nWorld")
                     '("off=0 message begin"
                       "off=0 len=4 span[protocol]=\"HTTP\""
                       "off=4 protocol complete"
                       "off=5 len=3 span[version]=\"1.1\""
                       "off=8 version complete"
                       "off=13 len=2 span[status]=\"OK\""
                       "off=17 status complete"
                       "off=17 len=6 span[header_field]=\"Accept\""
                       "off=24 header_field complete"
                       "off=25 len=3 span[header_value]=\"*/*\""
                       "off=30 header_value complete"
                       "off=30 len=17 span[header_field]=\"Transfer-Encoding\""
                       "off=48 header_field complete"
                       "off=49 len=16 span[header_value]=\"chunked, deflate\""
                       "off=67 header_value complete"
                       "off=69 headers complete status=200 v=1/1 flags=200 content_length=0"
                       "off=69 len=5 span[body]=\"World\""))))
    (harness-case "response/transfer-encoding.md#4"
      (lambda ()
        (check-equal "trace"
                     (trace "HTTP/1.1 200 OK\r\nAccept: */*\r\nTransfer-Encoding: chunked\r\nTransfer-Encoding: identity\r\n\r\nWorld")
                     '("off=0 message begin"
                       "off=0 len=4 span[protocol]=\"HTTP\""
                       "off=4 protocol complete"
                       "off=5 len=3 span[version]=\"1.1\""
                       "off=8 version complete"
                       "off=13 len=2 span[status]=\"OK\""
                       "off=17 status complete"
                       "off=17 len=6 span[header_field]=\"Accept\""
                       "off=24 header_field complete"
                       "off=25 len=3 span[header_value]=\"*/*\""
                       "off=30 header_value complete"
                       "off=30 len=17 span[header_field]=\"Transfer-Encoding\""
                       "off=48 header_field complete"
                       "off=49 len=7 span[header_value]=\"chunked\""
                       "off=58 header_value complete"
                       "off=58 len=17 span[header_field]=\"Transfer-Encoding\""
                       "off=76 header_field complete"
                       "off=77 len=8 span[header_value]=\"identity\""
                       "off=87 header_value complete"
                       "off=89 headers complete status=200 v=1/1 flags=200 content_length=0"
                       "off=89 len=5 span[body]=\"World\""))))
    (harness-case "response/transfer-encoding.md#5"
      (lambda ()
        (check-equal "trace"
                     (trace "HTTP/1.1 200 OK\r\nAccept: */*\r\nTransfer-Encoding: chunkedchunked\r\n\r\n2\r\nOK\r\n0\r\n\r\n")
                     '("off=0 message begin"
                       "off=0 len=4 span[protocol]=\"HTTP\""
                       "off=4 protocol complete"
                       "off=5 len=3 span[version]=\"1.1\""
                       "off=8 version complete"
                       "off=13 len=2 span[status]=\"OK\""
                       "off=17 status complete"
                       "off=17 len=6 span[header_field]=\"Accept\""
                       "off=24 header_field complete"
                       "off=25 len=3 span[header_value]=\"*/*\""
                       "off=30 header_value complete"
                       "off=30 len=17 span[header_field]=\"Transfer-Encoding\""
                       "off=48 header_field complete"
                       "off=49 len=14 span[header_value]=\"chunkedchunked\""
                       "off=65 header_value complete"
                       "off=67 headers complete status=200 v=1/1 flags=200 content_length=0"
                       "off=67 len=1 span[body]=\"2\""
                       "off=68 len=1 span[body]=cr"
                       "off=69 len=1 span[body]=lf"
                       "off=70 len=2 span[body]=\"OK\""
                       "off=72 len=1 span[body]=cr"
                       "off=73 len=1 span[body]=lf"
                       "off=74 len=1 span[body]=\"0\""
                       "off=75 len=1 span[body]=cr"
                       "off=76 len=1 span[body]=lf"
                       "off=77 len=1 span[body]=cr"
                       "off=78 len=1 span[body]=lf"))))))

(harness-finish)
