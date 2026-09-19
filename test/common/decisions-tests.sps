;;; (httparse decisions): llhttp's keep-alive / needs-eof rules, judged as pure
;;; functions.
;;;
;;; THE RULES ARE ASSERTED AGAINST llhttp, NOT AGAINST THIS PARSER. Every
;;; expectation is read from `src/native/http.c` -- `llhttp_should_keep_alive`
;;; and `llhttp_message_needs_eof` -- not from a run of the machine whose flags
;;; these read. No fixture in the corpus exercises the version comparison at
;;; all (the only `HTTP/2.0` bytes are `Upgrade:` values, and the `HTTP/x.y`
;;; malformations error at the version check), so the quadrant rows below carry
;;; the `http.c:157` citation in place of a trace.
(import (rnrs)
        (httparse test harness)
        (httparse decisions))

(define (refuses? thunk)
  (call/cc (lambda (k)
             (with-exception-handler
              (lambda (e) (k (httparse-decisions-error? e)))
              (lambda () (thunk) #f)))))

(harness-begin "unit.decisions")

(harness-group "llhttp's FLAGS bits"
  (lambda ()
    (harness-case "each is llhttp's own value"
      (lambda ()
        (check-equal "CONNECTION_KEEP_ALIVE" F-CONNECTION-KEEP-ALIVE 1)
        (check-equal "CONNECTION_CLOSE" F-CONNECTION-CLOSE 2)
        (check-equal "CONNECTION_UPGRADE" F-CONNECTION-UPGRADE 4)
        (check-equal "CHUNKED" F-CHUNKED 8)
        (check-equal "UPGRADE" F-UPGRADE 16)
        (check-equal "CONTENT_LENGTH" F-CONTENT-LENGTH 32)
        (check-equal "SKIPBODY" F-SKIP-BODY 64)
        (check-equal "TRAILING" F-TRAILING 128)
        ;; 1 << 9, not 1 << 8: llhttp leaves 256 unused.
        (check-equal "TRANSFER_ENCODING" F-TRANSFER-ENCODING 512)))
    (harness-case "each is a single distinct bit"
      (lambda ()
        (let ((bits (list F-CONNECTION-KEEP-ALIVE F-CONNECTION-CLOSE
                          F-CONNECTION-UPGRADE F-CHUNKED F-UPGRADE
                          F-CONTENT-LENGTH F-SKIP-BODY F-TRAILING
                          F-TRANSFER-ENCODING)))
          (check "each is a power of two"
                 (for-all (lambda (b) (and (positive? b)
                                           (zero? (bitwise-and b (- b 1)))))
                          bits))
          (check "no two share a bit"
                 (let loop ((bs bits) (seen 0))
                   (cond ((null? bs) #t)
                         ((zero? (bitwise-and seen (car bs)))
                          (loop (cdr bs) (bitwise-ior seen (car bs))))
                         (else #f)))))))))

(harness-group "message-needs-eof? : Symbol Nat Nat -> Boolean"
  (lambda ()
    (harness-case "a request never needs eof"
      (lambda ()
        ;; `if (type == HTTP_REQUEST) return 0` -- the first line of the C, and
        ;; the reason every pipelined request in the corpus restarts. status and
        ;; flags are not even read (a request parser carries status-code 0).
        (check-equal "plain" (message-needs-eof? 'request 0 0) #f)
        (check-equal "even with a body-less status shape"
                     (message-needs-eof? 'request 204 F-CONTENT-LENGTH) #f)))
    (harness-case "a response with no body by its status does not"
      (lambda ()
        (check-equal "100" (message-needs-eof? 'response 100 0) #f)
        (check-equal "199 (top of 1xx)" (message-needs-eof? 'response 199 0) #f)
        (check-equal "204" (message-needs-eof? 'response 204 0) #f)
        (check-equal "304" (message-needs-eof? 'response 304 0) #f)))
    (harness-case "a HEAD response (SKIP-BODY) does not, though it has framing"
      (lambda ()
        ;; The branch the grammar's own needs-eof graph omits on purpose: our
        ;; test client parses HEAD responses in response mode, and without this
        ;; a HEAD response carrying Content-Length would read to end of stream.
        (check-equal "skip-body wins over a content-length"
                     (message-needs-eof? 'response 200
                                         (bitwise-ior F-SKIP-BODY F-CONTENT-LENGTH))
                     #f)
        (check-equal "and over an eof-framed body"
                     (message-needs-eof? 'response 200 F-SKIP-BODY) #f)))
    (harness-case "a framed response does not"
      (lambda ()
        (check-equal "content-length" (message-needs-eof? 'response 200 F-CONTENT-LENGTH) #f)
        (check-equal "chunked" (message-needs-eof? 'response 200 F-CHUNKED) #f)))
    (harness-case "a non-chunked transfer-coding does (RFC 7230 3.3.3)"
      (lambda ()
        ;; TRANSFER_ENCODING set but CHUNKED clear: a coding that does not end
        ;; in chunked has no length but the connection's.
        (check-equal "te, not chunked" (message-needs-eof? 'response 200 F-TRANSFER-ENCODING) #t)
        ;; ...but chunked on top of it frames the message again.
        (check-equal "te AND chunked"
                     (message-needs-eof? 'response 200
                                         (bitwise-ior F-TRANSFER-ENCODING F-CHUNKED))
                     #f)))
    (harness-case "an unframed response ends with the connection"
      (lambda ()
        (check-equal "no framing at all" (message-needs-eof? 'response 200 0) #t)))))

(harness-group "should-keep-alive? : the version/Connection gate (http.c:157)"
  (lambda ()
    ;; Every row is a response framed by a content-length, so message-needs-eof?
    ;; is #f and what the row measures is the gate alone. The gate is llhttp's
    ;; literal `http_major > 0 && http_minor > 0`, checked one row per quadrant
    ;; because no corpus fixture reaches it.
    (define framed F-CONTENT-LENGTH)
    (harness-case "HTTP/1.1 stays alive unless it said close"
      (lambda ()
        (check-equal "no close" (should-keep-alive? 1 1 'response 200 framed) #t)
        (check-equal "close"
                     (should-keep-alive? 1 1 'response 200
                                         (bitwise-ior framed F-CONNECTION-CLOSE))
                     #f)))
    (harness-case "HTTP/1.0 stays alive only if it said keep-alive"
      (lambda ()
        (check-equal "no keep-alive" (should-keep-alive? 1 0 'response 200 framed) #f)
        (check-equal "keep-alive"
                     (should-keep-alive? 1 0 'response 200
                                         (bitwise-ior framed F-CONNECTION-KEEP-ALIVE))
                     #t)))
    (harness-case "HTTP/1.2 takes the 1.1 branch (minor > 0)"
      (lambda ()
        ;; `>= 1.1` and llhttp's `major>0 && minor>0` agree here; the next case
        ;; is where they part.
        (check-equal "no close" (should-keep-alive? 1 2 'response 200 framed) #t)
        (check-equal "close"
                     (should-keep-alive? 1 2 'response 200
                                         (bitwise-ior framed F-CONNECTION-CLOSE))
                     #f)))
    (harness-case "HTTP/2.0 takes the 1.0 branch (minor = 0)"
      (lambda ()
        ;; This is the row that fails under a naive `>= 1.1`: 2.0 > 1.1, yet
        ;; llhttp routes it to the 1.0 branch because its minor is 0, so it
        ;; needs an explicit keep-alive.
        (check-equal "no keep-alive" (should-keep-alive? 2 0 'response 200 framed) #f)
        (check-equal "keep-alive"
                     (should-keep-alive? 2 0 'response 200
                                         (bitwise-ior framed F-CONNECTION-KEEP-ALIVE))
                     #t)))
    (harness-case "HTTP/0.9 takes the 1.0 branch (major = 0)"
      (lambda ()
        (check-equal "no keep-alive" (should-keep-alive? 0 9 'response 200 framed) #f)
        (check-equal "keep-alive"
                     (should-keep-alive? 0 9 'response 200
                                         (bitwise-ior framed F-CONNECTION-KEEP-ALIVE))
                     #t)))))

(harness-group "should-keep-alive? folds in message-needs-eof?"
  (lambda ()
    (harness-case "a response that needs eof cannot keep alive, gate notwithstanding"
      (lambda ()
        ;; HTTP/1.1, no close: the gate says keep-alive. But an unframed 200
        ;; ends only at the connection, so `!needs_eof` drags the answer to #f.
        (check-equal "unframed 1.1" (should-keep-alive? 1 1 'response 200 0) #f)
        ;; The same message, framed, is kept alive: proof the gate was willing.
        (check-equal "framed 1.1" (should-keep-alive? 1 1 'response 200 F-CONTENT-LENGTH) #t)))
    (harness-case "a request's keep-alive is the gate alone (it never needs eof)"
      (lambda ()
        (check-equal "1.1 no close" (should-keep-alive? 1 1 'request 0 0) #t)
        (check-equal "1.0 no keep-alive" (should-keep-alive? 1 0 'request 0 0) #f)
        (check-equal "1.0 keep-alive"
                     (should-keep-alive? 1 0 'request 0 F-CONNECTION-KEEP-ALIVE) #t)))))

(harness-group "an unknown message type is refused, not treated as a response"
  (lambda ()
    (harness-case "message-needs-eof? refuses"
      (lambda ()
        (check "both" (refuses? (lambda () (message-needs-eof? 'both 200 0))))
        (check "a typo" (refuses? (lambda () (message-needs-eof? 'respones 200 0))))))
    (harness-case "should-keep-alive? refuses"
      (lambda ()
        (check "both" (refuses? (lambda () (should-keep-alive? 1 1 'both 200 0))))))))

(harness-finish)
