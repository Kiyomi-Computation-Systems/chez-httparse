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
          httparse-tchar-bytes httparse-url-bytes
          httparse-method-names)
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
  ;; WHY A TRIE AND NOT `make-sequence-dispatch-node`. That construct exists for
  ;; exactly this and cannot be used: it rejects a case list where one entry is
  ;; a proper prefix of another (`ambiguous-sequence-prefix`), and `GET` is a
  ;; proper prefix of `GET-PARAMETER`. A trie with an explicit terminator
  ;; handles the pair correctly -- at `GET`, a `-` continues and anything else
  ;; terminates -- which is the same shape a Gate 0 spike measured on
  ;; `close`/`closed`.
  (define httparse-method-names
    '("ACL" "ANNOUNCE" "BIND" "CHECKOUT" "CONNECT" "COPY" "DELETE" "DESCRIBE"
      "FLUSH" "GET" "GET-PARAMETER" "HEAD" "LINK" "LOCK" "M-SEARCH" "MERGE"
      "MKACTIVITY" "MKCALENDAR" "MKCOL" "MOVE" "NOTIFY" "OPTIONS" "PATCH"
      "PAUSE" "PLAY" "POST" "PRI" "PROPFIND" "PROPPATCH" "PURGE" "PUT" "QUERY"
      "REBIND" "RECORD" "REDIRECT" "REPORT" "SEARCH" "SET-PARAMETER" "SETUP"
      "SOURCE" "SUBSCRIBE" "TEARDOWN" "TRACE" "UNBIND" "UNLINK" "UNLOCK"
      "UNSUBSCRIBE"))

  (define (string-prefix-of? p s)
    (and (<= (string-length p) (string-length s))
         (string=? p (substring s 0 (string-length p)))))

  ;; Every distinct prefix of every method name, shortest first, "" included.
  (define method-prefixes
    (let ((seen '()))
      (for-each
       (lambda (name)
         (let loop ((i 0))
           (when (<= i (string-length name))
             (let ((p (substring name 0 i)))
               (unless (member p seen) (set! seen (cons p seen))))
             (loop (+ i 1)))))
       httparse-method-names)
      (list-sort (lambda (a b) (< (string-length a) (string-length b)))
                 (reverse seen))))

  (define (method-node-name p)
    (string->symbol
     (string-append "m" (number->string
                         (let loop ((xs method-prefixes) (i 0))
                           (cond ((null? xs) (assertion-violation 'grammar "no prefix" p))
                                 ((string=? (car xs) p) i)
                                 (else (loop (cdr xs) (+ i 1)))))))))

  ;; The bytes that may follow prefix `p` within some method name.
  (define (method-children p)
    (let ((out '()))
      (for-each
       (lambda (name)
         (when (and (> (string-length name) (string-length p))
                    (string-prefix-of? p name))
           (let ((b (char->integer (string-ref name (string-length p)))))
             (unless (member b out) (set! out (cons b out))))))
       httparse-method-names)
      (reverse out)))

  (define (method-terminal? p) (member p httparse-method-names))

  ;; One byte-dispatch per prefix. A byte that continues the trie advances; the
  ;; fallback TERMINATES the method when this prefix is a complete name --
  ;; reexecuting so the delimiter is unconsumed when the span closes -- and
  ;; rejects otherwise.
  (define (method-trie-nodes)
    (map (lambda (p)
           (make-byte-dispatch-node
            (method-node-name p)
            (map (lambda (b)
                   (make-byte-case
                    (make-exact-byte-matcher b)
                    (make-edge (method-node-name
                                (string-append p (string (integer->char b))))
                               'advance)
                    #f))
                 (method-children p))
            (if (method-terminal? p)
                (make-edge 'method-close 'reexecute)
                (make-edge 'e-bad-method-open 'reexecute))
            (if (method-terminal? p) 'e-eof-method 'e-eof-method)
            #f))
         method-prefixes))

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
           (make-error-declaration 'no-space-after-method 'invalid-method
                                   "Expected space after method" #f)
           (make-error-declaration 'bad-url 'invalid-url "invalid request target" #f)
           (make-error-declaration 'bad-protocol 'invalid-constant "expected a protocol name" #f)
           (make-error-declaration 'bad-version 'invalid-version "invalid version" #f)
           (make-error-declaration 'bad-crlf 'invalid-line-ending "expected CRLF" #f))
     (append (method-trie-nodes) (list
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
      (make-span-start-node 'method-open 'method-span (method-node-name "") #f)
      (make-span-end-node 'method-close 'method-span 'method-complete #f)
      ;; fires AT the delimiter: `off=7 method complete` with SP still at 7
      (ev 'method-complete 'on-method-complete 'after-method)
      ;; `MKCOLA`: the trie terminated at MKCOL, the span closed and the event
      ;; fired at offset 5, and the byte here is `A` rather than SP.
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
      ;; Reached from inside the trie, where the method span IS open -- a
      ;; separate node from `e-bad-method` because the verifier's flat lattice
      ;; refuses one node reached with two different span states.
      (make-error-node 'e-bad-method-open 'bad-method #f)
      (make-error-node 'e-no-space-after-method 'no-space-after-method #f)
      (make-error-node 'e-bad-url 'bad-url #f)
      (make-error-node 'e-bad-protocol 'bad-protocol #f)
      (make-error-node 'e-bad-crlf 'bad-crlf #f)
      (make-error-node 'e-eof-none 'eof #f)
      (make-error-node 'e-eof-method 'eof #f)
      (make-error-node 'e-eof-url 'eof #f)
      (make-error-node 'e-eof-protocol 'eof #f)
      (make-error-node 'e-eof-version 'eof #f)))
     'eof #f)))
