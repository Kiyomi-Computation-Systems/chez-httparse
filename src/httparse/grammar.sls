;;; (httparse grammar): the HTTP/1 grammar, as a byte-machine source machine.
;;;
;;; BUILD TIME ONLY. This library constructs the source IR; it is never loaded
;;; by a running parser. A generated parser depends on (byte-machine runtime)
;;; and nothing else.
;;;
;;; Both start lines -- a request's `method SP request-target SP HTTP-version
;;; CRLF` and a response's `HTTP-version SP status-code [SP reason] CRLF`,
;;; with the method and the protocol matched against llhttp's constant tables
;;; -- the header section, strictly, and the framing that section decides: a
;;; field NAME selects a value machine, `Content-Length` measures a body, and
;;; `Transfer-Encoding`, `Connection` and `Upgrade` set the FLAGS bits that
;;; `headers complete` prints -- the chunked body those bits can ask for,
;;; extensions and trailers included, and the body a response can have that
;;; ends with the connection instead -- and the loop back to the next message.
;;;
;;; THIS IS EVERY STRICT FIXTURE llhttp'S CORPUS RECORDS, request and response
;;; alike. What is still to come is the url sub-parser's structure, pausing,
;;; skip-body and the lenient modes.
;;;
;;; THE TWO KINDS SHARE EVERYTHING BUT THEIR FIRST LINE, and rather more of
;;; that than llhttp does. Its `req_after_http_start` and `res_after_start`
;;; are the same three constants and the same span; its two version blocks are
;;; the same four accepted pairs and the same three malformations. Each is ONE
;;; definition here with a zero-width branch on `type` where llhttp forks, so
;;; a response cannot drift from a request over what `HTTP` is or which
;;; versions are legal. Everything from `headers-start` on was already shared.
;;;
;;; WHICH KIND IT IS, IS ANSWERED AND NOT READ. llhttp loads a field its
;;; embedder wrote; byte-machine's runtime has no field writer, so the same
;;; configuration arrives as a DECISION callback and its branches store
;;; llhttp's own number -- decision 0017. Everything downstream reads the
;;; field, including the `headers complete` line, which llhttp's own callback
;;; renders from `s->type` too.
;;;
;;; THE HEADER SECTION IS PARSED TWICE, by the same states. A chunked
;;; message's trailers re-enter `header-field-start`, and the flag the zero
;;; chunk sets is the only thing that tells the empty line at the end which
;;; block it just closed.
;;;
;;; SO IS THE WHOLE MESSAGE. A message that keeps the connection alive clears
;;; the flags and returns to `start`, where a second one begins -- and the
;;; only thing separating a restart from a first start is a field, which is
;;; what makes `reset` fire between two messages and not before the first.
;;;
;;; A RESPONSE NEED NOT SAY HOW LONG ITS BODY IS, and that is the one shape a
;;; request cannot have. `message_needs_eof` decides, and its answer decides
;;; twice: whether there is a body to read at all, and whether there is a next
;;; message. A body it sends to `body-eof` opens a span that never closes and
;;; fires no `message complete` -- what ends such a message is the connection,
;;; which is a fact the parser is told rather than one it reads.
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
;;; input inside each span needs its own node even though they all name one
;;; `invalid-eof-state` declaration -- and so does a refusal two productions can
;;; reach with different spans open. The error codes and reasons are llhttp's
;;; own, per decision 0013 -- identity is the (code, reason) pair, because
;;; eight of its codes carry more than one reason. ONE declaration here has no
;;; llhttp number, deliberately: `unexpected-message-type`, because llhttp
;;; cannot reach that state -- the embedder writes the type, so no answer lands
;;; there. The finish-from-unsafe error was numberless too until #42, when it
;;; took llhttp's own `invalid-eof-state` (14); the corpus still never finishes
;;; to witness it, but `unit.finish` does.
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
;;; value" -- which is why 0013 makes the pair the identity. The status line
;;; has the same pair a fourth time, `res_status_code_otherwise`'s matched LF
;;; against its `.otherwise`, and there NO FIXTURE LOOKS: both carry
;;; "Invalid response status", which the corpus never records.
(library (httparse grammar)
  (export make-message-machine
          httparse-tchar-bytes httparse-header-bytes
          httparse-method-names httparse-method-numbers
          httparse-http-methods httparse-rtsp-methods httparse-ice-methods
          method-name->identifier)
  (import (rnrs) (byte-machine graph)
          (httparse modes) (httparse methods) (httparse decisions)
          (httparse url-grammar))

  (define (range lo hi)
    (let loop ((i hi) (acc '())) (if (< i lo) acc (loop (- i 1) (cons i acc)))))

  ;; tchar = ALPHA / DIGIT / "!#$%&'*+-.^_`|~"  (RFC 9110 5.6.2)
  (define httparse-tchar-bytes
    (append '(33 35 36 37 38 39 42 43 45 46 94 95 96 124 126)
            (range 48 57) (range 65 90) (range 97 122)))

  ;; What may appear in a header value: llhttp's HEADER_CHARS, which is
  ;; HTAB / SP / VCHAR / obs-text. Excluded are NUL, the C0 controls other than
  ;; HTAB, DEL, and -- the two that matter -- CR and LF, which is what makes the
  ;; loop stop at its own line ending.
  (define httparse-header-bytes
    (append '(9 32) (range 33 126) (range 128 255)))

  ;; llhttp's RELAXED_HEADER_CHARS: HEADER_CHARS plus the C0 controls and DEL,
  ;; which is every byte EXCEPT NUL, CR and LF. Its own comment says so.
  (define httparse-relaxed-header-bytes
    (append (range 1 9) '(11 12) (range 14 255)))

  (define COMMA 44)
  (define SP 32)
  (define CR 13)
  (define LF 10)
  (define SLASH 47)
  (define HTAB 9)
  (define COLON 58)

  ;; --- the method table ---------------------------------------------------
  ;;
  ;; `httparse-method-names` and `httparse-method-numbers` are llhttp's, and
  ;; they now live in the pure `(httparse methods)` library, imported above and
  ;; re-exported below so there is ONE source: an embedder reads the same two
  ;; tables at run time without pulling in `(byte-machine graph)`, exactly as
  ;; `(httparse modes)` is threaded in. What stays here is only how the grammar
  ;; CONSUMES them.
  ;;
  ;; llhttp matches the method against a TABLE, not against `1*tchar`, and the
  ;; difference is observable: `MKCOLA / HTTP/1.1` records
  ;; `span[method]="MKCOL"` and then `error code=6 "Expected space after
  ;; method"` at offset 5. A tchar loop would take `MKCOLA` whole and accept it.
  ;; The union is all 47 names, RTSP and HTTP/2 included: the corpus shows
  ;; `ANNOUNCE` (RTSP-only) parsed into a method span and rejected only later,
  ;; by the method-versus-protocol rule, so the matcher accepts it.
  ;;
  ;; WHY `keyword-table` AND NOT `make-sequence-dispatch-node`. Sequence
  ;; dispatch rejects a case list where one entry is a proper prefix of another
  ;; (`ambiguous-sequence-prefix`), and `GET` is a proper prefix of
  ;; `GET_PARAMETER` -- the only such pair across the 47, and one is enough.
  ;; `keyword-table` tolerates proper prefixes: the longer wins when the input
  ;; reaches it, the shorter when the next byte cannot extend it, and the
  ;; closing byte is reexecuted so the span ends at the keyword's own length.
  ;; That is what makes `MKCOLA` close the span at MKCOL and fail after it.

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
    '("ANNOUNCE" "DESCRIBE" "FLUSH" "GET" "GET_PARAMETER" "OPTIONS"
      "PAUSE" "PLAY" "POST" "RECORD" "REDIRECT" "SET_PARAMETER" "SETUP"
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
  ;; method-name->identifier : String -> String
  ;; A generated node name must be [a-z][a-z0-9-]*, and two of llhttp's method
  ;; names are not: `M-SEARCH` carries a hyphen, which is fine, and
  ;; `GET_PARAMETER` and `SET_PARAMETER` carry an UNDERSCORE, which the
  ;; generator refuses as unportable. Both separators fold to `-` here. That
  ;; is only safe while no two method names differ by nothing else, which is
  ;; a property of the list rather than of this function -- so the lane
  ;; checks it against this very procedure rather than against downcasing.
  (define (method-name->identifier name)
    (list->string
     (map (lambda (ch) (if (char=? ch #\_) #\- ch))
          (string->list (string-downcase name)))))

  (define (method-number-name name)
    (string->symbol (string-append "method-number-" (method-name->identifier name))))

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

  ;; --- llhttp's HEADER_STATE and FLAGS -------------------------------------
  ;;
  ;; Both are llhttp's own numbering, not ours, because both are OBSERVABLE:
  ;; `flags=%x` is printed verbatim on the `headers complete` line, and
  ;; `header_state` decides which value machine a field name selects. Renaming
  ;; either would mean the adapter had to translate a number back, which is a
  ;; computation it may not do (decision 0014).
  ;;
  ;; The FLAGS bits (`F-*`) now live in the pure `(httparse decisions)` library,
  ;; imported above: the grammar SETS them with its set-mask nodes, and an
  ;; embedder reads the same bits to decide keep-alive vs close -- one
  ;; definition, threaded in as `(httparse modes)` is. HEADER_STATE stays here;
  ;; it is internal to how a field name selects a value machine and nothing
  ;; outside the grammar reads it.
  (define HS-GENERAL 0)
  (define HS-CONNECTION 1)
  (define HS-CONTENT-LENGTH 2)
  (define HS-TRANSFER-ENCODING 3)
  (define HS-UPGRADE 4)
  (define HS-CONNECTION-KEEP-ALIVE 5)
  (define HS-CONNECTION-CLOSE 6)
  (define HS-CONNECTION-UPGRADE 7)
  (define HS-TRANSFER-ENCODING-CHUNKED 8)

  ;; llhttp's LENIENT_FLAGS, its own `i16 lenient_flags` and NOT part of
  ;; `flags`: the restart between two messages stores zero over `flags`, and a
  ;; mode the embedder chose must survive that. Upstream keeps them apart for
  ;; the same reason.
  ;;
  ;; THE FIELD IS SETTABLE AND THE EMBEDDER WRITES IT AT `make-parser`, which
  ;; is what llhttp does. It was eleven optional decision callbacks and
  ;; twenty-two entry nodes until byte-machine v0.5.0 -- the price of a
  ;; runtime with no way to start a parser in a mode, and the subject of this
  ;; project's fourth upstream brief. `parser-reset!` restores the embedder's
  ;; value, so the mode still survives a restart; it survives it as a field
  ;; initial now rather than as a chain the restart jumps over.
  ;;
  ;; The bit numbers are llhttp's and live in `(httparse modes)`, which the
  ;; harness and an embedder import too -- so the grammar that reads a bit and
  ;; the caller that sets it cannot hold different numbers.
  (define (lenient-bit name) (httparse-lenient-bit name))

  ;; lenient-fork : Symbol Symbol NodeName NodeName -> FieldBranchNode
  ;; llhttp's `testLenientFlags(FLAG, {1: lenient}, strict)`, which is a mask
  ;; test and nothing else. Every leniency in the grammar is one of these, so
  ;; the flag is read in exactly one shape.
  (define (lenient-fork name flag lenient strict)
    (make-field-branch-node name 'mask-any (list 'lenient-flags (lenient-bit flag))
                            lenient strict #f))

  ;; llhttp's TYPE. It is not derived from the input: the EMBEDDER sets it
  ;; before the first byte, and llhttp's own fixture harness does exactly that
  ;; -- `llhttp__test_init_response` is one line, `s->type = HTTP_RESPONSE`.
  ;; BOTH is llhttp's default and is NOT v0.1's: its `start_req_or_res` opens a
  ;; METHOD span on `H` and matches `HTTP/` inside it, so a response parsed
  ;; that way records `span[method]="HTTP/"` where every response fixture in
  ;; the corpus records `span[protocol]="HTTP"`. The value is here because the
  ;; `headers complete` line is rendered from it, exactly as llhttp's own
  ;; callback branches on `s->type` -- not because any byte sets it.
  (define TYPE-BOTH (httparse-message-type-value 'both))
  (define TYPE-REQUEST (httparse-message-type-value 'request))
  (define TYPE-RESPONSE (httparse-message-type-value 'response))

  ;; llhttp's FINISH, printed verbatim by the fixture harness as
  ;; `off=NULL finish=N`. SAFE-WITH-CB is a RESPONSE's: a body that runs to
  ;; end of input is COMPLETE when the input stops, but only if someone tells
  ;; the parser the input stopped -- which is the whole difference between it
  ;; and SAFE. `response/finish.md#1` is the fixture that prints it.
  (define FINISH-SAFE 0)
  (define FINISH-SAFE-WITH-CB 1)
  (define FINISH-UNSAFE 2)

  ;; llhttp's HEX_MAP as a byte set: both cases, which `request/transfer-
  ;; encoding.md#3` and `#4` establish by differing in nothing but that byte.
  ;; Only the overflow shim needs the set spelled out -- the accumulator reads
  ;; the same bytes from its base.
  (define httparse-hex-bytes
    (append (range 48 57) (range 97 102) (range 65 70)))

  (define DQUOTE 34)
  (define BACKSLASH 92)
  (define SEMICOLON 59)
  (define EQUALS 61)

  ;; llhttp's QDTEXT: the header bytes without the two a quoted string gives a
  ;; meaning of its own. Derived from the same list rather than transcribed, so
  ;; the two sets cannot drift apart -- and what llhttp allows after a
  ;; backslash is the WHOLE header set, these two included.
  (define httparse-qdtext-bytes
    (filter (lambda (b) (not (or (= b DQUOTE) (= b BACKSLASH))))
            httparse-header-bytes))


  ;; llhttp's SPECIAL_HEADERS: the five field names that select a value machine
  ;; rather than being copied through. `proxy-connection` shares CONNECTION's
  ;; state, so five names collapse to four store nodes.
  ;;
  ;; THE TABLE IS CASE-FOLDED, which is the second of the two reasons this
  ;; project asked for a keyword-table primitive upstream: llhttp lowercases
  ;; the field name before matching it, and `make-sequence-case` takes exact
  ;; bytes. The SPAN still carries the bytes as they arrived.
  (define httparse-special-headers
    (list (cons "connection" HS-CONNECTION)
          (cons "content-length" HS-CONTENT-LENGTH)
          (cons "proxy-connection" HS-CONNECTION)
          (cons "transfer-encoding" HS-TRANSFER-ENCODING)
          (cons "upgrade" HS-UPGRADE)))

  ;; llhttp's CONNECTION_TOKEN_CHARS: the header bytes minus the one that
  ;; separates the tokens. Derived rather than transcribed, so the two sets
  ;; cannot drift apart.
  (define httparse-connection-token-bytes
    (filter (lambda (b) (not (= b COMMA))) httparse-header-bytes))

  (define (header-state-store-name v)
    (string->symbol (string-append "header-state-store-" (number->string v))))

  (define header-state-values
    (let loop ((rows httparse-special-headers) (acc '()))
      (cond ((null? rows) (list-sort < acc))
            ((member (cdar rows) acc) (loop (cdr rows) acc))
            (else (loop (cdr rows) (cons (cdar rows) acc))))))

  ;; llhttp's `select(SPECIAL_HEADERS, store('header_state', 'header_field_colon'))`
  (define (header-state-store-nodes)
    (map (lambda (v)
           (make-field-action-node (header-state-store-name v) 'store
                                   (list 'header-state v)
                                   'header-field-colon #f #f))
         header-state-values))

  ;; The three Connection keywords store their sub-state and continue at the
  ;; token separator rather than at the colon, so they need their own store
  ;; nodes rather than the field table's.
  (define (conn-state-store-name v)
    (string->symbol (string-append "conn-state-store-" (number->string v))))
  (define connection-keyword-states
    (list (cons "close" HS-CONNECTION-CLOSE)
          (cons "upgrade" HS-CONNECTION-UPGRADE)
          (cons "keep-alive" HS-CONNECTION-KEEP-ALIVE)))
  (define (conn-state-store-nodes)
    (map (lambda (row)
           (make-field-action-node (conn-state-store-name (cdr row)) 'store
                                   (list 'header-state (cdr row)) 'conn-ws #f #f))
         connection-keyword-states))

  ;; llhttp's `setHeaderFlags`: a connection sub-state becomes a flag bit and
  ;; collapses back to CONNECTION, and the chunked sub-state becomes CHUNKED.
  ;; This is why `Connection: close, token, upgrade, token, keep-alive` ends at
  ;; flags=7 -- the chain runs once per comma and once at the end of the value.
  ;;
  ;; THREE CALL SITES, THREE COPIES, AND NOT BY CHOICE. The value span is open
  ;; at one of them and closed at the other two, and the verifier's flat span
  ;; lattice refuses one node reached with two different span states. So the
  ;; chain is generated from a prefix and a continuation.
  (define (set-header-flags-nodes prefix next)
    (define (nm suffix) (string->symbol (string-append prefix "-" suffix)))
    (list
     (make-field-branch-node (nm "keep-alive") 'equal
                             (list 'header-state HS-CONNECTION-KEEP-ALIVE)
                             (nm "set-keep-alive") (nm "close") #f)
     (make-field-action-node (nm "set-keep-alive") 'set-mask
                             (list 'flags F-CONNECTION-KEEP-ALIVE)
                             (nm "to-connection") #f #f)
     (make-field-branch-node (nm "close") 'equal
                             (list 'header-state HS-CONNECTION-CLOSE)
                             (nm "set-close") (nm "upgrade") #f)
     (make-field-action-node (nm "set-close") 'set-mask
                             (list 'flags F-CONNECTION-CLOSE)
                             (nm "to-connection") #f #f)
     (make-field-branch-node (nm "upgrade") 'equal
                             (list 'header-state HS-CONNECTION-UPGRADE)
                             (nm "set-upgrade") (nm "chunked") #f)
     (make-field-action-node (nm "set-upgrade") 'set-mask
                             (list 'flags F-CONNECTION-UPGRADE)
                             (nm "to-connection") #f #f)
     (make-field-branch-node (nm "chunked") 'equal
                             (list 'header-state HS-TRANSFER-ENCODING-CHUNKED)
                             (nm "set-chunked") next #f)
     (make-field-action-node (nm "set-chunked") 'set-mask
                             (list 'flags F-CHUNKED) next #f #f)
     ;; NO CHECK COVERS THIS LINE, and the mutation that changes it survives
     ;; both lanes. Collapsing to CONNECTION rather than to GENERAL is
     ;; unobservable in strict REQUEST parsing: the chain above tests only the
     ;; four sub-states, so 1 and 0 fall through it alike, and the field table
     ;; overwrites the state at the next name either way. It is llhttp's value
     ;; and it stays, because the obs-fold arm that reads it back is a lenient
     ;; mode's and responses reach it differently. The slice that makes it
     ;; observable owes this line a test.
     (make-field-action-node (nm "to-connection") 'store
                             (list 'header-state HS-CONNECTION) next #f #f)))

  (define (set-header-flags-entry prefix)
    (string->symbol (string-append prefix "-keep-alive")))

  (define DIGITS '(0 1 2 3 4 5 6 7 8 9))

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

  ;; STORE FIRST, CHECK AFTER -- which is llhttp's shape and was not this
  ;; grammar's. Both digits are stored whatever they are, and the PAIR is
  ;; judged by a separate chain afterwards (`checkVersion`). The older shape
  ;; fused the two: only a digit belonging to an accepted pair had a store
  ;; node, and every other digit fell into a subgraph that existed to fail. It
  ;; produced the same three errors at the same three offsets, and it could
  ;; not produce `v=5/6` -- so the moment a lenient parse had to PRINT a
  ;; version it rejects, the fusion had to come apart.
  (define all-digits '(0 1 2 3 4 5 6 7 8 9))

  (define (version-minor-node name)
    (make-byte-dispatch-node name
      (map (lambda (d)
             (make-byte-case (make-exact-byte-matcher (digit d))
                             (make-edge (version-minor-store-name d) 'advance) #f))
           all-digits)
      (make-edge 'version-close-bad-minor 'reexecute) 'e-eof-version #f))

  ;; The four accepted pairs are 0.9, 1.0, 1.1 and 2.0. The CHECK is derived
  ;; from this list rather than written out, so adding a pair cannot forget to
  ;; accept it.
  (define httparse-version-pairs '((0 . 9) (1 . 0) (1 . 1) (2 . 0)))
  (define (distinct ns)
    (let loop ((ns ns) (acc '()))
      (cond ((null? ns) (list-sort < acc))
            ((member (car ns) acc) (loop (cdr ns) acc))
            (else (loop (cdr ns) (cons (car ns) acc))))))
  (define version-majors (distinct (map car httparse-version-pairs)))
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
                                    'version-dot #f #f))
          all-digits)
     (map (lambda (d)
            (make-field-action-node (version-minor-store-name d) 'store
                                    (list 'http-minor d)
                                    'version-check #f #f))
          all-digits)))

  ;; The pair check: one branch per accepted MAJOR, and under each, one per
  ;; minor that major accepts. A major with no row, or a minor its major does
  ;; not accept, falls through to the span end that reports `Invalid HTTP
  ;; version` -- which fires having consumed the minor digit, where the
  ;; malformed-minor error fires before it. That offset difference is the
  ;; reason the two are separate errors and not one.
  ;; THE CHAIN'S HEAD IS THE ENTRY, rather than an extra node in front of it:
  ;; a node that asked the first major's question again would be unreachable
  ;; the moment the chain asked it too, which is what the verifier said.
  (define (version-check-major-name d)
    (if (= d (car version-majors))
        'version-check-strict
        (string->symbol (string-append "version-check-major-" (number->string d)))))
  (define (version-check-minor-name major d)
    (string->symbol (string-append "version-check-" (number->string major)
                                   "-" (number->string d))))
  (define (version-check-nodes)
    (let* ((majors version-majors)
           (major-chain
            (let loop ((ms majors) (acc '()))
              (if (null? ms)
                  (reverse acc)
                  (let* ((d (car ms))
                         (next (if (null? (cdr ms))
                                   'version-close-bad-version
                                   (version-check-major-name (cadr ms)))))
                    (loop (cdr ms)
                          (cons (make-field-branch-node
                                 (version-check-major-name d) 'equal
                                 (list 'http-major d)
                                 (version-check-minor-name d (car (version-minors-for d)))
                                 next #f)
                                acc))))))
           (minor-chains
            (apply append
                   (map (lambda (major)
                          (let loop ((ns (version-minors-for major)) (acc '()))
                            (if (null? ns)
                                (reverse acc)
                                (let* ((d (car ns))
                                       (next (if (null? (cdr ns))
                                                 'version-close-bad-version
                                                 (version-check-minor-name
                                                  major (cadr ns)))))
                                  (loop (cdr ns)
                                        (cons (make-field-branch-node
                                               (version-check-minor-name major d) 'equal
                                               (list 'http-minor d)
                                               'version-close next #f)
                                              acc))))))
                        majors))))
      (append major-chain minor-chains)))

  ;; Every node the version pair needs: a store per digit, the one dot node,
  ;; the one minor node, and the pair check.
  (define (version-nodes)
    (append
     (version-store-nodes)
     (list (version-dot-node 'version-dot 'version-minor)
           (version-minor-node 'version-minor)
           ;; `checkVersion` TESTS THE FLAG FIRST and accepts the pair
           ;; unexamined when it is set -- llhttp's own order, and the reason
           ;; the digits had to be stored before they were judged.
           (lenient-fork 'version-check 'version
                         'version-close 'version-check-strict))
     (version-check-nodes)))

  ;; llhttp's `llhttp_message_needs_eof`, which is a pure question over the
  ;; parser's state and is asked from TWO places: the body decision, where a
  ;; response with no framing headers reads to end of input, and
  ;; `should_keep_alive`, whose last line is `!message_needs_eof(parser)`.
  ;;
  ;; TWO COPIES, AND NOT BY CHOICE -- the same reason `setHeaderFlags` has
  ;; three. A subgraph's exits are node names, so one shared copy could not
  ;; answer two callers; generating it from a prefix is what keeps the RULE
  ;; single even though the nodes are not.
  ;;
  ;; THE FIRST LINE IS THE ONE THAT IS MEASURED HARDEST. `if (type ==
  ;; HTTP_REQUEST) return 0` is why every pipelined request in the corpus
  ;; restarts: without it a request with no Content-Length would fall to the
  ;; final `return 1`, `should_keep_alive` would answer 0, and
  ;; `request/pipelining.md#1` would stop after its first message.
  (define (needs-eof-nodes prefix yes no)
    (define (nm suffix) (string->symbol (string-append prefix "-" suffix)))
    (list
     (make-field-branch-node (nm "request") 'equal (list 'type TYPE-REQUEST)
                             no (nm "informational") #f)
     ;; llhttp's `status_code / 100 == 1`, which is 100 through 199 and is
     ;; wider than the four exact codes the body decision tests.
     (make-field-branch-node (nm "informational") 'range (list 'status-code 100 199)
                             no (nm "no-content") #f)
     (make-field-branch-node (nm "no-content") 'equal (list 'status-code 204)
                             no (nm "not-modified") #f)
     (make-field-branch-node (nm "not-modified") 'equal (list 'status-code 304)
                             no (nm "coding") #f)
     ;; RFC 7230 3.3.3 again: a response that named a transfer coding NOT
     ;; ending in `chunked` has no length but the connection's.
     ;; NO PATH IN v0.1 REACHES THIS PAIR WITH ANYTHING TO DECIDE, and the
     ;; mutation that inverts the second survives every lane. The body
     ;; decision tests TRANSFER_ENCODING itself and routes both answers away
     ;; before it would ask, so the copy it owns always finds the bit clear;
     ;; and the copy `should_keep_alive` owns is only consulted about a
     ;; message that already COMPLETED, which one needing eof never does
     ;; without a `parser-finish!` the corpus never calls (decision 0016). It
     ;; is llhttp's rule and it stays whole: the milestone that adds a finish
     ;; makes it observable and owes it a test.
     (make-field-branch-node (nm "coding") 'mask-any (list 'flags F-TRANSFER-ENCODING)
                             (nm "coding-chunked") (nm "framed") #f)
     (make-field-branch-node (nm "coding-chunked") 'mask-any (list 'flags F-CHUNKED)
                             (nm "framed") yes #f)
     (make-field-branch-node (nm "framed") 'mask-any
                             (list 'flags (+ F-CHUNKED F-CONTENT-LENGTH))
                             no yes #f)))

  (define (needs-eof-entry prefix)
    (string->symbol (string-append prefix "-request")))

  ;; An event invocation. `pause-continuation` is mandatory -- every callback
  ;; declares where to resume if it pauses -- and for an event that is the same
  ;; place `continue` goes, so a paused-then-resumed run re-enters the graph
  ;; exactly where an un-paused one would.
  (define (ev node callback continue)
    (make-callback-node node callback continue '() continue #f))

  (define (make-message-machine)
    (make-machine
     'httparse-message 'start
     ;; THE STATE `headers complete` PRINTS, plus the one that routes the
     ;; protocol check. llhttp's own callback reads `s->method, s->http_major,
     ;; s->http_minor, s->flags, s->content_length` and prints them, so these
     ;; four are named after its fields and the adapter reads them the same way
     ;; (decision 0014). `flags` needs ten bits -- TRANSFER_ENCODING is 1 << 9
     ;; -- and `content-length` is llhttp's uint64.
     (list (make-uint-field 'lenient-flags httparse-lenient-flags-width 0 #t #f)
           (make-uint-field 'method-protocols 8 0 #f)
           (make-uint-field 'method 8 0 #f)
           ;; llhttp's `i8 type`, and its `i16 status_code`. The first is
           ;; SETTABLE and the embedder writes it at `make-parser`, exactly as
           ;; llhttp's does before the parse; the second is accumulated from
           ;; the three digits of the status line. Both are printed: `headers
           ;; complete` carries one OR the other, chosen by `type`, which is
           ;; what llhttp's own callback does.
           (make-uint-field 'type 8 TYPE-BOTH #t #f)
           (make-uint-field 'status-code 16 0 #f)
           (make-uint-field 'http-major 8 0 #f)
           (make-uint-field 'http-minor 8 0 #f)
           (make-uint-field 'flags 16 0 #f)
           (make-uint-field 'content-length 64 0 #f)
           ;; Which value machine the field name selected. Not printed, but
           ;; llhttp's numbering all the same -- see the constants above.
           (make-uint-field 'header-state 8 0 #f)
           ;; llhttp's `upgrade`, computed by `before_headers_complete` from
           ;; the flags and the method and read by the body decision. Not
           ;; printed -- it is the one piece of framing state the trace does
           ;; not show, and it changes whether a body is read at all.
           (make-uint-field 'upgrade 8 0 #f)
           ;; llhttp's `finish`: how safe it would be for the input to stop
           ;; HERE. Not printed on any callback line -- the fixture harness
           ;; prints the field itself once the input runs out, which is what
           ;; `off=NULL finish=N` is.
           (make-uint-field 'finish 8 FINISH-SAFE #f)
           ;; llhttp's `initial_message_completed`, the only thing that tells
           ;; a restart from a first start. It is what makes `reset` fire
           ;; between two messages and not before the first.
           (make-uint-field 'initial-message-completed 8 0 #f))
     (list (make-callback-declaration 'on-reset 'event #t '() #f #f)
           (make-callback-declaration 'on-message-begin 'event #t '() #f #f)
           (make-callback-declaration 'on-method-data 'span-data #t '() #f #f)
           (make-callback-declaration 'on-method-complete 'event #t '() #f #f)
           (make-callback-declaration 'on-url-data 'span-data #t '() #f #f)
           (make-callback-declaration 'on-url-complete 'event #t '() #f #f)
           (make-callback-declaration 'on-protocol-data 'span-data #t '() #f #f)
           (make-callback-declaration 'on-protocol-complete 'event #t '() #f #f)
           (make-callback-declaration 'on-version-data 'span-data #t '() #f #f)
           (make-callback-declaration 'on-version-complete 'event #t '() #f #f)
           (make-callback-declaration 'on-status-data 'span-data #t '() #f #f)
           (make-callback-declaration 'on-status-complete 'event #t '() #f #f)
           (make-callback-declaration 'on-header-field-data 'span-data #t '() #f #f)
           (make-callback-declaration 'on-header-field-complete 'event #t '() #f #f)
           (make-callback-declaration 'on-header-value-data 'span-data #t '() #f #f)
           (make-callback-declaration 'on-header-value-complete 'event #t '() #f #f)
           ;; THE SECOND DECISION CALLBACK, and the only one whose question
           ;; is optional to answer: `callback-continue` means "carry on" and
           ;; the one branch means "no body". llhttp reads the same answer as
           ;; a C return value -- 0, 1 or 2 -- and this grammar has no use for
           ;; its 2, which sets `upgrade` from the embedder rather than from
           ;; the headers and which no vendored fixture exercises.
           (make-callback-declaration 'on-headers-complete 'decision #t
                                      '(skip-body) #f #f)
           (make-callback-declaration 'on-body-data 'span-data #t '() #f #f)
           (make-callback-declaration 'on-chunk-header 'event #t '() #f #f)
           (make-callback-declaration 'on-chunk-extension-name-data 'span-data #t '() #f #f)
           (make-callback-declaration 'on-chunk-extension-name-complete 'event #t '() #f #f)
           (make-callback-declaration 'on-chunk-extension-value-data 'span-data #t '() #f #f)
           (make-callback-declaration 'on-chunk-extension-value-complete 'event #t '() #f #f)
           (make-callback-declaration 'on-chunk-complete 'event #t '() #f #f)
           (make-callback-declaration 'on-message-complete 'event #t '() #f #f))
     (list (make-span-declaration 'method-span 'on-method-data #f #f)
           (make-span-declaration 'url-span 'on-url-data #f #f)
           (make-span-declaration 'protocol-span 'on-protocol-data #f #f)
           (make-span-declaration 'version-span 'on-version-data #f #f)
           (make-span-declaration 'status-span 'on-status-data #f #f)
           (make-span-declaration 'header-field-span 'on-header-field-data #f #f)
           (make-span-declaration 'header-value-span 'on-header-value-data #f #f)
           (make-span-declaration 'body-span 'on-body-data #f #f)
           (make-span-declaration 'chunk-ext-name-span
                                  'on-chunk-extension-name-data #f #f)
           (make-span-declaration 'chunk-ext-value-span
                                  'on-chunk-extension-value-data #f #f))
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
     (append
      (list
           ;; `eof`: a `parser-finish!` from an UNSAFE state (mid-message) is
           ;; llhttp's HTTP_FINISH_UNSAFE, and `llhttp_finish` answers
           ;; HPE_INVALID_EOF_STATE -- code 14, reason verbatim (api.c:152).
           ;; llhttp switches on the `finish` FIELD, not the open span, so this
           ;; ONE declaration serves every per-span EOF node. No fixture
           ;; witnesses it -- the corpus never finishes (decision 0016) -- and
           ;; the FEED path stays silent, answering `need-input` rather than
           ;; reaching here; `unit.finish` pins it. See #42.
           (make-error-declaration 'eof 'invalid-eof-state "Invalid EOF state" #f)
           ;; `no-message-type` has NO llhttp number, deliberately: llhttp
           ;; cannot reach this state at all, because the type is a field an
           ;; embedder wrote rather than an answer one gives. A binding that
           ;; returns neither branch key lands here, the adapter has no row to
           ;; rename it with, and the fixture fails rather than the lane
           ;; guessing a message kind.
           (make-error-declaration 'no-message-type 'unexpected-message-type
                                   "the embedder did not say whether this is a request or a response" #f)
           (make-error-declaration 'bad-method 'invalid-method
                                   "Invalid method encountered" #f)
           (make-error-declaration 'no-space-after-method 'invalid-method
                                   "Expected space after method" #f)
           ;; llhttp's own reasons, from `src/llhttp/url.ts`. `bad-url` was a
           ;; placeholder standing in for a decision the url sub-parser had
           ;; not made; no fixture ever recorded it, and these two are what
           ;; the strict request corpus actually asks for.
           (make-error-declaration 'expected-crlf 'invalid-url
                                   "Expected CRLF" #f)
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
           ;; --- the status line --------------------------------------------
           ;; A response's version is followed by a SPACE where a request's is
           ;; followed by CRLF, so the reason after it is a different one --
           ;; under the same code 9.
           (make-error-declaration 'no-space-after-version 'invalid-version
                                   "Expected space after version" #f)
           ;; Two reasons under code 13. Only the first is recorded anywhere
           ;; in the corpus; `corpus-load-tests.sps` pins that, and the second
           ;; is reached by three arms whose llparse idiom is named at each.
           (make-error-declaration 'bad-status-code 'invalid-status
                                   "Invalid status code" #f)
           (make-error-declaration 'bad-response-status 'invalid-status
                                   "Invalid response status" #f)
           (make-error-declaration 'cr-after-status 'cr-expected
                                   "Missing expected CR after response line" #f)
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
           ;; ONE DECLARATION, TWO PRODUCTIONS: the bare CR inside a header
           ;; value and the bare CR after a response's status line carry the
           ;; same (code, reason), so decision 0013's uniqueness makes them
           ;; one declaration and two error NODES -- which is also why this
           ;; is not named after either of them.
           (make-error-declaration 'lf-after-cr-strict 'strict
                                   "Expected LF after CR" #f)
           (make-error-declaration 'cr-after-value 'cr-expected
                                   "Missing expected CR after header value" #f)
           (make-error-declaration 'lf-after-value 'lf-expected
                                   "Missing expected LF after header value" #f)
           (make-error-declaration 'lf-after-headers 'strict
                                   "Expected LF after headers" #f)
           ;; --- framing ----------------------------------------------------
           ;; Four reasons under code 11 and two under 15, which is decision
           ;; 0013's shape again: the code alone identifies neither.
           (make-error-declaration 'duplicate-content-length
                                   'unexpected-content-length
                                   "Duplicate Content-Length" #f)
           (make-error-declaration 'content-length-overflow 'invalid-content-length
                                   "Content-Length overflow" #f)
           (make-error-declaration 'bad-content-length-char 'invalid-content-length
                                   "Invalid character in Content-Length" #f)
           (make-error-declaration 'empty-content-length 'invalid-content-length
                                   "Empty Content-Length" #f)
           (make-error-declaration 'empty-transfer-encoding
                                   'invalid-transfer-encoding
                                   "Empty Transfer-Encoding" #f)
           (make-error-declaration 'te-with-content-length
                                   'invalid-transfer-encoding
                                   "Transfer-Encoding can't be present with Content-Length" #f)
           (make-error-declaration 'cl-with-te 'invalid-content-length
                                   "Content-Length can't be present with Transfer-Encoding" #f)
           (make-error-declaration 'bad-te-value 'invalid-transfer-encoding
                                   "Invalid `Transfer-Encoding` header value" #f)
           (make-error-declaration 'request-invalid-te 'invalid-transfer-encoding
                                   "Request has invalid `Transfer-Encoding`" #f)
           ;; --- chunked bodies ---------------------------------------------
           ;; Two reasons under code 12, and the two line-ending reasons that
           ;; every llhttp production has a pair of: the strict one when a CR
           ;; is not followed by LF, and the cr-expected one when an LF
           ;; arrives with no CR before it.
           (make-error-declaration 'bad-chunk-size 'invalid-chunk-size
                                   "Invalid character in chunk size" #f)
           (make-error-declaration 'chunk-size-overflow 'invalid-chunk-size
                                   "Chunk size overflow" #f)
           (make-error-declaration 'lf-after-chunk-size 'strict
                                   "Expected LF after chunk size" #f)
           (make-error-declaration 'cr-after-chunk-size 'cr-expected
                                   "Missing expected CR after chunk size" #f)
           (make-error-declaration 'lf-after-chunk-data 'strict
                                   "Expected LF after chunk data" #f)
           (make-error-declaration 'cr-after-chunk-data 'cr-expected
                                   "Missing expected CR after chunk data" #f)
           ;; Six reasons under code 2 for one production, which is decision
           ;; 0013's shape at its most extreme: llhttp names the place inside
           ;; the extension where the byte was refused, and only the reason
           ;; says which.
           (make-error-declaration 'bad-chunk-ext 'strict
                                   "Invalid character in chunk extensions" #f)
           (make-error-declaration 'bad-chunk-ext-name 'strict
                                   "Invalid character in chunk extensions name" #f)
           (make-error-declaration 'bad-chunk-ext-value 'strict
                                   "Invalid character in chunk extensions value" #f)
           (make-error-declaration 'bad-chunk-ext-quoted 'strict
                                   "Invalid character in chunk extensions quoted value" #f)
           (make-error-declaration 'bad-chunk-ext-qp 'strict
                                   "Invalid quoted-pair in chunk extensions quoted value" #f)
           ;; llhttp's own wording, `quote value` and not `quoted value`, for
           ;; the byte after a closed quoted string. A trace is compared
           ;; BIT-EXACTLY, so the typo is part of the oracle.
           (make-error-declaration 'bad-chunk-ext-quote-value 'strict
                                   "Invalid character in chunk extensions quote value" #f)
           (make-error-declaration 'cr-after-chunk-ext-name 'cr-expected
                                   "Missing expected CR after chunk extension name" #f)
           (make-error-declaration 'cr-after-chunk-ext-value 'cr-expected
                                   "Missing expected CR after chunk extension value" #f)
           ;; --- the message loop -------------------------------------------
           ;; llhttp's reason names `Connection: close` even when what closed
           ;; the connection was an HTTP/1.0 request that never said
           ;; keep-alive (request/connection.md#3). The reason is the oracle's,
           ;; so it is reproduced as written.
           (make-error-declaration 'data-after-close 'closed-connection
                                   "Data after `Connection: close`" #f)
           ;; PRI's HTTP/2 preface. llhttp calls it a pause in the reason and
           ;; implements it as an ERROR, which is why this one has a number to
           ;; rename and the CONNECT/Upgrade pause does not.
           (make-error-declaration 'pri-upgrade 'paused-h2-upgrade
                                   "Pause on PRI/Upgrade" #f)
           (make-error-declaration 'bad-h2-preface 'invalid-version
                                   "Expected HTTP/2 Connection Preface" #f)
           ;; A PAUSE'S REASON, not an error's. It is declared in the same
           ;; shape because the generator reuses `error-declaration` for both
           ;; -- the difference is at the RESULT, where the error slot stays #f
           ;; and the reason arrives in its own. Nothing here may name this
           ;; declaration from an error node.
           (make-error-declaration 'upgrade-paused 'paused-upgrade
                                   "Pause on CONNECT/Upgrade" #f))
      ;; The url subgraph's own reasons. They are part of its contract rather
      ;; than an implementation detail, which is why they come from there
      ;; instead of being written out a second time here.
      (url-error-declarations))
     (append
      (list
      ;; --- the first byte -----------------------------------------------------
      ;; A dispatch rather than a callback node: the first byte must be
      ;; available but UNCONSUMED when `message begin` fires at offset 0.
      ;; A STRAY LINE ENDING BEFORE THE REQUEST LINE IS SKIPPED. llhttp's
      ;; `start` matches CR and LF back to itself, so `\r\nGET /test HTTP/1.1`
      ;; reports `message begin` at 2 -- the skipped bytes are consumed and
      ;; belong to no span.
      ;;
      ;; EVERY OTHER BYTE GOES ON, INCLUDING ONE NO METHOD MAY START WITH.
      ;; Rejecting a non-tchar here looks like the same answer one node
      ;; earlier -- the method table refuses it either way, at the same offset
      ;; and with the same reason -- but it is not: it errors BEFORE
      ;; `message begin`, and llhttp prints that event first. `@ET / HTTP/1.1`
      ;; records `off=0 message begin` and then `off=0 error code=6`. No
      ;; fixture in the corpus begins with a non-tchar, so this was measured
      ;; against a live llhttp rather than read off a recorded trace.
      (make-byte-dispatch-node 'start
        (list (make-byte-case (make-byte-set-matcher (list CR LF))
                              (make-edge 'start 'advance) #f))
        (make-edge 'start-check-reset 'reexecute) 'clean-eof #f)
      (make-finish-node 'clean-eof #f)

      ;; THE SKIPPED CRLF COMES FIRST AND `reset` SECOND, which is the order
      ;; the corpus records: `request/pipelining.md#1` ends a body at 44 and
      ;; fires `reset` at 46, having eaten the CRLF between. So the loop above
      ;; is not a leading-whitespace convenience -- it is where a pipelined
      ;; message's separator is consumed.
      (make-field-branch-node 'start-check-reset 'nonzero
                              (list 'initial-message-completed)
                              'start-reset 'after-start #f)
      (ev 'start-reset 'on-reset 'after-start)
      ;; From here to the end of this message, stopping would lose data.
      (make-field-action-node 'after-start 'store (list 'finish FINISH-UNSAFE)
                              'message-begin #f #f)
      (ev 'message-begin 'on-message-begin 'switch-type)

      ;; --- request or response? ------------------------------------------------
      ;;
      ;; llhttp's `switchType`, placed exactly where llhttp places it: AFTER
      ;; `message begin` and before the first byte of either start line, so
      ;; the event fires at the same offset for both kinds.
      ;;
      ;; llhttp reads a FIELD here -- `load('type', {REQUEST: start_req,
      ;; RESPONSE: start_res}, start_req_or_res)` -- which its embedder wrote
      ;; before the parse, and so does this. The field is SETTABLE and the
      ;; embedder writes it at `make-parser`, so these two nodes are a read
      ;; and nothing else.
      ;;
      ;; IT WAS A DECISION CALLBACK, ASKED ONCE PER MESSAGE, until the
      ;; generator could start a parser in a mode. That was a wider surface
      ;; than llhttp's, not a narrower one: `s->type` is written once over
      ;; there and cannot change between two pipelined messages, where an
      ;; embedder answering this callback could have said `request` and then
      ;; `response` on one connection. Nothing in the corpus did, so nothing
      ;; recorded it -- which is why this is worth writing down rather than
      ;; leaving to the ratchet.
      ;;
      ;; THE FALL-THROUGH IS AN ERROR, NOT A DEFAULT, and TYPE-BOTH is what
      ;; reaches it: llhttp's third arm is `start_req_or_res`, which v0.1 does
      ;; not have (see TYPE-BOTH above). An embedder that passes no `type`
      ;; initial gets the declared TYPE-BOTH and this refusal at the first
      ;; byte -- where a missing REQUIRED callback used to be refused at
      ;; `make-parser`. A field initial cannot be made mandatory, so the
      ;; refusal moved rather than went away; decision 0021 records the trade.
      (make-field-branch-node 'switch-type 'equal (list 'type TYPE-REQUEST)
                              'method-open 'switch-type-response #f)
      (make-field-branch-node 'switch-type-response 'equal (list 'type TYPE-RESPONSE)
                              'protocol-open 'e-no-message-type #f)

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
      ;; ONE SPACE IS REQUIRED AND THE REST ARE SKIPPED, which is two nodes in
      ;; llhttp and two here: `req_first_space_before_url` errors without a
      ;; space, `req_spaces_before_url` matches any further ones back to
      ;; itself. `PUT   /url HTTP/1.1` records the target at 6, not an empty
      ;; one at 4. No corpus fixture has a repeated space here, so this was
      ;; measured against a live llhttp.
      (make-byte-dispatch-node 'after-method
        (list (make-byte-case (make-exact-byte-matcher SP)
                              (make-edge 'spaces-before-url 'advance) #f))
        (make-edge 'e-no-space-after-method 'reexecute) 'e-eof-none #f)
      (make-byte-dispatch-node 'spaces-before-url
        (list (make-byte-case (make-exact-byte-matcher SP)
                              (make-edge 'spaces-before-url 'advance) #f))
        (make-edge 'url-which-entry 'reexecute) 'e-eof-none #f)
      ;; WHICH ENTRY THE URL MACHINE IS JOINED AT, and llhttp asks the same
      ;; question in the same place:
      ;;
      ;;   .otherwise(this.isEqual('method', METHODS.CONNECT, {
      ;;     equal: url.entry.connect, notEqual: url.entry.normal }))
      ;;
      ;; `CONNECT 0-home0.netscape.com:443 HTTP/1.0` has no scheme and no
      ;; leading slash, so `url-start` would refuse its first byte. The
      ;; connect entry skips `start` and opens at the host instead.
      (make-field-branch-node 'url-which-entry 'equal
                              (list 'method (method-number "CONNECT"))
                              'url-entry-connect 'url-entry-normal #f)

      ;; --- request target -----------------------------------------------------
      ;;
      ;; THE URL SUB-PARSER, SPLICED IN, and this is the whole of the change
      ;; decision 0023 records. `(httparse url-grammar)` holds one description
      ;; of llhttp's URL machine and builds it twice, exactly as upstream does
      ;; from `new URL(p, separateSpans)`. Here the parts are STUBS and the
      ;; whole target is ONE `url-span`, which is what every `uri.md` fixture
      ;; is written against; the url binary's five separate spans are the
      ;; other configuration.
      ;;
      ;; WHAT THIS BUYS is the structural refusal the opaque loop could not
      ;; make. `OPTIONS a.com:443 HTTP/1.1` reads `a.com` as a schema, wants
      ;; `//` after the colon, and errors -- where a loop over the target
      ;; characters read on to the end. That was the largest of the three
      ;; measured divergences.
      ;;
      ;; THE TARGET STILL HAS THREE LEGAL ENDINGS, and they are the caller's
      ;; half of the subgraph's contract -- upstream's `skipToHTTP`,
      ;; `skipCRLF` and `skipToHTTP09`, which it calls `exit`:
      ;;
      ;;   SP     the version follows           close, skip, `url complete`
      ;;   CRLF   there is no version: HTTP/0.9 close, skip both, 0/9
      ;;   LF     the same, one byte shorter    close, skip, 0/9
      ;;
      ;; AN ILLEGAL BYTE DOES NOT CLOSE THE SPAN, which is now the subgraph's
      ;; doing rather than a node of ours: every error inside it is reached
      ;; with `url-span` open and abandons it, so an illegal byte delivers no
      ;; `span[url]` fragment at all. `request/uri.md#7` records the error at
      ;; 5 and nothing before it but the method.
      ;;
      ;; Each ending closes the span and then SKIPS its own delimiter, which
      ;; is llparse's `skipTo` -- a dispatch with no cases whose fallback
      ;; advances. That is what puts `url complete` one byte PAST its space
      ;; while the other three completions fire AT their delimiter.
      (make-span-end-node 'url-close-sp 'url-span 'url-skip-sp #f)
      (make-byte-dispatch-node 'url-skip-sp
        '() (make-edge 'url-complete 'advance) 'e-eof-none #f)
      (ev 'url-complete 'on-url-complete 'http-start)

      ;; And again before the protocol: llhttp's `req_http_start` matches a
      ;; space back to itself and only then opens the protocol span, so
      ;; `PUT /url   HTTP/1.1` records the protocol at 11. THE RESPONSE PATH
      ;; DOES NOT COME THROUGH HERE -- `res_after_start` opens the span with
      ;; no skipping, which is why `switch-type-response` still targets
      ;; `protocol-open` directly.
      (make-byte-dispatch-node 'http-start
        (list (make-byte-case (make-exact-byte-matcher SP)
                              (make-edge 'http-start 'advance) #f))
        (make-edge 'protocol-open 'reexecute) 'e-eof-none #f)

      ;; HTTP/0.9: no protocol span, no version span, and the version pair set
      ;; from nothing at all. `request/sample.md#10` records `v=0/9` for
      ;; `GET /` and `url complete` at 7 -- past both bytes of the CRLF.
      (make-span-end-node 'url-close-cr 'url-span 'url-crlf-09 #f)
      (make-sequence-dispatch-node 'url-crlf-09
        (list (make-sequence-case (list CR LF) 'url-09-major #f))
        (make-edge 'e-expected-crlf 'reexecute) 'e-eof-none #f)
      (make-span-end-node 'url-close-lf 'url-span 'url-skip-lf #f)
      (make-byte-dispatch-node 'url-skip-lf
        '() (make-edge 'url-09-major 'advance) 'e-eof-none #f)
      (make-field-action-node 'url-09-major 'store (list 'http-major 0)
                              'url-09-minor #f #f)
      (make-field-action-node 'url-09-minor 'store (list 'http-minor 9)
                              'url-complete-09 #f #f)
      (ev 'url-complete-09 'on-url-complete 'headers-start)

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
      ;;
      ;; ONE TABLE FOR BOTH START LINES. llhttp writes the constant twice --
      ;; `req_after_http_start` with `checkMethod` and `res_after_start` with
      ;; `endResponseProtocol` -- and the two differ in nothing but what
      ;; follows the event. Here they are one keyword table and one span, with
      ;; a zero-width branch where llhttp forks, so `HTTP`, `RTSP` and `ICE`
      ;; have a single definition and the response cannot drift from the
      ;; request. THE METHOD CHECK IS THE FORK: a response has no method, and
      ;; its `method-protocols` is 0, which no protocol would accept.
      (make-span-end-node 'protocol-close-http 'protocol-span 'protocol-complete-http #f)
      (ev 'protocol-complete-http 'on-protocol-complete 'protocol-after-http)
      (make-field-branch-node 'protocol-after-http 'equal (list 'type TYPE-RESPONSE)
                              'after-protocol 'check-http #f)
      (make-field-branch-node 'check-http 'mask-any (list 'method-protocols HTTP-BIT)
                              'after-protocol 'e-method-not-http #f)
      (make-span-end-node 'protocol-close-rtsp 'protocol-span 'protocol-complete-rtsp #f)
      (ev 'protocol-complete-rtsp 'on-protocol-complete 'protocol-after-rtsp)
      (make-field-branch-node 'protocol-after-rtsp 'equal (list 'type TYPE-RESPONSE)
                              'after-protocol 'check-rtsp #f)
      (make-field-branch-node 'check-rtsp 'mask-any (list 'method-protocols RTSP-BIT)
                              'after-protocol 'e-method-not-rtsp #f)
      (make-span-end-node 'protocol-close-ice 'protocol-span 'protocol-complete-ice #f)
      (ev 'protocol-complete-ice 'on-protocol-complete 'protocol-after-ice)
      (make-field-branch-node 'protocol-after-ice 'equal (list 'type TYPE-RESPONSE)
                              'after-protocol 'check-ice #f)
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
      ;; EVERY DIGIT IS STORED, including the ones no accepted pair contains:
      ;; a lenient parse has to PRINT `v=5/6`, and a value never stored cannot
      ;; be printed. Whether the pair is acceptable is the check's question,
      ;; not this node's.
      (make-byte-dispatch-node 'version-major
        (map (lambda (d)
               (make-byte-case (make-exact-byte-matcher (digit d))
                               (make-edge (version-major-store-name d) 'advance) #f))
             all-digits)
        (make-edge 'version-close-bad-major 'reexecute) 'e-eof-version #f))
      (version-nodes)
      (list
      (make-span-end-node 'version-close 'version-span 'version-complete #f)
      (make-span-end-node 'version-close-bad-major 'version-span 'e-bad-major #f)
      (make-span-end-node 'version-close-expected-dot 'version-span 'e-expected-dot #f)
      (make-span-end-node 'version-close-bad-minor 'version-span 'e-bad-minor #f)
      (make-span-end-node 'version-close-bad-version 'version-span 'e-bad-version #f)
      ;; ONE VERSION SUBGRAPH FOR BOTH START LINES, for the same reason the
      ;; protocol has one table: llhttp's `req_http_major/dot/minor/end` and
      ;; its `res_http_major/dot/minor/end` are the same nodes with the same
      ;; `checkVersion` and differ only in what follows the event. So the four
      ;; accepted pairs, and the three ways a version can be malformed, have
      ;; one definition here and the fork is one zero-width branch.
      (make-field-branch-node 'version-after 'equal (list 'type TYPE-RESPONSE)
                              'res-after-version 'after-version #f)
      ;; llhttp loads the method right after `version complete`: PRI takes the
      ;; HTTP/2 preface path and everything else the CRLF.
      (ev 'version-complete 'on-version-complete 'version-after)
      (make-field-branch-node 'after-version 'equal
                              (list 'method (method-number "PRI"))
                              'pri-preface 'expect-cr #f)
      ;; A `.match` of all ten bytes, so the error lands PAST them: the whole
      ;; preface is consumed and `PRI * HTTP/1.1\r\n\r\nSM\r\n\r\n` reports at 24.
      ;; One sequence case, so the prefix ambiguity that rules this construct
      ;; out for the method and header tables cannot arise.
      (make-sequence-dispatch-node 'pri-preface
        (list (make-sequence-case (append (list CR LF CR LF)
                                          (ascii-bytes "SM")
                                          (list CR LF CR LF))
                                  'e-pri-upgrade #f))
        (make-edge 'e-bad-h2-preface 'reexecute) 'e-eof-none #f)

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
                              (make-edge 'lenient-lf-request-line 'advance) #f))
        (make-edge 'e-no-crlf 'reexecute) 'e-eof-none #f)
      ;; THE TENTH SITE, and the only one whose strict error is not a
      ;; `Missing expected CR`. A request line ending in a bare LF is
      ;; `Expected CRLF after version`, the same reason its lone-CR sibling
      ;; gives -- which is why the two sit on the same node and why this one
      ;; was missed until `request/invalid.md#22` named it: the failure read
      ;; as the OPTIONAL_LF_AFTER_CR fork already in place, and it was the
      ;; other flag's arm of the same node.
      ;;
      ;; ITS LENIENT ARM GOES TO `expect-lf`, NOT TO THE HEADERS, and that
      ;; costs a second flag. Upstream sends it to `req_http_complete_crlf`,
      ;; which is this node -- and that node wants an LF the `.match` above
      ;; has already CONSUMED, so it falls through to the OPTIONAL_LF_AFTER_CR
      ;; fork below. With `optional-cr-before-lf` alone the parse still fails,
      ;; at the same offset and with the same reason as strict, and a
      ;; different code: `Expected CRLF after version` as `strict` (2) rather
      ;; than as `invalid-version` (9).
      ;;
      ;; A JUMP STRAIGHT TO `headers-start` PASSES EVERY FIXTURE UPSTREAM
      ;; SHIPS -- the corpus tests one flag at a time, where this needs a
      ;; pair, and its only combination fixtures set both. The live
      ;; differential's lenient kind found it on its first run.
      (lenient-fork 'lenient-lf-request-line 'optional-cr-before-lf
                    'expect-lf 'e-no-crlf)
      (make-byte-dispatch-node 'expect-lf
        (list (make-byte-case (make-exact-byte-matcher LF)
                              (make-edge 'headers-start 'advance) #f))
        (make-edge 'lenient-lf-after-version 'reexecute) 'e-eof-none #f)
      ;; OPTIONAL_LF_AFTER_CR, first of four: the CR ending a REQUEST line
      ;; stands on its own. The LF is unconsumed either way, so the lenient
      ;; arm re-executes the header section's first byte against whatever
      ;; followed the CR.
      (lenient-fork 'lenient-lf-after-version 'optional-lf-after-cr
                    'headers-start 'e-lf-after-cr)

      ;; --- the status line ----------------------------------------------------
      ;;
      ;; `SP 3DIGIT [ SP reason-phrase ] CRLF`, and the reason phrase is
      ;; OPTIONAL -- `HTTP/1.1 200\r\n` closes the line at the CR with no
      ;; `span[status]` at all, because llhttp opens that span only on the
      ;; space arm.
      ;;
      ;; EXACTLY THREE DIGITS, not a loop. llhttp writes `res_status_code_
      ;; digit_1/2/3` as three `select(NUM_MAP, mulAdd)` steps, and the count
      ;; is observable: `HTTP/1.1 2 OK` errors at 10, one past its only digit,
      ;; where a loop would take the space as a terminator and carry on.
      (make-byte-dispatch-node 'res-after-version
        (list (make-byte-case (make-exact-byte-matcher SP)
                              (make-edge 'res-status-code-zero 'advance) #f))
        (make-edge 'e-no-space-after-version 'reexecute) 'e-eof-none #f)
      (make-field-action-node 'res-status-code-zero 'store (list 'status-code 0)
                              'res-status-digit-1 #f #f)
      ;; THE OVERFLOW ARM CANNOT FIRE, and that is arithmetic rather than
      ;; optimism: three base-ten digits reach 999 and the field is llhttp's
      ;; own `i16`. So the one-dispatch shim the chunk size needs -- our
      ;; accumulator REEXECUTES the digit that overflowed where llhttp's
      ;; `select` had already consumed it -- is not needed here, and the arm
      ;; names llhttp's error for the same reason llhttp writes one.
      (make-integer-accumulate-node 'res-status-digit-1 'status-code 10
                                    'res-status-digit-2
                                    (make-edge 'e-bad-status-code 'reexecute)
                                    'e-bad-status-code 'e-eof-none #f)
      (make-integer-accumulate-node 'res-status-digit-2 'status-code 10
                                    'res-status-digit-3
                                    (make-edge 'e-bad-status-code 'reexecute)
                                    'e-bad-status-code 'e-eof-none #f)
      (make-integer-accumulate-node 'res-status-digit-3 'status-code 10
                                    'res-status-after
                                    (make-edge 'e-bad-status-code 'reexecute)
                                    'e-bad-status-code 'e-eof-none #f)

      ;; THE BARE LF IS CONSUMED BEFORE IT FAILS and the foreign byte is not:
      ;; llhttp `.match`es the LF into a lenient test strict mode refuses, and
      ;; `.otherwise` does not consume. The same trap as the bare LF after a
      ;; request's version, and the same two offsets one apart. NO FIXTURE
      ;; RECORDS EITHER -- the reason "Invalid response status" appears
      ;; nowhere in the 274, which `corpus-load-tests.sps` pins; what is
      ;; measured is the IDIOM, by `request/invalid.md#21` for the consumed
      ;; bare LF and by `response/invalid.md` for `.otherwise` at the byte.
      (make-byte-dispatch-node 'res-status-after
        (list (make-byte-case (make-exact-byte-matcher SP)
                              (make-edge 'res-status-open 'advance) #f)
              (make-byte-case (make-exact-byte-matcher CR)
                              (make-edge 'res-line-almost-done 'advance) #f)
              (make-byte-case (make-exact-byte-matcher LF)
                              (make-edge 'lenient-lf-status-code 'advance) #f))
        (make-edge 'e-bad-response-status 'reexecute) 'e-eof-none #f)
      ;; THE ELEVENTH OPTIONAL_CR_BEFORE_LF SITE, and the one decision 0020's
      ;; disable sweep could not count, because a fork that is not there is
      ;; not a site. Upstream's arm is
      ;; `.match('\n', checkIfAllowLFWithoutCR(onStatusComplete, error))`,
      ;; and this parser had the error alone.
      ;;
      ;; ONE FLAG IS ENOUGH HERE, unlike the request line's bare LF: the
      ;; lenient arm goes STRAIGHT to `onStatusComplete` rather than to a node
      ;; that wants the LF the match has already eaten. The two sites read
      ;; alike and behave differently.
      ;;
      ;; NO FIXTURE UPSTREAM SHIPS REACHES IT -- `Invalid response status`
      ;; appears nowhere in the 274, and a status line with no reason phrase
      ;; AND a bare LF is two unusual things at once. The live differential's
      ;; lenient kind found it at two seeds.
      (lenient-fork 'lenient-lf-status-code 'optional-cr-before-lf
                    'status-complete 'e-bad-response-status)

      ;; THE REASON PHRASE TAKES ANY BYTE BUT ITS LINE ENDING. llhttp's
      ;; `res_status` is `.peek('\r', ...).peek('\n', ...).skipTo(res_status)`
      ;; -- a bare `skipTo` with no matcher, so NUL and DEL are status text.
      ;; `HTTP/1.1 200  OK` records `span[status]=" OK"`, which is the check
      ;; that the span starts one past the space llhttp consumed and takes the
      ;; second one whole.
      (make-span-start-node 'res-status-open 'status-span 'res-status #f)
      (make-byte-dispatch-node 'res-status
        (list (make-byte-case (make-exact-byte-matcher CR)
                              (make-edge 'res-status-close-cr 'reexecute) #f)
              (make-byte-case (make-exact-byte-matcher LF)
                              (make-edge 'res-status-close-lf 'reexecute) #f))
        (make-edge 'res-status 'advance) 'e-eof-status #f)
      ;; `span.status.end().skipTo(...)` is a PEEK that ends the span and THEN
      ;; consumes, so each of these is a span end followed by a one-byte
      ;; dispatch: the span closes AT the line ending and the next state
      ;; starts past it.
      (make-span-end-node 'res-status-close-cr 'status-span 'res-status-skip-cr #f)
      (make-byte-dispatch-node 'res-status-skip-cr
        '() (make-edge 'res-line-almost-done 'advance) 'e-eof-none #f)
      (make-span-end-node 'res-status-close-lf 'status-span 'res-status-skip-lf #f)
      (make-byte-dispatch-node 'res-status-skip-lf
        '() (make-edge 'lenient-lf-status 'advance) 'e-eof-none #f)
      ;; OPTIONAL_CR_BEFORE_LF, and every one of its ten sites is the same
      ;; sentence: a bare LF is taken as the line ending CRLF would have
      ;; been. The LENIENT TARGET IS WHEREVER THE CR ARM GOES ONCE THE LINE
      ;; ENDING IS CONSUMED -- which is not always the CR arm's own target,
      ;; because some of these sites eat the LF and some peek it.
      (lenient-fork 'lenient-lf-status 'optional-cr-before-lf 'status-complete 'e-cr-after-status)

      ;; `status complete` fires PAST the LF, which is why the CR arm above
      ;; carries no event of its own: a status line that never reaches its LF
      ;; records the span and then an error, never a completion.
      (make-byte-dispatch-node 'res-line-almost-done
        (list (make-byte-case (make-exact-byte-matcher LF)
                              (make-edge 'status-complete 'advance) #f))
        (make-edge 'lenient-lf-after-status 'reexecute) 'e-eof-none #f)
      ;; OPTIONAL_LF_AFTER_CR, second: the same for a RESPONSE's status line.
      ;; Its strict error carries a DIFFERENT reason from the request's --
      ;; "Expected LF after CR" against "Expected CRLF after version" -- which
      ;; is why the two are separate declarations and why one fork cannot
      ;; serve both.
      (lenient-fork 'lenient-lf-after-status 'optional-lf-after-cr
                    'status-complete 'e-lf-after-cr-strict)
      (ev 'status-complete 'on-status-complete 'headers-start)

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
                              (make-edge 'lenient-headers-start 'advance) #f))
        (make-edge 'header-field-start 'reexecute) 'e-eof-none #f)
      ;; LENIENT_HEADERS, first of six. The space is consumed either way --
      ;; llhttp `.match`es it INTO the test -- so the lenient arm resumes at
      ;; `header-field-start` having eaten it, which is why a lenient parse of
      ;; ` Host: x` reports the field at 1 and not at 0.
      (lenient-fork 'lenient-headers-start 'headers
                    'header-field-start 'e-unexpected-space)

      ;; Three ways a field can fail to start, each with its own reason: a bare
      ;; LF is `Invalid header field char`, a leading colon is `Invalid header
      ;; token`, and CR begins the empty line that ends the section.
      (make-byte-dispatch-node 'header-field-start
        (list (make-byte-case (make-exact-byte-matcher CR)
                              (make-edge 'headers-almost-done 'advance) #f)
              (make-byte-case (make-exact-byte-matcher LF)
                              (make-edge 'lenient-lf-field-start 'advance) #f)
              (make-byte-case (make-exact-byte-matcher COLON)
                              (make-edge 'e-bad-header-token 'reexecute) #f))
        (make-edge 'header-field-open 'reexecute) 'e-eof-none #f)

      ;; THE NAME IS MATCHED AGAINST llhttp's FIVE SPECIAL HEADERS FIRST, and
      ;; what the match changes is not the span -- it is which value machine
      ;; runs, and what a space before the colon means.
      ;;
      ;; A no-match leaves the walk where it broke and reexecutes, so the
      ;; general loop resumes mid-name with the span still open and the whole
      ;; name still lands in it: `Content-Type` breaks at the `T` that does not
      ;; continue `content-l`, and its span is all twelve bytes.
      (make-span-start-node 'header-field-open 'header-field-span 'header-field-table #f))
      (list
      (make-keyword-table-node 'header-field-table
        (map (lambda (row)
               (make-keyword-entry (ascii-bytes (car row))
                                   (header-state-store-name (cdr row)) #f))
             httparse-special-headers)
        (make-edge 'header-state-general 'reexecute)
        'e-eof-header-field #t #f))
      (header-state-store-nodes)
      (list
      ;; llhttp's `.otherwise(resetHeaderState('header_field_general'))`, shared
      ;; by the table's no-match and by a special name that turns out to be a
      ;; longer one -- `Connection-Duration` matches `connection`, then falls
      ;; through here at the hyphen.
      (make-field-action-node 'header-state-general 'store (list 'header-state HS-GENERAL)
                              'header-field-loop #f #f)

      ;; A SPACE BEFORE THE COLON IS A DIFFERENT ERROR FROM A SPACE ANYWHERE
      ;; ELSE, and only on this path. llhttp peeks it, ends the span, and then
      ;; `skipTo`s the error -- a skip CONSUMES -- so the reason is `Invalid
      ;; header field char` and the offset is one past the space, while the
      ;; general path's `Invalid header token` is at the character itself.
      ;; Two fixtures turn on the pair.
      (make-byte-dispatch-node 'header-field-colon
        (list (make-byte-case (make-exact-byte-matcher SP)
                              (make-edge 'lenient-field-colon 'reexecute) #f)
              (make-byte-case (make-exact-byte-matcher COLON)
                              (make-edge 'header-field-close 'reexecute) #f))
        (make-edge 'header-state-general 'reexecute) 'e-eof-header-field #f)
      ;; LENIENT_HEADERS, second. ONLY ON THIS PATH: the general-header route
      ;; has no lenient arm at all, so `Foo : x` is `Invalid header token`
      ;; whatever the flags say, while `Connection : x` is accepted. That
      ;; asymmetry is llhttp's -- `header_field_general_otherwise` carries no
      ;; flag test -- and it is the reason these two errors have separate
      ;; declarations.
      (lenient-fork 'lenient-field-colon 'headers
                    'field-colon-discard-ws 'field-close-before-space)
      ;; UPSTREAM LOOPS BACK HERE AND THIS CANNOT. llhttp's
      ;; `header_field_colon_discard_ws` eats spaces and then re-enters
      ;; `header_field_colon`, which is a cycle whose every edge is a peek --
      ;; safe at runtime, because the node it returns to only takes its space
      ;; arm on a space and this one only returns on a non-space, but the
      ;; verifier reasons over the GRAPH and refuses it as a zero-progress
      ;; cycle. So the two arms that can follow the spaces are inlined here
      ;; instead: a colon closes the field, and anything else is the general
      ;; header `header_field_colon` would have fallen through to. Same
      ;; answers, no back edge.
      (make-byte-dispatch-node 'field-colon-discard-ws
        (list (make-byte-case (make-exact-byte-matcher SP)
                              (make-edge 'field-colon-discard-ws 'advance) #f)
              (make-byte-case (make-exact-byte-matcher COLON)
                              (make-edge 'header-field-close 'reexecute) #f))
        (make-edge 'header-state-general 'reexecute) 'e-eof-header-field #f)
      (make-span-end-node 'field-close-before-space 'header-field-span
                          'eat-space-before-colon #f)
      (make-byte-dispatch-node 'eat-space-before-colon
        (list (make-byte-case (make-exact-byte-matcher SP)
                              (make-edge 'e-bad-header-field-char 'advance) #f))
        (make-edge 'e-bad-header-field-char 'reexecute) 'e-eof-none #f)

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
      ;; llhttp's `onHeaderFieldComplete` loads the header state and, for the
      ;; two framing headers, refuses the pair before the value is read. BOTH
      ;; sides exist now -- each has its own code AND its own reason, which is
      ;; decision 0013's point yet again:
      ;;
      ;;   TE then CL   code 11  Content-Length can't be present with Transfer-Encoding
      ;;   CL then TE   code 15  Transfer-Encoding can't be present with Content-Length
      (ev 'header-field-complete 'on-header-field-complete 'after-field-complete)
      (make-field-branch-node 'after-field-complete 'equal
                              (list 'header-state HS-TRANSFER-ENCODING)
                              'check-te-conflict 'after-field-complete-cl #f)
      (make-field-branch-node 'check-te-conflict 'mask-any
                              (list 'flags F-CONTENT-LENGTH)
                              'lenient-te-with-cl 'value-discard-ws #f)
      (make-field-branch-node 'after-field-complete-cl 'equal
                              (list 'header-state HS-CONTENT-LENGTH)
                              'check-cl-conflict 'value-discard-ws #f)
      (make-field-branch-node 'check-cl-conflict 'mask-any
                              (list 'flags F-TRANSFER-ENCODING)
                              'lenient-cl-with-te 'value-discard-ws #f)
      ;; CHUNKED_LENGTH, and it is BOTH of upstream's sites: the flag turns
      ;; off the refusal of `Content-Length` beside `Transfer-Encoding`,
      ;; whichever order they arrived in. Two errors, two reasons, two forks
      ;; -- llhttp's `checkInvalidTransferEncoding` and
      ;; `checkInvalidContentLength` are separate functions for the same
      ;; reason decision 0013 makes them separate declarations.
      (lenient-fork 'lenient-te-with-cl 'chunked-length
                    'value-discard-ws 'e-te-with-content-length)
      (lenient-fork 'lenient-cl-with-te 'chunked-length
                    'value-discard-ws 'e-cl-with-te)

      ;; --- the value ----------------------------------------------------------
      ;; Leading OWS is discarded and is not part of the span.
      (make-byte-dispatch-node 'value-discard-ws
        (list (make-byte-case (make-byte-set-matcher (list SP HTAB))
                              (make-edge 'value-discard-ws 'advance) #f)
              (make-byte-case (make-exact-byte-matcher CR)
                              (make-edge 'value-discard-ws-cr 'advance) #f)
              (make-byte-case (make-exact-byte-matcher LF)
                              (make-edge 'lenient-lf-discard-ws 'advance) #f))
        (make-edge 'value-open 'reexecute) 'e-eof-none #f)

      (make-byte-dispatch-node 'value-discard-ws-cr
        (list (make-byte-case (make-exact-byte-matcher LF)
                              (make-edge 'value-discard-lws 'advance) #f))
        (make-edge 'lenient-discard-ws-cr 'reexecute) 'e-eof-none #f)
      ;; LENIENT_HEADERS, third: a CR with no LF after it, in the whitespace
      ;; before a value.
      (lenient-fork 'lenient-discard-ws-cr 'headers
                    'value-discard-lws 'e-lf-after-cr-strict)

      ;; Obs-fold, first site: a continuation line after an EMPTY value. The
      ;; whitespace is CONSUMED before it fails (llhttp `.match`es it), unlike
      ;; the second site below, which peeks.
      (make-byte-dispatch-node 'value-discard-lws
        (list (make-byte-case (make-byte-set-matcher (list SP HTAB))
                              (make-edge 'lenient-discard-lws 'advance) #f))
        (make-edge 'value-empty-check 'reexecute) 'e-eof-none #f)
      ;; LENIENT_HEADERS, fourth: the folded line is taken as more leading
      ;; whitespace, so the value that finally arrives is the folded one.
      (lenient-fork 'lenient-discard-lws 'headers
                    'value-discard-ws 'e-bad-header-value-char)

      ;; llhttp's `checkEmptyHeaderValue`: an empty value is announced as an
      ;; empty span for a general header and is an ERROR for the two framing
      ;; ones, and the state is read BEFORE the span is opened.
      (make-field-branch-node 'value-empty-check 'equal
                              (list 'header-state HS-CONTENT-LENGTH)
                              'e-empty-content-length 'value-empty-check-te #f)
      (make-field-branch-node 'value-empty-check-te 'equal
                              (list 'header-state HS-TRANSFER-ENCODING)
                              'e-empty-transfer-encoding
                              (set-header-flags-entry "shf-empty") #f))
      (set-header-flags-nodes "shf-empty" 'value-empty-open)
      (list

      ;; An empty value is ANNOUNCED, not omitted: llhttp opens and immediately
      ;; closes the span, which is the upstream empty-span behaviour this
      ;; project asked for and picked up at v0.2.0.
      (make-span-start-node 'value-empty-open 'header-value-span 'value-empty-close #f)
      (make-span-end-node 'value-empty-close 'header-value-span 'value-complete #f)

      ;; llhttp's `header_value_start` loads the header state and picks a value
      ;; machine. Content-Length is this slice's; Transfer-Encoding, Connection
      ;; and Upgrade take llhttp's own default arm, `resetHeaderState`, until
      ;; the slice that reads them.
      (make-span-start-node 'value-open 'header-value-span 'value-start #f)
      (make-field-branch-node 'value-start 'equal (list 'header-state HS-UPGRADE)
                              'upgrade-set-flag 'value-start-te #f)
      (make-field-action-node 'upgrade-set-flag 'set-mask (list 'flags F-UPGRADE)
                              'value-state-general #f #f)
      (make-field-branch-node 'value-start-te 'equal
                              (list 'header-state HS-TRANSFER-ENCODING)
                              'te-check-chunked 'value-start-cl #f)
      (make-field-branch-node 'value-start-cl 'equal
                              (list 'header-state HS-CONTENT-LENGTH)
                              'cl-once 'value-start-conn #f)
      (make-field-branch-node 'value-start-conn 'equal
                              (list 'header-state HS-CONNECTION)
                              'conn-value 'value-state-general #f)
      (make-field-action-node 'value-state-general 'store (list 'header-state HS-GENERAL)
                              'value-loop #f #f)

      ;; --- Transfer-Encoding ---------------------------------------------------
      ;;
      ;; ONCE CHUNKED IS CHOSEN NO OTHER CODING IS ALLOWED IN A REQUEST, and
      ;; llhttp enforces that at the START of the next value and at the comma
      ;; inside one. IN A REQUEST -- the whole condition is llhttp's
      ;; `forbidAfterChunkedInRequest`, and RFC 7230 3.3.3 gives a response
      ;; the opposite treatment: a coding after `chunked` is allowed there and
      ;; simply un-chunks the message, so the body runs to end of connection
      ;; instead. `response/transfer-encoding.md#3` records the comma case and
      ;; `#4` the second-header case, both `flags=200` with no CHUNKED bit.
      ;;
      ;; Strict requests take the refusing arm both times, so the span is
      ;; ended -- EMPTY at the value start -- and one byte is skipped before
      ;; the error, because `skipTo` consumes. One refusal serves both sites:
      ;; the value span is open at each.
      (make-field-branch-node 'te-check-chunked 'mask-any (list 'flags F-CHUNKED)
                              'te-restart-type 'te-set-flag #f)
      (make-field-branch-node 'te-restart-type 'equal (list 'type TYPE-REQUEST)
                              'lenient-request-te 'te-set-flag #f)
      ;; TRANSFER_ENCODING: a REQUEST whose transfer coding does not end in
      ;; `chunked` is refused, and this flag accepts it. A response is not
      ;; refused in the first place -- it reads to end of input instead --
      ;; which is why the fork sits under the type test and not above it.
      (lenient-fork 'lenient-request-te 'transfer-encoding
                    'te-set-flag 'te-after-chunked)
      (make-span-end-node 'te-after-chunked 'header-value-span 'te-eat-one #f)
      (make-byte-dispatch-node 'te-eat-one
        '() (make-edge 'e-bad-te-value 'advance) 'e-eof-none #f)
      ;; THE SECOND OF THE TWO SITES that share the one refusal, and so the
      ;; second that the flag has to reach. Missing it left one fixture
      ;; reporting `span[header_value]="chunked"` where the oracle records
      ;; `"chunked, deflate"` -- the span ended at the comma because the
      ;; error path closed it.
      (make-field-branch-node 'te-comma-type 'equal (list 'type TYPE-REQUEST)
                              'lenient-comma-te 'te-chunked #f)
      (lenient-fork 'lenient-comma-te 'transfer-encoding
                    'te-chunked 'te-after-chunked)

      ;; The CHUNKED bit is CLEARED on the way in and set again only by
      ;; `setHeaderFlags` at the end of a value that really was `chunked`, so a
      ;; later coding un-chunks the message rather than adding to it.
      (make-field-action-node 'te-set-flag 'set-mask (list 'flags F-TRANSFER-ENCODING)
                              'te-unset-chunked #f #f)
      ;; AND THAT CLEAR IS NOW MEASURED. Through M6 it only ever ran with the
      ;; bit already clear, because the branch above refused every request
      ;; that could have set it -- the mutation that removed it survived both
      ;; lanes. `response/transfer-encoding.md#4` is the fixture that reaches
      ;; it with the bit SET: `Transfer-Encoding: chunked` then
      ;; `Transfer-Encoding: identity`, and the second header un-chunks the
      ;; first. The slice that makes an unchecked line observable owes it a
      ;; test, and this is that slice.
      (make-field-action-node 'te-unset-chunked 'clear-mask (list 'flags F-CHUNKED)
                              'te-chunked #f #f)
      (make-keyword-table-node 'te-chunked
        (list (make-keyword-entry (ascii-bytes "chunked") 'te-chunked-last #f))
        (make-edge 'te-token 'reexecute) 'e-eof-header-value #t #f)

      ;; `chunkedchunked` is not chunked: the table takes the first seven bytes
      ;; and the eighth continues the token, so this falls through to the token
      ;; loop and no sub-state is stored. Only SP is skipped here, not HTAB.
      (make-byte-dispatch-node 'te-chunked-last
        (list (make-byte-case (make-exact-byte-matcher SP)
                              (make-edge 'te-chunked-last 'advance) #f)
              (make-byte-case (make-byte-set-matcher (list CR LF))
                              (make-edge 'te-mark-chunked 'reexecute) #f)
              (make-byte-case (make-exact-byte-matcher COMMA)
                              (make-edge 'te-comma-type 'reexecute) #f))
        (make-edge 'te-token 'reexecute) 'e-eof-header-value #f)
      (make-field-action-node 'te-mark-chunked 'store
                              (list 'header-state HS-TRANSFER-ENCODING-CHUNKED)
                              'after-value #f #f)

      (make-byte-dispatch-node 'te-token
        (list (make-byte-case (make-exact-byte-matcher COMMA)
                              (make-edge 'te-token-ows 'advance) #f)
              (make-byte-case (make-byte-set-matcher httparse-connection-token-bytes)
                              (make-edge 'te-token 'advance) #f))
        (make-edge 'value-state-general 'reexecute) 'e-eof-header-value #f)
      (make-byte-dispatch-node 'te-token-ows
        (list (make-byte-case (make-byte-set-matcher (list SP HTAB))
                              (make-edge 'te-token-ows 'advance) #f))
        (make-edge 'te-chunked 'reexecute) 'e-eof-header-value #f)

      ;; --- Connection ----------------------------------------------------------
      ;;
      ;; `close` IS NOT `closed`. The table takes the keyword and reexecutes
      ;; the byte after it; `conn-ws` then finds a byte that is neither comma,
      ;; space nor line ending, resets the sub-state and hands the rest to the
      ;; token loop -- so `closed` sets nothing. This is the pair a Gate 0
      ;; spike measured, and the reason `make-sequence-dispatch-node` could
      ;; not be used here even if the names were case-sensitive.
      (make-byte-dispatch-node 'conn-value
        (list (make-byte-case (make-byte-set-matcher (list SP HTAB))
                              (make-edge 'conn-value 'advance) #f))
        (make-edge 'conn-table 'reexecute) 'e-eof-header-value #f))
      (list
      (make-keyword-table-node 'conn-table
        (map (lambda (row)
               (make-keyword-entry (ascii-bytes (car row))
                                   (conn-state-store-name (cdr row)) #f))
             connection-keyword-states)
        (make-edge 'conn-token 'reexecute) 'e-eof-header-value #t #f))
      (conn-state-store-nodes)
      (list
      (make-byte-dispatch-node 'conn-ws
        (list (make-byte-case (make-exact-byte-matcher COMMA)
                              (make-edge (set-header-flags-entry "shf-comma") 'advance) #f)
              (make-byte-case (make-byte-set-matcher (list SP HTAB))
                              (make-edge 'conn-ws 'advance) #f)
              (make-byte-case (make-byte-set-matcher (list CR LF))
                              (make-edge 'after-value 'reexecute) #f))
        (make-edge 'conn-token-reset 'reexecute) 'e-eof-header-value #f)
      (make-field-action-node 'conn-token-reset 'store (list 'header-state HS-GENERAL)
                              'conn-token #f #f)
      (make-byte-dispatch-node 'conn-token
        (list (make-byte-case (make-exact-byte-matcher COMMA)
                              (make-edge 'conn-value 'advance) #f)
              (make-byte-case (make-byte-set-matcher httparse-connection-token-bytes)
                              (make-edge 'conn-token 'advance) #f))
        (make-edge 'after-value 'reexecute) 'e-eof-header-value #f)

      ;; --- Content-Length ------------------------------------------------------
      ;;
      ;; The flag is tested where the VALUE starts, not where the name matches,
      ;; so a duplicate reports after the second name has completed.
      (make-field-branch-node 'cl-once 'mask-any (list 'flags F-CONTENT-LENGTH)
                              'e-duplicate-content-length 'cl-digits #f)

      ;; THE OFFENDING DIGIT IS CONSUMED BEFORE THE OVERFLOW IS REPORTED, and
      ;; that is the whole of `off=56 len=21` for a 22-digit length. llhttp
      ;; `select`s the digit -- which consumes -- and only then runs `mulAdd`,
      ;; so the value span holds the digit that broke it. This node reexecutes
      ;; on overflow instead, so the digit is eaten here, one dispatch wide.
      ;; Both overflow on the SAME digit: the check is `v > (max - d) / base`
      ;; against a uint64 either way, which for `1` followed by zeros is the
      ;; twenty-first.
      (make-integer-accumulate-node 'cl-digits 'content-length 10
                                    'cl-digits
                                    (make-edge 'cl-ws 'reexecute)
                                    'cl-overflow-eat
                                    'e-eof-header-value #f)
      (make-byte-dispatch-node 'cl-overflow-eat
        (list (make-byte-case (make-byte-set-matcher (map digit DIGITS))
                              (make-edge 'cl-overflow-close 'advance) #f))
        (make-edge 'cl-overflow-close 'reexecute) 'e-eof-header-value #f)
      (make-span-end-node 'cl-overflow-close 'header-value-span
                          'e-content-length-overflow #f)

      ;; Trailing spaces are MATCHED, so they are consumed and the span ends
      ;; past them: `Content-Length: 4 ` records `span[header_value]="4 "`.
      ;; Anything else is a reason of its own, at the character, with the span
      ;; ended first so the digits still render.
      (make-byte-dispatch-node 'cl-ws
        (list (make-byte-case (make-byte-set-matcher (list SP HTAB))
                              (make-edge 'cl-ws 'advance) #f)
              (make-byte-case (make-byte-set-matcher (list CR LF))
                              (make-edge 'cl-set-flag 'reexecute) #f))
        (make-edge 'cl-bad-close 'reexecute) 'e-eof-header-value #f)
      (make-field-action-node 'cl-set-flag 'set-mask (list 'flags F-CONTENT-LENGTH)
                              'after-value #f #f)
      (make-span-end-node 'cl-bad-close 'header-value-span
                          'e-bad-content-length-char #f)
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
        (make-edge 'lenient-value-char 'reexecute) 'e-eof-header-value #f)
      ;; LENIENT_HEADERS, fifth: the value accepts ANYTHING until the line
      ;; ends. llhttp asks HEADERS first and HEADER_VALUE_RELAXED second, so
      ;; the strict arm here is where that second flag's fork will go.
      (lenient-fork 'lenient-value-char 'headers
                    'value-lenient 'lenient-value-relaxed)
      ;; HEADER_VALUE_RELAXED, asked only when HEADERS was not -- upstream
      ;; nests the two tests, and the comment beside them says why: HEADERS
      ;; "accepts anything in values, drops some other header validation
      ;; too", where this one "accepts only specific extra (common but
      ;; discouraged) chars".
      (lenient-fork 'lenient-value-relaxed 'header-value-relaxed
                    'value-relaxed 'value-close-bad)
      ;; `header_value_relaxed`, with ONE DELIBERATE DIFFERENCE, marked here
      ;; because it is a divergence and not a transcription.
      ;;
      ;; Upstream's node is `.match(RELAXED_HEADER_CHARS, itself)
      ;; .otherwise(header_value_otherwise)`, and `header_value_otherwise`
      ;; falls back here for any byte that is not CR or LF. RELAXED covers
      ;; every byte but NUL, CR and LF -- so a NUL in a header value under
      ;; this flag alone walks relaxed -> otherwise -> relaxed forever, with
      ;; no byte consumed. This generator's verifier refuses that outright as
      ;; a zero-progress cycle, and is right to.
      ;;
      ;; So the three bytes upstream leaves to the fall-back are handled here
      ;; instead: CR and LF exactly as `after-value` handles them, and NUL as
      ;; the `Invalid header value char` the strict parser would have given.
      ;; NO ORACLE CAN SETTLE WHICH IS RIGHT: the fixture binary takes its
      ;; input as argv, so a NUL cannot be fed to it at all.
      (make-byte-dispatch-node 'value-relaxed
        (list (make-byte-case (make-byte-set-matcher httparse-relaxed-header-bytes)
                              (make-edge 'value-relaxed 'advance) #f)
              (make-byte-case (make-exact-byte-matcher CR)
                              (make-edge 'value-close 'reexecute) #f)
              (make-byte-case (make-exact-byte-matcher LF)
                              (make-edge 'value-close-no-cr 'reexecute) #f))
        (make-edge 'value-close-bad 'reexecute) 'e-eof-header-value #f)
      ;; `header_value_lenient`. Its LF arm does NOT consult
      ;; OPTIONAL_CR_BEFORE_LF -- once a value is lenient a bare LF ends it,
      ;; where `header_value_otherwise` would have asked. Faithful to
      ;; upstream, and not obvious from either node alone.
      (make-byte-dispatch-node 'value-lenient
        (list (make-byte-case (make-exact-byte-matcher CR)
                              (make-edge 'value-close 'reexecute) #f)
              (make-byte-case (make-exact-byte-matcher LF)
                              (make-edge 'value-close-lenient-lf 'reexecute) #f))
        (make-edge 'value-lenient 'advance) 'e-eof-header-value #f)
      (make-span-end-node 'value-close-lenient-lf 'header-value-span
                          'value-almost-done #f)
      (make-span-end-node 'value-close 'header-value-span 'eat-cr #f)
      (make-span-end-node 'value-close-no-cr 'header-value-span 'lenient-lf-value #f)
      (lenient-fork 'lenient-lf-value 'optional-cr-before-lf 'value-almost-done 'e-cr-after-value)
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
                              (make-edge 'lenient-value-lws 'reexecute) #f))
        (make-edge (set-header-flags-entry "shf-complete") 'reexecute) 'e-eof-none #f)
      ;; LENIENT_HEADERS, sixth: the continuation line becomes MORE VALUE.
      ;; The whitespace is peeked, so the re-opened span starts at it and the
      ;; folded value carries the fold's own spaces -- which is what the
      ;; recorded traces show.
      (lenient-fork 'lenient-value-lws 'headers 'value-lws-fold 'e-ws-after-value)
      ;; AND A CHUNKED TRANSFER-ENCODING IS FORGOTTEN ACROSS THE FOLD. llhttp
      ;; loads `header_state` here and resets it for
      ;; `TRANSFER_ENCODING_CHUNKED` alone, so `Transfer-Encoding: chunked`
      ;; continued on a folded line stops being chunked. Nothing else about
      ;; the fold depends on the state, and no other state is reset.
      (make-field-branch-node 'value-lws-fold 'equal
                              (list 'header-state HS-TRANSFER-ENCODING-CHUNKED)
                              'value-lws-reset-state 'value-open #f)
      (make-field-action-node 'value-lws-reset-state 'store
                              (list 'header-state HS-GENERAL) 'value-open #f #f))
      (set-header-flags-nodes "shf-complete" 'value-complete)
      (set-header-flags-nodes "shf-comma" 'conn-value)
      (list
      (ev 'value-complete 'on-header-value-complete 'header-field-start)

      ;; --- the empty line ------------------------------------------------------
      ;;
      ;; ONE NODE ENDS TWO DIFFERENT BLOCKS. The header section and a chunked
      ;; message's trailers are the same states, so the empty line that closes
      ;; them is the same node -- and what it means is decided by the flag the
      ;; zero chunk set, not by where the parser came from.
      (make-byte-dispatch-node 'headers-almost-done
        (list (make-byte-case (make-exact-byte-matcher LF)
                              (make-edge 'check-trailing 'advance) #f))
        (make-edge 'lenient-lf-after-headers 'reexecute) 'e-eof-none #f)
      ;; OPTIONAL_LF_AFTER_CR, third: the CR of the blank line that ends the
      ;; header section. The lenient arm joins `check-trailing`, so a message
      ;; whose headers end `\r` alone still decides trailer-versus-body the
      ;; same way.
      (lenient-fork 'lenient-lf-after-headers 'optional-lf-after-cr
                    'check-trailing 'e-lf-after-headers)
      (make-field-branch-node 'check-trailing 'mask-any (list 'flags F-TRAILING)
                              'trailer-chunk-complete 'before-headers-complete #f)
      ;; The zero chunk's own `chunk complete`, fired after its trailers rather
      ;; than at the chunk itself -- which is why a trailer section's header
      ;; lines sit BETWEEN `chunk header len=0` and `chunk complete` in the
      ;; corpus (request/transfer-encoding.md#7).
      (ev 'trailer-chunk-complete 'on-chunk-complete 'message-complete)

      ;; llhttp's `before_headers_complete`, which runs so the callback can see
      ;; the answer: a message upgrades when it carries BOTH upgrade bits AND
      ;; is entitled to, or when its method is CONNECT.
      ;;
      ;; ENTITLEMENT IS WHERE A RESPONSE DIFFERS. For a request the two bits
      ;; are enough; for a response `Connection: upgrade` and `Upgrade: foo`
      ;; are only an ANNOUNCEMENT unless the status is 101, which is llhttp's
      ;; own comment and is measured twice: `response/connection.md#13` and
      ;; `#14` carry both bits under a 200 and record no pause at all, where
      ;; the same headers under a 101 record one.
      (make-field-branch-node 'before-headers-complete 'mask-all
                              (list 'flags (+ F-UPGRADE F-CONNECTION-UPGRADE))
                              'bhc-upgrade-request 'bhc-check-connect #f)
      (make-field-branch-node 'bhc-upgrade-request 'equal (list 'type TYPE-REQUEST)
                              'bhc-upgrade-yes 'bhc-switching #f)
      ;; AND THIS ONE SETS A FIELD THE 101 PATH NEVER READS, so the mutation
      ;; that moves it to 100 survives every lane. `upgrade` is consulted by
      ;; the body decision and by the end of a body; a 101 takes neither,
      ;; because `ahc-switching` pauses it by a second and independent route.
      ;; The value still matters -- llhttp's `parser->upgrade` is what an
      ;; embedder reads after a paused-upgrade result, which is a surface no
      ;; trace can show -- so it is llhttp's and it stays.
      (make-field-branch-node 'bhc-switching 'equal (list 'status-code 101)
                              'bhc-upgrade-yes 'bhc-upgrade-no #f)
      ;; The `else` arm, and it needs no type test of its own: a response's
      ;; `method` is the field's initial 0, which is DELETE and not CONNECT.
      (make-field-branch-node 'bhc-check-connect 'equal
                              (list 'method (method-number "CONNECT"))
                              'bhc-upgrade-yes 'bhc-upgrade-no #f)
      (make-field-action-node 'bhc-upgrade-yes 'store (list 'upgrade 1)
                              'headers-complete #f #f)
      (make-field-action-node 'bhc-upgrade-no 'store (list 'upgrade 0)
                              'headers-complete #f #f)

      ;; `ev` cannot express this one: it is the callback with a branch.
      ;; The pause continuation is still `after-headers`, the place an
      ;; unanswered run goes, because pausing here IS answerable -- upstream
      ;; resumes into its own `headers_done`.
      (make-callback-node 'headers-complete 'on-headers-complete 'after-headers
                          (list (list 'skip-body 'headers-complete-skip-body))
                          'after-headers #f)
      (make-field-action-node 'headers-complete-skip-body 'set-mask
                              (list 'flags F-SKIP-BODY) 'after-headers #f #f)

      ;; THE UPGRADE ARM COMES FIRST, and it is why `CONNECT` with a
      ;; Content-Length of 10 reads no body at all:
      ;;
      ;;   ( upgrade && (method == CONNECT || !hasBody) )
      ;;     || (type == RESPONSE && status_code == 101)   ->  complete, PAUSE
      ;;
      ;; with `hasBody` being chunked-or-a-nonzero-length, and skip-body the
      ;; second disjunct -- `ahc-upgrade-skip-body` below. M9 added it when
      ;; the embedder gained a way to say so.
      (make-field-branch-node 'after-headers 'nonzero (list 'upgrade)
                              'after-headers-connect 'ahc-switching-type #f)
      (make-field-branch-node 'after-headers-connect 'equal
                              (list 'method (method-number "CONNECT"))
                              'message-complete-pause 'ahc-upgrade-skip-body #f)
      ;; THE SECOND DISJUNCT OF THE UPGRADE TEST:
      ;;   upgrade && (CONNECT || SKIPBODY || !hasBody)
      ;; An upgrade whose embedder said "no body" exits here rather than
      ;; reading the length it declared. NO VENDORED FIXTURE ARMS SKIP-BODY ON
      ;; AN UPGRADE, so this arm is transcribed from `src/native/http.c` and
      ;; checked by a unit case that says so; the corpus cannot vouch for it.
      (make-field-branch-node 'ahc-upgrade-skip-body 'mask-any
                              (list 'flags F-SKIP-BODY)
                              'message-complete-pause 'after-headers-has-chunked #f)
      (make-field-branch-node 'after-headers-has-chunked 'mask-any
                              (list 'flags F-CHUNKED)
                              'ahc-switching-type 'after-headers-has-length #f)
      (make-field-branch-node 'after-headers-has-length 'nonzero
                              (list 'content-length)
                              'ahc-switching-type 'message-complete-pause #f)

      ;; --- the five status codes that decide a response's body ----------------
      ;;
      ;; 101 exits to another protocol; 100, 102, 103, 204 and 304 have no
      ;; body at all. llhttp writes each as `type == HTTP_RESPONSE && status_
      ;; code == N`, and the type half of every one of those conjunctions is
      ;; REDUNDANT HERE AND KEPT ANYWAY: `status-code` is written only on the
      ;; response path and re-zeroed at every status line, so a request can
      ;; never carry one of these numbers. It is llhttp's structure, it costs
      ;; one zero-width branch, and it is what BOTH mode would need. A
      ;; mutation that inverts `ahc-switching-type` therefore survives both
      ;; lanes, and that is this paragraph rather than a missing test.
      (make-field-branch-node 'ahc-switching-type 'equal (list 'type TYPE-RESPONSE)
                              'ahc-switching 'ahc-skip-body #f)
      ;; 101 RETURNS 1 AND SO PAUSES WHATEVER `upgrade` SAYS, which is why it
      ;; joins the arm above rather than the no-body one below. Every 101 in
      ;; the corpus also carries the two upgrade bits, so the two routes agree
      ;; there; a 101 without them is where they would not, and llhttp's is
      ;; the one reproduced.
      (make-field-branch-node 'ahc-switching 'equal (list 'status-code 101)
                              'message-complete-pause 'ahc-continue #f)
      ;; FOUR OF THESE FIVE OVERLAP `message_needs_eof`, WHICH IS WHY ONE OF
      ;; THEM CANNOT BE MEASURED. On a response with no framing header the
      ;; two questions agree -- this arm answers "no body" and the needs-eof
      ;; test below answers "no eof", and either alone produces the right
      ;; trace. They part only when such a status arrives WITH a
      ;; `Content-Length` or a `Transfer-Encoding`, and the corpus records
      ;; that for 304 alone (`response/connection.md#15` and `#16`). So the
      ;; 304 mutation is caught and the 204 one survives every lane;
      ;; `corpus-load-tests.sps` pins which of the five the oracle separates,
      ;; and a refresh that adds one turns that check red.
      (make-field-branch-node 'ahc-continue 'equal (list 'status-code 100)
                              'message-complete-done 'ahc-processing #f)
      (make-field-branch-node 'ahc-processing 'equal (list 'status-code 102)
                              'message-complete-done 'ahc-early-hints #f)
      (make-field-branch-node 'ahc-early-hints 'equal (list 'status-code 103)
                              'message-complete-done 'ahc-no-content #f)
      (make-field-branch-node 'ahc-no-content 'equal (list 'status-code 204)
                              'message-complete-done 'ahc-not-modified #f)
      (make-field-branch-node 'ahc-not-modified 'equal (list 'status-code 304)
                              'message-complete-done 'ahc-skip-body #f)
      ;; THE OTHER PLACE THE FLAG IS READ:
      ;;   SKIPBODY || (response && (102 || 103 || 204 || 304))  ->  no body
      ;; llhttp writes it as one disjunction and puts SKIPBODY first; here it
      ;; sits where the two TYPES CONVERGE instead, which is the same answer
      ;; for every input and one node rather than two. A request reaches it
      ;; from the type test above, a response from the last status test, and
      ;; the four statuses that precede it already answer `no body` on their
      ;; own -- so testing the flag before or after them cannot differ.
      (make-field-branch-node 'ahc-skip-body 'mask-any (list 'flags F-SKIP-BODY)
                              'message-complete-done 'after-headers-chunked #f)

      ;; THE PAUSE CARRIES ITS REASON, which llhttp's harness prints as an
      ;; error line and which this parser can therefore render. It is still a
      ;; PAUSE: the result's status is `paused`, its error slot is #f, and the
      ;; continuation is where a resumed feed re-enters. The optional reason
      ;; came from this project's third upstream brief.
      (make-pause-node 'upgrade-pause 'after-message 'upgrade-paused #f)

      ;; --- is there a body? ----------------------------------------------------
      ;;
      ;; llhttp asks a C callback, `llhttp__after_headers_complete`, and for a
      ;; REQUEST its answer collapses to a short tree: `message_needs_eof` is
      ;; unconditionally 0 for requests, and upgrade and skip-body are decided
      ;; above. What is left is
      ;;
      ;;   CHUNKED                      -> read chunks
      ;;   TRANSFER_ENCODING, not chunked -> error, a request may not say that
      ;;   CONTENT_LENGTH and nonzero   -> read that many bytes
      ;;   otherwise                    -> no body
      ;;
      ;; This slice can make the third condition true, so its two branches are
      ;; here. The chunked and transfer-encoding arms wait for the slice that
      ;; can set their flags -- an unreachable node is refused, not stubbed.
      ;;
      ;; A CONTENT LENGTH OF ZERO IS NOT AN EMPTY BODY. llhttp answers 0 -- no
      ;; body at all -- so there is no `span[body]=""` for `Content-Length: 0`,
      ;; which is the opposite of what an empty HEADER value does.
      ;; CHUNKED FIRST -- it overrides a Content-Length that is also present.
      (make-field-branch-node 'after-headers-chunked 'mask-any (list 'flags F-CHUNKED)
                              'chunk-size-start 'after-headers-te #f)
      ;; A message that named a transfer coding and did not end with `chunked`
      ;; has no reliable body length, and RFC 7230 3.3.3 gives the two kinds
      ;; opposite remedies: a REQUEST is refused (llhttp returns 5, after the
      ;; line that printed the flag) and a RESPONSE is read until the
      ;; connection closes (returns 4). `response/transfer-encoding.md#5`
      ;; records the second.
      (make-field-branch-node 'after-headers-te 'mask-any (list 'flags F-TRANSFER-ENCODING)
                              'ahc-coding-type 'after-headers-cl #f)
      (make-field-branch-node 'ahc-coding-type 'equal (list 'type TYPE-REQUEST)
                              'lenient-request-coding 'body-eof #f)
      ;; TWO FLAGS SUPPRESS THIS ONE REFUSAL, and the test is in llhttp's C
      ;; rather than its grammar -- `llhttp__after_headers_complete` reads
      ;;
      ;;   type == HTTP_REQUEST &&
      ;;   (lenient_flags & LENIENT_CHUNKED_LENGTH) == 0 &&
      ;;   (lenient_flags & LENIENT_TRANSFER_ENCODING) == 0
      ;;
      ;; so EITHER flag is enough. Grepping `src/llhttp/*.ts` for the flag
      ;; names does not find it, which is how four fixtures across two
      ;; different flags came to fail at the same line.
      ;;
      ;; A response is not refused here at all: it reads to end of input,
      ;; which is the `body-eof` arm above.
      (lenient-fork 'lenient-request-coding 'chunked-length
                    'body-eof 'lenient-request-coding-te)
      (lenient-fork 'lenient-request-coding-te 'transfer-encoding
                    'body-eof 'e-request-invalid-te)
      (make-field-branch-node 'after-headers-cl 'mask-any (list 'flags F-CONTENT-LENGTH)
                              'body-length-check (needs-eof-entry "ahc-eof") #f)
      (make-field-branch-node 'body-length-check 'nonzero (list 'content-length)
                              'body-open 'message-complete-done #f))
      ;; NO FRAMING HEADER AT ALL, which is the one place the body decision
      ;; asks llhttp's other function: a request ends here (`needs_eof` is 0
      ;; for one) and a response reads until the connection closes.
      (needs-eof-nodes "ahc-eof" 'body-eof 'message-complete-done)
      (list

      ;; The counted consume DECREMENTS `content-length` as it goes, which is
      ;; llhttp's own `p.consume('content_length')`; the number the trace
      ;; prints was already printed by then.
      (make-span-start-node 'body-open 'body-span 'body-consume #f)
      (make-counted-consume-node 'body-consume 'content-length 'body-close 'e-eof-body #f)
      (make-span-end-node 'body-close 'body-span 'message-complete #f)

      ;; --- a body the connection ends -----------------------------------------
      ;;
      ;; llhttp's `body_identity_eof`: raise `finish` to SAFE_WITH_CB, open
      ;; the body span, and consume everything for ever. THE SPAN NEVER
      ;; CLOSES and there is no `message complete` -- `response/sample.md#19`
      ;; records `span[body]="hello world"` as its last line, and
      ;; `response/sample.md#5` records nothing after `headers complete` at
      ;; all. What ends the message is the CONNECTION, which is a fact the
      ;; parser is told rather than one it reads, and `finish` is where it is
      ;; told what that would mean: SAFE_WITH_CB says "complete, but only
      ;; once someone says the input stopped".
      (make-field-action-node 'body-eof 'store (list 'finish FINISH-SAFE-WITH-CB)
                              'body-eof-open #f #f)
      (make-span-start-node 'body-eof-open 'body-span 'body-eof-consume #f)
      (make-byte-dispatch-node 'body-eof-consume
        '() (make-edge 'body-eof-consume 'advance) 'body-eof-end #f)
      ;; Reached only if an embedder calls `parser-finish!`, which the corpus
      ;; driver never does (decision 0016): llhttp's own harness prints the
      ;; `finish` FIELD and does not end the parse. The completion fired here is
      ;; therefore the ONE the corpus cannot witness, and `unit.finish` is its
      ;; test.
      ;;
      ;; llhttp's `llhttp_finish` fires `on_message_complete` for a SAFE_WITH_CB
      ;; finish (`api.c:143-150`) and propagates a non-OK return from it before
      ;; answering OK. `finish` is SAFE_WITH_CB on exactly the path that reaches
      ;; here -- `body-eof` set it above -- so the completion is unconditional
      ;; rather than a read of the field: the graph already tells the arms
      ;; apart. The span END comes first, flushing the identity-eof body llhttp
      ;; delivers before it completes; then `on-message-complete`, whose `ev`
      ;; pause arm carries a callback's non-OK answer back out of
      ;; `parser-finish!`.
      (make-span-end-node 'body-eof-end 'body-span 'body-eof-complete #f)
      (ev 'body-eof-complete 'on-message-complete 'body-eof-stop)
      (make-finish-node 'body-eof-stop #f)

      ;; --- chunked bodies ------------------------------------------------------
      ;;
      ;; THE CHUNK SIZE IS `content-length`. llhttp accumulates it into the
      ;; same field a fixed-length body counts down, zeroing it at the start of
      ;; every chunk, and its `on_chunk_header` prints that field -- which is
      ;; why `chunk header len=` needs no field of its own and why the size
      ;; can be handed straight to the same counted consume.
      ;;
      ;; THE BASE IS SIXTEEN. `request/transfer-encoding.md#3` and `#4` are the
      ;; same ten bytes under `a` and `A`, which fixes the digit set; nothing in
      ;; the corpus separates base ten from base sixteen, because every other
      ;; size in it is below ten.
      (make-field-action-node 'chunk-size-start 'store (list 'content-length 0)
                              'chunk-size-digit #f #f)

      ;; TWO ACCUMULATORS, NOT ONE, because a size must have at least one
      ;; digit: the first non-digit is an error where the size begins and a
      ;; delimiter after it. Both continue at the second.
      (make-integer-accumulate-node 'chunk-size-digit 'content-length 16
                                    'chunk-size
                                    (make-edge 'e-bad-chunk-size 'reexecute)
                                    'chunk-size-overflow-eat
                                    'e-eof-none #f)
      (make-integer-accumulate-node 'chunk-size 'content-length 16
                                    'chunk-size
                                    (make-edge 'chunk-size-otherwise 'reexecute)
                                    'chunk-size-overflow-eat
                                    'e-eof-none #f)

      ;; The same one-dispatch shim `cl-overflow-eat` is, for the same reason:
      ;; llhttp `select`s the digit -- which CONSUMES -- and runs `mulAdd`
      ;; after, so the offending digit is behind the parser when the overflow
      ;; reports. NO FIXTURE REACHES THIS ONE. The corpus carries no chunk size
      ;; above 51 and no `Chunk size overflow` line at all, so the offset here
      ;; rests on the shared llhttp production rather than on a recorded trace
      ;; -- it is the same `mulAdd` helper behind the same `select`, and having
      ;; the two copies differ is the outcome worth avoiding.
      (make-byte-dispatch-node 'chunk-size-overflow-eat
        (list (make-byte-case (make-byte-set-matcher httparse-hex-bytes)
                              (make-edge 'e-chunk-size-overflow 'advance) #f))
        (make-edge 'e-chunk-size-overflow 'reexecute) 'e-eof-none #f)

      ;; What may follow the digits. The space is MATCHED into a lenient test
      ;; strict mode refuses, so its error is one PAST the space --
      ;; request/transfer-encoding.md#31 records off=51 for a space at 50 --
      ;; while the catch-all does not consume and reports AT the byte.
      ;; SPACES_AFTER_CHUNK_SIZE: whitespace between the size and its line
      ;; ending. The space is consumed either way, and the lenient arm
      ;; re-enters this node -- so a run of them is eaten one at a time,
      ;; which is upstream's shape and terminates because each pass advances.
      (lenient-fork 'lenient-chunk-size-space 'spaces-after-chunk-size
                    'chunk-size-otherwise 'e-bad-chunk-size)
      (make-byte-dispatch-node 'chunk-size-otherwise
        (list (make-byte-case (make-byte-set-matcher (list SP HTAB))
                              (make-edge 'lenient-chunk-size-space 'advance) #f)
              (make-byte-case (make-exact-byte-matcher CR)
                              (make-edge 'chunk-size-almost-done 'advance) #f)
              (make-byte-case (make-exact-byte-matcher LF)
                              (make-edge 'lenient-lf-chunk-size 'advance) #f)
              (make-byte-case (make-exact-byte-matcher SEMICOLON)
                              (make-edge 'chunk-extensions 'advance) #f))
        (make-edge 'e-bad-chunk-size 'reexecute) 'e-eof-none #f)

      (make-byte-dispatch-node 'chunk-size-almost-done
        (list (make-byte-case (make-exact-byte-matcher LF)
                              (make-edge 'chunk-size-header 'advance) #f))
        (make-edge 'lenient-lf-after-chunk-size 'reexecute) 'e-eof-none #f)
      ;; OPTIONAL_LF_AFTER_CR, fourth: after a chunk size.
      (lenient-fork 'lenient-lf-after-chunk-size 'optional-lf-after-cr
                    'chunk-size-header 'e-lf-after-chunk-size)

      ;; llhttp's `chunk_size_almost_done_lf`. The callback fires with the size
      ;; still whole: the consume below decrements the same field as it goes.
      (ev 'chunk-size-header 'on-chunk-header 'chunk-size-test)
      ;; A ZERO CHUNK IS NOT AN EMPTY ONE. It ends the body and re-enters the
      ;; header section for the trailers, with the flag that tells the empty
      ;; line which block it just closed.
      (make-field-branch-node 'chunk-size-test 'zero (list 'content-length)
                              'chunk-trailing-flag 'chunk-data-open #f)
      (make-field-action-node 'chunk-trailing-flag 'set-mask (list 'flags F-TRAILING)
                              'header-field-start #f #f)

      ;; The same span and the same counted consume a fixed-length body uses,
      ;; and the same end-of-input node: a chunk's data is body data, and the
      ;; corpus renders it as `span[body]`.
      (make-span-start-node 'chunk-data-open 'body-span 'chunk-data-consume #f)
      (make-counted-consume-node 'chunk-data-consume 'content-length
                                 'chunk-data-close 'e-eof-body #f)
      (make-span-end-node 'chunk-data-close 'body-span 'chunk-data-almost-done #f)

      ;; ONE NODE MATCHING TWO SEQUENCES, which is llhttp's own shape here --
      ;; `.match('\r\n', ...)` beside `.match('\n', ...)`. A CR already
      ;; consumed STAYS consumed when the LF does not arrive, so the strict
      ;; error lands at the byte that was not an LF: request/transfer-
      ;; encoding.md#29 records off=84 for five bytes of data ending at 84.
      (make-sequence-dispatch-node 'chunk-data-almost-done
        (list (make-sequence-case (list CR LF) 'chunk-complete #f)
              (make-sequence-case (list LF) 'lenient-lf-chunk-data #f))
        (make-edge 'lenient-crlf-after-chunk 'reexecute) 'e-eof-none #f)
      ;; OPTIONAL_CRLF_AFTER_CHUNK, and it is the whole flag: a chunk's data
      ;; may be followed by NEITHER a CR nor an LF, and the next chunk header
      ;; begins immediately. Its sibling flag OPTIONAL_CR_BEFORE_LF covers
      ;; the bare-LF case on the arm above; this one covers neither-of-them,
      ;; which is why the two are separate flags and not one.
      (lenient-fork 'lenient-crlf-after-chunk 'optional-crlf-after-chunk
                    'chunk-complete 'e-lf-after-chunk-data)

      (ev 'chunk-complete 'on-chunk-complete 'chunk-size-start)

      ;; --- chunk extensions ----------------------------------------------------
      ;;
      ;; `chunk-size ; name = value ; name ; name = "quoted" CRLF`, with the
      ;; name and the value each delivered as a span and each followed by its
      ;; own complete event.
      ;;
      ;; THE SPAN CLOSES AT ITS DELIMITER AND THE EVENT FIRES PAST IT. llhttp
      ;; PEEKS the delimiter to end the span and then SKIPS it, which is why
      ;; `request/transfer-encoding.md#8` records `span[chunk_extension_name]`
      ;; at 88 for ten bytes and `chunk_extension_name complete` at 99 rather
      ;; than 98. The shape here splits that into a span end, a dispatch that
      ;; re-reads the delimiter, and one callback node per arm -- the same
      ;; close-then-decide shape `after-value` uses in the header section, and
      ;; the reason the dispatch can be shared is that every delimiter falls
      ;; through the loop's own catch-all.
      ;;
      ;; THE BARE LF ARM DOES NOT SKIP. It is llhttp's one `.peek` that ends
      ;; the span WITHOUT a `skipTo`, so its error lands AT the LF while every
      ;; other arm's lands past its delimiter.
      ;;
      ;; SIX OF THE EIGHT REASONS BELOW ARE UNRECORDED. Of everything the
      ;; extension states can report, the corpus carries exactly two --
      ;; `Invalid character in chunk extensions` (#10) and `... quoted value`
      ;; (#12) -- and the M5 mutation pass proved it by surviving in BOTH
      ;; lanes when the other arms were changed. The corpus-load lane pins
      ;; that count, so a refresh that brings evidence goes red rather than
      ;; quiet.
      ;;
      ;; What stands behind the six is the IDIOM rather than the arm, and each
      ;; idiom is measured somewhere the corpus can see:
      ;;
      ;;   end().skipTo(error)   one past the byte    the quoted catch-all, #12
      ;;   .otherwise(error)     AT the byte          chunk_size_digit's, #24
      ;;   .peek(LF, end(...))   AT the LF            the header value's
      ;;                                              `Missing expected CR`
      ;;   .match(byte, error)   one past the byte    chunk_extensions', #10
      (make-byte-dispatch-node 'chunk-extensions
        (list (make-byte-case (make-byte-set-matcher (list SP CR))
                              (make-edge 'e-bad-chunk-ext 'advance) #f))
        (make-edge 'chunk-ext-name-open 'reexecute) 'e-eof-none #f)

      (make-span-start-node 'chunk-ext-name-open 'chunk-ext-name-span
                            'chunk-ext-name #f)
      (make-byte-dispatch-node 'chunk-ext-name
        (list (make-byte-case (make-byte-set-matcher httparse-tchar-bytes)
                              (make-edge 'chunk-ext-name 'advance) #f))
        (make-edge 'chunk-ext-name-close 'reexecute) 'e-eof-chunk-ext-name #f)
      (make-span-end-node 'chunk-ext-name-close 'chunk-ext-name-span
                          'chunk-ext-name-after #f)
      ;; The catch-all SKIPS the byte it refused and fires no complete event --
      ;; llhttp's `.otherwise(end().skipTo(error))`, where the four named arms
      ;; all announce the name and this one does not.
      (make-byte-dispatch-node 'chunk-ext-name-after
        (list (make-byte-case (make-exact-byte-matcher EQUALS)
                              (make-edge 'chunk-ext-name-done-eq 'advance) #f)
              (make-byte-case (make-exact-byte-matcher SEMICOLON)
                              (make-edge 'chunk-ext-name-done-semi 'advance) #f)
              (make-byte-case (make-exact-byte-matcher CR)
                              (make-edge 'chunk-ext-name-done-cr 'advance) #f)
              (make-byte-case (make-exact-byte-matcher LF)
                              (make-edge 'chunk-ext-name-done-lf 'reexecute) #f))
        (make-edge 'e-bad-chunk-ext-name 'advance) 'e-eof-none #f)

      ;; THE TWO ZERO-WIDTH STEPS ARE IN THE OTHER ORDER FROM llhttp'S, and
      ;; the trace cannot tell. llhttp opens the value span and THEN fires the
      ;; name's complete event; a callback reached with a span open is refused
      ;; here (`span-active-at-pause`), because a pause there would strand the
      ;; span. Both steps are zero-width and land on the byte after the `=`, so
      ;; firing the event first produces the same line at the same offset --
      ;; and it is the order that stays correct if the callback ever pauses.
      (ev 'chunk-ext-name-done-eq 'on-chunk-extension-name-complete
          'chunk-ext-value-open)
      (make-span-start-node 'chunk-ext-value-open 'chunk-ext-value-span
                            'chunk-ext-value #f)
      (ev 'chunk-ext-name-done-semi 'on-chunk-extension-name-complete
          'chunk-extensions)
      (ev 'chunk-ext-name-done-cr 'on-chunk-extension-name-complete
          'chunk-size-almost-done)
      (ev 'chunk-ext-name-done-lf 'on-chunk-extension-name-complete
          'lenient-lf-ext-name)

      ;; A DOUBLE QUOTE IS PART OF THE VALUE, not a wrapper around it. It is
      ;; MATCHED -- consumed with the span still open -- so a quoted value's
      ;; span carries both quotes and is two bytes longer than its text:
      ;; `request/transfer-encoding.md#11` records len=28 for 26 bytes of
      ;; content.
      (make-byte-dispatch-node 'chunk-ext-value
        (list (make-byte-case (make-exact-byte-matcher DQUOTE)
                              (make-edge 'chunk-ext-quoted 'advance) #f)
              (make-byte-case (make-byte-set-matcher httparse-tchar-bytes)
                              (make-edge 'chunk-ext-value 'advance) #f))
        (make-edge 'chunk-ext-value-close 'reexecute) 'e-eof-chunk-ext-value #f)
      (make-span-end-node 'chunk-ext-value-close 'chunk-ext-value-span
                          'chunk-ext-value-after #f)
      (make-byte-dispatch-node 'chunk-ext-value-after
        (list (make-byte-case (make-exact-byte-matcher SEMICOLON)
                              (make-edge 'chunk-ext-value-done-semi 'advance) #f)
              (make-byte-case (make-exact-byte-matcher CR)
                              (make-edge 'chunk-ext-value-done-cr 'advance) #f)
              (make-byte-case (make-exact-byte-matcher LF)
                              (make-edge 'chunk-ext-value-done-lf 'reexecute) #f))
        (make-edge 'e-bad-chunk-ext-value 'advance) 'e-eof-none #f)
      (ev 'chunk-ext-value-done-semi 'on-chunk-extension-value-complete
          'chunk-extensions)
      (ev 'chunk-ext-value-done-cr 'on-chunk-extension-value-complete
          'chunk-size-almost-done)
      (ev 'chunk-ext-value-done-lf 'on-chunk-extension-value-complete
          'lenient-lf-ext-value)

      ;; Inside the quotes. The closing quote is MATCHED and the span ends
      ;; after it; a backslash escapes the NEXT byte whatever it is, so the
      ;; quoted-pair node accepts the whole header set rather than QDTEXT.
      (make-byte-dispatch-node 'chunk-ext-quoted
        (list (make-byte-case (make-byte-set-matcher httparse-qdtext-bytes)
                              (make-edge 'chunk-ext-quoted 'advance) #f)
              (make-byte-case (make-exact-byte-matcher DQUOTE)
                              (make-edge 'chunk-ext-quoted-close 'advance) #f)
              (make-byte-case (make-exact-byte-matcher BACKSLASH)
                              (make-edge 'chunk-ext-quoted-pair 'advance) #f))
        (make-edge 'chunk-ext-quoted-bad-close 'reexecute)
        'e-eof-chunk-ext-value #f)
      (make-span-end-node 'chunk-ext-quoted-close 'chunk-ext-value-span
                          'chunk-ext-quoted-done-value #f)
      (ev 'chunk-ext-quoted-done-value 'on-chunk-extension-value-complete
          'chunk-ext-quoted-done)
      (make-byte-dispatch-node 'chunk-ext-quoted-done
        (list (make-byte-case (make-exact-byte-matcher SEMICOLON)
                              (make-edge 'chunk-extensions 'advance) #f)
              (make-byte-case (make-exact-byte-matcher CR)
                              (make-edge 'chunk-size-almost-done 'advance) #f)
              (make-byte-case (make-exact-byte-matcher LF)
                              (make-edge 'lenient-lf-ext-quoted 'reexecute) #f))
        (make-edge 'e-bad-chunk-ext-quote-value 'reexecute) 'e-eof-none #f)
      (make-byte-dispatch-node 'chunk-ext-quoted-pair
        (list (make-byte-case (make-byte-set-matcher httparse-header-bytes)
                              (make-edge 'chunk-ext-quoted 'advance) #f))
        (make-edge 'chunk-ext-qp-bad-close 'reexecute)
        'e-eof-chunk-ext-value #f)

      ;; Both refusals inside the quotes END THE SPAN FIRST and then skip the
      ;; byte, so what was read still renders and the error is one past it:
      ;; `request/transfer-encoding.md#12` records a nine-byte value and then
      ;; off=115 for the CR at 114.
      (make-span-end-node 'chunk-ext-quoted-bad-close 'chunk-ext-value-span
                          'chunk-ext-quoted-bad-eat #f)
      (make-byte-dispatch-node 'chunk-ext-quoted-bad-eat
        '() (make-edge 'e-bad-chunk-ext-quoted 'advance) 'e-eof-none #f)
      (make-span-end-node 'chunk-ext-qp-bad-close 'chunk-ext-value-span
                          'chunk-ext-qp-bad-eat #f)
      (make-byte-dispatch-node 'chunk-ext-qp-bad-eat
        '() (make-edge 'e-bad-chunk-ext-qp 'advance) 'e-eof-none #f)

      ;; THREE `message complete` SITES, WHICH IS llhttp's OWN COUNT, and they
      ;; differ in what follows rather than in what they report:
      ;;
      ;;   return 1   complete, then PAUSE -- whatever `upgrade` says
      ;;   return 0   complete, then carry on -- ditto
      ;;   a body end complete, then pause ONLY if this message upgraded
      ;;
      ;; Collapsing them would be safe for every fixture in the corpus, since
      ;; return 1 implies `upgrade` everywhere but a 101 with no upgrade
      ;; header and return 0 excludes it everywhere. It is not safe for real
      ;; input, and the whole point of this parser is the bytes nobody
      ;; recorded, so llhttp's three stay three.
      ;;
      ;; THE THIRD IS WHY A BODY IS STILL READ FOR AN UPGRADE THAT HAS ONE:
      ;; `Connection: upgrade` with `Content-Length: 4` has a body, so the
      ;; decision does NOT take the early exit -- it reads the four bytes and
      ;; pauses afterwards.
      (ev 'message-complete-pause 'on-message-complete 'upgrade-pause)
      (ev 'message-complete-done 'on-message-complete 'after-message)
      (ev 'message-complete 'on-message-complete 'after-message-upgrade)
      (make-field-branch-node 'after-message-upgrade 'nonzero (list 'upgrade)
                              'upgrade-pause 'after-message #f)

      ;; --- what a message leaves behind ----------------------------------------
      ;;
      ;; llhttp's `llhttp__after_message_complete` does three things and its
      ;; RETURN VALUE is the fourth: it computes `should_keep_alive` from the
      ;; state as it stands, sets `finish` to SAFE, clears the flags, and
      ;; answers whether to restart. The order matters -- the answer is read
      ;; off the flags the message set, and the flags are cleared after -- so
      ;; the test comes first here and each arm then does its own resetting.
      ;;
      ;; `should_keep_alive` FOR A REQUEST is the version test and one flag:
      ;;
      ;;   major > 0 && minor > 0   ->   keep alive unless CONNECTION_CLOSE
      ;;   otherwise (1.0 or 0.9)   ->   keep alive only if CONNECTION_KEEP_ALIVE
      ;;
      ;; and THEN `return !llhttp_message_needs_eof(parser)`, which is the
      ;; line M6 could leave out: `message_needs_eof` is unconditionally 0 for
      ;; a request, so its negation was always 1. For a response it is the
      ;; whole difference between a connection that restarts and one that
      ;; does not -- `response/connection.md#1` keeps alive on a 204 and
      ;; `#12` does not on a 200 with no framing header, under the same
      ;; version and the same absent `Connection`.
      ;;
      ;; THE ORDER IS LOAD-BEARING TWICE OVER. llhttp reads the answer before
      ;; it clears the flags, and `message_needs_eof` reads those same flags
      ;; -- so the question is asked here, between the version test and the
      ;; resetting, and not inside either arm.
      ;;
      ;; ITS ANSWER IS CONSTANT ON EVERY PATH THAT REACHES IT, and that is a
      ;; property of the graph rather than of the corpus: a message that
      ;; needs eof is one the body decision sent to `body-eof`, which never
      ;; completes, so nothing needing eof arrives here at all. Inverting the
      ;; answer is caught at once -- every keep-alive would close -- and
      ;; SKIPPING the question is not caught by anything. The milestone that
      ;; adds `parser-finish!` to the driver is the one that can tell the
      ;; difference.
      ;;
      ;; ONE ARM HAS NO STRICT FIXTURE: HTTP/1.0 WITH `Connection: keep-alive`
      ;; restarting. `request/connection.md#4` records it and is lenient, so
      ;; decision 0009 defers it and no gated trace can judge the arm. The
      ;; other three are measured -- #2 for 1.1, #9 for 1.1 with close, #3 for
      ;; 1.0 without keep-alive.
      (make-field-branch-node 'after-message 'nonzero (list 'http-major)
                              'amc-check-minor 'amc-old #f)
      (make-field-branch-node 'amc-check-minor 'nonzero (list 'http-minor)
                              'amc-modern 'amc-old #f)
      (make-field-branch-node 'amc-modern 'mask-any (list 'flags F-CONNECTION-CLOSE)
                              'amc-close (needs-eof-entry "amc-eof") #f)
      (make-field-branch-node 'amc-old 'mask-any (list 'flags F-CONNECTION-KEEP-ALIVE)
                              (needs-eof-entry "amc-eof") 'amc-close #f))
      (needs-eof-nodes "amc-eof" 'amc-close 'amc-keep-alive)
      (list

      ;; THE FLAGS RESET IS WHAT MAKES A SECOND MESSAGE PARSEABLE AT ALL, and
      ;; `request/pipelining.md#1` is the only fixture that measures it: each
      ;; of its three messages carries a `Content-Length`, and the duplicate
      ;; test is `flags & CONTENT_LENGTH`, so a loop that kept the flags would
      ;; report `Duplicate Content-Length` on the second.
      (make-field-action-node 'amc-keep-alive 'store (list 'finish FINISH-SAFE)
                              'restart-clear-flags #f #f)
      (make-field-action-node 'restart-clear-flags 'store (list 'flags 0)
                              'restart-clear-length #f #f)
      (make-field-action-node 'restart-clear-length 'store (list 'content-length 0)
                              'restart-mark #f #f)
      (make-field-action-node 'restart-mark 'store (list 'initial-message-completed 1)
                              'start #f #f)

      (make-field-action-node 'amc-close 'store (list 'finish FINISH-SAFE)
                              'lenient-keep-alive #f #f)
      ;; KEEP_ALIVE: a connection that should close is reused anyway. The
      ;; `finish` store happens FIRST either way -- upstream writes
      ;; `update('finish', FINISH.SAFE, lenientClose)` -- so a lenient parse
      ;; and a strict one agree about that field and differ only in where
      ;; they go next.
      (lenient-fork 'lenient-keep-alive 'keep-alive
                    'restart-clear-flags 'closed-clear-flags)
      (make-field-action-node 'closed-clear-flags 'store (list 'flags 0)
                              'closed #f #f)

      ;; A CLOSED CONNECTION STILL EATS LINE ENDINGS. llhttp matches CR and LF
      ;; back to this node, so the blank line after a body is consumed and only
      ;; the first real byte is data -- `request/connection.md#9` records
      ;; off=138 for a `G` at 137, two CRLFs after the body. The refusal
      ;; CONSUMES that byte, which is what puts the error one past it.
      (make-byte-dispatch-node 'closed
        (list (make-byte-case (make-byte-set-matcher (list CR LF))
                              (make-edge 'closed 'advance) #f))
        (make-edge 'lenient-data-after-close 'advance) 'clean-eof #f)
      ;; DATA_AFTER_CLOSE: the byte is discarded instead of refused. It is
      ;; CONSUMED either way -- upstream `skipTo`s into the test -- so the
      ;; lenient arm returns to `closed` having eaten it, and a closed
      ;; connection quietly swallows everything that follows.
      (lenient-fork 'lenient-data-after-close 'data-after-close
                    'closed 'e-data-after-close)

      ;; The other eight OPTIONAL_CR_BEFORE_LF forks. They are gathered here
      ;; rather than each beside its site because they say the same thing
      ;; eight times, and reading them together is how one notices that the
      ;; chunk-size arm rejoins `chunk-size-almost-done` -- a node that then
      ;; wants an LF it has already eaten. That is upstream's shape, not a
      ;; slip: with this flag ALONE a bare LF after a chunk size still fails,
      ;; at `Expected LF after chunk size`, and it takes OPTIONAL_LF_AFTER_CR
      ;; as well to parse. `lenient_all` sets both, which is the only
      ;; configuration in the corpus that reaches it.
      (lenient-fork 'lenient-lf-chunk-size 'optional-cr-before-lf
                    'chunk-size-almost-done 'e-cr-after-chunk-size)
      (lenient-fork 'lenient-lf-chunk-data 'optional-cr-before-lf
                    'chunk-complete 'e-cr-after-chunk-data)
      (lenient-fork 'lenient-lf-ext-name 'optional-cr-before-lf
                    'chunk-size-almost-done 'e-cr-after-chunk-ext-name)
      (lenient-fork 'lenient-lf-ext-value 'optional-cr-before-lf
                    'chunk-size-almost-done 'e-cr-after-chunk-ext-value)
      (lenient-fork 'lenient-lf-ext-quoted 'optional-cr-before-lf
                    'chunk-size-almost-done 'e-cr-after-chunk-ext-value)
      ;; The two that are NOT `Missing expected CR` errors: a bare LF where a
      ;; field name would start ends the header section, and a bare LF in the
      ;; whitespace before a value ends an empty one.
      (lenient-fork 'lenient-lf-field-start 'optional-cr-before-lf
                    'check-trailing 'e-bad-header-field-char)
      (lenient-fork 'lenient-lf-discard-ws 'optional-cr-before-lf
                    'value-discard-lws 'e-bad-header-value-char)

      ;; --- errors, one node per span state ------------------------------------
      ;; Reached from the table's no-match, where the method span IS open.
      ;; The `-open` in the name is the span state, which is what the
      ;; verifier's flat lattice distinguishes: a node reached with the span
      ;; both open and closed is refused, so a second reason node would be
      ;; needed the day one is reached with it closed.
      (make-error-node 'e-bad-method-open 'bad-method #f)
      (make-error-node 'e-no-space-after-method 'no-space-after-method #f)
      ;; Reached with the url span OPEN, which is what keeps a rejected target
      ;; from delivering a fragment.
      (make-error-node 'e-expected-crlf 'expected-crlf #f)
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
      (make-error-node 'e-eof-protocol 'eof #f)
      (make-error-node 'e-eof-version 'eof #f)
      (make-error-node 'e-no-space-after-version 'no-space-after-version #f)
      (make-error-node 'e-bad-status-code 'bad-status-code #f)
      (make-error-node 'e-bad-response-status 'bad-response-status #f)
      (make-error-node 'e-cr-after-status 'cr-after-status #f)
      (make-error-node 'e-eof-status 'eof #f)
      (make-error-node 'e-no-message-type 'no-message-type #f)
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
      (make-error-node 'e-lf-after-cr-strict 'lf-after-cr-strict #f)
      (make-error-node 'e-cr-after-value 'cr-after-value #f)
      (make-error-node 'e-lf-after-value 'lf-after-value #f)
      (make-error-node 'e-lf-after-headers 'lf-after-headers #f)
      (make-error-node 'e-eof-header-field 'eof #f)
      (make-error-node 'e-eof-header-value 'eof #f)
      (make-error-node 'e-eof-body 'eof #f)
      (make-error-node 'e-duplicate-content-length 'duplicate-content-length #f)
      (make-error-node 'e-content-length-overflow 'content-length-overflow #f)
      (make-error-node 'e-bad-content-length-char 'bad-content-length-char #f)
      (make-error-node 'e-empty-content-length 'empty-content-length #f)
      (make-error-node 'e-empty-transfer-encoding 'empty-transfer-encoding #f)
      (make-error-node 'e-te-with-content-length 'te-with-content-length #f)
      (make-error-node 'e-cl-with-te 'cl-with-te #f)
      (make-error-node 'e-bad-te-value 'bad-te-value #f)
      ;; `e-request-invalid-te` is a DOCUMENTED embedder surface, not just an
      ;; internal label: it is the one `invalid-transfer-encoding` node that
      ;; maps to 501 rather than 400 (RFC 9112 §6.1), and docs/api.org tells
      ;; embedders to split on it via `parser-error-node-name` -- decision 0013
      ;; keeps the CODE one-per-llhttp-number, so the node name is what carries
      ;; the finer status distinction. Renaming it is a public change.
      (make-error-node 'e-request-invalid-te 'request-invalid-te #f)
      ;; All five are reached with NO span open -- the chunk size and its
      ;; delimiters carry none, and the body span is closed by the counted
      ;; consume before anything looks at what follows it -- so one node each
      ;; serves every site that names it.
      (make-error-node 'e-bad-chunk-size 'bad-chunk-size #f)
      (make-error-node 'e-chunk-size-overflow 'chunk-size-overflow #f)
      (make-error-node 'e-lf-after-chunk-size 'lf-after-chunk-size #f)
      (make-error-node 'e-cr-after-chunk-size 'cr-after-chunk-size #f)
      (make-error-node 'e-lf-after-chunk-data 'lf-after-chunk-data #f)
      (make-error-node 'e-cr-after-chunk-data 'cr-after-chunk-data #f)
      ;; The extension errors. Every one is reached with the span already
      ;; ended -- llhttp closes it before it refuses, so what was read still
      ;; renders -- which is why none of them needs a second, span-open twin.
      (make-error-node 'e-bad-chunk-ext 'bad-chunk-ext #f)
      (make-error-node 'e-bad-chunk-ext-name 'bad-chunk-ext-name #f)
      (make-error-node 'e-bad-chunk-ext-value 'bad-chunk-ext-value #f)
      (make-error-node 'e-bad-chunk-ext-quoted 'bad-chunk-ext-quoted #f)
      (make-error-node 'e-bad-chunk-ext-qp 'bad-chunk-ext-qp #f)
      (make-error-node 'e-bad-chunk-ext-quote-value 'bad-chunk-ext-quote-value #f)
      (make-error-node 'e-cr-after-chunk-ext-name 'cr-after-chunk-ext-name #f)
      (make-error-node 'e-cr-after-chunk-ext-value 'cr-after-chunk-ext-value #f)
      ;; End of input with a span still OPEN, one node per span, as the
      ;; verifier's flat lattice requires.
      (make-error-node 'e-eof-chunk-ext-name 'eof #f)
      (make-error-node 'e-eof-chunk-ext-value 'eof #f)
      (make-error-node 'e-data-after-close 'data-after-close #f)
      (make-error-node 'e-pri-upgrade 'pri-upgrade #f)
      (make-error-node 'e-bad-h2-preface 'bad-h2-preface #f))

      ;; THE URL SUB-PARSER, in its HTTP configuration: the five part spans
      ;; stubbed, one `url-span` across the whole target, and the three exits
      ;; pointing at this machine's own adaptors. `#t` asks for the CONNECT
      ;; entry, which the standalone build has no reachable use for.
      ;;
      ;; ITS ERROR NODES ARE PREFIXED `e-url-`, because `e-eof-none` is a name
      ;; both machines want and a subgraph reaching into a node it does not
      ;; own is how two graphs stop being separable.
      (url-subgraph #f 'url-span 'url-close-sp 'url-close-cr 'url-close-lf
                    #t 'eof "e-url-"))
     'eof #f)))
