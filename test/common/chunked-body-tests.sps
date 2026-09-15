;;; Chunked bodies, asserted in llhttp's own trace text.
;;;
;;; These cases render through the SAME adapter the conformance driver uses,
;;; so an expectation here is a block of lines copied out of a fixture rather
;;; than a transliteration of it.
;;;
;;; ONE CASE PER DISTINCT CHUNK SHAPE, not one per fixture. The ratchet already
;;; runs all seventeen of `request/transfer-encoding.md`'s chunked fixtures at
;;; every chunk size; what this lane adds is a literal expectation that survives
;;; a corpus refresh -- so the cases here are the shapes that differ from each
;;; other (a lowercase size against an uppercase one, a trailer section, each
;;; way the reader can fail), and the fixtures that only re-run a shape with a
;;; different header block are left to the ratchet.
;;;
;;; THE CHUNK SIZE IS `content_length`. llhttp accumulates it into the same
;;; field a Content-Length body uses and its `on_chunk_header` prints that
;;; field, so `chunk header len=` is read off the parser exactly as the four
;;; numbers on `headers complete` are (decision 0014) -- never recomputed from
;;; the digits this lane fed in.
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
         (p (make-parser machine (trace-recorder-bindings r 'request #f) #f))
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

;; The prelude `request/transfer-encoding.md#3`, `#4`, `#24`, `#25` and `#31`
;; all share, and the fourteen lines it produces. Stripped below so a case is
;; its CHUNK trace and nothing else -- and asserted while stripping, so a
;; regression in the header section fails here rather than shifting a chunk
;; offset and looking like a chunk bug.
(define chunked-prelude "PUT /url HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n")

(define chunked-prelude-lines
  '("off=0 message begin"
    "off=0 len=3 span[method]=\"PUT\""
    "off=3 method complete"
    "off=4 len=4 span[url]=\"/url\""
    "off=9 url complete"
    "off=9 len=4 span[protocol]=\"HTTP\""
    "off=13 protocol complete"
    "off=14 len=3 span[version]=\"1.1\""
    "off=17 version complete"
    "off=19 len=17 span[header_field]=\"Transfer-Encoding\""
    "off=37 header_field complete"
    "off=38 len=7 span[header_value]=\"chunked\""
    "off=47 header_value complete"
    "off=49 headers complete method=4 v=1/1 flags=208 content_length=0"))

(define (after-prelude body)
  (let loop ((lines (trace (string-append chunked-prelude body)))
             (expected chunked-prelude-lines))
    (if (null? expected)
        lines
        (begin
          (unless (and (pair? lines) (string=? (car lines) (car expected)))
            (assertion-violation 'after-prelude "the prelude moved"
                                 (car expected) (and (pair? lines) (car lines))))
          (loop (cdr lines) (cdr expected))))))

;; The prelude `request/transfer-encoding.md#8`, `#11` and `#12` share, and
;; the fourteen lines it produces -- the same trick the PUT prelude plays
;; above, for the three fixtures whose extensions are the point.
(define ext-prelude "POST /chunked_w_unicorns_after_length HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n")

(define ext-prelude-lines
  '("off=0 message begin"
    "off=0 len=4 span[method]=\"POST\""
    "off=4 method complete"
    "off=5 len=32 span[url]=\"/chunked_w_unicorns_after_length\""
    "off=38 url complete"
    "off=38 len=4 span[protocol]=\"HTTP\""
    "off=42 protocol complete"
    "off=43 len=3 span[version]=\"1.1\""
    "off=46 version complete"
    "off=48 len=17 span[header_field]=\"Transfer-Encoding\""
    "off=66 header_field complete"
    "off=67 len=7 span[header_value]=\"chunked\""
    "off=76 header_value complete"
    "off=78 headers complete method=3 v=1/1 flags=208 content_length=0"))

(define (after-ext-prelude body)
  (let loop ((lines (trace (string-append ext-prelude body)))
             (expected ext-prelude-lines))
    (if (null? expected)
        lines
        (begin
          (unless (and (pair? lines) (string=? (car lines) (car expected)))
            (assertion-violation 'after-ext-prelude "the prelude moved"
                                 (car expected) (and (pair? lines) (car lines))))
          (loop (cdr lines) (cdr expected))))))

(harness-begin "unit.chunked-body")

(harness-group "one chunk, then the zero chunk"
  (lambda ()
    (harness-case "request/transfer-encoding.md#3 -- a lowercase hex size"
      (lambda ()
        (check-equal "trace"
                     (after-prelude "a\r\n0123456789\r\n0\r\n\r\n")
                     '("off=52 chunk header len=10"
                       "off=52 len=10 span[body]=\"0123456789\""
                       "off=64 chunk complete"
                       "off=67 chunk header len=0"
                       "off=69 chunk complete"
                       "off=69 message complete"))))
    (harness-case "request/transfer-encoding.md#4 -- an uppercase hex size"
      (lambda ()
        ;; The same ten bytes under `A`. llhttp's HEX_MAP carries both cases
        ;; and the two fixtures differ in nothing else, so the whole of the
        ;; difference between them is this one byte.
        (check-equal "trace"
                     (after-prelude "A\r\n0123456789\r\n0\r\n\r\n")
                     '("off=52 chunk header len=10"
                       "off=52 len=10 span[body]=\"0123456789\""
                       "off=64 chunk complete"
                       "off=67 chunk header len=0"
                       "off=69 chunk complete"
                       "off=69 message complete"))))
    (harness-case "the size is hex, not decimal"
      (lambda ()
        ;; No fixture pairs `10` against `a`, and a base-10 accumulator would
        ;; pass every case above -- `a` is not a decimal digit, so it would
        ;; fail loudly rather than measure sixteen. This is the case that
        ;; separates the two bases: `10` is SIXTEEN bytes.
        (check-equal "trace"
                     (after-prelude "10\r\n0123456789abcdef\r\n0\r\n\r\n")
                     '("off=53 chunk header len=16"
                       "off=53 len=16 span[body]=\"0123456789abcdef\""
                       "off=71 chunk complete"
                       "off=74 chunk header len=0"
                       "off=76 chunk complete"
                       "off=76 message complete"))))))

(harness-group "several chunks, and the trailer section"
  (lambda ()
    (harness-case "request/transfer-encoding.md#6 -- two chunks, and `000` ends it"
      (lambda ()
        ;; The zero chunk is a VALUE, not a literal: `000` accumulates to zero
        ;; and ends the body exactly as `0` does.
        (check-equal "trace"
                     (trace "POST /two_chunks_mult_zero_end HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n6\r\n world\r\n000\r\n\r\n")
                     '("off=0 message begin"
                       "off=0 len=4 span[method]=\"POST\""
                       "off=4 method complete"
                       "off=5 len=25 span[url]=\"/two_chunks_mult_zero_end\""
                       "off=31 url complete"
                       "off=31 len=4 span[protocol]=\"HTTP\""
                       "off=35 protocol complete"
                       "off=36 len=3 span[version]=\"1.1\""
                       "off=39 version complete"
                       "off=41 len=17 span[header_field]=\"Transfer-Encoding\""
                       "off=59 header_field complete"
                       "off=60 len=7 span[header_value]=\"chunked\""
                       "off=69 header_value complete"
                       "off=71 headers complete method=3 v=1/1 flags=208 content_length=0"
                       "off=74 chunk header len=5"
                       "off=74 len=5 span[body]=\"hello\""
                       "off=81 chunk complete"
                       "off=84 chunk header len=6"
                       "off=84 len=6 span[body]=\" world\""
                       "off=92 chunk complete"
                       "off=97 chunk header len=0"
                       "off=99 chunk complete"
                       "off=99 message complete"))))
    (harness-case "request/transfer-encoding.md#7 -- trailers are the header section again"
      (lambda ()
        ;; THE ZERO CHUNK RE-ENTERS `header_field_start`. What follows it is
        ;; parsed by the same states the header section uses and delivers the
        ;; same `header_field` / `header_value` spans -- and the empty line
        ;; that ends it fires `chunk complete` instead of `headers complete`,
        ;; which is the whole of what llhttp's TRAILING flag decides.
        (check-equal "trace"
                     (trace "POST /chunked_w_trailing_headers HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n6\r\n world\r\n0\r\nVary: *\r\nContent-Type: text/plain\r\n\r\n")
                     '("off=0 message begin"
                       "off=0 len=4 span[method]=\"POST\""
                       "off=4 method complete"
                       "off=5 len=27 span[url]=\"/chunked_w_trailing_headers\""
                       "off=33 url complete"
                       "off=33 len=4 span[protocol]=\"HTTP\""
                       "off=37 protocol complete"
                       "off=38 len=3 span[version]=\"1.1\""
                       "off=41 version complete"
                       "off=43 len=17 span[header_field]=\"Transfer-Encoding\""
                       "off=61 header_field complete"
                       "off=62 len=7 span[header_value]=\"chunked\""
                       "off=71 header_value complete"
                       "off=73 headers complete method=3 v=1/1 flags=208 content_length=0"
                       "off=76 chunk header len=5"
                       "off=76 len=5 span[body]=\"hello\""
                       "off=83 chunk complete"
                       "off=86 chunk header len=6"
                       "off=86 len=6 span[body]=\" world\""
                       "off=94 chunk complete"
                       "off=97 chunk header len=0"
                       "off=97 len=4 span[header_field]=\"Vary\""
                       "off=102 header_field complete"
                       "off=103 len=1 span[header_value]=\"*\""
                       "off=106 header_value complete"
                       "off=106 len=12 span[header_field]=\"Content-Type\""
                       "off=119 header_field complete"
                       "off=120 len=10 span[header_value]=\"text/plain\""
                       "off=132 header_value complete"
                       "off=134 chunk complete"
                       "off=134 message complete"))))))

(harness-group "the four ways a chunk reader fails"
  (lambda ()
    (harness-case "request/transfer-encoding.md#24 -- a size that is not hex at all"
      (lambda ()
        ;; The CR of the message's own terminator, read where a size was due.
        ;; llhttp's `.otherwise` does not consume, so the error is AT it.
        (check-equal "trace"
                     (after-prelude "3\r\nfoo\r\n\r\n")
                     '("off=52 chunk header len=3"
                       "off=52 len=3 span[body]=\"foo\""
                       "off=57 chunk complete"
                       "off=57 error code=12 reason=\"Invalid character in chunk size\""))))
    (harness-case "request/transfer-encoding.md#31 -- a space after the size"
      (lambda ()
        ;; The space is MATCHED into a lenient test strict mode refuses, and a
        ;; match consumes -- so the error is one PAST the space at 50.
        (check-equal "trace"
                     (after-prelude "a \r\n0123456789\r\n0\r\n\r\n")
                     '("off=51 error code=12 reason=\"Invalid character in chunk size\""))))
    (harness-case "request/transfer-encoding.md#27 -- a CR that no LF follows"
      (lambda ()
        (check-equal "trace"
                     (trace "GET / HTTP/1.1\r\nHost: a\r\nConnection: close \r\nTransfer-Encoding: chunked \r\n\r\n5\r\r;ABCD\r\n34\r\nE\r\n0\r\n\r\nGET / HTTP/1.1 \r\nHost: a\r\nContent-Length: 5\r\n\r\n0\r\n")
                     '("off=0 message begin"
                       "off=0 len=3 span[method]=\"GET\""
                       "off=3 method complete"
                       "off=4 len=1 span[url]=\"/\""
                       "off=6 url complete"
                       "off=6 len=4 span[protocol]=\"HTTP\""
                       "off=10 protocol complete"
                       "off=11 len=3 span[version]=\"1.1\""
                       "off=14 version complete"
                       "off=16 len=4 span[header_field]=\"Host\""
                       "off=21 header_field complete"
                       "off=22 len=1 span[header_value]=\"a\""
                       "off=25 header_value complete"
                       "off=25 len=10 span[header_field]=\"Connection\""
                       "off=36 header_field complete"
                       "off=37 len=6 span[header_value]=\"close \""
                       "off=45 header_value complete"
                       "off=45 len=17 span[header_field]=\"Transfer-Encoding\""
                       "off=63 header_field complete"
                       "off=64 len=8 span[header_value]=\"chunked \""
                       "off=74 header_value complete"
                       "off=76 headers complete method=1 v=1/1 flags=20a content_length=0"
                       "off=78 error code=2 reason=\"Expected LF after chunk size\""))))
    (harness-case "request/transfer-encoding.md#29 -- no CRLF after the chunk data"
      (lambda ()
        ;; The span still delivers its five bytes: the data is counted, so it
        ;; is complete before anything looks at what follows it.
        (check-equal "trace"
                     (trace "GET / HTTP/1.1\r\nHost: a\r\nConnection: close \r\nTransfer-Encoding: chunked \r\n\r\n5\r\nABCDE0\r\n")
                     '("off=0 message begin"
                       "off=0 len=3 span[method]=\"GET\""
                       "off=3 method complete"
                       "off=4 len=1 span[url]=\"/\""
                       "off=6 url complete"
                       "off=6 len=4 span[protocol]=\"HTTP\""
                       "off=10 protocol complete"
                       "off=11 len=3 span[version]=\"1.1\""
                       "off=14 version complete"
                       "off=16 len=4 span[header_field]=\"Host\""
                       "off=21 header_field complete"
                       "off=22 len=1 span[header_value]=\"a\""
                       "off=25 header_value complete"
                       "off=25 len=10 span[header_field]=\"Connection\""
                       "off=36 header_field complete"
                       "off=37 len=6 span[header_value]=\"close \""
                       "off=45 header_value complete"
                       "off=45 len=17 span[header_field]=\"Transfer-Encoding\""
                       "off=63 header_field complete"
                       "off=64 len=8 span[header_value]=\"chunked \""
                       "off=74 header_value complete"
                       "off=76 headers complete method=1 v=1/1 flags=20a content_length=0"
                       "off=79 chunk header len=5"
                       "off=79 len=5 span[body]=\"ABCDE\""
                       "off=84 error code=2 reason=\"Expected LF after chunk data\""))))))

(harness-group "chunk extensions"
  (lambda ()
    (harness-case "request/transfer-encoding.md#8 -- names, values, and names alone"
      (lambda ()
        ;; EVERY COMPLETE FIRES PAST ITS DELIMITER. The name span ends AT the
        ;; `=` or `;` and the event that follows fires one byte later, because
        ;; llhttp peeks the delimiter to close the span and then skips it.
        (check-equal "trace"
                     (after-ext-prelude "5;ilovew3;somuchlove=aretheseparametersfor;another=withvalue\r\nhello\r\n6;blahblah;blah\r\n world\r\n0\r\n")
                     '("off=80 len=7 span[chunk_extension_name]=\"ilovew3\""
                       "off=88 chunk_extension_name complete"
                       "off=88 len=10 span[chunk_extension_name]=\"somuchlove\""
                       "off=99 chunk_extension_name complete"
                       "off=99 len=21 span[chunk_extension_value]=\"aretheseparametersfor\""
                       "off=121 chunk_extension_value complete"
                       "off=121 len=7 span[chunk_extension_name]=\"another\""
                       "off=129 chunk_extension_name complete"
                       "off=129 len=9 span[chunk_extension_value]=\"withvalue\""
                       "off=139 chunk_extension_value complete"
                       "off=140 chunk header len=5"
                       "off=140 len=5 span[body]=\"hello\""
                       "off=147 chunk complete"
                       "off=149 len=8 span[chunk_extension_name]=\"blahblah\""
                       "off=158 chunk_extension_name complete"
                       "off=158 len=4 span[chunk_extension_name]=\"blah\""
                       "off=163 chunk_extension_name complete"
                       "off=164 chunk header len=6"
                       "off=164 len=6 span[body]=\" world\""
                       "off=172 chunk complete"
                       "off=175 chunk header len=0"))))
    (harness-case "request/transfer-encoding.md#11 -- quoted values, quotes included"
      (lambda ()
        ;; THE QUOTES ARE IN THE SPAN. The value span opens on the byte after
        ;; the `=` -- which is the opening quote -- and closes after the
        ;; closing one, so a quoted value is two bytes longer than its text
        ;; and an escaped `\\"` inside it is two bytes, not one.
        (check-equal "trace"
                     (after-ext-prelude "5;ilovew3=\"I \\\"love\\\"; \\\\extensions\\\\\";somuchlove=\"aretheseparametersfor\";blah;foo=bar\r\nhello\r\n6;blahblah;blah\r\n world\r\n0\r\n")
                     '("off=80 len=7 span[chunk_extension_name]=\"ilovew3\""
                       "off=88 chunk_extension_name complete"
                       "off=88 len=28 span[chunk_extension_value]=\"\"I \\\"love\\\"; \\\\extensions\\\\\"\""
                       "off=116 chunk_extension_value complete"
                       "off=117 len=10 span[chunk_extension_name]=\"somuchlove\""
                       "off=128 chunk_extension_name complete"
                       "off=128 len=23 span[chunk_extension_value]=\"\"aretheseparametersfor\"\""
                       "off=151 chunk_extension_value complete"
                       "off=152 len=4 span[chunk_extension_name]=\"blah\""
                       "off=157 chunk_extension_name complete"
                       "off=157 len=3 span[chunk_extension_name]=\"foo\""
                       "off=161 chunk_extension_name complete"
                       "off=161 len=3 span[chunk_extension_value]=\"bar\""
                       "off=165 chunk_extension_value complete"
                       "off=166 chunk header len=5"
                       "off=166 len=5 span[body]=\"hello\""
                       "off=173 chunk complete"
                       "off=175 len=8 span[chunk_extension_name]=\"blahblah\""
                       "off=184 chunk_extension_name complete"
                       "off=184 len=4 span[chunk_extension_name]=\"blah\""
                       "off=189 chunk_extension_name complete"
                       "off=190 chunk header len=6"
                       "off=190 len=6 span[body]=\" world\""
                       "off=198 chunk complete"
                       "off=201 chunk header len=0"))))
    (harness-case "request/transfer-encoding.md#12 -- a quoted value no quote closes"
      (lambda ()
        ;; The span still delivers what it read: the value closes at the CR
        ;; and the CR is then skipped, so the error is one past it.
        (check-equal "trace"
                     (after-ext-prelude "5;ilovew3=\"abc\";somuchlove=\"def; ghi\r\nhello\r\n6;blahblah;blah\r\n world\r\n0\r\n")
                     '("off=80 len=7 span[chunk_extension_name]=\"ilovew3\""
                       "off=88 chunk_extension_name complete"
                       "off=88 len=5 span[chunk_extension_value]=\"\"abc\"\""
                       "off=93 chunk_extension_value complete"
                       "off=94 len=10 span[chunk_extension_name]=\"somuchlove\""
                       "off=105 chunk_extension_name complete"
                       "off=105 len=9 span[chunk_extension_value]=\"\"def; ghi\""
                       "off=115 error code=2 reason=\"Invalid character in chunk extensions quoted value\""))))
    (harness-case "request/transfer-encoding.md#10 -- a semicolon a CR follows"
      (lambda ()
        ;; An extension must START with something. CR and SP are refused where
        ;; a name is due, and both are MATCHED -- so the error is one past the
        ;; CR at 97, not at it.
        (check-equal "trace"
                     (trace "POST /chunked_w_unicorns_after_length HTTP/1.1\r\nHost: localhost\r\nTransfer-encoding: chunked\r\n\r\n2;\r\naa\r\n0\r\n\r\n")
                     '("off=0 message begin"
                       "off=0 len=4 span[method]=\"POST\""
                       "off=4 method complete"
                       "off=5 len=32 span[url]=\"/chunked_w_unicorns_after_length\""
                       "off=38 url complete"
                       "off=38 len=4 span[protocol]=\"HTTP\""
                       "off=42 protocol complete"
                       "off=43 len=3 span[version]=\"1.1\""
                       "off=46 version complete"
                       "off=48 len=4 span[header_field]=\"Host\""
                       "off=53 header_field complete"
                       "off=54 len=9 span[header_value]=\"localhost\""
                       "off=65 header_value complete"
                       "off=65 len=17 span[header_field]=\"Transfer-encoding\""
                       "off=83 header_field complete"
                       "off=84 len=7 span[header_value]=\"chunked\""
                       "off=93 header_value complete"
                       "off=95 headers complete method=3 v=1/1 flags=208 content_length=0"
                       "off=98 error code=2 reason=\"Invalid character in chunk extensions\""))))))

(harness-finish)
