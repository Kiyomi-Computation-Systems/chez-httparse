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
  (let* ((r (make-trace-recorder))
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
                  #f)))))))
    (append (map utf8->string (trace-format (trace-recorder-events r)))
            (if refused '("(refused)") '()))))

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
