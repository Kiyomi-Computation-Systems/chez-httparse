;;; The live llhttp differential, over inputs nobody wrote down.
;;;
;;; WHY THIS LANE IS LOCAL. The vendored corpus is the CI oracle and
;;; already carries llhttp's own trace for every fixture at every chunk size,
;;; so replaying fixtures through a live binary would print what is already
;;; checked in. What a live binary adds is the one thing no recorded trace
;;; can: an input the corpus does not contain. So this lane is local, opt-in,
;;; never a merge gate, and its subject is generated input.
;;;
;;; THE ORACLE IS UPSTREAM'S OWN FIXTURE BINARY, built by llhttp's harness
;;; from a checkout named at configure time -- the same program that produced
;;; the corpus, not a driver of ours that prints the same shape. Its raw lines
;;; come back through `(httparse test oracle)`, which turns each one into the
;;; event it was printed from and lets the renderer both sides share do the
;;; coalescing. That module is calibrated against all 253 recorded blocks in
;;; its own lane, which needs no llhttp and runs on every pull request.
;;;
;;; A VERSION MISMATCH IS REPORTED AS ONE. If the binaries are built from a
;;; different llhttp than the corpus was vendored from, every divergence this
;;; lane finds is version drift wearing a parser bug's clothes. So the first
;;; case compares the two and says which it is.
;;;
;;; THERE ARE THREE KINDS AND THREE BINARIES. `request` and `response` are
;;; two modes of llhttp's message parser; `url` is its URL sub-parser built
;;; standalone, and it is a second machine on this side too.
;;; The kind travels with the case and picks the binary over there and the
;;; machine over here, so a url case is never asked of a message parser.
;;;
;;; WHAT THIS LANE CANNOT SEE. Generated input is held to [1,127] because the
;;; oracle takes its input as an argv string: a NUL cannot reach it and a high
;;; byte reaches it UTF-8 encoded, which would put different bytes into the
;;; two parsers. obs-text and NUL are covered by the corpus and not here.
(import (rnrs)
        (httparse test harness)
        (httparse test corpus-load)
        (httparse test corpus-decode)
        (httparse test generate)
        (httparse test drive)
        (httparse modes)
        (httparse test oracle)
        (generated httparse-message)
        (generated httparse-url))

(define (read-text path)
  (utf8->string (adapter-file-bytes path)))

(define (env name) (adapter-environment-variable name))

(define corpus-dir (env "HTTPARSE_CORPUS_DIR"))
(define bin-dir (env "HTTPARSE_ORACLE_BIN_DIR"))
(define runner (env "HTTPARSE_ORACLE_RUNNER"))
(define node (or (env "HTTPARSE_ORACLE_NODE") "node"))
(define work-dir (or (env "HTTPARSE_TEST_TMPDIR") (env "HTTPARSE_ORACLE_WORK_DIR") "."))

(define seed
  (let ((v (env "HTTPARSE_DIFFERENTIAL_SEED")))
    (or (and (string? v) (string->number v)) 20260915)))

(define case-count
  (let ((v (env "HTTPARSE_DIFFERENTIAL_CASES")))
    (or (and (string? v) (string->number v)) 60)))

;; Urls are SHORT, so the chunk ladder gives every size rather than the sparse
;; one a 200-byte message gets -- a 20-byte url is 20 probes where a message
;; is 9. The knob is separate so the two kinds can be dialled independently,
;; and it defaults to the same number of cases.
(define url-case-count
  (let ((v (env "HTTPARSE_DIFFERENTIAL_URL_CASES")))
    (or (and (string? v) (string->number v)) case-count)))

;; The lenient schedule is 67 entries -- 11 singletons, 55 pairs, the whole
;; set -- so a count below that leaves pairs unvisited. The default is a
;; multiple of it, and it is its own knob because these cases go to their own
;; oracle binary.
(define lenient-case-count
  (let ((v (env "HTTPARSE_DIFFERENTIAL_LENIENT_CASES")))
    (or (and (string? v) (string->number v)) 67)))

;; THREE SEEDS, NOT ONE, AND THAT IS A MEASUREMENT RATHER THAN A PRECAUTION.
;; A divergence can be absent at one seed and present at its neighbours: a
;; host holding two `@` that are not adjacent, which llhttp accepts, does not
;; show up at the default seed but does at `20260915 + 1`. A lane pinned to
;; one seed is a lane that can be silently lucky, and a green run would read
;; as evidence.
;;
;; The sweep is the seed it was given and its two successors, so the run is
;; still named by one number and any member replays alone by being named
;; directly.
(define seeds (list seed (+ seed 1) (+ seed 2)))

;; TWO MACHINES, AND THE CASE'S KIND SAYS WHICH -- exactly as the conformance
;; driver picks one per fixture. `url` is llhttp's URL sub-parser built
;; standalone; it shares no callback and no field with the message parser,
;; and the oracle side picks a different BINARY for it.
(define (machine-for kind)
  (if (eq? kind 'url) httparse-url-machine httparse-message-machine))

;; --- bases, as in the property lane ---------------------------------------

(define base-files
  '("request/sample.md" "request/connection.md" "request/content-length.md"
    "request/transfer-encoding.md" "request/method.md" "request/uri.md"
    "response/sample.md" "response/connection.md" "response/content-length.md"
    "response/transfer-encoding.md"))

(define (first-word s)
  (let loop ((i 0))
    (cond ((= i (string-length s)) s)
          ((char=? (string-ref s i) #\-) (substring s 0 i))
          (else (loop (+ i 1))))))

(define (message-kind f)
  (let ((type (fixture-meta-ref f 'type #f)))
    (and (string? type) (string->symbol (first-word type)))))

(define bases
  (let loop ((files base-files) (acc '()))
    (if (null? files)
        (reverse acc)
        (let inner ((fs (corpus-parse-file
                         (read-text (string-append corpus-dir "/" (car files)))))
                    (i 1) (acc acc))
          (if (null? fs)
              (loop (cdr files) acc)
              (let* ((f (car fs))
                     (kind (message-kind f))
                     (bv (corpus-decode-input (fixture-input-text f))))
                (inner (cdr fs) (+ i 1)
                       (if (and (memq kind '(request response))
                                (generate-safe-bytes? bv))
                           (cons (cons kind
                                       (cons (string-append (car files) "#"
                                                            (number->string i))
                                             bv))
                                 acc)
                           acc))))))))

;; The url bases are `url.md` entire. It is small enough not to need choosing
;; from, and every one of its 21 inputs is a shape somebody thought worth
;; recording -- which is exactly what a mutation wants under it.
(define url-bases
  (let inner ((fs (corpus-parse-file (read-text (string-append corpus-dir "/url.md"))))
              (i 1) (acc '()))
    (if (null? fs)
        (reverse acc)
        (let ((bv (corpus-decode-input (fixture-input-text (car fs)))))
          (inner (cdr fs) (+ i 1)
                 (if (generate-safe-bytes? bv)
                     (cons (cons 'url
                                 (cons (string-append "url.md#" (number->string i)) bv))
                           acc)
                     acc))))))

;; THE URL CASES ARE A SEPARATE RUN, not more bases in the existing one. Added
;; to `bases`, they would change every message mutant this lane produces, and
;; a divergence would have two possible causes. Kept apart, the request and
;; response inputs do not depend on the url bases at all, so a divergence in a
;; message case cannot come from the url kind.
(define (cases-at s)
  (append (generate-structured s case-count)
          (generate-mutants s case-count bases)
          (generate-urls s url-case-count)
          (generate-mutants s url-case-count url-bases)
          (generate-lenient s lenient-case-count)))

(define cases (apply append (map cases-at seeds)))

;; --- the batch the runner is given ----------------------------------------
;;
;; One line per (case, chunk size). The input crosses as hex so that no
;; generated byte ever has to survive a shell.

(define-record-type probe (fields case size))

(define probes
  (apply append
         (map (lambda (c)
                (map (lambda (s) (make-probe c s))
                     (drive-chunk-ladder (bytevector-length (gen-case-bytes c)))))
              cases)))

(define cases-file (string-append work-dir "/differential-cases.txt"))
(define traces-file (string-append work-dir "/differential-traces.txt"))

(define (write-cases! path ps)
  (let ((port (open-file-output-port path (file-options no-fail))))
    (for-each
     (lambda (p)
       (let* ((c (probe-case p))
              (size (probe-size p)))
         (put-bytevector
          port
          (string->utf8
           (string-append (symbol->string (gen-case-kind c)) " "
                          (number->string size) ":" (number->string (+ size 1)) " "
                          (oracle-hex-encode (gen-case-bytes c))
                          ;; NO MASK FIELD FOR A STRICT CASE, so it goes to
                          ;; upstream's own binary and every strict comparison
                          ;; is against the program the corpus was recorded
                          ;; from.
                          ;;
                          ;; The mask is this project's own bit numbering from
                          ;; `(httparse modes)`; `lenient-init.c` translates
                          ;; each bit into the constant upstream declares, so
                          ;; the two sides agree on a FLAG and not on a number.
                          (if (null? (gen-case-flags c))
                              ""
                              (string-append
                               " " (number->string
                                    (httparse-lenient-flags-value
                                     (gen-case-flags c)))))
                          "\n")))))
     ps)
    (close-port port)))

(define (run-oracle!)
  (adapter-run-command
   (string-append "'" node "' '" runner "' '" bin-dir "' '"
                  cases-file "' '" traces-file "'")))

;; oracle-results : (Listof (Either String (Listof Bytevector)))
;; A refusal is carried as a string so a crashed oracle is a reported case
;; rather than a crashed lane.
(define (read-results path)
  (let* ((bytes (adapter-file-bytes path))
         (lines (let loop ((start 0) (i 0) (acc '()))
                  (cond
                   ((= i (bytevector-length bytes))
                    (reverse (if (> i start) (cons (subbytes bytes start i) acc) acc)))
                   ((= (bytevector-u8-ref bytes i) 10)
                    (loop (+ i 1) (+ i 1) (cons (subbytes bytes start i) acc)))
                   (else (loop start (+ i 1) acc))))))
    (map parse-result lines)))

(define (subbytes bv from to)
  (let ((out (make-bytevector (- to from))))
    (bytevector-copy! bv from out 0 (- to from))
    out))

(define (parse-result line)
  (let ((text (utf8->string line)))
    (cond
     ((and (> (string-length text) 3) (string=? (substring text 0 3) "ok "))
      (let ((blocks (oracle-split-scans (oracle-hex-decode (substring text 3 (string-length text))))))
        (if (= (length blocks) 1)
            (car blocks)
            (string-append "the oracle printed " (number->string (length blocks))
                           " scan blocks where one was asked for"))))
     ((string=? text "ok ") '())
     (else (string-append "the oracle did not succeed: " text)))))


;; --- how a divergence is named -------------------------------------------
;;
;; Two classes account for every known divergence, and both are decided
;; limitations rather than open findings. A divergence in NEITHER class fails
;; the lane: that is the whole point of naming them, and a classifier wide
;; enough to swallow a new bug would be worse than none.
;;
;; Each class is anchored by an exact witness below -- llhttp's own bytes for
;; one reduced input -- so the class is pinned by an example and the predicate
;; only decides membership for the rest. When a class is fixed, its witness
;; turns red and says so. A fixed class is then deleted, and its witness is
;; kept, inverted, asserting the agreement it now produces -- the
;; `OPTIONS a.com:443` group below is one.

(define (ends-with? s suffix)
  (let ((n (string-length s)) (m (string-length suffix)))
    (and (>= n m) (string=? (substring s (- n m) n) suffix))))

(define (line-offset line)
  ;; `off=N ...` -> N, and #f for `off=NULL ...`, which no generated input
  ;; can produce because nothing here asks the parser to finish.
  (and (> (string-length line) 4)
       (string=? (substring line 0 4) "off=")
       (let loop ((i 4) (acc 0) (any #f))
         (if (and (< i (string-length line))
                  (char<=? #\0 (string-ref line i))
                  (char<=? (string-ref line i) #\9))
             (loop (+ i 1) (+ (* acc 10) (- (char->integer (string-ref line i)) 48)) #t)
             (and any acc)))))

(define (all-at? lines off)
  (for-all (lambda (l) (equal? (line-offset l) off)) lines))

(define (drop-n xs k) (if (or (= k 0) (null? xs)) xs (drop-n (cdr xs) (- k 1))))

;; The two classes below are the same question asked from either side: at the
;; end of the input, does the event after a token fire? They are recognised
;; by SHAPE and by POSITION -- one trace is a proper prefix of the other, the
;; first line that differs is a completion, and every extra line sits at the
;; end-of-input offset, because nothing further was consumed. A divergence
;; whose extra lines are anywhere else is a different animal and stays
;; unclassified.

(define (late-complete-divergence? theirs ours len)
  ;; llhttp fires a keyword's completion event on the keyword's LAST BYTE;
  ;; the generator's keyword table returns need-input at that point and takes
  ;; the terminal edge only when a further byte arrives. So an input ending
  ;; exactly at the keyword is short of that event -- and of anything the
  ;; event led to without reading another byte, which is why the tail may be
  ;; more than one line: a completed protocol can fail its method check at
  ;; the same offset.
  (let ((n (length ours)))
    (and (> (length theirs) n)
         (equal? ours (harness-take theirs n))
         (ends-with? (list-ref theirs n) " complete")
         (all-at? (drop-n theirs n) len))))

(define (early-complete-divergence? theirs ours len)
  ;; The mirror image, and a different mechanism. Where a completion fires
  ;; one byte PAST its delimiter -- `url complete`, `header_field complete`
  ;; -- llhttp needs that byte to be present and this parser does not, so an
  ;; input ending exactly at the delimiter has one event too many.
  (let ((n (length theirs)))
    (and (> (length ours) n)
         (equal? theirs (harness-take ours n))
         (ends-with? (list-ref ours n) " complete")
         (all-at? (drop-n ours n) len))))

(define (classify theirs ours len)
  (cond ((late-complete-divergence? theirs ours len) 'late-complete)
        ((early-complete-divergence? theirs ours len) 'early-complete)
        (else 'unclassified)))

(define (render-divergence origin size theirs ours)
  (string-append origin " @" (number->string size)
                 "\n      llhttp: " (harness-join theirs " | ")
                 "\n        ours: " (harness-join ours " | ")))

(harness-begin "differential.llhttp")

(harness-group "the oracle is the llhttp the corpus came from"
  (lambda ()
    (harness-case "the built binaries carry the version the corpus records"
      (lambda ()
        ;; Otherwise every divergence below is version drift wearing a parser
        ;; bug's clothes, and the run would be read exactly backwards.
        (let* ((version (let ((t (read-text (string-append bin-dir "/VERSION"))))
                          (let loop ((i 0))
                            (cond ((= i (string-length t)) t)
                                  ((char=? (string-ref t i) #\newline) (substring t 0 i))
                                  (else (loop (+ i 1)))))))
               (provenance (read-text (string-append corpus-dir "/PROVENANCE"))))
          (check (string-append "corpus provenance names llhttp " version)
                 (harness-string-contains? provenance
                                           (string-append "upstream-ref: v" version))))))))

(harness-group "this parser and llhttp agree, or diverge for a named reason"
  (lambda ()
    (harness-case "every divergence falls into a class this project has decided about"
      (lambda ()
        (write-cases! cases-file probes)
        (let ((status (run-oracle!)))
          (check-equal "the oracle runner succeeded" status 0))
        (let ((results (read-results traces-file)))
          (check-equal "one result per probe" (length results) (length probes))
          (let loop ((ps probes) (rs results)
                     (unclassified '()) (late 0) (early 0) (agreed 0))
            (cond
             ((or (null? ps) (null? rs))
              ;; The counts are printed rather than asserted: they move with
              ;; the seed, and a number that moves is not a check. What IS
              ;; checked is that nothing landed outside the two classes, and
              ;; the two witnesses below hold each class to exact bytes.
              (display (string-append
                        "httparse-differential: agreed=" (number->string agreed)
                        " late-complete=" (number->string late)
                        " early-complete=" (number->string early)
                        " unclassified=" (number->string (length unclassified))
                        "\n"))
              (adapter-flush-output)
              (check-equal "divergences with no named reason"
                           (harness-take (reverse unclassified) 6) '())
              (check "some comparisons happened" (> agreed 0)))
             (else
              (let* ((p (car ps))
                     (c (probe-case p))
                     (r (car rs))
                     (mine (drive-trace (machine-for (gen-case-kind c))
                                        (drive-init (gen-case-kind c)
                                                    (gen-case-flags c))
                                        (gen-case-bytes c) (probe-size p))))
                (cond
                 ((string? r)
                  (loop (cdr ps) (cdr rs)
                        (cons (string-append (gen-case-origin c) " @"
                                             (number->string (probe-size p)) " :: " r)
                              unclassified)
                        late early agreed))
                 ((drive-refusal? mine)
                  (loop (cdr ps) (cdr rs)
                        (cons (string-append (gen-case-origin c) " @"
                                             (number->string (probe-size p))
                                             " :: this parser refused: "
                                             (drive-refusal-detail mine))
                              unclassified)
                        late early agreed))
                 (else
                  (let* ((theirs (guard (e ((oracle-error? e) #f)) 
                                   (map utf8->string (oracle-normalize r))))
                         (ours (map utf8->string mine)))
                    (cond
                     ((not theirs)
                      (loop (cdr ps) (cdr rs)
                            (cons (string-append (gen-case-origin c)
                                                 " :: the oracle printed a line this lane cannot read")
                                  unclassified)
                            late early agreed))
                     ((equal? theirs ours)
                      (loop (cdr ps) (cdr rs) unclassified late early (+ agreed 1)))
                     (else
                      (case (classify theirs ours (bytevector-length (gen-case-bytes c)))
                        ((late-complete)
                         (loop (cdr ps) (cdr rs) unclassified (+ late 1) early agreed))
                        ((early-complete)
                         (loop (cdr ps) (cdr rs) unclassified late (+ early 1) agreed))
                        (else
                         (loop (cdr ps) (cdr rs)
                               (cons (render-divergence (gen-case-origin c) (probe-size p)
                                                        theirs ours)
                                     unclassified)
                               late early agreed)))))))))))))))))

;; --- the witness for each class -------------------------------------------
;;
;; BOTH TRACES ARE llhttp'S OWN OUTPUT for the reduced input, taken from the
;; fixture binary and read back through the same module the bulk comparison
;; uses. They are not written from this parser, and they are not run through
;; the classifier: a class anchored only by a predicate is a class that can
;; quietly widen.

;; Upstream's own binary for a kind that is not one of the three the bulk
;; run uses -- `request-lenient-headers` is built by its harness with its own
;; `-D`, and the runner resolves the kind to the binary of that name.
(define (oracle-with-binary kind text size)
  (oracle-run kind text size ""))

;; No mask field: upstream's own binary for the kind.
(define (oracle-trace-of kind text size)
  (oracle-run kind text size ""))

;; A mask field, ALWAYS -- even an empty one, which is how the group below
;; asks `http-modes-c` for a strict parse and compares it with the program
;; upstream ships.
(define (oracle-lenient-trace-of kind text size flags)
  (oracle-run kind text size
              (string-append " " (number->string
                                  (httparse-lenient-flags-value flags)))))

(define (oracle-run kind text size mask-field)
  (let ((path (string-append work-dir "/witness-cases.txt")))
    (let ((port (open-file-output-port path (file-options no-fail))))
      (put-bytevector port (string->utf8
                            (string-append kind " " (number->string size) ":"
                                           (number->string (+ size 1)) " "
                                           (oracle-hex-encode (string->utf8 text))
                                           mask-field
                                           "\n")))
      (close-port port))
    (adapter-run-command
     (string-append "'" node "' '" runner "' '" bin-dir "' '" path "' '"
                    work-dir "/witness-traces.txt'"))
    (let ((rs (read-results (string-append work-dir "/witness-traces.txt"))))
      (if (or (null? rs) (string? (car rs)))
          (list (if (null? rs) "no result" (car rs)))
          (map utf8->string (oracle-normalize (car rs)))))))

(define (our-trace-of kind text size) (our-lenient-trace-of kind text size '()))

(define (our-lenient-trace-of kind text size flags)
  (let* ((k (string->symbol kind))
         (t (drive-trace (machine-for k) (drive-init k flags)
                         (string->utf8 text) size)))
    (if (drive-refusal? t)
        (list (string-append "refused: " (drive-refusal-detail t)))
        (map utf8->string t))))

(harness-group "the divergence that was, and is not"
  (lambda ()
    ;; `OPTIONS a.com:443` is an authority-form target, which llhttp's URL
    ;; machine rejects for a method that is not CONNECT. A parser that read
    ;; the target as one opaque span would carry on to the version instead.
    ;;
    ;; So this is the sharpest evidence there is that the URL machine is in
    ;; the request path. A count of zero divergences is a number; two traces
    ;; that are the same list of strings is the behaviour.
    (harness-case "llhttp stops inside the target and so does this parser"
      (lambda ()
        (let ((theirs (oracle-trace-of "request" "OPTIONS a.com:443 HTTP/1.1\r\n\r\n" 30))
              (ours (our-trace-of "request" "OPTIONS a.com:443 HTTP/1.1\r\n\r\n" 30)))
          (check-equal "llhttp stops at the dot"
                       theirs
                       '("off=0 message begin"
                         "off=0 len=7 span[method]=\"OPTIONS\""
                         "off=7 method complete"
                         "off=9 error code=7 reason=\"Unexpected char in url schema\""))
          ;; NO `span[url]` BEFORE THE ERROR. The target span is open when
          ;; the url machine refuses, and an error abandons an open span
          ;; rather than flushing it -- the same rule `span[method]` follows.
          (check-equal "and this parser stops at the same byte, for the same reason"
                       ours theirs)
          (check-equal "so there is nothing left for the classifier to name"
                       (classify theirs ours 30) 'unclassified))))))

(harness-group "and a CONNECT target still gets through"
  (lambda ()
    ;; The other half of the URL machine in the request target, and the
    ;; reason it needs a branch rather than one entry:
    ;; `0-home0.netscape.com:443` has no scheme and no
    ;; leading slash, so `url_start` would refuse its first byte. llhttp
    ;; routes a CONNECT request past `start` and opens at the host instead.
    ;; `request/method.md#4` covers this in the corpus; here it is checked
    ;; against the live oracle, because the two entries are one field test
    ;; apart and a wrong test would fail only for CONNECT.
    (harness-case "the authority form llhttp accepts, this parser accepts"
      (lambda ()
        (let ((theirs (oracle-trace-of "request" "CONNECT a.com:443 HTTP/1.0\r\n\r\n" 30))
              (ours (our-trace-of "request" "CONNECT a.com:443 HTTP/1.0\r\n\r\n" 30)))
          (check "llhttp accepted it"
                 (harness-member? "off=30 message complete" theirs))
          (check-equal "and so did this parser, line for line" ours theirs))))))

(harness-group "the witness for the keyword table's terminal"
  (lambda ()
    ;; `HTTP` is the whole input. llhttp matches the constant and fires
    ;; `protocol complete` on its last byte; the generator's keyword table
    ;; returns need-input at the same point and takes the terminal edge only
    ;; when a further byte arrives, so the event is missing entirely.
    (harness-case "llhttp completes the protocol at end of input and this parser does not"
      (lambda ()
        (let ((theirs (oracle-trace-of "response" "HTTP" 4))
              (ours (our-trace-of "response" "HTTP" 4)))
          (check-equal "llhttp"
                       theirs
                       '("off=0 message begin"
                         "off=0 len=4 span[protocol]=\"HTTP\""
                         "off=4 protocol complete"))
          (check-equal "ours"
                       ours
                       '("off=0 message begin"
                         "off=0 len=4 span[protocol]=\"HTTP\""))
          (check-equal "and the class names it"
                       (classify theirs ours 4) 'late-complete))))
    (harness-case "one more byte and the two agree again"
      (lambda ()
        ;; Which is why 190 corpus fixtures cannot see this: every one of them
        ;; has a byte after the protocol.
        (check-equal "HTTP/"
                     (our-trace-of "response" "HTTP/" 5)
                     (oracle-trace-of "response" "HTTP/" 5))))))

(harness-group "the witness for a completion one byte past its delimiter"
  (lambda ()
    ;; `PUT /url ` ends on the space that terminates the target. llhttp puts
    ;; `url complete` at 9 -- one past the space -- and needs the byte at 9 to
    ;; be there; this parser fires it without. Same offset when the byte does
    ;; arrive, which is why every corpus fixture agrees.
    (harness-case "this parser completes the target at end of input and llhttp does not"
      (lambda ()
        (let ((theirs (oracle-trace-of "request" "PUT /url " 9))
              (ours (our-trace-of "request" "PUT /url " 9)))
          (check-equal "llhttp"
                       theirs
                       '("off=0 message begin"
                         "off=0 len=3 span[method]=\"PUT\""
                         "off=3 method complete"
                         "off=4 len=4 span[url]=\"/url\""))
          (check-equal "ours"
                       ours
                       '("off=0 message begin"
                         "off=0 len=3 span[method]=\"PUT\""
                         "off=3 method complete"
                         "off=4 len=4 span[url]=\"/url\""
                         "off=9 url complete"))
          (check-equal "and the class names it"
                       (classify theirs ours 9) 'early-complete))))
    (harness-case "one more byte and the two agree again"
      (lambda ()
        (check-equal "PUT /url H"
                     (our-trace-of "request" "PUT /url H" 10)
                     (oracle-trace-of "request" "PUT /url H" 10))))))

(harness-group "the first byte is not a reason to withhold message begin"
  (lambda ()
    ;; llhttp prints `message begin` before it refuses a first byte no method
    ;; may start with, so `@ET / HTTP/1.1` prints the event and then the
    ;; error. A start node that refused the byte first would print the error
    ;; alone. No corpus fixture begins with a non-tchar, so only the live
    ;; oracle can say which is right.
    (harness-case "a first byte no method may start with still begins a message"
      (lambda ()
        (check-equal "@ET"
                     (our-trace-of "request" "@ET / HTTP/1.1\r\n\r\n" 18)
                     (oracle-trace-of "request" "@ET / HTTP/1.1\r\n\r\n" 18))))
    (harness-case "and so does a leading space"
      (lambda ()
        (check-equal "space"
                     (our-trace-of "request" " / HTTP/1.1" 11)
                     (oracle-trace-of "request" " / HTTP/1.1" 11))))
    (harness-case "a leading CRLF is still skipped and moves the offset"
      (lambda ()
        ;; The exception: llhttp's start matches CR and LF back to itself,
        ;; so the event lands at 2 rather than 0.
        (check-equal "crlf"
                     (our-trace-of "request" "\r\nGET / HTTP/1.1\r\n\r\n" 20)
                     (oracle-trace-of "request" "\r\nGET / HTTP/1.1\r\n\r\n" 20))))))

;;; --- WHAT THE URL KIND BUYS -----------------------------------------------
;;;
;;; The url kind has no divergence class to anchor: its comparisons agree.
;;; What the three groups below pin is the two ways that agreement could be
;;; worthless -- comparing the WRONG PARSER, and comparing graph the corpus
;;; already covers.

(harness-group "the url kind reaches a different binary and a different machine"
  (lambda ()
    (harness-case "the same bytes, read as a url and as a request, are two traces"
      (lambda ()
        ;; If `run-oracle.mjs` resolved `url` to a message binary, or this
        ;; lane picked the message machine for a url case, every url
        ;; comparison would still be internally consistent -- and the whole
        ;; kind would be measuring the wrong parser twice, in agreement.
        (let ((as-url (oracle-trace-of "url" "/p?q=1" 6))
              (as-request (oracle-trace-of "request" "/p?q=1" 6)))
          (check-equal "as a url" as-url
                       '("off=0 len=2 span[url.path]=\"/p\""
                         "off=3 len=3 span[url.query]=\"q=1\""))
          (check-equal "as a request" as-request
                       '("off=0 message begin"
                         "off=0 error code=6 reason=\"Invalid method encountered\""))
          (check-equal "this parser answers the url question" 
                       (our-trace-of "url" "/p?q=1" 6) as-url)
          (check-equal "and the request one, from the other machine"
                       (our-trace-of "request" "/p?q=1" 6) as-request))))))

(harness-group "the url exits, which no fixture in the corpus reaches"
  (lambda ()
    ;; NOT ONE OF `url.md`'S 21 INPUTS CONTAINS A SPACE, A CR OR AN LF, and
    ;; upstream's test build loops both exits back to the entry. So this is
    ;; graph the conformance lanes cannot execute at all, and generated input
    ;; walks through it constantly -- `sep=` is one of seven edges per case.
    (harness-case "a space ends one url and begins another"
      (lambda ()
        (check-equal "/path /next"
                     (our-trace-of "url" "/path /next" 11)
                     (oracle-trace-of "url" "/path /next" 11))))
    (harness-case "a CR that brings no LF is Expected CRLF"
      (lambda ()
        (check-equal "/p#frag\\rX"
                     (our-trace-of "url" "/p#frag\rX" 9)
                     (oracle-trace-of "url" "/p#frag\rX" 9))))))

(harness-group "the fragment arm that only this lane can see"
  (lambda ()
    ;; `#` AND `?` ARE ORDINARY INSIDE A FRAGMENT -- upstream's edge is
    ;; `fragment.match(['?','#'], fragment)` -- and no fixture in `url.md`
    ;; carries either. MEASURED: dropping `#` from that edge leaves every
    ;; other lane green, `url.md`'s 21 at every chunk size included, and puts
    ;; 48 of this lane's comparisons outside the classifier.
    ;;
    ;; So it is written down here as llhttp's own bytes rather than left to a
    ;; count: this is the case the url kind exists for, and a lane that only
    ;; ever printed `agreed=N` would not say which N.
    (harness-case "a fragment runs through a second `#`"
      (lambda ()
        (let ((theirs (oracle-trace-of "url" "*?a&b=c#a#b" 11)))
          (check-equal "llhttp" theirs
                       '("off=0 len=1 span[url.path]=\"*\""
                         "off=2 len=5 span[url.query]=\"a&b=c\""
                         "off=8 len=3 span[url.fragment]=\"a#b\""))
          (check-equal "ours" (our-trace-of "url" "*?a&b=c#a#b" 11) theirs))))))

;;; --- THE FOURTH BINARY IS HELD TO UPSTREAM'S OWN -------------------------
;;;
;;; `http-modes-c` is the one piece of this differential whose init hook is
;;; not upstream's. The oracle is upstream's harness, not a driver of ours,
;;; because a printer of our own would be a second implementation of the
;;; format under comparison. The hook keeps to that -- it assigns two integer
;;; fields and prints nothing, so every trace line still comes from
;;; upstream's `extra.c` -- but that is an argument, and what follows is a
;;; measurement.
;;;
;;; TWO EQUIVALENCES, and between them they pin both fields the hook writes.

(harness-group "at no flags, our binary is upstream's binary"
  (lambda ()
    ;; A mask field of `0` is what routes this at `http-modes-c` at all; with
    ;; no field the runner uses `http-request-c`, which is what every strict
    ;; case in the bulk run above does.
    (harness-case "a request parses identically through both"
      (lambda ()
        (check-equal "GET"
                     (oracle-lenient-trace-of "request" "GET /a HTTP/1.1\r\n\r\n" 19 '())
                     (oracle-trace-of "request" "GET /a HTTP/1.1\r\n\r\n" 19))))
    (harness-case "and so does a response, which is the other half of `type`"
      (lambda ()
        ;; The hook writes `s->type` as well as `s->lenient_flags`, and it
        ;; reads that from the environment too. A hook that always said
        ;; REQUEST would pass the case above and fail this one.
        (check-equal "HTTP/1.1 200"
                     (oracle-lenient-trace-of "response" "HTTP/1.1 200 OK\r\n\r\n" 19 '())
                     (oracle-trace-of "response" "HTTP/1.1 200 OK\r\n\r\n" 19))))
    (harness-case "and this parser agrees with both"
      (lambda ()
        (check-equal "ours"
                     (our-trace-of "request" "GET /a HTTP/1.1\r\n\r\n" 19)
                     (oracle-trace-of "request" "GET /a HTTP/1.1\r\n\r\n" 19))))))

(harness-group "at one flag, our binary is upstream's dedicated binary"
  (lambda ()
    ;; `http-request-lenient-headers-c` is built by upstream's own harness
    ;; with `-DLLPARSE__TEST_INIT=llhttp__test_init_request_lenient_headers`;
    ;; our file is not involved in it at all. If the hook set the wrong bit,
    ;; or set it after `llparse_init` had already been read, these would
    ;; differ -- and nothing else in this lane would say so, because both
    ;; sides of every lenient comparison would be wrong together.
    (harness-case "LENIENT_HEADERS through the mask is LENIENT_HEADERS"
      (lambda ()
        (let ((theirs (oracle-with-binary "request-lenient-headers"
                                          "GET /url HTTP/1.1\r\nHeader1: \x0c;\r\n\r\n" 33))
              (ours-mask (oracle-lenient-trace-of
                          "request" "GET /url HTTP/1.1\r\nHeader1: \x0c;\r\n\r\n" 33
                          '(headers))))
          (check-equal "upstream's own binary"
                       theirs
                       '("off=0 message begin"
                         "off=0 len=3 span[method]=\"GET\""
                         "off=3 method complete"
                         "off=4 len=4 span[url]=\"/url\""
                         "off=9 url complete"
                         "off=9 len=4 span[protocol]=\"HTTP\""
                         "off=13 protocol complete"
                         "off=14 len=3 span[version]=\"1.1\""
                         "off=17 version complete"
                         "off=19 len=7 span[header_field]=\"Header1\""
                         "off=27 header_field complete"
                         "off=28 len=1 span[header_value]=\"\x0c;\""
                         "off=31 header_value complete"
                         "off=33 headers complete method=1 v=1/1 flags=0 content_length=0"
                         "off=33 message complete"))
          (check-equal "and the mask reproduces it" ours-mask theirs)
          (check-equal "and so does this parser"
                       (our-lenient-trace-of
                        "request" "GET /url HTTP/1.1\r\nHeader1: \x0c;\r\n\r\n" 33
                        '(headers))
                       theirs))))
    (harness-case "and the same bytes at no flags are an error"
      (lambda ()
        ;; Otherwise the case above would pass with a hook that set nothing:
        ;; `\f` in a header value is `Invalid header value char` strictly.
        (check "strict refuses it"
               (exists (lambda (l) (harness-string-contains? l "Invalid header value char"))
                       (oracle-trace-of "request"
                                        "GET /url HTTP/1.1\r\nHeader1: \x0c;\r\n\r\n" 33)))))))

(harness-finish)
