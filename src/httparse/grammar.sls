;;; (httparse grammar): the HTTP/1 grammar, as a byte-machine source machine.
;;;
;;; BUILD TIME ONLY. This library constructs the source IR; it is never loaded
;;; by a running parser. A generated parser depends on (byte-machine runtime)
;;; and nothing else.
;;;
;;; M2: the request line alone -- `method SP request-target SP HTTP-version
;;; CRLF` -- with the method matched against llhttp's 47-name table. Later
;;; slices extend this same machine: the protocol constants, version validity
;;; and llhttp's method-versus-protocol rules, then the header section.
;;;
;;; THE EVENT OFFSETS ARE ASYMMETRIC, AND THAT IS NOT A MISTAKE. Read off
;;; `request/sample.md`, for `OPTIONS /url HTTP/1.1`:
;;;
;;;   off=7  method complete     the SP, UNCONSUMED
;;;   off=13 url complete        one byte PAST its SP, which was consumed
;;;   off=17 protocol complete   the "/", UNCONSUMED
;;;   off=21 version complete    the CR, UNCONSUMED
;;;
;;; So three of the four fire at their delimiter and `url` fires after it. The
;;; shapes below differ accordingly: `after-method` fires the event and THEN
;;; consumes the SP, while `after-url` consumes the SP and THEN fires. Making
;;; them uniform would shift every url offset in the corpus by one.
;;;
;;; SPANS END BEFORE THEIR DELIMITER. Each `*-loop` consumes its own bytes and
;;; REEXECUTES the first foreign byte into a span-end node, so the delimiter is
;;; still unconsumed when the span closes and the following dispatch reads it.
;;;
;;; ERROR NODES ARE PER SPAN STATE, NOT PER CODE. A node reached with two
;;; different span states is rejected by the verifier's flat lattice, so end of
;;; input inside each span needs its own node even though all five name one
;;; `unexpected-eof` declaration. The error CODES here are structural
;;; placeholders; llhttp's numbered taxonomy arrives with the slices that need
;;; it.
(library (httparse grammar)
  (export make-request-line-machine
          httparse-tchar-bytes httparse-url-bytes
          httparse-method-names
          httparse-http-methods httparse-rtsp-methods httparse-ice-methods)
  (import (rnrs) (byte-machine graph))

  (define (range lo hi)
    (let loop ((i hi) (acc '())) (if (< i lo) acc (loop (- i 1) (cons i acc)))))

  ;; tchar = ALPHA / DIGIT / "!#$%&'*+-.^_`|~"  (RFC 9110 5.6.2)
  (define httparse-tchar-bytes
    (append '(33 35 36 37 38 39 42 43 45 46 94 95 96 124 126)
            (range 48 57) (range 65 90) (range 97 122)))

  ;; The request target, as bytes: printable ASCII with SP excluded. The finer
  ;; rules -- and llhttp's "Invalid char in url path" -- belong to the slice
  ;; that reproduces that error.
  (define httparse-url-bytes (range 33 126))

  (define SP 32)
  (define CR 13)
  (define LF 10)
  (define SLASH 47)

  ;; --- the method table ---------------------------------------------------
  ;;
  ;; llhttp matches the method against a TABLE, not against `1*tchar`, and the
  ;; difference is observable: `MKCOLA / HTTP/1.1` records
  ;; `span[method]="MKCOL"` and then `error code=6 "Expected space after
  ;; method"` at offset 5. A tchar loop would take `MKCOLA` whole and accept it.
  ;;
  ;; The union is all 47 names llhttp knows, RTSP and HTTP/2 included: the
  ;; corpus shows `ANNOUNCE` (RTSP-only) parsed into a method span and rejected
  ;; only later, by the method-versus-protocol rule, so the matcher accepts it.
  ;;
  ;; WHY `keyword-table` AND NOT `make-sequence-dispatch-node`. Sequence
  ;; dispatch rejects a case list where one entry is a proper prefix of another
  ;; (`ambiguous-sequence-prefix`), and `GET` is a proper prefix of
  ;; `GET-PARAMETER` -- the only such pair across the 47, and one is enough.
  ;; `keyword-table` tolerates proper prefixes: the longer wins when the input
  ;; reaches it, the shorter when the next byte cannot extend it, and the
  ;; closing byte is reexecuted so the span ends at the keyword's own length.
  ;; That is what makes `MKCOLA` close the span at MKCOL and fail after it.
  (define httparse-method-names
    '("ACL" "ANNOUNCE" "BIND" "CHECKOUT" "CONNECT" "COPY" "DELETE" "DESCRIBE"
      "FLUSH" "GET" "GET-PARAMETER" "HEAD" "LINK" "LOCK" "M-SEARCH" "MERGE"
      "MKACTIVITY" "MKCALENDAR" "MKCOL" "MOVE" "NOTIFY" "OPTIONS" "PATCH"
      "PAUSE" "PLAY" "POST" "PRI" "PROPFIND" "PROPPATCH" "PURGE" "PUT" "QUERY"
      "REBIND" "RECORD" "REDIRECT" "REPORT" "SEARCH" "SET-PARAMETER" "SETUP"
      "SOURCE" "SUBSCRIBE" "TEARDOWN" "TRACE" "UNBIND" "UNLINK" "UNLOCK"
      "UNSUBSCRIBE"))

  ;; --- which protocol accepts which method ---------------------------------
  ;;
  ;; llhttp checks the method against the protocol AT THE PROTOCOL CONSTANT,
  ;; before the version is read, and reports a different reason per protocol --
  ;; the four distinct reasons under error code 8. These three lists are
  ;; llhttp's `METHODS_HTTP`, `METHODS_RTSP` and `METHODS_ICECAST`; their union
  ;; is `httparse-method-names`, they overlap only in GET / OPTIONS / POST, and
  ;; SOURCE is the only ICE method (and is also an HTTP one).
  (define httparse-http-methods
    '("ACL" "BIND" "CHECKOUT" "CONNECT" "COPY" "DELETE" "GET" "HEAD"
      "LINK" "LOCK" "M-SEARCH" "MERGE" "MKACTIVITY" "MKCALENDAR" "MKCOL"
      "MOVE" "NOTIFY" "OPTIONS" "PATCH" "POST" "PRI" "PROPFIND"
      "PROPPATCH" "PURGE" "PUT" "QUERY" "REBIND" "REPORT" "SEARCH"
      "SOURCE" "SUBSCRIBE" "TRACE" "UNBIND" "UNLINK" "UNLOCK"
      "UNSUBSCRIBE"))
  (define httparse-rtsp-methods
    '("ANNOUNCE" "DESCRIBE" "FLUSH" "GET" "GET-PARAMETER" "OPTIONS"
      "PAUSE" "PLAY" "POST" "RECORD" "REDIRECT" "SET-PARAMETER" "SETUP"
      "TEARDOWN"))
  (define httparse-ice-methods '("SOURCE"))

  ;; One bit per protocol, stored in `method-protocols` when the method matches
  ;; and tested with `mask-any` when the protocol constant does. A method
  ;; belongs to one to three of them, so the table's 47 entries collapse to one
  ;; store node per DISTINCT mask rather than one per name.
  (define HTTP-BIT 1)
  (define RTSP-BIT 2)
  (define ICE-BIT 4)

  (define (method-mask name)
    (+ (if (member name httparse-http-methods) HTTP-BIT 0)
       (if (member name httparse-rtsp-methods) RTSP-BIT 0)
       (if (member name httparse-ice-methods) ICE-BIT 0)))

  ;; The distinct masks, ascending. A method in none of the three lists would
  ;; produce mask 0, which no protocol accepts and which the store-node set
  ;; would carry silently -- so it is refused here instead.
  (define method-masks
    (let loop ((names httparse-method-names) (acc '()))
      (if (null? names)
          (list-sort < acc)
          (let ((m (method-mask (car names))))
            (when (= m 0)
              (assertion-violation 'httparse-grammar
                                   "method belongs to no protocol" (car names)))
            (loop (cdr names) (if (member m acc) acc (cons m acc)))))))

  (define (method-store-name m)
    (string->symbol (string-append "method-store-" (number->string m))))

  ;; llhttp stores the method and THEN ends the span (`select(METHODS,
  ;; store('method', span.method.end(...)))`), so the store sits between the
  ;; table and the span end here too.
  (define (method-store-nodes)
    (map (lambda (m)
           (make-field-action-node (method-store-name m) 'store
                                   (list 'method-protocols m)
                                   'method-close #f #f))
         method-masks))

  (define DOT 46)
  (define (digit n) (+ 48 n))
  (define (other-digits ok)
    (let loop ((i 9) (acc '()))
      (cond ((< i 0) acc)
            ((member i ok) (loop (- i 1) acc))
            (else (loop (- i 1) (cons i acc))))))

  ;; `.` continues to the minor digit; anything else ends the version span
  ;; where it stands and is `Expected dot`.
  (define (version-dot-node name minor)
    (make-byte-dispatch-node name
      (list (make-byte-case (make-exact-byte-matcher DOT)
                            (make-edge minor 'advance) #f))
      (make-edge 'version-close-expected-dot 'reexecute) 'e-eof-version #f))

  ;; `ok` is the minor digits this major accepts. Every other DIGIT is a
  ;; well-formed version llhttp rejects as a pair, and a non-digit is a
  ;; malformed minor -- and the two land at different offsets, because the pair
  ;; error fires after its digit is consumed and the malformed one before.
  (define (version-minor-node name ok)
    (let ((bad (other-digits ok)))
      (make-byte-dispatch-node name
        (append
         (if (null? ok) '()
             (list (make-byte-case (make-byte-set-matcher (map digit ok))
                                   (make-edge 'version-close 'advance) #f)))
         (if (null? bad) '()
             (list (make-byte-case (make-byte-set-matcher (map digit bad))
                                   (make-edge 'version-close-bad-version 'advance) #f))))
        (make-edge 'version-close-bad-minor 'reexecute) 'e-eof-version #f)))

  ;; An event invocation. `pause-continuation` is mandatory -- every callback
  ;; declares where to resume if it pauses -- and for an event that is the same
  ;; place `continue` goes, so a paused-then-resumed run re-enters the graph
  ;; exactly where an un-paused one would.
  (define (ev node callback continue)
    (make-callback-node node callback continue '() continue #f))

  (define (make-request-line-machine)
    (make-machine
     'httparse-request-line 'start
     (list (make-uint-field 'method-protocols 8 0 #f))
     (list (make-callback-declaration 'on-message-begin 'event #t '() #f #f)
           (make-callback-declaration 'on-method-data 'span-data #t '() #f #f)
           (make-callback-declaration 'on-method-complete 'event #t '() #f #f)
           (make-callback-declaration 'on-url-data 'span-data #t '() #f #f)
           (make-callback-declaration 'on-url-complete 'event #t '() #f #f)
           (make-callback-declaration 'on-protocol-data 'span-data #t '() #f #f)
           (make-callback-declaration 'on-protocol-complete 'event #t '() #f #f)
           (make-callback-declaration 'on-version-data 'span-data #t '() #f #f)
           (make-callback-declaration 'on-version-complete 'event #t '() #f #f))
     (list (make-span-declaration 'method-span 'on-method-data #f #f)
           (make-span-declaration 'url-span 'on-url-data #f #f)
           (make-span-declaration 'protocol-span 'on-protocol-data #f #f)
           (make-span-declaration 'version-span 'on-version-data #f #f))
     ;; ONE CODE SYMBOL PER llhttp ERROR NUMBER, AND llhttp's REASON VERBATIM.
     ;; The corpus records `error code=N reason="..."`, and two of llhttp's
     ;; reasons are the same string under different numbers ("Expected CRLF
     ;; after version" is 9 when there is no CR and 2 when a CR is not followed
     ;; by LF). So neither half identifies an error on its own: the pair does,
     ;; and the pair is unique here by construction. The conformance adapter
     ;; then renames a symbol to its number and passes the reason through, which
     ;; is the least it can do and still be a rename (decision 0008 item 2).
     ;; `bad-url` is the one placeholder left: llhttp's url reasons belong to
     ;; the URL sub-parser, deferred by decision 0009.
     (list (make-error-declaration 'eof 'unexpected-eof "unexpected end of input" #f)
           (make-error-declaration 'bad-method 'invalid-method
                                   "Invalid method encountered" #f)
           (make-error-declaration 'no-space-after-method 'invalid-method
                                   "Expected space after method" #f)
           (make-error-declaration 'bad-url 'invalid-url "invalid request target" #f)
           (make-error-declaration 'bad-protocol 'invalid-constant
                                   "Expected HTTP/, RTSP/ or ICE/" #f)
           (make-error-declaration 'method-not-http 'invalid-constant
                                   "Invalid method for HTTP/x.x request" #f)
           (make-error-declaration 'method-not-rtsp 'invalid-constant
                                   "Invalid method for RTSP/x.x request" #f)
           (make-error-declaration 'method-not-ice 'invalid-constant
                                   "Expected SOURCE method for ICE/x.x request" #f)
           (make-error-declaration 'bad-major 'invalid-version
                                   "Invalid major version" #f)
           (make-error-declaration 'expected-dot 'invalid-version
                                   "Expected dot" #f)
           (make-error-declaration 'bad-minor 'invalid-version
                                   "Invalid minor version" #f)
           (make-error-declaration 'bad-version 'invalid-version
                                   "Invalid HTTP version" #f)
           (make-error-declaration 'no-crlf 'invalid-version
                                   "Expected CRLF after version" #f)
           (make-error-declaration 'lf-after-cr 'strict
                                   "Expected CRLF after version" #f))
     (append
      (list
      ;; --- the first byte -----------------------------------------------------
      ;; A dispatch rather than a callback node: the first method byte must be
      ;; available but UNCONSUMED when `message begin` fires at offset 0, and
      ;; this also enforces `method = 1*tchar` -- an empty method is rejected
      ;; here, before any span opens.
      (make-byte-dispatch-node 'start
        (list (make-byte-case (make-byte-set-matcher httparse-tchar-bytes)
                              (make-edge 'message-begin 'reexecute) #f))
        (make-edge 'e-bad-method 'reexecute) 'clean-eof #f)
      (make-finish-node 'clean-eof #f)
      (ev 'message-begin 'on-message-begin 'method-open)

      ;; --- method -------------------------------------------------------------
      (make-span-start-node 'method-open 'method-span 'method-table #f)
      ;; No match leaves the span OPEN and reexecutes, so a method that is only
      ;; a prefix of real ones (`GE `) errors at the byte that broke the walk
      ;; with no span fragment delivered -- which is what the corpus records:
      ;; `span[method]` never precedes an error in any of the 253 fixtures.
      (make-keyword-table-node 'method-table
        (map (lambda (name)
               (make-keyword-entry (ascii-bytes name)
                                   (method-store-name (method-mask name)) #f))
             httparse-method-names)
        (make-edge 'e-bad-method-open 'reexecute)
        'e-eof-method #f #f))
      ;; one store node per distinct protocol mask, not per name
      (method-store-nodes)
      (list
      (make-span-end-node 'method-close 'method-span 'method-complete #f)
      ;; fires AT the delimiter: `off=7 method complete` with SP still at 7
      (ev 'method-complete 'on-method-complete 'after-method)
      ;; `MKCOLA`: the table took MKCOL, the span closed and the event fired at
      ;; offset 5, and the byte here is `A` rather than SP.
      (make-byte-dispatch-node 'after-method
        (list (make-byte-case (make-exact-byte-matcher SP)
                              (make-edge 'url-open 'advance) #f))
        (make-edge 'e-no-space-after-method 'reexecute) 'e-eof-none #f)

      ;; --- request target -----------------------------------------------------
      (make-span-start-node 'url-open 'url-span 'url-loop #f)
      (make-byte-dispatch-node 'url-loop
        (list (make-byte-case (make-byte-set-matcher httparse-url-bytes)
                              (make-edge 'url-loop 'advance) #f))
        (make-edge 'url-close 'reexecute) 'e-eof-url #f)
      (make-span-end-node 'url-close 'url-span 'after-url #f)
      ;; the SP is consumed FIRST, so the event lands one byte later than the
      ;; other three: `off=13 url complete` with the SP at 12
      (make-byte-dispatch-node 'after-url
        (list (make-byte-case (make-exact-byte-matcher SP)
                              (make-edge 'url-complete 'advance) #f))
        (make-edge 'e-bad-url 'reexecute) 'e-eof-none #f)
      (ev 'url-complete 'on-url-complete 'protocol-open)

      ;; --- protocol -----------------------------------------------------------
      ;;
      ;; A keyword table, for the same reason the method is one, plus a second:
      ;; the span must close over exactly the bytes the walk took. `HTP/1.1`
      ;; records `span[protocol]="HT"` and errors at 2; `IHTTP/1.0` records
      ;; `span[protocol]="I"`; `GET /foo bar/ HTTP/1.1` records the EMPTY
      ;; `span[protocol]=""` at 9. A loop over A-Z reproduces none of those --
      ;; it has no notion of a constant, so it would accept `HTTX/1.1` whole.
      ;;
      ;; `protocol complete` fires only on a COMPLETE match, which is why the
      ;; three hits pass through their own event node and the no-match does not:
      ;; `HTTPER/1.1` records `protocol complete` at 4 and then the error, while
      ;; the three partial matches record no completion at all.
      (make-span-start-node 'protocol-open 'protocol-span 'protocol-table #f)
      (make-keyword-table-node 'protocol-table
        (list (make-keyword-entry (ascii-bytes "HTTP") 'protocol-close-http #f)
              (make-keyword-entry (ascii-bytes "RTSP") 'protocol-close-rtsp #f)
              (make-keyword-entry (ascii-bytes "ICE") 'protocol-close-ice #f))
        (make-edge 'protocol-close-bad 'reexecute) 'e-eof-protocol #f #f)
      (make-span-end-node 'protocol-close-bad 'protocol-span 'e-bad-protocol #f)

      ;; llhttp's `checkMethod` is `span.protocol.end(on_protocol_complete(
      ;; load('method', accepted, failure)))` -- span end, event, THEN the
      ;; compatibility branch, all at the protocol's own offset and before the
      ;; version is read. `ANNOUNCE /music/sweet/music HTTP/1.0` records
      ;; `off=32 protocol complete` and `off=32 error code=8`.
      (make-span-end-node 'protocol-close-http 'protocol-span 'protocol-complete-http #f)
      (ev 'protocol-complete-http 'on-protocol-complete 'check-http)
      (make-field-branch-node 'check-http 'mask-any (list 'method-protocols HTTP-BIT)
                              'after-protocol 'e-method-not-http #f)
      (make-span-end-node 'protocol-close-rtsp 'protocol-span 'protocol-complete-rtsp #f)
      (ev 'protocol-complete-rtsp 'on-protocol-complete 'check-rtsp)
      (make-field-branch-node 'check-rtsp 'mask-any (list 'method-protocols RTSP-BIT)
                              'after-protocol 'e-method-not-rtsp #f)
      (make-span-end-node 'protocol-close-ice 'protocol-span 'protocol-complete-ice #f)
      (ev 'protocol-complete-ice 'on-protocol-complete 'check-ice)
      (make-field-branch-node 'check-ice 'mask-any (list 'method-protocols ICE-BIT)
                              'after-protocol 'e-method-not-ice #f)

      ;; The slash is a separate check with the SAME reason as a failed
      ;; constant: `HTTPER/1.1` completes the protocol and then fails here.
      (make-byte-dispatch-node 'after-protocol
        (list (make-byte-case (make-exact-byte-matcher SLASH)
                              (make-edge 'version-open 'advance) #f))
        (make-edge 'e-bad-protocol 'reexecute) 'e-eof-none #f)

      ;; --- version ------------------------------------------------------------
      ;;
      ;; `<digit> "." <digit>`, and the PAIR must be 0.9, 1.0, 1.1 or 2.0
      ;; (llhttp's `checkVersion`, strict). Major and minor are single digits
      ;; there too -- `select(MAJOR, ...)` over a digit map -- so the accepted
      ;; pairs are four one-byte cases and no field is needed to hold them.
      ;; A loop over digits-and-dot, which is what stood here, accepts `1.1.1`.
      ;;
      ;; Three distinct failures at three distinct offsets:
      ;;
      ;;   HTTP/01.1   span[version]="0"     error@6    Expected dot
      ;;   HTTP/5.6    span[version]="5.6"   error@14   Invalid HTTP version
      ;;   HTTP/1.x    span[version]="1."               Invalid minor version
      (make-span-start-node 'version-open 'version-span 'version-major #f)
      (make-byte-dispatch-node 'version-major
        (list (make-byte-case (make-exact-byte-matcher (digit 0))
                              (make-edge 'version-dot-0 'advance) #f)
              (make-byte-case (make-exact-byte-matcher (digit 1))
                              (make-edge 'version-dot-1 'advance) #f)
              (make-byte-case (make-exact-byte-matcher (digit 2))
                              (make-edge 'version-dot-2 'advance) #f)
              (make-byte-case (make-byte-set-matcher (map digit (other-digits '(0 1 2))))
                              (make-edge 'version-dot-other 'advance) #f))
        (make-edge 'version-close-bad-major 'reexecute) 'e-eof-version #f)
      (version-dot-node 'version-dot-0 'version-minor-0)
      (version-dot-node 'version-dot-1 'version-minor-1)
      (version-dot-node 'version-dot-2 'version-minor-2)
      (version-dot-node 'version-dot-other 'version-minor-other)
      (version-minor-node 'version-minor-0 '(9))
      (version-minor-node 'version-minor-1 '(0 1))
      (version-minor-node 'version-minor-2 '(0))
      (version-minor-node 'version-minor-other '())
      (make-span-end-node 'version-close 'version-span 'version-complete #f)
      (make-span-end-node 'version-close-bad-major 'version-span 'e-bad-major #f)
      (make-span-end-node 'version-close-expected-dot 'version-span 'e-expected-dot #f)
      (make-span-end-node 'version-close-bad-minor 'version-span 'e-bad-minor #f)
      (make-span-end-node 'version-close-bad-version 'version-span 'e-bad-version #f)
      (ev 'version-complete 'on-version-complete 'expect-cr)

      ;; --- CRLF ---------------------------------------------------------------
      ;; Strict: a bare CR or a bare LF is a line-ending error, not a newline.
      (make-byte-dispatch-node 'expect-cr
        (list (make-byte-case (make-exact-byte-matcher CR)
                              (make-edge 'expect-lf 'advance) #f))
        (make-edge 'e-no-crlf 'reexecute) 'e-eof-none #f)
      (make-byte-dispatch-node 'expect-lf
        (list (make-byte-case (make-exact-byte-matcher LF)
                              (make-edge 'request-line-done 'advance) #f))
        (make-edge 'e-lf-after-cr 'reexecute) 'e-eof-none #f)
      ;; M2 stops at the end of the request line; M3 replaces this with the
      ;; header section and the message loop.
      (make-stop-node 'request-line-done #f)

      ;; --- errors, one node per span state ------------------------------------
      (make-error-node 'e-bad-method 'bad-method #f)
      ;; Reached from the table's no-match, where the method span IS open -- a
      ;; separate node from `e-bad-method` because the verifier's flat lattice
      ;; refuses one node reached with two different span states.
      (make-error-node 'e-bad-method-open 'bad-method #f)
      (make-error-node 'e-no-space-after-method 'no-space-after-method #f)
      (make-error-node 'e-bad-url 'bad-url #f)
      (make-error-node 'e-bad-protocol 'bad-protocol #f)
      (make-error-node 'e-method-not-http 'method-not-http #f)
      (make-error-node 'e-method-not-rtsp 'method-not-rtsp #f)
      (make-error-node 'e-method-not-ice 'method-not-ice #f)
      (make-error-node 'e-bad-major 'bad-major #f)
      (make-error-node 'e-expected-dot 'expected-dot #f)
      (make-error-node 'e-bad-minor 'bad-minor #f)
      (make-error-node 'e-bad-version 'bad-version #f)
      (make-error-node 'e-no-crlf 'no-crlf #f)
      (make-error-node 'e-lf-after-cr 'lf-after-cr #f)
      (make-error-node 'e-eof-none 'eof #f)
      (make-error-node 'e-eof-method 'eof #f)
      (make-error-node 'e-eof-url 'eof #f)
      (make-error-node 'e-eof-protocol 'eof #f)
      (make-error-node 'e-eof-version 'eof #f)))
     'eof #f)))
