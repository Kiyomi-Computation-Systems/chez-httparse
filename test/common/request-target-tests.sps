;;; The request target's two ends: where it stops, and what follows it.
;;;
;;; These cases render through the SAME adapter the conformance driver uses,
;;; so an expectation here is a block of lines copied out of a fixture rather
;;; than a transliteration of it.
;;;
;;; THIS IS NOT THE URL SUB-PARSER'S LANE. llhttp's `src/llhttp/url.ts` is a
;;; schema, a server with its `@` rules, a path, a query and a fragment, each
;;; with its own span, and `unit.url` judges it against `url.md`. What is here
;;; is the two behaviours the strict REQUEST fixtures need from it, and both
;;; are about the target's boundary rather than its structure:
;;;
;;;   a byte that ends the target but cannot follow it is an error with the
;;;   span STILL OPEN, so no fragment is delivered
;;;
;;;   a target followed by CRLF instead of a version is HTTP/0.9, which has
;;;   no protocol span, no version span, and `v=0/9` on the headers line
;;;
;;; The second is why the first matters: because CR and LF end a target
;;; legally, a byte that ends it illegally carries llhttp's own reason rather
;;; than a catch-all's.
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
         (p (make-parser machine (trace-recorder-bindings r '(request) #f) #f
                         (adapter-parser-inits '(request))))
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

(harness-begin "unit.request-target")

(harness-group "where the target stops"
  (lambda ()
    (harness-case "request/uri.md#7 -- a byte no target may carry, with the span open"
      (lambda ()
        ;; NO `span[url]` LINE AT ALL. llhttp ends the PATH span here and
        ;; leaves the URL span open, so the error delivers no fragment -- and
        ;; the byte is unconsumed, which puts it at the first byte of the
        ;; two-byte character rather than past it.
        (check-equal "trace"
                     (trace "GET /δ¶/δt/pope?q=1#narf HTTP/1.1\r\nHost: github.com\r\n\r\n")
                     '("off=0 message begin"
                       "off=0 len=3 span[method]=\"GET\""
                       "off=3 method complete"
                       "off=5 error code=7 reason=\"Invalid char in url path\""))))
    (harness-case "a space still ends it, and the protocol still follows"
      (lambda ()
        ;; The arm every other request fixture takes, kept beside the other
        ;; two because they are the same dispatch. `request/sample.md#1`
        ;; records these offsets.
        (check-equal "trace"
                     (trace "OPTIONS /url HTTP/1.1\r\n\r\n")
                     '("off=0 message begin"
                       "off=0 len=7 span[method]=\"OPTIONS\""
                       "off=7 method complete"
                       "off=8 len=4 span[url]=\"/url\""
                       "off=13 url complete"
                       "off=13 len=4 span[protocol]=\"HTTP\""
                       "off=17 protocol complete"
                       "off=18 len=3 span[version]=\"1.1\""
                       "off=21 version complete"
                       "off=25 headers complete method=6 v=1/1 flags=0 content_length=0"
                       "off=25 message complete"))))))

(harness-group "the version that is not there"
  (lambda ()
    (harness-case "request/sample.md#10 -- a target followed by CRLF is HTTP/0.9"
      (lambda ()
        ;; `url complete` fires PAST the CRLF, at 7 for a target ending at 4:
        ;; the span closes before the CR and the CRLF is then matched whole.
        ;; No protocol span and no version span are ever opened.
        (check-equal "trace"
                     (trace "GET /\r\n\r\n")
                     '("off=0 message begin"
                       "off=0 len=3 span[method]=\"GET\""
                       "off=3 method complete"
                       "off=4 len=1 span[url]=\"/\""
                       "off=7 url complete"
                       "off=9 headers complete method=1 v=0/9 flags=0 content_length=0"
                       "off=9 message complete"))))
    (harness-case "a bare LF ends it the same way, one byte earlier"
      (lambda ()
        ;; llhttp reaches HTTP/0.9 by two routes -- `.match('\r\n')` and a
        ;; `skipTo` over a lone LF -- and they differ only in how many bytes
        ;; they eat. No fixture in the corpus records the second, so this is
        ;; the CRLF case above with its CR removed and its offsets moved by
        ;; the one byte that is gone.
        (check-equal "trace"
                     (trace "GET /\n\r\n")
                     '("off=0 message begin"
                       "off=0 len=3 span[method]=\"GET\""
                       "off=3 method complete"
                       "off=4 len=1 span[url]=\"/\""
                       "off=6 url complete"
                       "off=8 headers complete method=1 v=0/9 flags=0 content_length=0"
                       "off=8 message complete"))))
    (harness-case "a CR that no LF follows is llhttp's own `Expected CRLF`"
      (lambda ()
        ;; Also unrecorded in the corpus: `skipCRLF.otherwise(...)` in
        ;; `src/llhttp/url.ts`. The sequence keeps the CR it already consumed,
        ;; so the error is at the byte that was not an LF.
        (check-equal "trace"
                     (trace "GET /\rX")
                     '("off=0 message begin"
                       "off=0 len=3 span[method]=\"GET\""
                       "off=3 method complete"
                       "off=4 len=1 span[url]=\"/\""
                       "off=6 error code=7 reason=\"Expected CRLF\""))))))

;;; THE SECOND CONFIGURATION OF ONE DESCRIPTION. `url-subgraph` is built
;;; twice -- once standalone for `url.md`, once spliced in here with the five
;;; part spans stubbed and one whole-target span in their place. A fix to the
;;; shared description is tested in the build that found it and NOT in the
;;; other one unless something says so, which is what this group is.
;;;
;;; These two are the `@` rule, whose edges no fixture separates and the live
;;; differential does. Both traces are the live request binary's, measured
;;; through `tools/oracle/run-oracle.mjs` rather than read off this parser.
(harness-group "the userinfo `@` rule, in the request target"
  (lambda ()
    (harness-case "two `@` separated by a host byte are a target like any other"
      (lambda ()
        ;; THE WHOLE MESSAGE PARSES. With the parts stubbed there is one
        ;; `span[url]` covering all of it, which is the difference between
        ;; this build and the standalone one -- and the reason a green
        ;; `unit.url` does not settle it.
        (check-equal "trace"
                     (trace "GET http://a@b@c/p HTTP/1.1\r\n\r\n")
                     '("off=0 message begin"
                       "off=0 len=3 span[method]=\"GET\""
                       "off=3 method complete"
                       "off=4 len=14 span[url]=\"http://a@b@c/p\""
                       "off=19 url complete"
                       "off=19 len=4 span[protocol]=\"HTTP\""
                       "off=23 protocol complete"
                       "off=24 len=3 span[version]=\"1.1\""
                       "off=27 version complete"
                       "off=31 headers complete method=1 v=1/1 flags=0 content_length=0"
                       "off=31 message complete"))))
    (harness-case "adjacent ones still stop the message, with the target span open"
      (lambda ()
        ;; No `span[url]`: the target span is open when the url machine
        ;; refuses, and an error abandons an open span rather than flushing
        ;; it. Same rule `span[method]` follows.
        (check-equal "trace"
                     (trace "GET http://a@@b/p HTTP/1.1\r\n\r\n")
                     '("off=0 message begin"
                       "off=0 len=3 span[method]=\"GET\""
                       "off=3 method complete"
                       "off=14 error code=7 reason=\"Double @ in url\""))))))

(harness-finish)
