;;; (httparse grammar): the HTTP/1 grammar, as a byte-machine source machine.
;;;
;;; BUILD TIME ONLY. This library constructs the source IR; it is never loaded
;;; by a running parser. A generated parser depends on (byte-machine runtime)
;;; and nothing else.
;;;
;;; The request line -- `method SP request-target SP HTTP-version CRLF`, with
;;; the method and the protocol matched against llhttp's constant tables -- and
;;; the header section, strictly: field, colon, OWS, value, line ending, and the
;;; empty line that ends them. Field names are OPAQUE here; llhttp's
;;; special-header table, and the message framing behind it, belong to a later
;;; slice, as does the body.
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
;;; `unexpected-eof` declaration. The error codes and reasons are llhttp's own,
;;; per decision 0013 -- identity is the (code, reason) pair, because eight of
;;; its codes carry more than one reason. `bad-url` is the one reason still
;;; standing in for a decision the url sub-parser has not made.
;;;
;;; TRANSLATING AN llhttp ARM: `.match` CONSUMES; `.peek` AND `.otherwise` DO
;;; NOT. An error reached through a match therefore lands one byte LATER than
;;; one reached through a peek, so an arm's KIND is part of its meaning and must
;;; be read off `src/llhttp/http.ts` rather than inferred from the shape it
;;; would take here. Three offset bugs in three slices, all this:
;;;
;;;   headers_start's SP           .match   invalid.md#20 records off=17 for a
;;;                                         space at 16
;;;   header_value_discard_lws's   .match   obs-fold after an EMPTY value, one
;;;     SP/HTAB                             byte past the whitespace
;;;   header_value_lws's SP/HTAB   .peek    obs-fold after a NON-EMPTY value,
;;;                                         AT the whitespace
;;;
;;; The last two are the same production and differ in BOTH offset and reason
;;; -- "Invalid header value char" against "Unexpected whitespace after header
;;; value" -- which is why 0013 makes the pair the identity.
(library (httparse grammar)
  (export make-request-line-machine
          httparse-tchar-bytes httparse-url-bytes httparse-header-bytes
          httparse-method-names httparse-method-numbers
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

  ;; What may appear in a header value: llhttp's HEADER_CHARS, which is
  ;; HTAB / SP / VCHAR / obs-text. Excluded are NUL, the C0 controls other than
  ;; HTAB, DEL, and -- the two that matter -- CR and LF, which is what makes the
  ;; loop stop at its own line ending.
  (define httparse-header-bytes
    (append '(9 32) (range 33 126) (range 128 255)))

  (define SP 32)
  (define CR 13)
  (define LF 10)
  (define SLASH 47)
  (define HTAB 9)
  (define COLON 58)

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

  ;; THE NUMBER llhttp PRINTS. `headers complete` carries `method=%d`, and the
  ;; number is the method's value in llhttp's own `METHODS` map -- NOT its
  ;; position in the list above, which is alphabetical. The map is assembled
  ;; from eight sub-maps with explicit values and one alias, so the pairs are
  ;; extracted by script and given two invariants to violate: the key set must
  ;; equal `httparse-method-names` (checked in the unit lane) and the values
  ;; must be exactly 0..46 with no gap or repeat. The corpus is the third
  ;; check, and the strongest -- sixteen fixtures print a method span and a
  ;; `method=` on the same trace, so the conformance lane compares the pairs
  ;; against the oracle directly.
  (define httparse-method-numbers
    '(("ACL" . 19) ("ANNOUNCE" . 36) ("BIND" . 16) ("CHECKOUT" . 22)
      ("CONNECT" . 5) ("COPY" . 8) ("DELETE" . 0) ("DESCRIBE" . 35)
      ("FLUSH" . 45) ("GET" . 1) ("GET-PARAMETER" . 41) ("HEAD" . 2)
      ("LINK" . 31) ("LOCK" . 9) ("M-SEARCH" . 24) ("MERGE" . 23)
      ("MKACTIVITY" . 21) ("MKCALENDAR" . 30) ("MKCOL" . 10) ("MOVE" . 11)
      ("NOTIFY" . 25) ("OPTIONS" . 6) ("PATCH" . 28) ("PAUSE" . 39)
      ("PLAY" . 38) ("POST" . 3) ("PRI" . 34) ("PROPFIND" . 12)
      ("PROPPATCH" . 13) ("PURGE" . 29) ("PUT" . 4) ("QUERY" . 46)
      ("REBIND" . 17) ("RECORD" . 44) ("REDIRECT" . 43) ("REPORT" . 20)
      ("SEARCH" . 14) ("SET-PARAMETER" . 42) ("SETUP" . 37) ("SOURCE" . 33)
      ("SUBSCRIBE" . 26) ("TEARDOWN" . 40) ("TRACE" . 7) ("UNBIND" . 18)
      ("UNLINK" . 32) ("UNLOCK" . 15) ("UNSUBSCRIBE" . 27)))

  (define (method-number name)
    (let ((row (assoc name httparse-method-numbers)))
      (unless row
        (assertion-violation 'httparse-grammar "method has no llhttp number" name))
      (cdr row)))

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
  ;;
  ;; TWO FIELDS, TWO HOPS. The number is per NAME and the protocol mask is per
  ;; CLASS, so a table entry lands on its own number node and every number node
  ;; falls through to one of the four mask nodes -- 47 + 4 rather than 47 x 4.
  ;; A field-action node is zero-width, so the pair costs no byte.
  ;; Downcased: a node name is `[a-z][a-z0-9-]*` and a method name is not.
  ;; The 47 names stay distinct under downcasing, which the unit lane checks.
  (define (method-number-name name)
    (string->symbol (string-append "method-number-" (string-downcase name))))

  (define (method-number-nodes)
    (map (lambda (name)
           (make-field-action-node (method-number-name name) 'store
                                   (list 'method (method-number name))
                                   (method-store-name (method-mask name)) #f #f))
         httparse-method-names))

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
  ;;
  ;; THE ACCEPTED DIGITS ARE NOW ONE CASE EACH, not one byte-set case, because
  ;; each has to store its own value on the way through: `headers complete`
  ;; prints `v=%d/%d`. The rejected ones stay a single set -- a version that
  ;; fails never reaches the line that would print it.
  (define (version-minor-node name ok)
    (let ((bad (other-digits ok)))
      (make-byte-dispatch-node name
        (append
         (map (lambda (d)
                (make-byte-case (make-exact-byte-matcher (digit d))
                                (make-edge (version-minor-store-name d) 'advance) #f))
              ok)
         (if (null? bad) '()
             (list (make-byte-case (make-byte-set-matcher (map digit bad))
                                   (make-edge 'version-close-bad-version 'advance) #f))))
        (make-edge 'version-close-bad-minor 'reexecute) 'e-eof-version #f)))

  ;; The four accepted pairs are 0.9, 1.0, 1.1 and 2.0, so three majors and
  ;; three minors are storable; the sets are derived from the pairs rather than
  ;; written out, so adding a pair cannot forget its store node.
  (define httparse-version-pairs '((0 . 9) (1 . 0) (1 . 1) (2 . 0)))
  (define (distinct ns)
    (let loop ((ns ns) (acc '()))
      (cond ((null? ns) (list-sort < acc))
            ((member (car ns) acc) (loop (cdr ns) acc))
            (else (loop (cdr ns) (cons (car ns) acc))))))
  (define version-majors (distinct (map car httparse-version-pairs)))
  (define version-minors (distinct (map cdr httparse-version-pairs)))
  (define (version-minors-for major)
    (list-sort < (map cdr (filter (lambda (p) (= (car p) major))
                                  httparse-version-pairs))))
  (define (version-major-store-name d)
    (string->symbol (string-append "version-major-store-" (number->string d))))
  (define (version-minor-store-name d)
    (string->symbol (string-append "version-minor-store-" (number->string d))))
  (define (version-store-nodes)
    (append
     (map (lambda (d)
            (make-field-action-node (version-major-store-name d) 'store
                                    (list 'http-major d)
                                    (version-dot-name d) #f #f))
          version-majors)
     (map (lambda (d)
            (make-field-action-node (version-minor-store-name d) 'store
                                    (list 'http-minor d)
                                    'version-close #f #f))
          version-minors)))
  (define (version-dot-name d)
    (string->symbol (string-append "version-dot-" (number->string d))))
  (define (version-minor-name d)
    (string->symbol (string-append "version-minor-" (number->string d))))

  ;; Every node the version pair needs, generated from the pair list: a store
  ;; per storable digit, a dot node and a minor node per accepted major, and
  ;; the `other` pair that exists only to fail.
  (define (version-nodes)
    (append
     (version-store-nodes)
     (map (lambda (d) (version-dot-node (version-dot-name d) (version-minor-name d)))
          version-majors)
     (map (lambda (d) (version-minor-node (version-minor-name d) (version-minors-for d)))
          version-majors)
     (list (version-dot-node 'version-dot-other 'version-minor-other)
           (version-minor-node 'version-minor-other '()))))

  ;; An event invocation. `pause-continuation` is mandatory -- every callback
  ;; declares where to resume if it pauses -- and for an event that is the same
  ;; place `continue` goes, so a paused-then-resumed run re-enters the graph
  ;; exactly where an un-paused one would.
  (define (ev node callback continue)
    (make-callback-node node callback continue '() continue #f))

  (define (make-request-line-machine)
    (make-machine
     'httparse-request-line 'start
     ;; THE STATE `headers complete` PRINTS, plus the one that routes the
     ;; protocol check. llhttp's own callback reads `s->method, s->http_major,
     ;; s->http_minor, s->flags, s->content_length` and prints them, so these
     ;; four are named after its fields and the adapter reads them the same way
     ;; (decision 0014). `flags` needs ten bits -- TRANSFER_ENCODING is 1 << 9
     ;; -- and `content-length` is llhttp's uint64.
     (list (make-uint-field 'method-protocols 8 0 #f)
           (make-uint-field 'method 8 0 #f)
           (make-uint-field 'http-major 8 0 #f)
           (make-uint-field 'http-minor 8 0 #f)
           (make-uint-field 'flags 16 0 #f)
           (make-uint-field 'content-length 64 0 #f))
     (list (make-callback-declaration 'on-message-begin 'event #t '() #f #f)
           (make-callback-declaration 'on-method-data 'span-data #t '() #f #f)
           (make-callback-declaration 'on-method-complete 'event #t '() #f #f)
           (make-callback-declaration 'on-url-data 'span-data #t '() #f #f)
           (make-callback-declaration 'on-url-complete 'event #t '() #f #f)
           (make-callback-declaration 'on-protocol-data 'span-data #t '() #f #f)
           (make-callback-declaration 'on-protocol-complete 'event #t '() #f #f)
           (make-callback-declaration 'on-version-data 'span-data #t '() #f #f)
           (make-callback-declaration 'on-version-complete 'event #t '() #f #f)
           (make-callback-declaration 'on-header-field-data 'span-data #t '() #f #f)
           (make-callback-declaration 'on-header-field-complete 'event #t '() #f #f)
           (make-callback-declaration 'on-header-value-data 'span-data #t '() #f #f)
           (make-callback-declaration 'on-header-value-complete 'event #t '() #f #f)
           (make-callback-declaration 'on-headers-complete 'event #t '() #f #f)
           (make-callback-declaration 'on-message-complete 'event #t '() #f #f))
     (list (make-span-declaration 'method-span 'on-method-data #f #f)
           (make-span-declaration 'url-span 'on-url-data #f #f)
           (make-span-declaration 'protocol-span 'on-protocol-data #f #f)
           (make-span-declaration 'version-span 'on-version-data #f #f)
           (make-span-declaration 'header-field-span 'on-header-field-data #f #f)
           (make-span-declaration 'header-value-span 'on-header-value-data #f #f))
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
                                   "Expected CRLF after version" #f)
           ;; --- the header section -----------------------------------------
           ;; Four llhttp reasons share code 10 here and are four declarations,
           ;; per decision 0013.
           (make-error-declaration 'unexpected-space 'unexpected-space
                                   "Unexpected space after start line" #f)
           (make-error-declaration 'bad-header-field-char 'invalid-header-token
                                   "Invalid header field char" #f)
           (make-error-declaration 'bad-header-token 'invalid-header-token
                                   "Invalid header token" #f)
           (make-error-declaration 'bad-header-value-char 'invalid-header-token
                                   "Invalid header value char" #f)
           (make-error-declaration 'ws-after-value 'invalid-header-token
                                   "Unexpected whitespace after header value" #f)
           (make-error-declaration 'lf-after-cr-in-value 'strict
                                   "Expected LF after CR" #f)
           (make-error-declaration 'cr-after-value 'cr-expected
                                   "Missing expected CR after header value" #f)
           (make-error-declaration 'lf-after-value 'lf-expected
                                   "Missing expected LF after header value" #f)
           (make-error-declaration 'lf-after-headers 'strict
                                   "Expected LF after headers" #f))
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
                                   (method-number-name name) #f))
             httparse-method-names)
        (make-edge 'e-bad-method-open 'reexecute)
        'e-eof-method #f #f))
      ;; one node per name for the number, then one per distinct mask
      (method-number-nodes)
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
        (append
         (map (lambda (d)
                (make-byte-case (make-exact-byte-matcher (digit d))
                                (make-edge (version-major-store-name d) 'advance) #f))
              version-majors)
         (list (make-byte-case
                (make-byte-set-matcher (map digit (other-digits version-majors)))
                (make-edge 'version-dot-other 'advance) #f)))
        (make-edge 'version-close-bad-major 'reexecute) 'e-eof-version #f))
      (version-nodes)
      (list
      (make-span-end-node 'version-close 'version-span 'version-complete #f)
      (make-span-end-node 'version-close-bad-major 'version-span 'e-bad-major #f)
      (make-span-end-node 'version-close-expected-dot 'version-span 'e-expected-dot #f)
      (make-span-end-node 'version-close-bad-minor 'version-span 'e-bad-minor #f)
      (make-span-end-node 'version-close-bad-version 'version-span 'e-bad-version #f)
      (ev 'version-complete 'on-version-complete 'expect-cr)

      ;; --- CRLF ---------------------------------------------------------------
      ;; Strict: a bare CR or a bare LF is a line-ending error, not a newline.
      ;; A BARE LF IS CONSUMED BEFORE IT FAILS, and an unrelated byte is not.
      ;; llhttp `.match('\n', ...)` into a lenient test that strict mode
      ;; refuses, and a match consumes; its `.otherwise` does not. So the two
      ;; failures land one byte apart, and request/invalid.md#21 records the
      ;; difference: version complete at 15, error at 16.
      (make-byte-dispatch-node 'expect-cr
        (list (make-byte-case (make-exact-byte-matcher CR)
                              (make-edge 'expect-lf 'advance) #f)
              (make-byte-case (make-exact-byte-matcher LF)
                              (make-edge 'e-no-crlf 'advance) #f))
        (make-edge 'e-no-crlf 'reexecute) 'e-eof-none #f)
      (make-byte-dispatch-node 'expect-lf
        (list (make-byte-case (make-exact-byte-matcher LF)
                              (make-edge 'headers-start 'advance) #f))
        (make-edge 'e-lf-after-cr 'reexecute) 'e-eof-none #f)
      ;; --- the header section -------------------------------------------------
      ;;
      ;; Strict throughout. Every lenient arm of llhttp's header machine is an
      ;; error here -- decision 0009's scope, not a simplification. OBS-FOLD IS
      ;; REJECTED in two places: `value-discard-lws` after an empty value and
      ;; `value-lws` after a non-empty one, which are llhttp's two
      ;; LENIENT_FLAGS.HEADERS arms and carry different reasons.
      ;;
      ;; FIELD NAMES ARE OPAQUE. llhttp routes `Connection`, `Content-Length`
      ;; and `Transfer-Encoding` through a special-header table that changes
      ;; what a space before the colon does; that table, and the framing it
      ;; feeds, is M4's. Here every name is a general one.
      ;; The space is CONSUMED before it fails -- llhttp `.match`es it into a
      ;; lenient test strict mode refuses, and a match consumes. So the error
      ;; is one past it: request/invalid.md#20 records `off=17` for a space at
      ;; 16. The same trap as the bare LF after the version.
      (make-byte-dispatch-node 'headers-start
        (list (make-byte-case (make-exact-byte-matcher SP)
                              (make-edge 'e-unexpected-space 'advance) #f))
        (make-edge 'header-field-start 'reexecute) 'e-eof-none #f)

      ;; Three ways a field can fail to start, each with its own reason: a bare
      ;; LF is `Invalid header field char`, a leading colon is `Invalid header
      ;; token`, and CR begins the empty line that ends the section.
      (make-byte-dispatch-node 'header-field-start
        (list (make-byte-case (make-exact-byte-matcher CR)
                              (make-edge 'headers-almost-done 'advance) #f)
              (make-byte-case (make-exact-byte-matcher LF)
                              (make-edge 'e-bad-header-field-char 'advance) #f)
              (make-byte-case (make-exact-byte-matcher COLON)
                              (make-edge 'e-bad-header-token 'reexecute) #f))
        (make-edge 'header-field-open 'reexecute) 'e-eof-none #f)

      (make-span-start-node 'header-field-open 'header-field-span 'header-field-loop #f)
      (make-byte-dispatch-node 'header-field-loop
        (list (make-byte-case (make-byte-set-matcher httparse-tchar-bytes)
                              (make-edge 'header-field-loop 'advance) #f))
        (make-edge 'after-field-name 'reexecute) 'e-eof-header-field #f)

      ;; A name not followed by a colon errors WITH THE SPAN OPEN, so no
      ;; fragment is delivered: `Fo@: Failure` records no `span[header_field]`
      ;; at all, only the error at the `@` (request/invalid.md#11).
      (make-byte-dispatch-node 'after-field-name
        (list (make-byte-case (make-exact-byte-matcher COLON)
                              (make-edge 'header-field-close 'reexecute) #f))
        (make-edge 'e-bad-header-token-open 'reexecute) 'e-eof-header-field #f)
      ;; The span ends BEFORE the colon and the colon is then consumed, so
      ;; `header_field complete` fires one byte past it -- the same asymmetry
      ;; `url complete` has. `Line1:` records the span at 16 len 5 and the
      ;; event at 22, with the colon at 21.
      (make-span-end-node 'header-field-close 'header-field-span 'eat-colon #f)
      (make-byte-dispatch-node 'eat-colon
        (list (make-byte-case (make-exact-byte-matcher COLON)
                              (make-edge 'header-field-complete 'advance) #f))
        (make-edge 'e-bad-header-token 'reexecute) 'e-eof-none #f)
      (ev 'header-field-complete 'on-header-field-complete 'value-discard-ws)

      ;; --- the value ----------------------------------------------------------
      ;; Leading OWS is discarded and is not part of the span.
      (make-byte-dispatch-node 'value-discard-ws
        (list (make-byte-case (make-byte-set-matcher (list SP HTAB))
                              (make-edge 'value-discard-ws 'advance) #f)
              (make-byte-case (make-exact-byte-matcher CR)
                              (make-edge 'value-discard-ws-cr 'advance) #f)
              (make-byte-case (make-exact-byte-matcher LF)
                              (make-edge 'e-bad-header-value-char 'advance) #f))
        (make-edge 'value-open 'reexecute) 'e-eof-none #f)

      (make-byte-dispatch-node 'value-discard-ws-cr
        (list (make-byte-case (make-exact-byte-matcher LF)
                              (make-edge 'value-discard-lws 'advance) #f))
        (make-edge 'e-lf-after-cr-in-value 'reexecute) 'e-eof-none #f)

      ;; Obs-fold, first site: a continuation line after an EMPTY value. The
      ;; whitespace is CONSUMED before it fails (llhttp `.match`es it), unlike
      ;; the second site below, which peeks.
      (make-byte-dispatch-node 'value-discard-lws
        (list (make-byte-case (make-byte-set-matcher (list SP HTAB))
                              (make-edge 'e-bad-header-value-char 'advance) #f))
        (make-edge 'value-empty-open 'reexecute) 'e-eof-none #f)

      ;; An empty value is ANNOUNCED, not omitted: llhttp opens and immediately
      ;; closes the span, which is the upstream empty-span behaviour this
      ;; project asked for and picked up at v0.2.0.
      (make-span-start-node 'value-empty-open 'header-value-span 'value-empty-close #f)
      (make-span-end-node 'value-empty-close 'header-value-span 'value-complete #f)

      (make-span-start-node 'value-open 'header-value-span 'value-loop #f)
      (make-byte-dispatch-node 'value-loop
        (list (make-byte-case (make-byte-set-matcher httparse-header-bytes)
                              (make-edge 'value-loop 'advance) #f))
        (make-edge 'after-value 'reexecute) 'e-eof-header-value #f)

      ;; All three arms close the span first and differ in what follows. A bare
      ;; LF is `Missing expected CR after header value` AT the LF, unconsumed.
      (make-byte-dispatch-node 'after-value
        (list (make-byte-case (make-exact-byte-matcher CR)
                              (make-edge 'value-close 'reexecute) #f)
              (make-byte-case (make-exact-byte-matcher LF)
                              (make-edge 'value-close-no-cr 'reexecute) #f))
        (make-edge 'value-close-bad 'reexecute) 'e-eof-header-value #f)
      (make-span-end-node 'value-close 'header-value-span 'eat-cr #f)
      (make-span-end-node 'value-close-no-cr 'header-value-span 'e-cr-after-value #f)
      (make-span-end-node 'value-close-bad 'header-value-span 'e-bad-header-value-char #f)
      (make-byte-dispatch-node 'eat-cr
        (list (make-byte-case (make-exact-byte-matcher CR)
                              (make-edge 'value-almost-done 'advance) #f))
        (make-edge 'e-cr-after-value 'reexecute) 'e-eof-none #f)

      (make-byte-dispatch-node 'value-almost-done
        (list (make-byte-case (make-exact-byte-matcher LF)
                              (make-edge 'value-lws 'advance) #f))
        (make-edge 'e-lf-after-value 'reexecute) 'e-eof-none #f)

      ;; Obs-fold, second site: a continuation line after a NON-EMPTY value.
      ;; llhttp's reason differs from the empty-value one.
      (make-byte-dispatch-node 'value-lws
        (list (make-byte-case (make-byte-set-matcher (list SP HTAB))
                              (make-edge 'e-ws-after-value 'reexecute) #f))
        (make-edge 'value-complete 'reexecute) 'e-eof-none #f)
      (ev 'value-complete 'on-header-value-complete 'header-field-start)

      ;; --- the empty line ------------------------------------------------------
      (make-byte-dispatch-node 'headers-almost-done
        (list (make-byte-case (make-exact-byte-matcher LF)
                              (make-edge 'headers-complete 'advance) #f))
        (make-edge 'e-lf-after-headers 'reexecute) 'e-eof-none #f)
      (ev 'headers-complete 'on-headers-complete 'after-headers)

      ;; --- is there a body? ----------------------------------------------------
      ;;
      ;; llhttp asks a C callback, `llhttp__after_headers_complete`, and for a
      ;; REQUEST its answer collapses to a short tree: `message_needs_eof` is
      ;; unconditionally 0 for requests, and upgrade and skip-body are a later
      ;; milestone's. What is left is
      ;;
      ;;   CHUNKED                      -> read chunks
      ;;   TRANSFER_ENCODING, not chunked -> error, a request may not say that
      ;;   CONTENT_LENGTH and nonzero   -> read that many bytes
      ;;   otherwise                    -> no body
      ;;
      ;; M4 Slice 0 sets no flag and accumulates no length, so every message
      ;; takes the last arm. The branch nodes arrive with the slices that can
      ;; make their conditions true; putting them here now would be three
      ;; unreachable nodes, which the verifier refuses anyway.
      (ev 'after-headers 'on-message-complete 'after-message)

      ;; A TERMINAL CANNOT SIT DIRECTLY BEHIND A ZERO-WIDTH EVENT. A stop behind
      ;; one is EOF-reachable (`eof-reachable-stop`) and a finish behind one is
      ;; byte-reachable (`non-eof-into-finish`) -- the verifier refuses both,
      ;; and the request line's stop tripped neither because it sat directly
      ;; behind a consumed byte. A dispatch separates them: end of input after
      ;; a complete message is clean, and a byte is the next message, which is
      ;; the pipelining milestone's.
      (make-byte-dispatch-node 'after-message
        '()
        (make-edge 'message-done 'reexecute) 'clean-eof #f)
      (make-stop-node 'message-done #f)

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
      (make-error-node 'e-eof-version 'eof #f)
      (make-error-node 'e-unexpected-space 'unexpected-space #f)
      (make-error-node 'e-bad-header-field-char 'bad-header-field-char #f)
      (make-error-node 'e-bad-header-token 'bad-header-token #f)
      ;; The same reason reached with the field span OPEN -- a separate node
      ;; because the verifier's flat lattice refuses one node reached with two
      ;; span states, and the open one is what keeps `Fo@: Failure` from
      ;; delivering a fragment.
      (make-error-node 'e-bad-header-token-open 'bad-header-token #f)
      (make-error-node 'e-bad-header-value-char 'bad-header-value-char #f)
      (make-error-node 'e-ws-after-value 'ws-after-value #f)
      (make-error-node 'e-lf-after-cr-in-value 'lf-after-cr-in-value #f)
      (make-error-node 'e-cr-after-value 'cr-after-value #f)
      (make-error-node 'e-lf-after-value 'lf-after-value #f)
      (make-error-node 'e-lf-after-headers 'lf-after-headers #f)
      (make-error-node 'e-eof-header-field 'eof #f)
      (make-error-node 'e-eof-header-value 'eof #f)))
     'eof #f)))
