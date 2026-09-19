;;; (httparse decisions): llhttp's after-a-message connection decisions --
;;; `should_keep_alive` and `message_needs_eof` -- and the FLAGS bits they read,
;;; as pure procedures an embedder runs at RUN time.
;;;
;;; THIS LIBRARY IS PURE AND DEPENDS ON NOTHING. Not on byte-machine, not on the
;;; generated parser, not on the harness -- it is llhttp's two rules and the
;;; flag bits they test. The grammar SETS these bits while parsing (its set-mask
;;; nodes) and imports the constants from here so there is ONE definition; an
;;; embedder reads the same bits off the `headers complete` line and calls the
;;; two procedures below to decide keep-alive vs close after every message, the
;;; way `llhttp_should_keep_alive` / `llhttp_message_needs_eof` do. `(httparse
;;; modes)` and `(httparse methods)` are threaded into the grammar the same way.
;;;
;;; THE RULES ARE llhttp's, TRANSCRIBED FROM `src/native/http.c`, NOT read off a
;;; run of this parser -- which would be the parser grading its own homework.
;;; The version comparison in particular is llhttp's literal `http_major > 0 &&
;;; http_minor > 0` (`http.c:157`), NOT `>= 1.1`: HTTP/1.2 takes the 1.1 branch,
;;; while HTTP/2.0 (minor 0) and HTTP/0.9 (major 0) take the 1.0 branch.
(library (httparse decisions)
  (export F-CONNECTION-KEEP-ALIVE F-CONNECTION-CLOSE F-CONNECTION-UPGRADE
          F-CHUNKED F-UPGRADE F-CONTENT-LENGTH F-SKIP-BODY F-TRAILING
          F-TRANSFER-ENCODING
          should-keep-alive? message-needs-eof?
          httparse-decisions-error? httparse-decisions-error-detail)
  (import (rnrs))

  ;; A refusal from this library, its own condition type so a `&assertion` from
  ;; an unrelated bug cannot read as the refusal a caller is testing for --
  ;; exactly as `(httparse modes)` and `(httparse methods)` do.
  (define-condition-type &httparse-decisions &error
    make-httparse-decisions-error httparse-decisions-error?
    (detail httparse-decisions-error-detail))

  (define (refuse who detail)
    (raise (condition (make-httparse-decisions-error detail)
                      (make-who-condition who)
                      (make-message-condition detail))))

  ;; --- llhttp's FLAGS, in its own bit order --------------------------------
  ;;
  ;; llhttp's `enum flags`, printed verbatim as `flags=%x` on the `headers
  ;; complete` line. All nine are exported, though the two decisions below read
  ;; only six, so an embedder can pin its own copy against these values and go
  ;; red if either side moves. `1 << 8` (256) is deliberately absent: llhttp
  ;; leaves it unused and numbers TRANSFER_ENCODING at `1 << 9`.
  (define F-CONNECTION-KEEP-ALIVE 1)
  (define F-CONNECTION-CLOSE 2)
  (define F-CONNECTION-UPGRADE 4)
  (define F-CHUNKED 8)
  (define F-UPGRADE 16)
  (define F-CONTENT-LENGTH 32)
  ;; Set by the embedder's `on_headers_complete` returning 1 -- "this message
  ;; has no body after all", which llhttp lowers as `setFlag(FLAGS.SKIPBODY)`.
  ;; `message_needs_eof` reads it so a HEAD response, which carries framing
  ;; headers it must ignore, is not read to end of connection.
  (define F-SKIP-BODY 64)
  ;; Set by the ZERO CHUNK, not by a header. Neither decision below reads it;
  ;; exported for completeness with llhttp's enum.
  (define F-TRAILING 128)
  (define F-TRANSFER-ENCODING 512)

  ;; flag-set? : Nat Nat -> Boolean -- is `bit` set in `flags`.
  (define (flag-set? flags bit)
    (not (zero? (bitwise-and flags bit))))

  ;; A completed message is a request or a response, never llhttp's `both`
  ;; initial, so an unknown symbol is REFUSED rather than silently treated as a
  ;; response -- the same "no default" rule the modes and methods tables keep.
  (define (check-type who type)
    (unless (memq type '(request response))
      (refuse who (string-append
                   "type must be 'request or 'response"
                   (if (symbol? type)
                       (string-append ", not '" (symbol->string type))
                       "")))))

  ;; message-needs-eof? : Symbol Nat Nat -> Boolean   ; type status-code flags
  ;;
  ;; `llhttp_message_needs_eof` (`src/native/http.c`): does this message end
  ;; only when the connection closes, rather than at a length it announced? A
  ;; request never does. A response does not when it is 1xx / 204 / 304, when
  ;; the embedder set SKIP-BODY (a HEAD response), or when it is framed by a
  ;; content-length or a chunked coding; a transfer-coding that is NOT chunked
  ;; leaves it framed by eof (RFC 7230 3.3.3).
  (define (message-needs-eof? type status-code flags)
    (check-type 'message-needs-eof? type)
    (cond
      ((eq? type 'request) #f)
      ((or (<= 100 status-code 199)     ; llhttp's `status_code / 100 == 1`
           (= status-code 204)
           (= status-code 304)
           (flag-set? flags F-SKIP-BODY))
       #f)
      ((and (flag-set? flags F-TRANSFER-ENCODING)
            (not (flag-set? flags F-CHUNKED)))
       #t)
      ((flag-set? flags (bitwise-ior F-CHUNKED F-CONTENT-LENGTH)) #f)
      (else #t)))

  ;; should-keep-alive? : Nat Nat Symbol Nat Nat -> Boolean
  ;;   http-major http-minor type status-code flags
  ;;
  ;; `llhttp_should_keep_alive` (`src/native/http.c:157`): the version/Connection
  ;; gate AND `not (message-needs-eof? ...)`. The gate is llhttp's literal
  ;; `http_major > 0 && http_minor > 0` -- an HTTP/1.1-or-later message stays
  ;; alive unless it said `Connection: close`; anything else (HTTP/1.0, 0.9, and
  ;; 2.0, whose minor is 0) must have said `Connection: keep-alive`.
  (define (should-keep-alive? http-major http-minor type status-code flags)
    (check-type 'should-keep-alive? type)
    (and (if (and (> http-major 0) (> http-minor 0))
             (not (flag-set? flags F-CONNECTION-CLOSE))
             (flag-set? flags F-CONNECTION-KEEP-ALIVE))
         (not (message-needs-eof? type status-code flags)))))
