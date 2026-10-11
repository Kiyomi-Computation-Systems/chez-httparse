;;; The message loop, asserted in llhttp's own trace text.
;;;
;;; These cases render through the SAME adapter the conformance driver uses,
;;; so an expectation here is a block of lines copied out of a fixture rather
;;; than a transliteration of it.
;;;
;;; WHAT A MESSAGE LEAVES BEHIND IS THE SUBJECT. Every other lane in this tree
;;; judges one message; these judge what the parser carries into the NEXT one
;;; -- whether it restarts at all, what it forgets when it does, and what it
;;; refuses when it does not. The trace shows that as three zero-width events
;;; on one byte, so the offsets matter more here than anywhere else.
;;;
;;; ONE ARM OF `should_keep_alive` HAS NO STRICT FIXTURE: HTTP/1.0 WITH
;;; `Connection: keep-alive` restarting. `request/connection.md#4` records it
;;; under `request-lenient-keep-alive`, so the conformance lane judges it in
;;; that mode and not here. What the cases below pin is the other three --
;;; 1.1 restarts, 1.1 with `close` does not, 1.0 without keep-alive does not.
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

(harness-begin "unit.message-loop")

(harness-group "what a message leaves behind"
  (lambda ()
    (harness-case "request/connection.md#2 -- keep-alive, and `reset` between the two"
      (lambda ()
        ;; `reset` fires between the messages and BEFORE the second `message begin`,
        ;; at the same offset as both -- three zero-width events on one byte.
        (check-equal "trace"
                     (trace "PUT /url HTTP/1.1\r\nConnection: keep-alive\r\n\r\nPUT /url HTTP/1.1\r\nConnection: keep-alive\r\n\r\n")
                     '("off=0 message begin"
                       "off=0 len=3 span[method]=\"PUT\""
                       "off=3 method complete"
                       "off=4 len=4 span[url]=\"/url\""
                       "off=9 url complete"
                       "off=9 len=4 span[protocol]=\"HTTP\""
                       "off=13 protocol complete"
                       "off=14 len=3 span[version]=\"1.1\""
                       "off=17 version complete"
                       "off=19 len=10 span[header_field]=\"Connection\""
                       "off=30 header_field complete"
                       "off=31 len=10 span[header_value]=\"keep-alive\""
                       "off=43 header_value complete"
                       "off=45 headers complete method=4 v=1/1 flags=1 content_length=0"
                       "off=45 message complete"
                       "off=45 reset"
                       "off=45 message begin"
                       "off=45 len=3 span[method]=\"PUT\""
                       "off=48 method complete"
                       "off=49 len=4 span[url]=\"/url\""
                       "off=54 url complete"
                       "off=54 len=4 span[protocol]=\"HTTP\""
                       "off=58 protocol complete"
                       "off=59 len=3 span[version]=\"1.1\""
                       "off=62 version complete"
                       "off=64 len=10 span[header_field]=\"Connection\""
                       "off=75 header_field complete"
                       "off=76 len=10 span[header_value]=\"keep-alive\""
                       "off=88 header_value complete"
                       "off=90 headers complete method=4 v=1/1 flags=1 content_length=0"
                       "off=90 message complete"))))
    (harness-case "request/pipelining.md#1 -- three messages, and the flags reset"
      (lambda ()
        ;; THE FLAGS RESET IS MEASURED HERE AND NOWHERE ELSE. Each message carries
        ;; its own `Content-Length`, and the duplicate test is `flags & CONTENT_LENGTH`
        ;; -- so a loop that did not clear the flags would report `Duplicate
        ;; Content-Length` on the second message instead of parsing it.
        ;; 
        ;; The CRLF between messages is skipped by `start` BEFORE the reset fires:
        ;; the body ends at 44 and `reset` is at 46.
        (check-equal "trace"
                     (trace "POST /aaa HTTP/1.1\r\nContent-Length: 3\r\n\r\nAAA\r\nPUT /bbb HTTP/1.1\r\nContent-Length: 4\r\n\r\nBBBB\r\nPATCH /ccc HTTP/1.1\r\nContent-Length: 5\r\n\r\nCCCC")
                     '("off=0 message begin"
                       "off=0 len=4 span[method]=\"POST\""
                       "off=4 method complete"
                       "off=5 len=4 span[url]=\"/aaa\""
                       "off=10 url complete"
                       "off=10 len=4 span[protocol]=\"HTTP\""
                       "off=14 protocol complete"
                       "off=15 len=3 span[version]=\"1.1\""
                       "off=18 version complete"
                       "off=20 len=14 span[header_field]=\"Content-Length\""
                       "off=35 header_field complete"
                       "off=36 len=1 span[header_value]=\"3\""
                       "off=39 header_value complete"
                       "off=41 headers complete method=3 v=1/1 flags=20 content_length=3"
                       "off=41 len=3 span[body]=\"AAA\""
                       "off=44 message complete"
                       "off=46 reset"
                       "off=46 message begin"
                       "off=46 len=3 span[method]=\"PUT\""
                       "off=49 method complete"
                       "off=50 len=4 span[url]=\"/bbb\""
                       "off=55 url complete"
                       "off=55 len=4 span[protocol]=\"HTTP\""
                       "off=59 protocol complete"
                       "off=60 len=3 span[version]=\"1.1\""
                       "off=63 version complete"
                       "off=65 len=14 span[header_field]=\"Content-Length\""
                       "off=80 header_field complete"
                       "off=81 len=1 span[header_value]=\"4\""
                       "off=84 header_value complete"
                       "off=86 headers complete method=4 v=1/1 flags=20 content_length=4"
                       "off=86 len=4 span[body]=\"BBBB\""
                       "off=90 message complete"
                       "off=92 reset"
                       "off=92 message begin"
                       "off=92 len=5 span[method]=\"PATCH\""
                       "off=97 method complete"
                       "off=98 len=4 span[url]=\"/ccc\""
                       "off=103 url complete"
                       "off=103 len=4 span[protocol]=\"HTTP\""
                       "off=107 protocol complete"
                       "off=108 len=3 span[version]=\"1.1\""
                       "off=111 version complete"
                       "off=113 len=14 span[header_field]=\"Content-Length\""
                       "off=128 header_field complete"
                       "off=129 len=1 span[header_value]=\"5\""
                       "off=132 header_value complete"
                       "off=134 headers complete method=28 v=1/1 flags=20 content_length=5"
                       "off=134 len=4 span[body]=\"CCCC\""))))
    (harness-case "request/connection.md#3 -- HTTP/1.0 without keep-alive does not restart"
      (lambda ()
        ;; `should_keep_alive` reads the version before the flags: 1.0 keeps alive
        ;; only when `Connection: keep-alive` says so, and this one does not say it.
        ;; The byte that follows is CONSUMED before the error, so off=22 for a `P`
        ;; at 21.
        (check-equal "trace"
                     (trace "PUT /url HTTP/1.0\r\n\r\nPUT /url HTTP/1.1\r\n\r\n")
                     '("off=0 message begin"
                       "off=0 len=3 span[method]=\"PUT\""
                       "off=3 method complete"
                       "off=4 len=4 span[url]=\"/url\""
                       "off=9 url complete"
                       "off=9 len=4 span[protocol]=\"HTTP\""
                       "off=13 protocol complete"
                       "off=14 len=3 span[version]=\"1.0\""
                       "off=17 version complete"
                       "off=21 headers complete method=4 v=1/0 flags=0 content_length=0"
                       "off=21 message complete"
                       "off=22 error code=5 reason=\"Data after `Connection: close`\""))))
    (harness-case "request/connection.md#9 -- `Connection: close`, and the CRLFs it still eats"
      (lambda ()
        ;; A closed connection matches CR and LF back to itself, so the blank line
        ;; after the body is consumed and only the `G` at 137 is data. flags=22 is
        ;; CONTENT_LENGTH and CONNECTION_CLOSE together.
        (check-equal "trace"
                     (trace "POST / HTTP/1.1\r\nHost: www.example.com\r\nContent-Type: application/x-www-form-urlencoded\r\nContent-Length: 4\r\nConnection: close\r\n\r\nq=42\r\n\r\nGET / HTTP/1.1")
                     '("off=0 message begin"
                       "off=0 len=4 span[method]=\"POST\""
                       "off=4 method complete"
                       "off=5 len=1 span[url]=\"/\""
                       "off=7 url complete"
                       "off=7 len=4 span[protocol]=\"HTTP\""
                       "off=11 protocol complete"
                       "off=12 len=3 span[version]=\"1.1\""
                       "off=15 version complete"
                       "off=17 len=4 span[header_field]=\"Host\""
                       "off=22 header_field complete"
                       "off=23 len=15 span[header_value]=\"www.example.com\""
                       "off=40 header_value complete"
                       "off=40 len=12 span[header_field]=\"Content-Type\""
                       "off=53 header_field complete"
                       "off=54 len=33 span[header_value]=\"application/x-www-form-urlencoded\""
                       "off=89 header_value complete"
                       "off=89 len=14 span[header_field]=\"Content-Length\""
                       "off=104 header_field complete"
                       "off=105 len=1 span[header_value]=\"4\""
                       "off=108 header_value complete"
                       "off=108 len=10 span[header_field]=\"Connection\""
                       "off=119 header_field complete"
                       "off=120 len=5 span[header_value]=\"close\""
                       "off=127 header_value complete"
                       "off=129 headers complete method=3 v=1/1 flags=22 content_length=4"
                       "off=129 len=4 span[body]=\"q=42\""
                       "off=133 message complete"
                       "off=138 error code=5 reason=\"Data after `Connection: close`\""))))))

(harness-finish)
