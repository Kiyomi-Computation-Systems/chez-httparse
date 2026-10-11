;;; (httparse url-grammar): llhttp's URL sub-parser, as a source machine.
;;;
;;; Derived from llhttp (https://github.com/nodejs/llhttp), MIT License,
;;; Copyright (c) 2018 Fedor Indutny. See NOTICE at the repository root.
;;;
;;; BUILD TIME ONLY, like its sibling (httparse grammar). This is a SECOND
;;; machine and not more of the first one: llhttp builds it from `URL.build()`
;;; with `separateSpans = true`, loops its two exits back to its own entry, and
;;; runs it over a bare URL with no HTTP framing around it. `url.md`'s 21
;;; fixtures are what that binary prints, and their traces carry no
;;; `message begin` and no `headers complete` -- only five span names and
;;; errors.
;;;
;;; THE HTTP PARSER SPLICES IN THE SAME SUBGRAPH, built the other way. Its
;;; request-target is ONE span, `span[url]`, which is llhttp's
;;; `separateSpans = false` build. The five separate spans exist only in the
;;; URL binary.
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
          url-subgraph url-error-declarations url-span-parts
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

  ;; THE SUBGRAPH IS BUILT TWICE, FROM ONE DESCRIPTION. llhttp does the same
  ;; thing with one boolean: `new URL(p, separateSpans)`. With it, the span
  ;; table holds `schema`/`host`/`path`/`query`/`fragment` and the whole-url
  ;; span is a stub -- that is the `url` binary `url.md` was recorded from.
  ;; Without it the table holds `url` alone and the five parts are stubs --
  ;; that is the HTTP parser, whose request target is one `span[url]`.
  ;;
  ;; A `cfg` carries which of the two, plus where the three exits go. It is a
  ;; plain list because it is read in one library and never crosses a
  ;; boundary; the accessors below are the documentation.
  ;;
  ;;   parts-spanned? : Boolean          the five parts are real spans
  ;;   whole-span     : (Option Symbol)  the span open across the whole url
  ;;   exit-sp/cr/lf  : Symbol           where a space, CR or LF goes once
  ;;                                     this subgraph has closed its own span
  (define (make-url-config parts-spanned? whole-span exit-sp exit-cr exit-lf err-prefix)
    (list parts-spanned? whole-span exit-sp exit-cr exit-lf err-prefix))
  (define (cfg-parts-spanned? c) (list-ref c 0))
  (define (cfg-whole-span c) (list-ref c 1))
  (define (cfg-exit c which)
    (case which ((sp) (list-ref c 2)) ((cr) (list-ref c 3)) ((lf) (list-ref c 4))
      (else (assertion-violation 'cfg-exit "no such exit" which))))
  ;; WHAT THIS SUBGRAPH'S ERROR NODES ARE CALLED. A machine that splices the
  ;; subgraph in already has error nodes of its own, and `e-eof-none` is the
  ;; name both would want -- so the caller chooses a prefix rather than the
  ;; two colliding or the subgraph quietly reusing a node it does not own.
  (define (cfg-err-prefix c) (list-ref c 5))
  (define (cfg-err c name)
    (string->symbol (string-append (cfg-err-prefix c) name)))
  (define (cfg-span-err c kind span)
    (cfg-err c (string-append kind "-" (span-suffix span))))

  ;; The span actually open at a node that is "inside" the part named `part`.
  ;; With separate spans that IS the part; with one whole-url span it is that
  ;; span throughout, because the part spans are stubs and open nothing.
  ;;
  ;; `'outside` IS NOT `#f`. `#f` means "inside the url, between parts" --
  ;; where the whole-url span IS open if there is one. `'outside` means the
  ;; entry nodes, which run BEFORE that span opens and after nothing has.
  ;; With separate spans the two coincide; with one whole span they do not,
  ;; and a build that conflates them does not verify.
  (define (cfg-span c part)
    (cond ((eq? part 'outside) #f)
          ((cfg-parts-spanned? c) part)
          (else (cfg-whole-span c))))

  ;; The five part spans, in the order upstream's table lists them.
  (define url-span-parts '(schema-span host-span path-span query-span fragment-span))

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
      ;; The HTTP parser's whole-target span. It reaches the same two errors
      ;; every other span does, and needs its own copies for the same reason.
      ((url-span) "url")
      (else (assertion-violation 'span-suffix "no such span" span))))
  ;; EVERY NODE REFUSES TAB AND FORM FEED, and consumes the offending byte.
  ;; That is upstream's `private node(name)`, which wraps every construction
  ;; in `.match(['\t','\f'], this.errorInvalid)` -- a MATCH and not a peek, so
  ;; `/foo\tbar/` reports at 5 and not at 4. Written as a helper here for the
  ;; same reason it is one there: a node that forgot it would be a hole no
  ;; fixture outside `url.md#20` and `#21` could find.
  (define (url-node c name part cases fallback)
    (let ((span (cfg-span c part)))
      (make-byte-dispatch-node name
        (cons (bytes-case (list TAB FF) (cfg-span-err c "invalid" span) 'advance) cases)
        fallback (cfg-span-err c "eof" span) #f)))

  ;; A node that consumes exactly one byte, whatever it is, and moves on.
  ;; Upstream's `.skipTo(n)`, which is `otherwise` with the advance it
  ;; normally withholds.
  (define (skip-to c name part target)
    (make-byte-dispatch-node name '() (make-edge target 'advance)
                             (cfg-span-err c "eof" (cfg-span c part)) #f))

  ;; The space / CR / LF exits, which every node inside a URL carries and no
  ;; fixture in `url.md` reaches -- none of the 21 inputs contains one. They
  ;; are here because leaving them out would make a space in a URL an ERROR
  ;; where llhttp ends the URL and goes looking for `HTTP/`, and that is a
  ;; behaviour difference rather than an omission. Measured against a
  ;; purpose-built url oracle rather than left to argument; see the cases in
  ;; `unit.url`.
  ;;
  ;; A PART SPAN'S START AND END ARE STUBS WHEN THE PARTS ARE NOT SPANNED, so
  ;; these two return the node only when there is a span to open or close and
  ;; otherwise say "go straight there". Upstream emits a forwarding node
  ;; (`span_start_stub_path`); a node that only forwards is not a behaviour,
  ;; and this generator's verifier would want it reachable for no reason.
  (define (part-span-start c name part next)
    (if (cfg-parts-spanned? c) (list (make-span-start-node name part next #f)) '()))
  (define (part-span-start-target c name next)
    (if (cfg-parts-spanned? c) name next))
  (define (part-span-end c name part next)
    (if (cfg-parts-spanned? c) (list (make-span-end-node name part next #f)) '()))
  (define (part-span-end-target c name next)
    (if (cfg-parts-spanned? c) name next))

  ;; `part` is the part span to close before leaving, or #f. The WHOLE-url
  ;; span is closed by the caller's exit node, because the caller is what
  ;; knows whether there is one -- upstream's `endTo` closes `url` after the
  ;; part for the same division of labour.
  (define (exit-nodes c prefix part)
    (let* ((sp-name (lambda (suffix) (string->symbol (string-append prefix suffix))))
           (via (lambda (suffix which)
                  (part-span-end c (sp-name suffix) part (cfg-exit c which)))))
      (append (via "-exit-sp" 'sp) (via "-exit-cr" 'cr) (via "-exit-lf" 'lf))))

  (define (exit-target c prefix part suffix which)
    (if (and part (cfg-parts-spanned? c))
        (string->symbol (string-append prefix suffix))
        (cfg-exit c which)))

  ;; The three exit cases a node inside a URL carries, as byte cases. All
  ;; three PEEK: upstream's `node.peek(' ', endTo(...))` leaves the byte for
  ;; the adaptor to consume, which is what makes `skip_to_http` a skip.
  (define (exit-cases c prefix part)
    (list (bytes-case (list SP) (exit-target c prefix part "-exit-sp" 'sp) 'reexecute)
          (bytes-case (list CR) (exit-target c prefix part "-exit-cr" 'cr) 'reexecute)
          (bytes-case (list LF) (exit-target c prefix part "-exit-lf" 'lf) 'reexecute)))

  ;; The spans that can be open at a node, `#f` for none. Drives the copies
  ;; of the two errors every node can reach.
  (define url-span-states
    '(#f schema-span host-span path-span query-span fragment-span))

  ;; url-error-declarations : -> (Listof ErrorDeclaration)
  ;; Every error the subgraph can reach. All but the EOF one are llhttp's
  ;; INVALID_URL, code 7; the reason strings are its own, and an error's
  ;; identity is the (code, reason) PAIR -- which is the whole of why eight
  ;; reasons share one code rather than being collapsed.
  ;;
  ;; A MACHINE THAT SPLICES THE SUBGRAPH IN MUST DECLARE THESE. The names are
  ;; part of the contract, not an implementation detail, which is why they
  ;; come from here rather than being written out twice.
  (define (url-error-declarations)
    (list (make-error-declaration 'invalid-chars 'invalid-url
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
                                  "Invalid char in url fragment start" #f)))

  ;; url-subgraph : Boolean (Option Symbol) Symbol Symbol Symbol Boolean Symbol
  ;;                -> (Listof Node)
  ;;
  ;;   parts-spanned?  the five part spans are real (the `url` binary), or
  ;;                   stubs (the HTTP parser, whose target is one span)
  ;;   whole-span      the span open across the whole url, or #f
  ;;   exit-sp/cr/lf   where a space, CR or LF goes once this subgraph has
  ;;                   closed the part span it had open
  ;;   connect?        also emit `url-entry-connect`, which skips the schema
  ;;                   and opens at the host -- llhttp routes a CONNECT
  ;;                   request's target there and nothing else does
  ;;   eof-error       the error DECLARATION the EOF nodes name
  ;;
  ;; The caller owns the exits and the whole-url span's END, because the
  ;; caller is what knows whether there is one. Upstream divides it the same
  ;; way: its `endTo` closes `url` after the part span, outside the loop that
  ;; gives each node its three edges.
  (define (url-subgraph parts-spanned? whole-span exit-sp exit-cr exit-lf
                        connect? eof-error err-prefix)
    (let* ((c (make-url-config parts-spanned? whole-span exit-sp exit-cr exit-lf
                               err-prefix))
           ;; Where `entry.normal` goes: through the whole-url span's start if
           ;; there is one, straight to `start` if there is not.
           (after-entry (if whole-span 'url-whole-open 'url-start))
           (host-entry (part-span-start-target c 'url-host-open 'url-server))
           (path-entry (part-span-start-target c 'url-path-open 'url-path-skip))
           (query-entry (part-span-start-target c 'url-query-open 'url-query))
           (fragment-entry (part-span-start-target c 'url-fragment-open 'url-fragment))
           (none (lambda (kind) (cfg-span-err c kind (cfg-span c #f))))
           ;; The span states any node can be in, and so how many copies of
           ;; the two errors every node reaches are needed. With separate
           ;; spans that is six; with one whole-url span it is two.
           (states (if parts-spanned? (cons #f url-span-parts) (list #f whole-span))))
      (append
       (list
        ;; --- entry ------------------------------------------------------------
        ;; Upstream's `entry.normal`, which opens the whole-url span and falls
        ;; into `start`. The tab/form-feed refusal is the node wrapper's.
        (url-node c 'url-entry-normal 'outside '() (make-edge after-entry 'reexecute)))
       (if whole-span
           (list (make-span-start-node 'url-whole-open whole-span 'url-start #f))
           '())

       ;; --- CONNECT's entry --------------------------------------------------
       ;; `CONNECT 0-home0.netscape.com:443 HTTP/1.0` has no scheme and no
       ;; leading slash, so `start` would refuse its first byte. Upstream
       ;; routes it past both -- `entry.connect` opens the host span and lands
       ;; on `server` -- and the branch that chooses is a test on the METHOD
       ;; field, made by the caller.
       (if connect?
           (append
            (list (url-node c 'url-entry-connect 'outside '()
                            (make-edge (if whole-span 'url-connect-open host-entry)
                                       'reexecute)))
            (if whole-span
                (list (make-span-start-node 'url-connect-open whole-span host-entry #f))
                '()))
           '())

       (list
        ;; --- start: a path, or a schema ---------------------------------------
        ;; `/` and `*` PEEK into the path span so it opens ON the delimiter --
        ;; `span[url.path]="/path"` includes its leading slash. ALPHA peeks
        ;; into the schema span for the same reason, and then `schema` reads
        ;; the same byte again.
        ;;
        ;; SP, CR and LF are refused HERE and are exits everywhere else: a URL
        ;; may end at a space, but it may not begin at one.
        (url-node c 'url-start #f
          (list (bytes-case (list SP CR LF) (none "invalid") 'advance)
                (bytes-case '(47 42) path-entry 'reexecute)
                (bytes-case httparse-url-alpha-bytes
                            (part-span-start-target c 'url-schema-open 'url-schema)
                            'reexecute))
          (make-edge (cfg-err c "bad-start") 'reexecute)))

       ;; --- schema -------------------------------------------------------------
       (part-span-start c 'url-schema-open 'schema-span 'url-schema)
       (list
        (url-node c 'url-schema 'schema-span
          (list (bytes-case (list SP CR LF)
                            (cfg-span-err c "invalid" (cfg-span c 'schema-span)) 'advance)
                (bytes-case httparse-url-alpha-bytes 'url-schema 'advance)
                (bytes-case '(58)
                            (part-span-end-target c 'url-schema-close 'url-schema-colon)
                            'reexecute))
          (make-edge (cfg-err c "bad-schema-open") 'reexecute)))
       ;; The colon is PEEKED so the span closes before it, then skipped.
       (part-span-end c 'url-schema-close 'schema-span 'url-schema-colon)
       (list
        (skip-to c 'url-schema-colon #f 'url-schema-delim)

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
        (url-node c 'url-schema-delim #f
          (list (bytes-case (list SP CR LF) (none "invalid") 'advance))
          (make-edge 'url-schema-slashes 'reexecute))
        (make-sequence-dispatch-node 'url-schema-slashes
          (list (make-sequence-case '(47 47) host-entry #f))
          (make-edge (cfg-err c "bad-schema-delim") 'reexecute) (none "eof") #f))

       ;; --- server (host, and the userinfo that may precede it) ----------------
       (part-span-start c 'url-host-open 'host-span 'url-server)
       (list
        ;; `@` moves to the twin below, WHICH IS ONE BYTE WIDE. Upstream
        ;; builds the two from one loop, and the edges inside that loop name
        ;; `server` explicitly rather than the loop variable --
        ;;
        ;;     .match(USERINFO_CHARS, server)
        ;;     .match([ '[', ']' ], server)
        ;;
        ;; -- so any ordinary host byte sends the twin straight back here and
        ;; re-arms `@`. Only `@@` is `Double @ in url`; `a@b@c` is a host.
        ;;
        ;; READING THAT LOOP AS "the same node twice, minus one edge" IS
        ;; WRONG, and `url.md`'s "Double `@`" fixture cannot tell the two
        ;; readings apart, because its two `@` are adjacent. Only generated
        ;; input in the live differential does, and not at every seed, which
        ;; is why that lane sweeps several.
        (url-node c 'url-server 'host-span
          (append
           (list (bytes-case '(47) (part-span-end-target c 'url-server-path path-entry)
                             'reexecute)
                 (bytes-case '(63) (part-span-end-target c 'url-server-query query-entry)
                             'advance)
                 (bytes-case '(64) 'url-server-with-at 'advance)
                 (bytes-case httparse-userinfo-bytes 'url-server 'advance)
                 (bytes-case '(91 93) 'url-server 'advance))
           (exit-cases c "url-server" 'host-span))
          (make-edge (cfg-err c "bad-server") 'reexecute))
        (url-node c 'url-server-with-at 'host-span
          (append
           (list (bytes-case '(47) (part-span-end-target c 'url-server-path path-entry)
                             'reexecute)
                 (bytes-case '(63) (part-span-end-target c 'url-server-query query-entry)
                             'advance)
                 (bytes-case '(64) (cfg-err c "double-at") 'advance)
                 (bytes-case httparse-userinfo-bytes 'url-server 'advance)
                 (bytes-case '(91 93) 'url-server 'advance))
           (exit-cases c "url-server" 'host-span))
          (make-edge (cfg-err c "bad-server") 'reexecute)))

       ;; `/` is peeked, so the host span closes before it and the path span
       ;; opens ON it: `span[url.host]="hostname"` then `span[url.path]="/"`.
       (part-span-end c 'url-server-path 'host-span path-entry)
       ;; `?` IS CONSUMED FIRST AND THE HOST SPAN CLOSES AFTER IT, which is
       ;; upstream's `.match('?', spanEnd('host', spanStart('query', query)))`
       ;; read in the order it executes: the match advances, and only then
       ;; does the span end. So a host ending at a query keeps the `?`. No
       ;; fixture in `url.md` has one; `unit.url` measures it against the
       ;; oracle rather than asserting the reading.
       (part-span-end c 'url-server-query 'host-span query-entry)

       ;; --- path ---------------------------------------------------------------
       (part-span-start c 'url-path-open 'path-span 'url-path-skip)
       (list
        (skip-to c 'url-path-skip 'path-span 'url-path)
        ;; NO EXITS OF ITS OWN. Upstream leaves `path` out of the adaptor loop:
        ;; a space here is simply not a URL_CHAR, so it falls through to
        ;; `query_or_fragment` -- which closes the path span and carries the
        ;; exits. One node further along, same answer.
        (url-node c 'url-path 'path-span
          (list (bytes-case httparse-url-char-bytes 'url-path 'advance))
          (make-edge (part-span-end-target c 'url-path-close 'url-query-or-fragment)
                     'reexecute)))
       (part-span-end c 'url-path-close 'path-span 'url-query-or-fragment)

       (list
        (url-node c 'url-query-or-fragment #f
          (append
           (list (bytes-case '(63) query-entry 'advance)
                 (bytes-case '(35) fragment-entry 'advance))
           (exit-cases c "url-qf" #f))
          (make-edge (cfg-err c "bad-path") 'reexecute)))

       ;; --- query --------------------------------------------------------------
       (part-span-start c 'url-query-open 'query-span 'url-query)
       (list
        ;; A SECOND `?` IS ORDINARY INSIDE A QUERY, which `url.md#9` is
        ;; entirely about: `??fp-header-min.css,...?t=20101022.css` is one
        ;; span. `#` is peeked so the span closes before it.
        (url-node c 'url-query 'query-span
          (append
           (list (bytes-case httparse-url-char-bytes 'url-query 'advance)
                 (bytes-case '(63) 'url-query 'advance)
                 (bytes-case '(35)
                             (part-span-end-target c 'url-query-close 'url-query-hash)
                             'reexecute))
           (exit-cases c "url-query" 'query-span))
          (make-edge (cfg-err c "bad-query") 'reexecute)))
       (part-span-end c 'url-query-close 'query-span 'url-query-hash)
       (list (skip-to c 'url-query-hash #f fragment-entry))

       ;; --- fragment -----------------------------------------------------------
       (part-span-start c 'url-fragment-open 'fragment-span 'url-fragment)
       (list
        ;; `?` and `#` are ordinary here: a fragment runs to the end of input
        ;; or to a space.
        (url-node c 'url-fragment 'fragment-span
          (append
           (list (bytes-case httparse-url-char-bytes 'url-fragment 'advance)
                 (bytes-case '(63 35) 'url-fragment 'advance))
           (exit-cases c "url-fragment" 'fragment-span))
          (make-edge (cfg-err c "bad-fragment") 'reexecute)))

       ;; The span-closing exits, one set per part span that can be open.
       ;; With the parts stubbed these contribute nothing and the exit edges
       ;; point straight at the caller's adaptors.
       (exit-nodes c "url-server" 'host-span)
       (exit-nodes c "url-query" 'query-span)
       (exit-nodes c "url-fragment" 'fragment-span)

       ;; ONE COPY OF TWO ERRORS PER SPAN STATE -- the verifier keeps a flat
       ;; span lattice, so an error reachable with two different spans open
       ;; needs two nodes. Six states with separate spans, two with one.
       (map (lambda (span)
              (make-error-node (cfg-span-err c "invalid" span) 'invalid-chars #f))
            states)
       (map (lambda (span)
              (make-error-node (cfg-span-err c "eof" span) eof-error #f))
            states)

       (list
        (make-error-node (cfg-err c "bad-start") 'bad-start #f)
        ;; ONE REASON, TWO NODES, and the difference is whether the schema span
        ;; is still open: `url_schema` refuses a non-ALPHA with the span live,
        ;; `url_schema_delim` refuses a missing `//` after it has closed.
        ;; Upstream has one error object there because llparse does not track
        ;; spans this way; the pair is the same behaviour, since the reason
        ;; string and the code are what a trace shows.
        (make-error-node (cfg-err c "bad-schema-open") 'bad-schema #f)
        (make-error-node (cfg-err c "bad-schema-delim") 'bad-schema #f)
        (make-error-node (cfg-err c "bad-server") 'bad-server #f)
        (make-error-node (cfg-err c "double-at") 'double-at #f)
        (make-error-node (cfg-err c "bad-path") 'bad-path #f)
        (make-error-node (cfg-err c "bad-query") 'bad-query #f)
        (make-error-node (cfg-err c "bad-fragment") 'bad-fragment #f)))))

  ;; make-url-machine : -> Machine
  ;; The STANDALONE build: five separate spans, no whole-url span, and both
  ;; exits looped back to the entry. That is `test/md-test.ts`'s `buildURL()`,
  ;; which is the binary `url.md` was recorded from.
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
     (append
      (list (make-error-declaration 'eof 'unexpected-eof "unexpected end of input" #f)
            (make-error-declaration 'expected-crlf 'invalid-url "Expected CRLF" #f))
      (url-error-declarations))
     (append
      ;; NO CONNECT ENTRY. Upstream builds one and the url binary never
      ;; reaches it -- its entry is `entry.normal` -- so this verifier would
      ;; refuse it as an unreachable node. The HTTP parser is where it is
      ;; needed and where it is asked for.
      (url-subgraph #t #f 'url-skip-to-http 'url-skip-lf-to-http09
                    'url-skip-to-http09 #f 'eof "e-")
      (list
       ;; --- the adaptors, and the loop the test build closes -------------------
       ;; Upstream returns `toHTTP`/`toHTTP09` as EXITS for the HTTP parser to
       ;; join. The url fixture binary instead loops both back to the entry --
       ;; `node.exit.toHTTP.otherwise(node.entry.normal)` -- so one input can
       ;; hold several URLs separated by spaces. This machine is built for
       ;; that binary, so the loop is here.
       (make-byte-dispatch-node 'url-skip-to-http '()
                                (make-edge 'url-to-http 'advance) 'e-eof-none #f)
       (make-byte-dispatch-node 'url-skip-to-http09 '()
                                (make-edge 'url-to-http09 'advance) 'e-eof-none #f)
       (make-byte-dispatch-node 'url-to-http
         (list (bytes-case (list TAB FF) 'e-invalid-none 'advance))
         (make-edge 'url-entry-normal 'reexecute) 'e-eof-none #f)
       (make-byte-dispatch-node 'url-to-http09
         (list (bytes-case (list TAB FF) 'e-invalid-none 'advance))
         (make-edge 'url-entry-normal 'reexecute) 'e-eof-none #f)
       ;; A CR must be followed by its LF, and the pair is a sequence for the
       ;; same reason `//` is.
       (make-sequence-dispatch-node 'url-skip-lf-to-http09
         (list (make-sequence-case '(13 10) 'url-to-http09 #f))
         (make-edge 'e-expected-crlf 'reexecute) 'e-eof-none #f)
       (make-error-node 'e-expected-crlf 'expected-crlf #f)))
     'eof #f)))
