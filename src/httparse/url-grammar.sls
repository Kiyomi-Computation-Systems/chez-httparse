;;; (httparse url-grammar): llhttp's URL sub-parser, as a source machine.
;;;
;;; BUILD TIME ONLY, like its sibling (httparse grammar). This is a SECOND
;;; machine and not more of the first one: llhttp builds it from `URL.build()`
;;; with `separateSpans = true`, loops its two exits back to its own entry, and
;;; runs it over a bare URL with no HTTP framing around it. `url.md`'s 21
;;; fixtures are what that binary prints, and their traces carry no
;;; `message begin` and no `headers complete` -- only five span names and
;;; errors.
;;;
;;; THE HTTP PARSER DOES NOT USE THIS. Its request-target is ONE span,
;;; `span[url]`, which is llhttp's `separateSpans = false` build and is
;;; already what `(httparse grammar)`'s `url-open`/`url-loop` produce. The
;;; five separate spans exist only in the URL binary, so this machine adds a
;;; capability rather than refining one.
;;;
;;; WHAT `separateSpans` MEANS HERE. Upstream's span table then holds schema,
;;; host, path, query and fragment, and NOT `url` -- so its `spanStart('url')`
;;; and `spanEnd('url')` resolve to `span_start_stub_url` / `span_end_stub_url`,
;;; pass-through nodes that do nothing. They are omitted rather than
;;; reproduced: a node that only forwards is not a behaviour, and the verifier
;;; would have to call it reachable for no reason.
;;;
;;; `url_query_start` IS LIKEWISE ABSENT. Upstream constructs it and never
;;; routes to it -- nothing in `build()` targets it, and it survives only in
;;; the exit-adaptor loop that gives every node its space/CR/LF edges. llparse
;;; drops it; this generator's verifier would refuse it as an unreachable
;;; node, which is the same judgement said out loud.
(library (httparse url-grammar)
  (export make-url-machine
          httparse-url-char-bytes httparse-userinfo-bytes
          httparse-url-alpha-bytes)
  (import (rnrs) (byte-machine graph))

  (define (range lo hi)
    (let loop ((i hi) (acc '())) (if (< i lo) acc (loop (- i 1) (cons i acc)))))

  (define TAB 9)
  (define LF 10)
  (define FF 12)
  (define CR 13)
  (define SP 32)

  ;; llhttp's `ALPHA`, `DIGIT`, `ALPHANUM`, `MARK`, `USERINFO_CHARS` and
  ;; `URL_CHAR` (`src/llhttp/constants.ts`), as byte sets.
  (define httparse-url-alpha-bytes (append (range 65 90) (range 97 122)))
  (define httparse-url-digit-bytes (range 48 57))
  (define httparse-url-alphanum-bytes
    (append httparse-url-alpha-bytes httparse-url-digit-bytes))
  ;; MARK = - _ . ! ~ * ' ( )
  (define httparse-url-mark-bytes '(45 95 46 33 126 42 39 40 41))
  ;; USERINFO_CHARS = ALPHANUM + MARK + % ; : & = + $ ,
  (define httparse-userinfo-bytes
    (append httparse-url-alphanum-bytes httparse-url-mark-bytes
            '(37 59 58 38 61 43 36 44)))
  ;; URL_CHAR, upstream's own list. NOT a standard: `#` and `?` are absent
  ;; because the query and fragment nodes take them, and so are SP, CR, LF,
  ;; TAB and FF -- each of which has an edge of its own.
  (define httparse-url-char-bytes
    (append '(33 34 36 37 38 39 40 41 42 43 44 45 46 47
              58 59 60 61 62 64 91 92 93 94 95 96 123 124 125 126)
            httparse-url-alphanum-bytes))

  (define (bytes-case bs target mode)
    (make-byte-case (make-byte-set-matcher bs) (make-edge target mode) #f))

  ;; WHICH SPAN IS OPEN HERE. Every node-building helper below takes one,
  ;; because the verifier keeps a FLAT span lattice: a node whose incoming
  ;; edges disagree about the active span is refused, so an error reachable
  ;; with two different spans open needs two nodes. `(httparse grammar)` pays
  ;; the same price and says so at its own `e-eof-*` block.
  ;;
  ;; Naming the span at every call site is the point rather than the cost: a
  ;; node placed under the wrong one does not verify.
  (define (span-suffix span)
    (case span
      ((#f) "none")
      ((schema-span) "schema")
      ((host-span) "host")
      ((path-span) "path")
      ((query-span) "query")
      ((fragment-span) "fragment")
      (else (assertion-violation 'span-suffix "no such span" span))))
  (define (span-error prefix span)
    (string->symbol (string-append prefix (span-suffix span))))

  ;; EVERY NODE REFUSES TAB AND FORM FEED, and consumes the offending byte.
  ;; That is upstream's `private node(name)`, which wraps every construction
  ;; in `.match(['\t','\f'], this.errorInvalid)` -- a MATCH and not a peek, so
  ;; `/foo\tbar/` reports at 5 and not at 4. Written as a helper here for the
  ;; same reason it is one there: a node that forgot it would be a hole no
  ;; fixture outside `url.md#20` and `#21` could find.
  (define (url-node name span cases fallback)
    (make-byte-dispatch-node name
      (cons (bytes-case (list TAB FF) (span-error "e-invalid-" span) 'advance) cases)
      fallback (span-error "e-eof-" span) #f))

  ;; A node that consumes exactly one byte, whatever it is, and moves on.
  ;; Upstream's `.skipTo(n)`, which is `otherwise` with the advance it
  ;; normally withholds.
  (define (skip-to name span target)
    (make-byte-dispatch-node name '() (make-edge target 'advance)
                             (span-error "e-eof-" span) #f))

  ;; The space / CR / LF exits, which every node inside a URL carries and no
  ;; fixture in `url.md` reaches -- none of the 21 inputs contains one. They
  ;; are here because leaving them out would make a space in a URL an ERROR
  ;; where llhttp ends the URL and goes looking for `HTTP/`, and that is a
  ;; behaviour difference rather than an omission. Measured against a
  ;; purpose-built url oracle rather than left to argument; see the cases in
  ;; `unit.url`.
  ;;
  ;; `span` is the span to close first, or #f. Upstream closes the `url` span
  ;; too, which is a stub in this build and so is not here.
  (define (exit-nodes prefix span)
    (let* ((sp-name (lambda (suffix) (string->symbol (string-append prefix suffix))))
           (via (lambda (suffix target)
                  ;; With a span open, close it and then go; without one, the
                  ;; edge is direct and no node is emitted at all.
                  (if span
                      (list (make-span-end-node (sp-name suffix) span target #f))
                      '()))))
      (append (via "-exit-sp" 'url-skip-to-http)
              (via "-exit-cr" 'url-skip-lf-to-http09)
              (via "-exit-lf" 'url-skip-to-http09))))

  (define (exit-target prefix span suffix direct)
    (if span (string->symbol (string-append prefix suffix)) direct))

  ;; The three exit cases a node inside a URL carries, as byte cases. All
  ;; three PEEK: upstream's `node.peek(' ', endTo(...))` leaves the byte for
  ;; the adaptor to consume, which is what makes `skip_to_http` a skip.
  (define (exit-cases prefix span)
    (list (bytes-case (list SP) (exit-target prefix span "-exit-sp" 'url-skip-to-http) 'reexecute)
          (bytes-case (list CR) (exit-target prefix span "-exit-cr" 'url-skip-lf-to-http09) 'reexecute)
          (bytes-case (list LF) (exit-target prefix span "-exit-lf" 'url-skip-to-http09) 'reexecute)))

  ;; The spans that can be open at a node, `#f` for none. Drives the copies
  ;; of the two errors every node can reach.
  (define url-span-states
    '(#f schema-span host-span path-span query-span fragment-span))

  ;; make-url-machine : -> Machine
  (define (make-url-machine)
    (make-machine
     'httparse-url 'url-entry-normal
     '()
     (list (make-callback-declaration 'on-url-schema-data 'span-data #t '() #f #f)
           (make-callback-declaration 'on-url-host-data 'span-data #t '() #f #f)
           (make-callback-declaration 'on-url-path-data 'span-data #t '() #f #f)
           (make-callback-declaration 'on-url-query-data 'span-data #t '() #f #f)
           (make-callback-declaration 'on-url-fragment-data 'span-data #t '() #f #f))
     (list (make-span-declaration 'schema-span 'on-url-schema-data #f #f)
           (make-span-declaration 'host-span 'on-url-host-data #f #f)
           (make-span-declaration 'path-span 'on-url-path-data #f #f)
           (make-span-declaration 'query-span 'on-url-query-data #f #f)
           (make-span-declaration 'fragment-span 'on-url-fragment-data #f #f))
     ;; Every error here is llhttp's INVALID_URL, code 7. The reason strings
     ;; are its own, and decision 0013 makes the (code, reason) PAIR the
     ;; identity -- which is the whole of why nine reasons share one code
     ;; rather than being collapsed.
     (list (make-error-declaration 'eof 'unexpected-eof "unexpected end of input" #f)
           (make-error-declaration 'invalid-chars 'invalid-url
                                   "Invalid characters in url" #f)
           (make-error-declaration 'bad-start 'invalid-url
                                   "Unexpected start char in url" #f)
           (make-error-declaration 'bad-schema 'invalid-url
                                   "Unexpected char in url schema" #f)
           (make-error-declaration 'bad-server 'invalid-url
                                   "Unexpected char in url server" #f)
           (make-error-declaration 'double-at 'invalid-url "Double @ in url" #f)
           (make-error-declaration 'bad-path 'invalid-url
                                   "Invalid char in url path" #f)
           (make-error-declaration 'bad-query 'invalid-url
                                   "Invalid char in url query" #f)
           (make-error-declaration 'bad-fragment 'invalid-url
                                   "Invalid char in url fragment start" #f)
           (make-error-declaration 'expected-crlf 'invalid-url "Expected CRLF" #f))
     (append
      (list
       ;; --- entry ------------------------------------------------------------
       ;; Upstream's `entry.normal`, which opens the (stubbed) `url` span and
       ;; falls into `start`. The tab/form-feed refusal is the node wrapper's.
       (url-node 'url-entry-normal #f '() (make-edge 'url-start 'reexecute))

       ;; --- start: a path, or a schema ---------------------------------------
       ;; `/` and `*` PEEK into the path span so it opens ON the delimiter --
       ;; `span[url.path]="/path"` includes its leading slash. ALPHA peeks
       ;; into the schema span for the same reason, and then `schema` reads
       ;; the same byte again.
       ;;
       ;; SP, CR and LF are refused HERE and are exits everywhere else: a URL
       ;; may end at a space, but it may not begin at one.
       (url-node 'url-start #f
         (list (bytes-case (list SP CR LF) 'e-invalid-none 'advance)
               (bytes-case '(47 42) 'url-path-open 'reexecute)
               (bytes-case httparse-url-alpha-bytes 'url-schema-open 'reexecute))
         (make-edge 'e-bad-start 'reexecute))

       ;; --- schema -----------------------------------------------------------
       (make-span-start-node 'url-schema-open 'schema-span 'url-schema #f)
       (url-node 'url-schema 'schema-span
         (list (bytes-case (list SP CR LF) 'e-invalid-schema 'advance)
               (bytes-case httparse-url-alpha-bytes 'url-schema 'advance)
               (bytes-case '(58) 'url-schema-close 'reexecute))
         (make-edge 'e-bad-schema-open 'reexecute))
       ;; The colon is PEEKED so the span closes before it, then skipped.
       (make-span-end-node 'url-schema-close 'schema-span 'url-schema-colon #f)
       (skip-to 'url-schema-colon #f 'url-schema-delim)

       ;; `//`, AS A SEQUENCE, and the mismatch is why `schema:/path` reports
       ;; at 8 rather than 7: a sequence keeps the prefix bytes it already
       ;; consumed, so the first `/` is gone and the mismatch edge reexecutes
       ;; the `p`. Upstream's `.match('//')` behaves the same way, and
       ;; `url.md#3` is the fixture that pins it.
       ;;
       ;; TWO NODES WHERE UPSTREAM HAS ONE, because a single-byte refusal and
       ;; a two-byte sequence are different node kinds here. The split is
       ;; behaviour-preserving: the byte dispatch consumes nothing on its
       ;; fallback, and upstream consults its own tab/space matches only at
       ;; the node's first byte too.
       (url-node 'url-schema-delim #f
         (list (bytes-case (list SP CR LF) 'e-invalid-none 'advance))
         (make-edge 'url-schema-slashes 'reexecute))
       (make-sequence-dispatch-node 'url-schema-slashes
         (list (make-sequence-case '(47 47) 'url-host-open #f))
         (make-edge 'e-bad-schema-delim 'reexecute) 'e-eof-none #f)

       ;; --- server (host, and the userinfo that may precede it) ---------------
       (make-span-start-node 'url-host-open 'host-span 'url-server #f)

       ;; `@` moves to the twin below, which is this node without that edge.
       ;; Upstream builds both from one loop and withholds `@` from the
       ;; second; here they are written twice, because the alternative is a
       ;; field and a branch for a distinction that costs one node.
       (url-node 'url-server 'host-span
         (append
          (list (bytes-case '(47) 'url-server-path 'reexecute)
                (bytes-case '(63) 'url-server-query 'advance)
                (bytes-case '(64) 'url-server-with-at 'advance)
                (bytes-case httparse-userinfo-bytes 'url-server 'advance)
                (bytes-case '(91 93) 'url-server 'advance))
          (exit-cases "url-server" 'host-span))
         (make-edge 'e-bad-server 'reexecute))
       (url-node 'url-server-with-at 'host-span
         (append
          (list (bytes-case '(47) 'url-server-path 'reexecute)
                (bytes-case '(63) 'url-server-query 'advance)
                (bytes-case '(64) 'e-double-at 'advance)
                (bytes-case httparse-userinfo-bytes 'url-server-with-at 'advance)
                (bytes-case '(91 93) 'url-server-with-at 'advance))
          (exit-cases "url-server" 'host-span))
         (make-edge 'e-bad-server 'reexecute))

       ;; `/` is peeked, so the host span closes before it and the path span
       ;; opens ON it: `span[url.host]="hostname"` then
       ;; `span[url.path]="/"`.
       (make-span-end-node 'url-server-path 'host-span 'url-path-open #f)
       ;; `?` IS CONSUMED FIRST AND THE HOST SPAN CLOSES AFTER IT, which is
       ;; upstream's `.match('?', spanEnd('host', spanStart('query', query)))`
       ;; read in the order it executes: the match advances, and only then
       ;; does the span end. So a host ending at a query keeps the `?`. No
       ;; fixture in `url.md` has one; `unit.url` measures it against the
       ;; oracle rather than asserting the reading.
       (make-span-end-node 'url-server-query 'host-span 'url-query-open #f)

       ;; --- path -------------------------------------------------------------
       (make-span-start-node 'url-path-open 'path-span 'url-path-skip #f)
       (skip-to 'url-path-skip 'path-span 'url-path)
       ;; NO EXITS OF ITS OWN. Upstream leaves `path` out of the adaptor loop:
       ;; a space here is simply not a URL_CHAR, so it falls through to
       ;; `query_or_fragment` -- which closes the path span and carries the
       ;; exits. One node further along, same answer.
       (url-node 'url-path 'path-span
         (list (bytes-case httparse-url-char-bytes 'url-path 'advance))
         (make-edge 'url-path-close 'reexecute))
       (make-span-end-node 'url-path-close 'path-span 'url-query-or-fragment #f)

       (url-node 'url-query-or-fragment #f
         (append
          (list (bytes-case '(63) 'url-query-open 'advance)
                (bytes-case '(35) 'url-fragment-open 'advance))
          (exit-cases "url-qf" #f))
         (make-edge 'e-bad-path 'reexecute))

       ;; --- query ------------------------------------------------------------
       (make-span-start-node 'url-query-open 'query-span 'url-query #f)
       ;; A SECOND `?` IS ORDINARY INSIDE A QUERY, which `url.md#9` is
       ;; entirely about: `??fp-header-min.css,...?t=20101022.css` is one
       ;; span. `#` is peeked so the span closes before it.
       (url-node 'url-query 'query-span
         (append
          (list (bytes-case httparse-url-char-bytes 'url-query 'advance)
                (bytes-case '(63) 'url-query 'advance)
                (bytes-case '(35) 'url-query-close 'reexecute))
          (exit-cases "url-query" 'query-span))
         (make-edge 'e-bad-query 'reexecute))
       (make-span-end-node 'url-query-close 'query-span 'url-query-hash #f)
       (skip-to 'url-query-hash #f 'url-fragment-open)

       ;; --- fragment ---------------------------------------------------------
       (make-span-start-node 'url-fragment-open 'fragment-span 'url-fragment #f)
       ;; `?` and `#` are ordinary here: a fragment runs to the end of input
       ;; or to a space.
       (url-node 'url-fragment 'fragment-span
         (append
          (list (bytes-case httparse-url-char-bytes 'url-fragment 'advance)
                (bytes-case '(63 35) 'url-fragment 'advance))
          (exit-cases "url-fragment" 'fragment-span))
         (make-edge 'e-bad-fragment 'reexecute))

       ;; --- the adaptors, and the loop the test build closes ------------------
       ;; Upstream returns `toHTTP`/`toHTTP09` as EXITS for the HTTP parser to
       ;; join. The url fixture binary instead loops both back to the entry --
       ;; `node.exit.toHTTP.otherwise(node.entry.normal)` -- so one input can
       ;; hold several URLs separated by spaces. This machine is built for
       ;; that binary, so the loop is here.
       (skip-to 'url-skip-to-http #f 'url-to-http)
       (skip-to 'url-skip-to-http09 #f 'url-to-http09)
       (url-node 'url-to-http #f '() (make-edge 'url-entry-normal 'reexecute))
       (url-node 'url-to-http09 #f '() (make-edge 'url-entry-normal 'reexecute))
       ;; A CR must be followed by its LF, and the pair is a sequence for the
       ;; same reason `//` is.
       (make-sequence-dispatch-node 'url-skip-lf-to-http09
         (list (make-sequence-case '(13 10) 'url-to-http09 #f))
         (make-edge 'e-expected-crlf 'reexecute) 'e-eof-none #f))

      ;; The span-closing exits, one set per span that can be open.
      (exit-nodes "url-server" 'host-span)
      (exit-nodes "url-query" 'query-span)
      (exit-nodes "url-fragment" 'fragment-span)

      ;; SIX COPIES OF TWO ERRORS, one per span that can be open when they
      ;; are reached -- the flat lattice again. Every one is reachable: tab
      ;; and form feed are refused inside each span in turn, and so is end of
      ;; input.
      (map (lambda (span)
             (make-error-node (span-error "e-invalid-" span) 'invalid-chars #f))
           url-span-states)
      (map (lambda (span)
             (make-error-node (span-error "e-eof-" span) 'eof #f))
           url-span-states)

      (list
       (make-error-node 'e-bad-start 'bad-start #f)
       ;; ONE REASON, TWO NODES, and the difference is whether the schema span
       ;; is still open: `url_schema` refuses a non-ALPHA with the span live,
       ;; `url_schema_delim` refuses a missing `//` after it has closed.
       ;; Upstream has one error object there because llparse does not track
       ;; spans this way; the pair is the same behaviour, since the reason
       ;; string and the code are what a trace shows.
       (make-error-node 'e-bad-schema-open 'bad-schema #f)
       (make-error-node 'e-bad-schema-delim 'bad-schema #f)
       (make-error-node 'e-bad-server 'bad-server #f)
       (make-error-node 'e-double-at 'double-at #f)
       (make-error-node 'e-bad-path 'bad-path #f)
       (make-error-node 'e-bad-query 'bad-query #f)
       (make-error-node 'e-bad-fragment 'bad-fragment #f)
       (make-error-node 'e-expected-crlf 'expected-crlf #f)))
     'eof #f)))
