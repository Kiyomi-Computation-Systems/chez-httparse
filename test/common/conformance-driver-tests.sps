;;; The two-way ratchet, driven over the vendored corpus.
;;;
;;; This is the lane the milestone exit criteria are stated in. For every
;;; in-scope fixture it replays the input at each chunk size the selection asks
;;; for, renders the parser's callbacks into llhttp's trace text through the
;;; adapter, and compares BIT-EXACTLY against the fixture's own expected block
;;; (decision 0008).
;;;
;;; THE GATE IS TWO-WAY (decision 0008 item 6). A `passing` entry that fails is
;;; an error, and a `not-yet` entry that PASSES is also an error. The second
;;; half is what stops a milestone's exit criterion from being met by accident:
;;; the manifest is a reviewed file, so every promotion is a diff.
;;;
;;; `deferred` entries are not run. Decision 0009 puts them outside v0.1, and a
;;; lane that gated on them would be asserting something this milestone has
;;; deliberately not built.
;;;
;;; THE GATE RUNS THE SHIPPED ARTIFACT. `(generated httparse-message)` is
;;; the committed derived parser, loaded and run here as itself rather than
;;; re-derived from the grammar -- an emitter that wrote a wrong-but-well-formed
;;; artifact would otherwise survive, because nothing read what it wrote. The
;;; reference interpreter runs beside it over the same fixtures and must agree.
;;;
;;; A FIXTURE THE ADAPTER REFUSES IS A FAILING FIXTURE, NOT A CRASHED LANE. The
;;; adapter raises on a callback or error code it has no row for, which is the
;;; no-default discipline decision 0008 item 2 requires. Here that is caught and
;;; reported as this fixture not passing -- the parser produced something the
;;; oracle's vocabulary has no word for, which is exactly a conformance failure.
(import (rnrs)
        (httparse test harness)
        (httparse test corpus-load)
        (httparse test corpus-decode)
        (httparse test trace-format)
        (httparse test conformance)
        (httparse test ratchet)
        (httparse test adapter)
        (httparse test drive)
        (httparse grammar)
        (httparse url-grammar)
        (generated httparse-message)
        (generated httparse-url)
        (byte-machine verify)
        (byte-machine interpret)
        (byte-machine runtime))

(define (read-text path)
  (utf8->string (call-with-port (open-file-input-port path) get-bytevector-all)))

(define corpus-dir (adapter-environment-variable "HTTPARSE_CORPUS_DIR"))
(define ratchet-path (adapter-environment-variable "HTTPARSE_RATCHET_FILE"))

;; 'extremes (chunk size 1 and the whole buffer) or 'full (every size) --
;; decision 0008 item 5's split across the pr and release presets.
(define selection
  (let ((v (adapter-environment-variable "HTTPARSE_SCAN_SELECTION")))
    (if (and (string? v) (string=? v "full")) 'full 'extremes)))

(define corpus-files
  '("request/connection.md" "request/content-length.md" "request/finish.md"
    "request/invalid.md" "request/lenient-header-value-relaxed.md"
    "request/lenient-headers.md" "request/lenient-version.md" "request/method.md"
    "request/pausing.md" "request/pipelining.md" "request/sample.md"
    "request/transfer-encoding.md" "request/uri.md"
    "response/connection.md" "response/content-length.md" "response/finish.md"
    "response/invalid.md" "response/lenient-version.md" "response/pausing.md"
    "response/pipelining.md" "response/sample.md" "response/transfer-encoding.md"
    "url.md"))

(define (corpus-index)
  (apply append
         (map (lambda (rel)
                (let loop ((fs (corpus-parse-file (read-text (string-append corpus-dir "/" rel))))
                           (i 1) (acc '()))
                  (if (null? fs)
                      (reverse acc)
                      (loop (cdr fs) (+ i 1)
                            (cons (cons (ratchet-fixture-id rel i) (car fs)) acc)))))
              corpus-files)))

;; The committed artifact, run as itself. The interpreter is built beside it
;; from the same grammar and is compared against it below, never substituted
;; for it.
;; TWO MACHINES, AND THE FIXTURE SAYS WHICH. `url.md`'s 21 fixtures are typed
;; by their input fence (```url rather than ```http) and upstream runs them
;; against a different binary -- `test/md-test.ts` calls `buildURL()` and
;; passes no `-D` at all. So this driver resolves a machine per fixture rather
;; than holding one.
(define (url-fixture? f) (eq? (fixture-kind f) 'url))

(define interpreted-message
  (make-interpreted-machine (verify-machine (make-message-machine))))
(define interpreted-url
  (make-interpreted-machine (verify-machine (make-url-machine))))

;; lane is 'generated (the committed artifact) or 'interpreted (the reference
;; executor). Both lanes cover both machines, so the executor differential
;; below judges the url parser exactly as it judges the message parser.
(define (machine-for lane f)
  (case lane
    ((generated) (if (url-fixture? f) httparse-url-machine httparse-message-machine))
    ((interpreted) (if (url-fixture? f) interpreted-url interpreted-message))
    (else (assertion-violation 'conformance-driver "no such lane" lane))))

;; llhttp's own harness asks for a finish LINE only for the `*-finish` fixture
;; types (test/fixtures/index.ts, which defines `LLPARSE__TEST_FINISH` for
;; exactly those two), so this does too.
;;
;; WHAT THAT HOOK DOES IS PRINT A FIELD, NOT END A PARSE.
;; `llhttp__test_finish` is one line -- `llparse__print(NULL, NULL,
;; "finish=%d", s->finish)`. It never calls `llhttp_finish`, so no callback
;; fires and no end-of-input state is entered; the trace simply gains
;; `off=NULL finish=N` after the last feed. Driving this parser to its
;; eof-targets instead would produce a finish error the oracle records on no
;; fixture -- `invalid-eof-state` now (#42), the numberless `unexpected-eof`
;; the adapter refused before M6 -- so decision 0016 has the driver print the
;; `finish` field rather than finish.
(define (finishing? f)
  (let ((type (fixture-meta-ref f 'type #f)))
    (and (string? type)
         (let ((n (string-length type)) (suffix "-finish"))
           (and (> n 7)
                (string=? (substring type (- n 7) n) suffix))))))

(define (no-scan? f) (eq? #t (fixture-meta-ref f 'noScan #f)))

;; THE HARNESS MODE IS THE FIXTURE'S OWN META, RENAMED AND NOT INTERPRETED.
;; `test/md-test.ts` turns `pause` into `-DLLHTTP__TEST_PAUSE_<NAME>=1` and
;; caches one compiled binary per mode, so over there the mode is a property
;; of the BINARY a fixture runs against. Here it is an argument, and it is
;; read off the meta the same way the type is.
;;
;; A mode this driver cannot spell is handed on as it stands: the ADAPTER
;; refuses a pause point upstream has no macro for, so a meta naming one is a
;; failing fixture there rather than a crash here.
;;
;; THE TWO ARE EXCLUSIVE and upstream's `#elif` is why, so a fixture carrying
;; both is handed on as `(pause ...)` for the adapter to accept -- which is
;; what the C would do, since its `#ifdef` wins over its `#elif`. No vendored
;; fixture carries both, and a refresh that added one would be renaming an
;; oracle build that cannot exist.
(define (fixture-harness-mode f)
  (let ((pause (fixture-meta-ref f 'pause 'absent)))
    (cond ((not (eq? pause 'absent)) (list 'pause pause))
          ((eq? #t (fixture-meta-ref f 'skipBody #f)) (list 'skip-body))
          (else #f))))

;; THE PARSER'S KIND IS THE FIXTURE'S OWN META, RENAMED AND NOT INTERPRETED.
;; llhttp's harness turns the meta type into `-DLLPARSE__TEST_INIT=
;; llhttp__test_init_<type>`, and each of those hooks sets `s->type` from the
;; type's FIRST WORD -- `llhttp__test_init_response_lenient_all` opens by
;; calling `llhttp__test_init_response`. So the first word is the kind, and
;; that is all this reads.
;;
;; A type this driver cannot spell is handed on as it stands: the ADAPTER
;; decides what it can bind, so a `url` fixture or one with no type at all is
;; a failing fixture there rather than a crash here -- the same rule as every
;; other refusal in this lane.
;; fixture-init : Fixture -> (Pair Symbol (Listof Symbol))
;; The init hook upstream compiles in, decomposed: its kind and the lenient
;; flags it sets. One value because it is one function over there.
(define (fixture-init f)
  (cons (fixture-message-type f) (fixture-lenient-flags f)))

(define (fixture-message-type f)
  (let ((type (fixture-meta-ref f 'type #f)))
    (if (string? type)
        (string->symbol
         (let loop ((i 0))
           (cond ((= i (string-length type)) type)
                 ((char=? (string-ref type i) #\-) (substring type 0 i))
                 (else (loop (+ i 1))))))
        'none)))

;; run-at : Symbol Fixture Bytevector Nat -> (Listof Bytevector)
;; The trace one executor produces for one chunk size.
;;
;; A URL FIXTURE BINDS FIVE SPANS AND NOTHING ELSE, and passes no field
;; initials: that machine declares no settable field, because its binary has
;; no mode to be in.
(define (run-at lane f bv size)
  (let* ((machine (machine-for lane f))
         (r (make-trace-recorder))
         (p (if (url-fixture? f)
                (make-parser machine (trace-recorder-url-bindings r) #f)
                (make-parser machine
                             (trace-recorder-bindings r (fixture-init f)
                                                      (fixture-harness-mode f))
                             #f
                             (adapter-parser-inits (fixture-init f)))))
         (len (bytevector-length bv)))
    (let loop ((bounds (corpus-chunk-bounds len size)) (result #f))
      (cond
       ((null? bounds)
        (let ((final result))
          (when (and final (eq? (parser-result-status final) 'error))
            (trace-recorder-note-error! r (parser-result-error final)))
          ;; A PAUSE IS AN OUTCOME, NOT AN ENDING, and it is a renameable
          ;; one: the pause reason arrives in its own result slot, leaving the
          ;; error slot #f so a resumable outcome is still distinguishable
          ;; from a failed one.
          (when (and final (eq? (parser-result-status final) 'paused))
            (trace-recorder-note-paused! r (parser-result-pause final)))
          ;; The adapter refuses an outcome it has no row for, here as
          ;; everywhere else -- so a `*-finish` fixture that did not parse
          ;; cleanly is a FAILING FIXTURE and not a crashed lane.
          (when (and (not (url-fixture? f)) (finishing? f))
            (trace-recorder-note-finish!
             r p (and final (parser-result-status final))))
          (trace-format (trace-recorder-events r))))
       (else
        ;; `drive-feed!` records and resumes a pause THIS HARNESS ASKED FOR
        ;; and hands back every other outcome, so a paused fixture's trace is
        ;; a complete parse with extra lines in it -- which is what upstream's
        ;; driver produces and what the fixture records.
        (let ((res (drive-feed! r p bv (caar bounds) (cdar bounds))))
          (if (eq? (parser-result-status res) 'need-input)
              (loop (cdr bounds) res)
              (loop '() res))))))))

;; fixture-mismatch : Fixture -> #f when every chunk size matches, else a
;; string naming the first size that did not and how.
(define (fixture-mismatch f)
  (let* ((bv (corpus-decode-input (fixture-input-text f)))
         (expected (fixture-expected f))
         (sizes (corpus-scan-sizes (bytevector-length bv) (no-scan? f) selection)))
    (let loop ((sizes sizes))
      (if (null? sizes)
          #f
          (let ((m (call/cc
                    (lambda (k)
                      (with-exception-handler
                       (lambda (e)
                         (if (adapter-error? e)
                             (k (string-append "adapter refused: " (adapter-error-detail e)))
                             (raise e)))
                       (lambda ()
                         (let ((d (trace-compare expected (run-at 'generated f bv (car sizes)))))
                           (and d
                                (string-append
                                 "line " (number->string (mismatch-index d))
                                 " expected " (quoted (mismatch-expected d))
                                 " got " (quoted (mismatch-actual d))
                                 " (" (symbol->string (mismatch-reason d)) ")")))))))))
            (if m
                (string-append "at chunk size " (number->string (car sizes)) ": " m)
                (loop (cdr sizes))))))))

(define (quoted s)
  (string-append "\"" s "\""))

(define fixtures (corpus-index))
(define entries (ratchet-parse (read-text ratchet-path)))

(define (fixture-of id)
  (let ((row (assoc id fixtures)))
    (unless row (assertion-violation 'conformance-driver "no such fixture" id))
    (cdr row)))

;; (id status mismatch) for every gated entry, computed once.
(define results
  (map (lambda (e)
         (let ((id (ratchet-entry-id e)))
           (list id (ratchet-entry-status e) (fixture-mismatch (fixture-of id)))))
       (filter (lambda (e) (not (eq? (ratchet-entry-status e) 'deferred))) entries)))

(define (ids-where pred)
  (map car (filter (lambda (r) (pred (cadr r) (caddr r))) results)))

;; The whole-buffer trace from each executor, for every gated fixture. One
;; chunk size, because this asks whether the two AGREE -- the corpus itself
;; already replays the passing ones at every size against the artifact.
;; A refusal is an OUTCOME, not a crash: the two executors must agree about
;; that too, so it is captured as a value and compared like any other.
(define (outcome lane f bv n)
  (call/cc
   (lambda (k)
     (with-exception-handler
      (lambda (e) (if (adapter-error? e) (k (list 'refused (adapter-error-detail e))) (raise e)))
      (lambda () (run-at lane f bv n))))))

(define (executors-disagree)
  (filter
   (lambda (id)
     (let* ((f (fixture-of id))
            (bv (corpus-decode-input (fixture-input-text f)))
            (n (max 1 (bytevector-length bv))))
       (not (equal? (outcome 'generated f bv n) (outcome 'interpreted f bv n)))))
   (map car results)))

(harness-begin "conformance.message")

(harness-group "the ratchet, both ways"
  (lambda ()
    (harness-case "every fixture marked passing still passes"
      (lambda ()
        (check-equal "regressions"
                     (ids-where (lambda (status m) (and (eq? status 'passing) m)))
                     '())))
    (harness-case "no fixture marked not-yet has started passing"
      (lambda ()
        ;; The half that makes the manifest a gate rather than a TODO list. A
        ;; fixture listed here is one to PROMOTE, in a reviewed diff -- not a
        ;; failure to fix.
        (check-equal "promote these"
                     (ids-where (lambda (status m) (and (eq? status 'not-yet) (not m))))
                     '())))))

(harness-group "the artifact and the interpreter agree"
  (lambda ()
    (harness-case "every gated fixture produces the same trace either way"
      (lambda ()
        ;; The committed parser is emitted from this grammar; if the two ever
        ;; disagree, one of them is not the machine the grammar describes.
        (check-equal "fixtures where they differ" (executors-disagree) '())))))

(harness-group "the selection is the one the preset asked for"
  (lambda ()
    (harness-case "every gated fixture ran"
      (lambda ()
        ;; A selection that silently matched nothing would make both checks
        ;; above vacuously true.
        (check "at least one gated fixture" (> (length results) 0))
        (check-equal "gated = in-scope entries"
                     (length results)
                     (length (filter (lambda (e)
                                       (not (eq? (ratchet-entry-status e) 'deferred)))
                                     entries)))))))

(harness-finish)
