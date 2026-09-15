;;; Skip body: the answer that says this message has no body after all.
;;;
;;; Upstream's `on_headers_complete` is the one callback whose RETURN VALUE is
;;; read. `test/fixtures/extra.c` under `-DLLHTTP__TEST_SKIP_BODY=1` prints
;;; `skip body` and returns 1, and `src/llhttp/http.ts` turns that 1 into
;;; `setFlag(FLAGS.SKIPBODY)` before rejoining `headers_done` -- so the
;;; decision is a FLAG the body decision then reads, not a jump. This parser
;;; does the same, because the flag is read in two places and a jump could
;;; only serve one of them.
;;;
;;; `llhttp__after_headers_complete` (src/native/http.c) reads it twice:
;;;
;;;   upgrade && (CONNECT || SKIPBODY || !hasBody)      -> 1, complete + pause
;;;   SKIPBODY || (response && 102|103|204|304)         -> 0, complete
;;;
;;; The second is what the two vendored fixtures record. THE FIRST IS READ OFF
;;; UPSTREAM'S SOURCE AND NOT OFF A TRACE: no fixture arms skip-body on an
;;; upgrade, so its case below asserts the consequence the C states -- the
;;; declared body is not read -- and says so rather than pretending to a
;;; recorded number.
;;;
;;; THE `skip body` LINE IS THE CALLBACK'S, NOT THE DRIVER'S, which is what
;;; makes it different from `pause`: upstream prints it inside the callback,
;;; before returning, so it lands between `headers complete` and
;;; `message complete` at the same offset as both.
(import (rnrs)
        (httparse test harness)
        (httparse test adapter)
        (httparse test drive)
        (httparse test trace-format)
        (httparse grammar)
        (byte-machine verify)
        (byte-machine interpret)
        (byte-machine runtime))

(define machine
  (make-interpreted-machine (verify-machine (make-message-machine))))

;; trace : Symbol HarnessMode String -> (Listof String)
(define (trace kind mode input)
  (let* ((r (make-trace-recorder))
         (p (make-parser machine (trace-recorder-bindings r kind mode) #f))
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
                  (when (eq? (parser-result-status res) 'paused)
                    (trace-recorder-note-paused! r (parser-result-pause res)))
                  #f)))))))
    (append (map utf8->string (trace-format (trace-recorder-events r)))
            (if refused '("(refused)") '()))))

;; contains? : String String -> Boolean
(define (contains? s sub)
  (let ((n (string-length s)) (m (string-length sub)))
    (let loop ((i 0))
      (cond ((> (+ i m) n) #f)
            ((string=? (substring s i (+ i m)) sub) #t)
            (else (loop (+ i 1)))))))

(define two-requests
  (string-append "PUT /url HTTP/1.1\r\nContent-Length: 123\r\n\r\n"
                 "POST /url HTTP/1.1\r\nContent-Length: 456\r\n\r\n\r\n"))

(define two-responses
  (string-append "HTTP/1.1 200 OK\r\nContent-Length: 123\r\n\r\n"
                 "HTTP/1.1 200 OK\r\nContent-Length: 456\r\n\r\n\r\n"))

(harness-begin "unit.skip-body")

(harness-group "the two fixtures, entire"
  (lambda ()
    (harness-case "a request whose declared body is skipped, twice over"
      (lambda ()
        ;; request/content-length.md, "Content-Length reset when no body is
        ;; received". The second message is the point of the fixture: the
        ;; first message's 123 must not survive the reset.
        (check-equal "the fixture's own trace"
                     (trace 'request '(skip-body) two-requests)
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
                       "off=35 len=3 span[header_value]=\"123\""
                       "off=40 header_value complete"
                       "off=42 headers complete method=4 v=1/1 flags=20 content_length=123"
                       "off=42 skip body"
                       "off=42 message complete"
                       "off=42 reset"
                       "off=42 message begin"
                       "off=42 len=4 span[method]=\"POST\""
                       "off=46 method complete"
                       "off=47 len=4 span[url]=\"/url\""
                       "off=52 url complete"
                       "off=52 len=4 span[protocol]=\"HTTP\""
                       "off=56 protocol complete"
                       "off=57 len=3 span[version]=\"1.1\""
                       "off=60 version complete"
                       "off=62 len=14 span[header_field]=\"Content-Length\""
                       "off=77 header_field complete"
                       "off=78 len=3 span[header_value]=\"456\""
                       "off=83 header_value complete"
                       "off=85 headers complete method=3 v=1/1 flags=20 content_length=456"
                       "off=85 skip body"
                       "off=85 message complete"))))
    (harness-case "a response whose declared body is skipped, twice over"
      (lambda ()
        ;; response/content-length.md, the same title. `flags=20` is HEX --
        ;; 0x20 is CONTENT_LENGTH alone, so setting SKIPBODY does not show
        ;; here: upstream sets the flag AFTER the callback that prints it.
        (check-equal "the fixture's own trace"
                     (trace 'response '(skip-body) two-responses)
                     '("off=0 message begin"
                       "off=0 len=4 span[protocol]=\"HTTP\""
                       "off=4 protocol complete"
                       "off=5 len=3 span[version]=\"1.1\""
                       "off=8 version complete"
                       "off=13 len=2 span[status]=\"OK\""
                       "off=17 status complete"
                       "off=17 len=14 span[header_field]=\"Content-Length\""
                       "off=32 header_field complete"
                       "off=33 len=3 span[header_value]=\"123\""
                       "off=38 header_value complete"
                       "off=40 headers complete status=200 v=1/1 flags=20 content_length=123"
                       "off=40 skip body"
                       "off=40 message complete"
                       "off=40 reset"
                       "off=40 message begin"
                       "off=40 len=4 span[protocol]=\"HTTP\""
                       "off=44 protocol complete"
                       "off=45 len=3 span[version]=\"1.1\""
                       "off=48 version complete"
                       "off=53 len=2 span[status]=\"OK\""
                       "off=57 status complete"
                       "off=57 len=14 span[header_field]=\"Content-Length\""
                       "off=72 header_field complete"
                       "off=73 len=3 span[header_value]=\"456\""
                       "off=78 header_value complete"
                       "off=80 headers complete status=200 v=1/1 flags=20 content_length=456"
                       "off=80 skip body"
                       "off=80 message complete"))))))

(harness-group "the mode is what decides, and it decides only when armed"
  (lambda ()
    (harness-case "the same bytes without the mode read the body"
      (lambda ()
        ;; THE CONTRAST THAT MAKES THE FIXTURES MEAN SOMETHING. Without it a
        ;; parser that skipped every body would pass both cases above, and the
        ;; 190 fixtures that read one would be the only thing objecting --
        ;; after the fact, and in another lane.
        ;; Asserted by SHAPE rather than by bytes, because no fixture
        ;; records these bytes WITHOUT the mode -- the pair of claims is what
        ;; the C states and neither is read off this parser: the skip line is
        ;; absent, and the declared body is read.
        (let ((ls (trace 'request #f two-requests)))
          (check-equal "no skip line anywhere"
                       (filter (lambda (l) (contains? l "skip body")) ls)
                       '())
          (check "a body span is delivered"
                 (> (length (filter (lambda (l) (contains? l "span[body]")) ls)) 0)))))
    (harness-case "the flag does not survive into the next message"
      (lambda ()
        ;; `restart` stores zero over the flags, so the second message decides
        ;; for itself. It reaches the same answer here because the mode arms
        ;; the callback EVERY time -- which is upstream's `#ifdef`, not a
        ;; latched flag -- and the two `skip body` lines above are that.
        (check-equal "two skip lines, not one"
                     (length (filter (lambda (l) (contains? l "skip body"))
                                     (trace 'request '(skip-body) two-requests)))
                     2)))))

(harness-group "the upgrade disjunct, read off upstream's C"
  (lambda ()
    (harness-case "an upgrade with skip-body armed does not read its body"
      (lambda ()
        ;; `upgrade && (CONNECT || SKIPBODY || !hasBody)` -- src/native/http.c.
        ;; NO VENDORED FIXTURE ARMS SKIP-BODY ON AN UPGRADE, so what is
        ;; asserted here is the consequence the C states and not a recorded
        ;; trace: the four declared bytes are not read, where the same bytes
        ;; WITHOUT the mode read them (header-section-tests pins that half
        ;; against `request/connection.md`).
        (let ((ls (trace 'request '(skip-body)
                         (string-append "PUT /url HTTP/1.1\r\n"
                                        "Connection: upgrade\r\nContent-Length: 4\r\n"
                                        "Upgrade: ws\r\n\r\nabcdefgh"))))
          (check-equal "no body span"
                       (filter (lambda (l) (string=? l "off=74 len=4 span[body]=\"abcd\"")) ls)
                       '())
          (check-equal "complete, then the upgrade pause"
                       (list-tail ls (- (length ls) 3))
                       '("off=74 skip body"
                         "off=74 message complete"
                         "off=74 error code=22 reason=\"Pause on CONNECT/Upgrade\"")))))
    (harness-case "without the mode the same bytes DO read it"
      (lambda ()
        ;; The half that is recorded, kept beside the half that is not, so the
        ;; pair says which arm the flag changed.
        (check-equal "the body is read"
                     (filter (lambda (l) (string=? l "off=74 len=4 span[body]=\"abcd\""))
                             (trace 'request #f
                                    (string-append "PUT /url HTTP/1.1\r\n"
                                                   "Connection: upgrade\r\nContent-Length: 4\r\n"
                                                   "Upgrade: ws\r\n\r\nabcdefgh")))
                     '("off=74 len=4 span[body]=\"abcd\""))))))

(harness-finish)
