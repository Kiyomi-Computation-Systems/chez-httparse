;;; The response start line, asserted in llhttp's own trace text.
;;;
;;; These cases render through the SAME adapter the conformance driver uses,
;;; so an expectation here is a block of lines copied out of a fixture rather
;;; than a transliteration of it.
;;;
;;; WHAT A RESPONSE HAS INSTEAD OF A REQUEST LINE. Three of the four spans are
;;; the request's own -- protocol, version and, later, the headers -- and the
;;; grammar really does share them, so what these cases pin is the two things
;;; that are NOT shared: where the protocol span opens, and the status.
;;;
;;; THE OFFSETS ARE THE POINT, AND THEY ARE ASYMMETRIC HERE TOO. For
;;; `HTTP/1.1 200 OK`:
;;;
;;;   off=4  protocol complete   the "/", UNCONSUMED
;;;   off=8  version complete    the SP, UNCONSUMED
;;;   off=17 status complete     one byte PAST the LF, which was consumed
;;;
;;; so the status is the reason phrase alone -- the three digits are not in
;;; any span, and arrive on the `headers complete` line as `status=`.
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

;; trace-as : Symbol String -> (Listof String)
;; The KIND is an argument because a parser not told it refuses at the first
;; byte; it becomes the `type` initial `make-parser` writes.
(define (trace-as kind input)
  (let* ((r (make-trace-recorder))
         (p (make-parser machine (trace-recorder-bindings r (list kind) #f) #f
                         (adapter-parser-inits (list kind))))
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

(define (trace input) (trace-as 'response input))
(define (trace-request input) (trace-as 'request input))

(harness-begin "unit.status-line")

(harness-group "the line a response opens with"
  (lambda ()
    (harness-case "response/sample.md#1"
      (lambda ()
        (check-equal "trace"
                     (trace "HTTP/1.1 200 OK\r\nHeader1: Value1\r\nHeader2:	 Value2\r\nContent-Length: 0\r\n\r\n")
                     '("off=0 message begin"
                       "off=0 len=4 span[protocol]=\"HTTP\""
                       "off=4 protocol complete"
                       "off=5 len=3 span[version]=\"1.1\""
                       "off=8 version complete"
                       "off=13 len=2 span[status]=\"OK\""
                       "off=17 status complete"
                       "off=17 len=7 span[header_field]=\"Header1\""
                       "off=25 header_field complete"
                       "off=26 len=6 span[header_value]=\"Value1\""
                       "off=34 header_value complete"
                       "off=34 len=7 span[header_field]=\"Header2\""
                       "off=42 header_field complete"
                       "off=44 len=6 span[header_value]=\"Value2\""
                       "off=52 header_value complete"
                       "off=52 len=14 span[header_field]=\"Content-Length\""
                       "off=67 header_field complete"
                       "off=68 len=1 span[header_value]=\"0\""
                       "off=71 header_value complete"
                       "off=73 headers complete status=200 v=1/1 flags=20 content_length=0"
                       "off=73 message complete"))))
    (harness-case "response/sample.md#3"
      (lambda ()
        (check-equal "trace"
                     (trace "ICE/1.1 200 OK\r\n\r\n")
                     '("off=0 message begin"
                       "off=0 len=3 span[protocol]=\"ICE\""
                       "off=3 protocol complete"
                       "off=4 len=3 span[version]=\"1.1\""
                       "off=7 version complete"
                       "off=12 len=2 span[status]=\"OK\""
                       "off=16 status complete"
                       "off=18 headers complete status=200 v=1/1 flags=0 content_length=0"))))
    (harness-case "response/sample.md#4"
      (lambda ()
        (check-equal "trace"
                     (trace "HTTPER/1.1 200 OK\r\n\r\n")
                     '("off=0 message begin"
                       "off=0 len=4 span[protocol]=\"HTTP\""
                       "off=4 protocol complete"
                       "off=4 error code=8 reason=\"Expected HTTP/, RTSP/ or ICE/\""))))
    (harness-case "response/sample.md#9"
      (lambda ()
        (check-equal "trace"
                     (trace "HTTP/1.1 301\r\n\r\n")
                     '("off=0 message begin"
                       "off=0 len=4 span[protocol]=\"HTTP\""
                       "off=4 protocol complete"
                       "off=5 len=3 span[version]=\"1.1\""
                       "off=8 version complete"
                       "off=14 status complete"
                       "off=16 headers complete status=301 v=1/1 flags=0 content_length=0"))))
    (harness-case "response/sample.md#10"
      (lambda ()
        (check-equal "trace"
                     (trace "HTTP/1.1 200 \r\n\r\n")
                     '("off=0 message begin"
                       "off=0 len=4 span[protocol]=\"HTTP\""
                       "off=4 protocol complete"
                       "off=5 len=3 span[version]=\"1.1\""
                       "off=8 version complete"
                       "off=13 len=0 span[status]=\"\""
                       "off=15 status complete"
                       "off=17 headers complete status=200 v=1/1 flags=0 content_length=0"))))
    (harness-case "response/invalid.md#1"
      (lambda ()
        (check-equal "trace"
                     (trace "HTP/1.1 200 OK\r\n\r\n")
                     '("off=0 message begin"
                       "off=0 len=2 span[protocol]=\"HT\""
                       "off=2 error code=8 reason=\"Expected HTTP/, RTSP/ or ICE/\""))))
    (harness-case "response/invalid.md#5"
      (lambda ()
        (check-equal "trace"
                     (trace "HTTP/1.1	200 OK\r\n\r\n")
                     '("off=0 message begin"
                       "off=0 len=4 span[protocol]=\"HTTP\""
                       "off=4 protocol complete"
                       "off=5 len=3 span[version]=\"1.1\""
                       "off=8 version complete"
                       "off=8 error code=9 reason=\"Expected space after version\""))))
    (harness-case "response/invalid.md#8"
      (lambda ()
        (check-equal "trace"
                     (trace "HTTP/1.1 200 OK\rContent-Length: 0\r\n\r\n")
                     '("off=0 message begin"
                       "off=0 len=4 span[protocol]=\"HTTP\""
                       "off=4 protocol complete"
                       "off=5 len=3 span[version]=\"1.1\""
                       "off=8 version complete"
                       "off=13 len=2 span[status]=\"OK\""
                       "off=16 error code=2 reason=\"Expected LF after CR\""))))
    (harness-case "response/invalid.md#13"
      (lambda ()
        (check-equal "trace"
                     (trace "HTTP/1.1  200 OK\r\n\r\n")
                     '("off=0 message begin"
                       "off=0 len=4 span[protocol]=\"HTTP\""
                       "off=4 protocol complete"
                       "off=5 len=3 span[version]=\"1.1\""
                       "off=8 version complete"
                       "off=9 error code=13 reason=\"Invalid status code\""))))
    (harness-case "response/invalid.md#14"
      (lambda ()
        (check-equal "trace"
                     (trace "HTTP/1.1 200  OK\r\n\r\n")
                     '("off=0 message begin"
                       "off=0 len=4 span[protocol]=\"HTTP\""
                       "off=4 protocol complete"
                       "off=5 len=3 span[version]=\"1.1\""
                       "off=8 version complete"
                       "off=13 len=3 span[status]=\" OK\""
                       "off=18 status complete"
                       "off=20 headers complete status=200 v=1/1 flags=0 content_length=0"))))
    (harness-case "response/invalid.md#15"
      (lambda ()
        (check-equal "trace"
                     (trace "HTTP/1.1 2 OK\r\n\r\n")
                     '("off=0 message begin"
                       "off=0 len=4 span[protocol]=\"HTTP\""
                       "off=4 protocol complete"
                       "off=5 len=3 span[version]=\"1.1\""
                       "off=8 version complete"
                       "off=10 error code=13 reason=\"Invalid status code\""))))
    (harness-case "response/invalid.md#16"
      (lambda ()
        (check-equal "trace"
                     (trace "HTTP/1.1 200 OK\nContent-Length: 0\n\n")
                     '("off=0 message begin"
                       "off=0 len=4 span[protocol]=\"HTTP\""
                       "off=4 protocol complete"
                       "off=5 len=3 span[version]=\"1.1\""
                       "off=8 version complete"
                       "off=13 len=2 span[status]=\"OK\""
                       "off=16 error code=25 reason=\"Missing expected CR after response line\""))))
    (harness-case "response/sample.md#2"
      (lambda ()
        (check-equal "trace"
                     (trace "RTSP/1.1 200 OK\r\n\r\n")
                     '("off=0 message begin"
                       "off=0 len=4 span[protocol]=\"RTSP\""
                       "off=4 protocol complete"
                       "off=5 len=3 span[version]=\"1.1\""
                       "off=8 version complete"
                       "off=13 len=2 span[status]=\"OK\""
                       "off=17 status complete"
                       "off=19 headers complete status=200 v=1/1 flags=0 content_length=0"))))
    (harness-case "response/sample.md#18"
      (lambda ()
        (check-equal "trace"
                     (trace "HTTP/0.9 200 OK\r\n\r\n")
                     '("off=0 message begin"
                       "off=0 len=4 span[protocol]=\"HTTP\""
                       "off=4 protocol complete"
                       "off=5 len=3 span[version]=\"0.9\""
                       "off=8 version complete"
                       "off=13 len=2 span[status]=\"OK\""
                       "off=17 status complete"
                       "off=19 headers complete status=200 v=0/9 flags=0 content_length=0"))))))

(harness-group "one protocol table, two start lines"
  (lambda ()
    ;; THE METHOD CHECK IS THE ONLY FORK. llhttp writes the three constants
    ;; twice -- once for a request, where `checkMethod` follows, and once for
    ;; a response, where nothing does -- and here they are one keyword table
    ;; and one span with a branch on `type` after the event. These two
    ;; fixtures reach the SAME `ICE` arm of that table and part at the branch:
    ;; the request is refused for its method and the response, which has none,
    ;; carries on. A fork that went the other way turns both of them red.
    (harness-case "request/invalid.md#1"
      (lambda ()
        (check-equal "trace"
                     (trace-request "GET /music/sweet/music ICE/1.0\r\nHost: example.com\r\n\r\n")
                     '("off=0 message begin"
                       "off=0 len=3 span[method]=\"GET\""
                       "off=3 method complete"
                       "off=4 len=18 span[url]=\"/music/sweet/music\""
                       "off=23 url complete"
                       "off=23 len=3 span[protocol]=\"ICE\""
                       "off=26 protocol complete"
                       "off=26 error code=8 reason=\"Expected SOURCE method for ICE/x.x request\""))))
    (harness-case "response/sample.md#3"
      (lambda ()
        (check-equal "trace"
                     (trace "ICE/1.1 200 OK\r\n\r\n")
                     '("off=0 message begin"
                       "off=0 len=3 span[protocol]=\"ICE\""
                       "off=3 protocol complete"
                       "off=4 len=3 span[version]=\"1.1\""
                       "off=7 version complete"
                       "off=12 len=2 span[status]=\"OK\""
                       "off=16 status complete"
                       "off=18 headers complete status=200 v=1/1 flags=0 content_length=0"))))))

(harness-finish)
