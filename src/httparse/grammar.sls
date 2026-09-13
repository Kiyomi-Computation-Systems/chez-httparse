;;; (httparse grammar): the HTTP/1 grammar, as a byte-machine source machine.
;;;
;;; BUILD TIME ONLY. This library constructs the source IR; it is never loaded
;;; by a running parser. A generated parser depends on (byte-machine runtime)
;;; and nothing else.
;;;
;;; M2 SLICE ①: the request line alone -- `method SP request-target SP
;;; HTTP-version CRLF`. Later slices extend this same machine: the method table
;;; and `Expected space after method`, then the protocol constants, version
;;; validity and llhttp's method-versus-protocol rules, then the header section.
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
          httparse-tchar-bytes httparse-url-bytes)
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

  ;; An event invocation. `pause-continuation` is mandatory -- every callback
  ;; declares where to resume if it pauses -- and for an event that is the same
  ;; place `continue` goes, so a paused-then-resumed run re-enters the graph
  ;; exactly where an un-paused one would.
  (define (ev node callback continue)
    (make-callback-node node callback continue '() continue #f))

  (define (make-request-line-machine)
    (make-machine
     'httparse-request-line 'start
     '()                                        ; no fields yet
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
     (list (make-error-declaration 'eof 'unexpected-eof "unexpected end of input" #f)
           (make-error-declaration 'bad-method 'invalid-method "invalid method" #f)
           (make-error-declaration 'bad-url 'invalid-url "invalid request target" #f)
           (make-error-declaration 'bad-protocol 'invalid-constant "expected a protocol name" #f)
           (make-error-declaration 'bad-version 'invalid-version "invalid version" #f)
           (make-error-declaration 'bad-crlf 'invalid-line-ending "expected CRLF" #f))
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
      (make-span-start-node 'method-open 'method-span 'method-loop #f)
      (make-byte-dispatch-node 'method-loop
        (list (make-byte-case (make-byte-set-matcher httparse-tchar-bytes)
                              (make-edge 'method-loop 'advance) #f))
        (make-edge 'method-close 'reexecute) 'e-eof-method #f)
      (make-span-end-node 'method-close 'method-span 'method-complete #f)
      ;; fires AT the delimiter: `off=7 method complete` with SP still at 7
      (ev 'method-complete 'on-method-complete 'after-method)
      (make-byte-dispatch-node 'after-method
        (list (make-byte-case (make-exact-byte-matcher SP)
                              (make-edge 'url-open 'advance) #f))
        (make-edge 'e-bad-method 'reexecute) 'e-eof-none #f)

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
      (make-span-start-node 'protocol-open 'protocol-span 'protocol-loop #f)
      (make-byte-dispatch-node 'protocol-loop
        (list (make-byte-case (make-byte-range-matcher 65 90)
                              (make-edge 'protocol-loop 'advance) #f))
        (make-edge 'protocol-close 'reexecute) 'e-eof-protocol #f)
      (make-span-end-node 'protocol-close 'protocol-span 'protocol-complete #f)
      (ev 'protocol-complete 'on-protocol-complete 'after-protocol)
      (make-byte-dispatch-node 'after-protocol
        (list (make-byte-case (make-exact-byte-matcher SLASH)
                              (make-edge 'version-open 'advance) #f))
        (make-edge 'e-bad-protocol 'reexecute) 'e-eof-none #f)

      ;; --- version ------------------------------------------------------------
      (make-span-start-node 'version-open 'version-span 'version-loop #f)
      (make-byte-dispatch-node 'version-loop
        (list (make-byte-case (make-byte-set-matcher (cons 46 (range 48 57)))
                              (make-edge 'version-loop 'advance) #f))
        (make-edge 'version-close 'reexecute) 'e-eof-version #f)
      (make-span-end-node 'version-close 'version-span 'version-complete #f)
      (ev 'version-complete 'on-version-complete 'expect-cr)

      ;; --- CRLF ---------------------------------------------------------------
      ;; Strict: a bare CR or a bare LF is a line-ending error, not a newline.
      (make-byte-dispatch-node 'expect-cr
        (list (make-byte-case (make-exact-byte-matcher CR)
                              (make-edge 'expect-lf 'advance) #f))
        (make-edge 'e-bad-crlf 'reexecute) 'e-eof-none #f)
      (make-byte-dispatch-node 'expect-lf
        (list (make-byte-case (make-exact-byte-matcher LF)
                              (make-edge 'request-line-done 'advance) #f))
        (make-edge 'e-bad-crlf 'reexecute) 'e-eof-none #f)
      ;; M2 stops at the end of the request line; M3 replaces this with the
      ;; header section and the message loop.
      (make-stop-node 'request-line-done #f)

      ;; --- errors, one node per span state ------------------------------------
      (make-error-node 'e-bad-method 'bad-method #f)
      (make-error-node 'e-bad-url 'bad-url #f)
      (make-error-node 'e-bad-protocol 'bad-protocol #f)
      (make-error-node 'e-bad-crlf 'bad-crlf #f)
      (make-error-node 'e-eof-none 'eof #f)
      (make-error-node 'e-eof-method 'eof #f)
      (make-error-node 'e-eof-url 'eof #f)
      (make-error-node 'e-eof-protocol 'eof #f)
      (make-error-node 'e-eof-version 'eof #f))
     'eof #f)))
