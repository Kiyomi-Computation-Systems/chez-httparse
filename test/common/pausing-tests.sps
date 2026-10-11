;;; Pausing: the outcome that is neither an ending nor a failure.
;;;
;;; Upstream's harness arms ONE callback per binary. `test/md-test.ts` turns a
;;; fixture's `pause` meta into `-DLLHTTP__TEST_PAUSE_<NAME>=1` and caches one
;;; compiled binary per mode; `test/fixtures/extra.c` guards the matching
;;; callback so it calls `llparse__print` and THEN returns
;;; `LLPARSE__ERROR_PAUSE`. The driver prints `off=N pause`, resumes, and runs
;;; on -- so a paused fixture's trace is a complete parse with extra lines in
;;; it, not a truncated one.
;;;
;;; TWO PAUSES ARE DIFFERENT LINES AND THE DIFFERENCE IS MEASURED, NOT AGREED.
;;; A pause reason is declared on a NODE, so the machine's own pause node
;;; carries one and a callback answering `callback-pause` cannot. The first
;;; renders as llhttp's error line (`code=22`), the second as the bare word.
;;; The cases below pin both, because a driver that confused them would render
;;; a deliberate pause where a parser had merely stopped.
;;;
;;; Expectations are blocks copied out of the vendored fixtures named in each
;;; case, run through the same adapter the conformance driver uses.
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
;; The whole-buffer trace, driven the way the conformance lane drives it.
(define (trace kind mode input)
  (let* ((r (make-trace-recorder))
         (p (make-parser machine (trace-recorder-bindings r (list kind) mode) #f
                         (adapter-parser-inits (list kind))))
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

(define post-3 "POST / HTTP/1.1\r\nContent-Length: 3\r\n\r\nabc")
;; from : String (Listof String) -> (Listof String)
;; The trace from the first line equal to `anchor` onward. A missing anchor is
;; an ERROR and not an empty tail: a case that compared two empty lists would
;; pass whatever the parser did, which is the one failure a copied block is
;; supposed to make impossible.
(define (from anchor ls)
  (cond ((null? ls) (assertion-violation 'from "no such line in the trace" anchor))
        ((string=? (car ls) anchor) ls)
        (else (from anchor (cdr ls)))))

(harness-begin "unit.pausing")

;;; The two chunk-extension rows are the ones a mechanical fold would get
;;; wrong, so the table is checked through the door the driver uses.
(harness-group "the mode arms one callback and no other"
  (lambda ()
    (harness-case "the plain harness arms nothing"
      (lambda ()
        ;; Every fixture without a `pause` meta runs in this mode, so an
        ;; accidental arming here would show up as 190 broken traces -- but
        ;; only after the fact. This says it directly.
        (check-equal "no pause anywhere in an ordinary parse"
                     (filter (lambda (l) (string=? l "off=0 pause"))
                             (trace 'request #f post-3))
                     '())))
    (harness-case "on_message_begin pauses at offset zero"
      (lambda ()
        ;; request/pausing.md, "on_message_begin", copied entire. The pause is
        ;; the SECOND line: the callback records and then pauses.
        (check-equal "the fixture's own trace"
                     (trace 'request '(pause "on_message_begin") post-3)
                     '("off=0 message begin"
                       "off=0 pause"
                       "off=0 len=4 span[method]=\"POST\""
                       "off=4 method complete"
                       "off=5 len=1 span[url]=\"/\""
                       "off=7 url complete"
                       "off=7 len=4 span[protocol]=\"HTTP\""
                       "off=11 protocol complete"
                       "off=12 len=3 span[version]=\"1.1\""
                       "off=15 version complete"
                       "off=17 len=14 span[header_field]=\"Content-Length\""
                       "off=32 header_field complete"
                       "off=33 len=1 span[header_value]=\"3\""
                       "off=36 header_value complete"
                       "off=38 headers complete method=3 v=1/1 flags=20 content_length=3"
                       "off=38 len=3 span[body]=\"abc\""
                       "off=41 message complete"))))
    (harness-case "on_message_complete pauses at the end, and the parse is over"
      (lambda ()
        ;; request/pausing.md, "on_message_complete". The same input and the
        ;; same seventeen lines, with the pause LAST -- which is the case that
        ;; distinguishes "record then pause" from "pause then record".
        (check-equal "the last two lines"
                     (from "off=41 message complete"
                           (trace 'request '(pause "on_message_complete") post-3))
                     '("off=41 message complete"
                       "off=41 pause"))))
    (harness-case "a header callback pauses mid-message and the rest still runs"
      (lambda ()
        ;; request/pausing.md, "on_header_field_complete". A pause inside the
        ;; header section is the one that proves the resume re-enters where an
        ;; unpaused run would have gone: everything after it is unchanged.
        (check-equal "from the field on"
                     (from "off=17 len=14 span[header_field]=\"Content-Length\""
                           (trace 'request '(pause "on_header_field_complete") post-3))
                     '("off=17 len=14 span[header_field]=\"Content-Length\""
                       "off=32 header_field complete"
                       "off=32 pause"
                       "off=33 len=1 span[header_value]=\"3\""
                       "off=36 header_value complete"
                       "off=38 headers complete method=3 v=1/1 flags=20 content_length=3"
                       "off=38 len=3 span[body]=\"abc\""
                       "off=41 message complete"))))
    (harness-case "an armed callback that fires twice pauses twice"
      (lambda ()
        ;; request/pausing.md, "on_chunk_complete". Upstream's macro is not
        ;; a one-shot -- the guarded callback returns the pause EVERY time --
        ;; so a driver that resumed once and then disarmed would lose the
        ;; second line. Two chunks, two pauses.
        (check-equal "from headers complete on"
                     (from "off=46 headers complete method=4 v=1/1 flags=208 content_length=0"
                           (trace 'request '(pause "on_chunk_complete")
                                  (string-append "PUT / HTTP/1.1\r\n"
                                                 "Transfer-Encoding: chunked\r\n\r\n"
                                                 "a\r\n0123456789\r\n0\r\n\r\n")))
                     '("off=46 headers complete method=4 v=1/1 flags=208 content_length=0"
                       "off=49 chunk header len=10"
                       "off=49 len=10 span[body]=\"0123456789\""
                       "off=61 chunk complete"
                       "off=61 pause"
                       "off=64 chunk header len=0"
                       "off=66 chunk complete"
                       "off=66 pause"
                       "off=66 message complete"))))
    (harness-case "the chunk-extension name arms the complete, not the span"
      (lambda ()
        ;; The row a fold would get wrong. `pause: "on_chunk_extension_name"`
        ;; names the MACRO, which upstream puts inside
        ;; `llhttp__on_chunk_extension_name_complete`; the span callback of
        ;; the same name carries none. Arming the span would put the pause
        ;; before `off=52 chunk_extension_name complete` instead of after it
        ;; -- and would not even be callable, since a span callback takes five
        ;; arguments where a pausing one takes two.
        ;;
        ;; request/pausing.md, "on_chunk_extension_name".
        (check-equal "from the extension name on"
                     (from "off=48 len=3 span[chunk_extension_name]=\"foo\""
                           (trace 'request '(pause "on_chunk_extension_name")
                                  (string-append "PUT / HTTP/1.1\r\n"
                                                 "Transfer-Encoding: chunked\r\n\r\n"
                                                 "a;foo=bar\r\n0123456789\r\n0\r\n\r\n")))
                     '("off=48 len=3 span[chunk_extension_name]=\"foo\""
                       "off=52 chunk_extension_name complete"
                       "off=52 pause"
                       "off=52 len=3 span[chunk_extension_value]=\"bar\""
                       "off=56 chunk_extension_value complete"
                       "off=57 chunk header len=10"
                       "off=57 len=10 span[body]=\"0123456789\""
                       "off=69 chunk complete"
                       "off=72 chunk header len=0"
                       "off=74 chunk complete"
                       "off=74 message complete"))))))

;;; The other half: the bare `pause` line belongs to a callback's pause only.
(harness-group "the machine's own pause is still an error line"
  (lambda ()
    (harness-case "an upgrade pause renders with its code and reason"
      (lambda ()
        ;; request/connection.md, "Emitting part of body and pausing", the
        ;; same bytes header-section-tests uses. Driven through `drive-feed!`
        ;; it must NOT become `off=78 pause`: this pause carries a reason, so
        ;; it is the machine's and upstream prints it as an error.
        (check-equal "the last line"
                     (from "off=74 headers complete method=4 v=1/1 flags=34 content_length=4"
                           (trace 'request #f
                                  (string-append "PUT /url HTTP/1.1\r\n"
                                                 "Connection: upgrade\r\n"
                                                 "Content-Length: 4\r\n"
                                                 "Upgrade: ws\r\n\r\nabcdefgh")))
                     '("off=74 headers complete method=4 v=1/1 flags=34 content_length=4"
                       "off=74 len=4 span[body]=\"abcd\""
                       "off=78 message complete"
                       "off=78 error code=22 reason=\"Pause on CONNECT/Upgrade\""))))
    (harness-case "arming a pause does not turn the machine's pause into one"
      (lambda ()
        ;; The same bytes with a callback armed. `on_message_begin` pauses at
        ;; offset 0 and the upgrade still pauses with its reason at the end --
        ;; the two do not collapse into one another.
        (let ((ls (trace 'request '(pause "on_message_begin")
                         (string-append "PUT /url HTTP/1.1\r\n"
                                        "Connection: upgrade\r\n"
                                        "Content-Length: 4\r\n"
                                        "Upgrade: ws\r\n\r\nabcdefgh"))))
          (check-equal "the requested one" (list-ref ls 1) "off=0 pause")
          (check-equal "the declared one"
                       (list-ref ls (- (length ls) 1))
                       "off=78 error code=22 reason=\"Pause on CONNECT/Upgrade\""))))))

(harness-finish)
