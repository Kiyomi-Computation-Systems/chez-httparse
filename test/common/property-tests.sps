;;; Properties of the parser over inputs nobody wrote down.
;;;
;;; The corpus is replayed at every chunk size and compared bit-exactly, so
;;; what it cannot cover is an input it does not contain. This lane takes the
;;; two properties the corpus establishes for its own 190 inputs and asks them
;;; of generated ones instead. It needs no llhttp: both sides of every
;;; comparison here are ours.
;;;
;;; 1. FRAGMENTATION INVARIANCE, FOR A PARSE THAT REACHES NO ERROR. Upstream's
;;;    scan exists because a resumable parser must produce the same trace
;;;    however the bytes arrive. The qualifier was MEASURED, not assumed: over
;;;    240 generated inputs, every one of the 71 that parsed without an error
;;;    was invariant across chunk sizes, and 13 of the 169 that errored were
;;;    not. The exception has its own group below and llhttp shares it exactly,
;;;    so the unqualified property would have been a false one -- and the
;;;    corpus could not have said so, because upstream chose fixtures it holds
;;;    for.
;;;
;;; 2. THE TWO EXECUTORS AGREE. The committed artifact is what ships and the
;;;    interpreter is what the grammar means. The conformance lane compares
;;;    them on corpus inputs; this compares them where no expectation exists,
;;;    which is the only place a compiler bug could hide from that lane.
;;;
;;; BOTH PROPERTIES ARE ASKED OF BOTH MACHINES. The url sub-parser has its own
;;; emitted artifact and its own interpreted twin, and 21 fixtures is not much
;;; to judge a twenty-node machine on. The kind travels with each case and
;;; picks the pair, exactly as the conformance driver picks one per fixture.
;;;
;;; AND OF BOTH MODES. A lenient case is the same parser with two fields
;;; written before the first byte, so both properties apply to it unchanged.
;;; What it adds is the combinations: upstream's harness has one init hook per
;;; single flag, so a PAIR is something no fixture anywhere tests.
;;;
;;; EVERY FLOOR HERE IS PER KIND AND PER MODE. A floor over all kinds is
;;; satisfied by one kind, and a floor over all modes by strict alone: a url
;;; machine that errored on everything, or a lenient half that stopped being
;;; generated, would leave a global floor cleared by the others and this lane
;;; green with nothing to say about it. Both tallies are printed beside their
;;; checks so a reader can see which member is carrying one.
;;;
;;; A REFUSAL IS A FINDING, NOT A CRASH. The adapter has no row for an outcome
;;; llhttp never prints, and a generated input is the likeliest way to reach
;;; one. Reported here as a failing case naming the seed and the origin, so it
;;; replays exactly.
(import (rnrs)
        (httparse test harness)
        (httparse test corpus-load)
        (httparse test corpus-decode)
        (httparse test generate)
        (httparse test drive)
        (httparse test adapter)
        (httparse grammar)
        (httparse url-grammar)
        (generated httparse-message)
        (generated httparse-url)
        (byte-machine verify)
        (byte-machine interpret))

(define (read-text path)
  (utf8->string (call-with-port (open-file-input-port path) get-bytevector-all)))

(define corpus-dir (adapter-environment-variable "HTTPARSE_CORPUS_DIR"))

(define seed
  (let ((v (adapter-environment-variable "HTTPARSE_PROPERTY_SEED")))
    (or (and (string? v) (string->number v)) 20260915)))

(define case-count
  (let ((v (adapter-environment-variable "HTTPARSE_PROPERTY_CASES")))
    (or (and (string? v) (string->number v)) 120)))

(define url-case-count
  (let ((v (adapter-environment-variable "HTTPARSE_PROPERTY_URL_CASES")))
    (or (and (string? v) (string->number v)) case-count)))

;; The lenient schedule is 67 entries -- 11 singletons, 55 pairs, the whole
;; set -- so a count below that leaves pairs unvisited. Three passes, because
;; only the MATCHED half of a pass produces error-free parses and the floor
;; below is over those: at two passes the worst of six seeds gave 23 against
;; a floor of 15, which is less margin than the kind floors have; at three it
;; is 32. The lane costs about a second either way.
(define lenient-case-count
  (let ((v (adapter-environment-variable "HTTPARSE_PROPERTY_LENIENT_CASES")))
    (or (and (string? v) (string->number v)) 201)))

;; TWO MACHINES, AND THE CASE'S KIND SAYS WHICH -- the same resolution the
;; conformance driver makes per fixture and the differential makes per case.
;; Both are built here, so the executor comparison below is made twice: once
;; for the message parser and once for the url sub-parser, which has its own
;; emitted artifact and its own interpreted twin.
(define interpreted-message
  (make-interpreted-machine (verify-machine (make-message-machine))))
(define interpreted-url
  (make-interpreted-machine (verify-machine (make-url-machine))))

(define (generated-for kind)
  (if (eq? kind 'url) httparse-url-machine httparse-message-machine))
(define (interpreted-for kind)
  (if (eq? kind 'url) interpreted-url interpreted-message))

;; The message lane's own name for the message artifact, kept because the
;; measured exception below is a response and says so.
(define generated httparse-message-machine)

;; --- bases -------------------------------------------------------------
;;
;; A mutant of a real message lands in the neighbourhood where the grammar's
;; arms are densest, so the corpus supplies the bases. The six fixtures
;; carrying a non-ASCII byte are excluded HERE rather than inside the
;; generator, which refuses them: an unsafe base is a caller's mistake, and
;; silently dropping one inside the generator is how a run gets shorter with
;; nothing to show for it.
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
        (let inner ((fs (corpus-parse-file (read-text (string-append corpus-dir "/" (car files)))))
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
                                       (cons (string-append (car files) "#" (number->string i))
                                             bv))
                                 acc)
                           acc))))))))

;; `url.md` entire, as in the differential: 21 inputs is small enough not to
;; need choosing from, and every one is a shape somebody thought worth
;; recording -- which is what a mutation wants under it.
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

;; THE URL CASES ARE A SEPARATE RUN, not more bases in the existing one --
;; the same reason the differential keeps them apart. `HTTPARSE_PROPERTY_URL_CASES=0`
;; reproduces this lane as it was before the url kind existed, so a finding
;; here has one possible source.
;; LENIENT CASES ARE A MODE, NOT A MACHINE. They run the same parser as the
;; strict ones, with two fields written before the first byte -- so both
;; properties apply to them unchanged, and the only new question is whether
;; they are here at all, which the mode tally below answers.
(define cases
  (append (generate-structured seed case-count)
          (generate-mutants seed case-count bases)
          (generate-urls seed url-case-count)
          (generate-mutants seed url-case-count url-bases)
          (generate-lenient seed lenient-case-count)))

(define (trace-text lines)
  (harness-join (map utf8->string lines) "\n"))

(define (describe c) (gen-case-origin c))

;; A case carries its own init: the kind, and the lenient flags the embedder
;; is to set before the first byte.
(define (case-init c) (drive-init (gen-case-kind c) (gen-case-flags c)))

;; --- counting per kind ----------------------------------------------------
;;
;; A FLOOR OVER ALL KINDS IS SATISFIED BY ONE KIND. Both properties below are
;; guarded by a floor, because a run that selected nothing would pass them
;; vacuously -- and once a third kind shares the lane, the floor has to be
;; per kind or the two message kinds go on satisfying it alone while the url
;; machine contributes nothing and nobody notices.
(define kinds '(request response url))

;; AND A SECOND DIMENSION, for the same reason the first one is split. A
;; lenient case is a request or a response, so it clears the kind floors
;; without being distinguishable from a strict one -- and a run that stopped
;; generating lenient input entirely would leave every kind floor green.
(define modes '(strict lenient))

(define (case-mode c) (if (null? (gen-case-flags c)) 'strict 'lenient))

(define (tally-new) (map (lambda (k) (cons k 0)) kinds))

(define (mode-tally-new) (map (lambda (m) (cons m 0)) modes))

(define (tally-add t key)
  (map (lambda (row) (if (eq? (car row) key) (cons (car row) (+ (cdr row) 1)) row)) t))

(define (tally-ref t kind) (cdr (assq kind t)))

(define (tally-show label t)
  (display (string-append "httparse-property: " label))
  (for-each (lambda (row)
              (display (string-append " " (symbol->string (car row))
                                      "=" (number->string (cdr row)))))
            t)
  (display "\n")
  (adapter-flush-output))

;; The floor each kind AND each mode must clear on its own. MEASURED RATHER
;; THAN CHOSEN -- error-free inputs per kind at the default count, over six
;; seeds:
;;
;;     seed        request  response  url
;;     20260915      49        48     115
;;     1             50        50      98
;;     2             40        58     102
;;     777           51        53     103
;;     20260916      57        53      93
;;     31337         40        56     104
;;
;; The request and response columns grew when the lenient producer arrived --
;; a lenient case is a request or a response too. RE-MEASURED rather than
;; scaled: the figures these replace were taken before it existed, and a
;; scaled guess is what put a wrong table here in the first place.
;;
;; and by mode, at 201 lenient cases:
;;
;;     seed        strict  lenient
;;     20260915      180      32
;;     1             159      39
;;     2             158      42
;;     777           169      38
;;     20260916      164      39
;;     31337         164      36
;;
;; The smallest anyone produced is 40 by kind and 32 by mode, and what the
;; floor has to catch is a kind or a mode contributing nothing at all. 15
;; clears every seed tried by seventeen or more and still lands far above a
;; subject that stopped being generated, or whose every input became an
;; error.
;;
;; THE LENIENT ROW IS WHY THE GENERATOR MATCHES HALF ITS MALFORMATIONS TO THE
;; FLAGS IT WAS GIVEN. Drawn freely it was 4 of 134, because an input dies at
;; the first thing its subset cannot excuse -- and this property is about
;; parses that reach no error. The floor is what said so.
(define kind-floor 15)

(harness-begin "property.generated-input")

(harness-group "the parser produces a trace for every generated input"
  (lambda ()
    (harness-case "no generated input reaches an outcome the adapter cannot name"
      (lambda ()
        (let loop ((cs cases) (refused '()))
          (cond
           ((null? cs)
            (check-equal "refusals" refused '()))
           (else
            (let ((t (drive-trace (generated-for (gen-case-kind (car cs)))
                                  (case-init (car cs))
                                  (gen-case-bytes (car cs))
                                  (max 1 (bytevector-length (gen-case-bytes (car cs)))))))
              (loop (cdr cs)
                    (if (drive-refusal? t)
                        (cons (string-append (describe (car cs)) " :: "
                                             (drive-refusal-detail t))
                              refused)
                        refused))))))))))

(define (has-error? lines)
  (exists (lambda (l) (harness-string-contains? (utf8->string l) "error code="))
          lines))

(harness-group "a parse that reaches no error does not depend on how the bytes arrive"
  (lambda ()
    (harness-case "every chunk size yields the trace the whole buffer does"
      (lambda ()
        (let loop ((cs cases) (bad '()) (clean (tally-new)) (cmode (mode-tally-new)))
          (cond
           ((null? cs)
            (check-equal "divergences" bad '())
            (tally-show "error-free inputs" clean)
            (tally-show "error-free by mode" cmode)
            (for-each
             (lambda (m)
               (check (string-append "enough error-free " (symbol->string m)
                                     " inputs to be a property")
                      (> (tally-ref cmode m) kind-floor)))
             modes)
            ;; Without a floor this passes by selecting nothing: a generator
            ;; that only ever produced errors would leave it green. Per kind,
            ;; because a url machine that errored on everything it was given
            ;; would still leave a global floor cleared by the other two.
            (for-each
             (lambda (k)
               (check (string-append "enough error-free " (symbol->string k)
                                     " inputs to be a property")
                      (> (tally-ref clean k) kind-floor)))
             kinds))
           (else
            (let* ((c (car cs))
                   (bv (gen-case-bytes c))
                   (len (bytevector-length bv))
                   (whole (drive-trace (generated-for (gen-case-kind c))
                                       (case-init c) bv (max 1 len))))
              (if (or (drive-refusal? whole) (has-error? whole))
                  (loop (cdr cs) bad clean cmode)
                  (let ((ref (trace-text whole)))
                    (let inner ((ss (drive-chunk-ladder len)) (bad bad))
                      (if (null? ss)
                          (loop (cdr cs) bad (tally-add clean (gen-case-kind c))
                                (tally-add cmode (case-mode c)))
                          (let ((t (drive-trace (generated-for (gen-case-kind c))
                                                (case-init c) bv (car ss))))
                            (inner (cdr ss)
                                   (if (and (not (drive-refusal? t))
                                            (string=? (trace-text t) ref))
                                       bad
                                       (cons (string-append
                                              (describe c) " at chunk size "
                                              (number->string (car ss)))
                                             bad)))))))))))))))) 

;; --- the exception, measured against a live llhttp ------------------------
;;
;; A span the parse never closed is printed only for the bytes a chunk
;; boundary already flushed, so the same input traces differently at
;; different chunk sizes. BOTH TRACES BELOW ARE llhttp'S OWN OUTPUT, taken
;; from its fixture binary at v9.4.3-1-gee51043 -- the whole-buffer one
;; verbatim, the one-byte one through the same coalescing upstream's checker
;; applies. They are not this parser's output written down.
;;
;; The input is a generated one: a header name with a space before its colon,
;; which is a token error. At 52 bytes the name span is open when the error
;; fires and llhttp prints nothing for it; at one byte at a time the boundary
;; flushes have already printed all seven bytes, which coalesce into one line.
(define unclosed-span-input
  (string->utf8 "ICE/2.0 102 OK\r\nUpgrade:websocket\r\nTrailer : X-T\r\n\r\n"))

(define (trace-of size)
  (let ((t (drive-trace generated (drive-init 'response '())
                        unclosed-span-input size)))
    (if (drive-refusal? t)
        (list (string-append "refused: " (drive-refusal-detail t)))
        (map utf8->string t))))

(define unclosed-span-prefix
  '("off=0 message begin"
    "off=0 len=3 span[protocol]=\"ICE\""
    "off=3 protocol complete"
    "off=4 len=3 span[version]=\"2.0\""
    "off=7 version complete"
    "off=12 len=2 span[status]=\"OK\""
    "off=16 status complete"
    "off=16 len=7 span[header_field]=\"Upgrade\""
    "off=24 header_field complete"
    "off=24 len=9 span[header_value]=\"websocket\""
    "off=35 header_value complete"))

(harness-group "a span still open when the parse fails"
  (lambda ()
    (harness-case "the whole buffer never prints it"
      (lambda ()
        (check-equal "52 bytes at once"
                     (trace-of 52)
                     (append unclosed-span-prefix
                             '("off=42 error code=10 reason=\"Invalid header token\"")))))
    (harness-case "one byte at a time prints what the boundaries flushed"
      (lambda ()
        (check-equal "size 1"
                     (trace-of 1)
                     (append unclosed-span-prefix
                             '("off=35 len=7 span[header_field]=\"Trailer\""
                               "off=42 error code=10 reason=\"Invalid header token\"")))))
    (harness-case "so the two differ, which is the whole point of the case"
      (lambda ()
        ;; Stated as a check because the two cases above would both pass if
        ;; someone made them the same by accident.
        (check-not-equal "52 vs 1" (trace-of 52) (trace-of 1))))))

;;; AND THE URL MACHINE HAS THE SAME EXCEPTION, which is why the qualifier
;;; above is not a message-parser quirk. Every span the url parser has is a
;;; part of the url, so an error with one open is the ordinary case rather
;;; than a corner: 249 of this lane's url probes disagree across chunk sizes
;;; once the error-free qualifier is dropped.
;;;
;;; UPSTREAM ANNOTATES IT, THOUGH NOT EXACTLY. `url.md` marks four of its 21
;;; fixtures `noScan`, and the group after this one measures which of them
;;; actually need it.
;;;
;;; The input below is `url.md`'s "Double `@`" verbatim, and BOTH TRACES ARE
;;; llhttp'S OWN OUTPUT from the url fixture binary at v9.4.3 -- the
;;; whole-buffer one as printed, the one-byte one through the same coalescing
;;; upstream's checker applies. They are not this parser's output written
;;; down.
(define open-host-span-input
  (string->utf8 "http://a:b@@hostname:443/"))

(define (url-trace-of size)
  (let ((t (drive-trace httparse-url-machine (drive-init 'url '())
                        open-host-span-input size)))
    (if (drive-refusal? t)
        (list (string-append "refused: " (drive-refusal-detail t)))
        (map utf8->string t))))

(harness-group "a url span still open when the parse fails"
  (lambda ()
    (harness-case "the whole buffer never prints the host"
      (lambda ()
        ;; The schema span CLOSED and so it prints; the host span was open at
        ;; the error and does not. An error abandons an open span rather than
        ;; flushing it.
        (check-equal "25 bytes at once"
                     (url-trace-of 25)
                     '("off=0 len=4 span[url.schema]=\"http\""
                       "off=12 error code=7 reason=\"Double @ in url\""))))
    (harness-case "one byte at a time prints what the boundaries flushed"
      (lambda ()
        ;; `a:b@` -- the four host bytes read before the second `@`, already
        ;; delivered by four chunk boundaries and coalesced into one line.
        (check-equal "size 1"
                     (url-trace-of 1)
                     '("off=0 len=4 span[url.schema]=\"http\""
                       "off=7 len=4 span[url.host]=\"a:b@\""
                       "off=12 error code=7 reason=\"Double @ in url\""))))
    (harness-case "so the two differ, which is why upstream marks it noScan"
      (lambda ()
        (check-not-equal "25 vs 1" (url-trace-of 25) (url-trace-of 1))))))

;;; WHICH FIXTURES NEED `noScan`, AND WHICH ONLY CARRY IT. Upstream's
;;; annotation is what tells the conformance driver not to replay a fixture at
;;; every chunk size, so it is the corpus's own statement about where the
;;; exception above bites. It is worth checking against rather than quoting,
;;; and the two directions are not the same claim.
;;;
;;; THE DIRECTION THAT MATTERS is that nothing diverges unmarked: an unmarked
;;; fixture IS replayed at every chunk size and compared bit-exactly, so one
;;; whose trace depended on chunking would make that comparison meaningless.
;;;
;;; The other direction is upstream being cautious, and MEASURED rather than
;;; assumed: `url.md`'s four marked fixtures are its four error fixtures, but
;;; only three of them diverge. "Failing on broken schema" does not -- its
;;; schema span is CLOSED before the error, so there is no open span for a
;;; chunk boundary to flush early. llhttp does not diverge on it either,
;;; checked against the url fixture binary at both sizes.
(define url-fixtures
  (corpus-parse-file (read-text (string-append corpus-dir "/url.md"))))

(define (chunking-changes-the-trace? f)
  (let* ((bv (corpus-decode-input (fixture-input-text f)))
         (n (bytevector-length bv))
         (url (drive-init 'url '()))
         (whole (drive-trace httparse-url-machine url bv (max 1 n)))
         (one (drive-trace httparse-url-machine url bv 1)))
    (not (and (not (drive-refusal? whole))
              (not (drive-refusal? one))
              (string=? (trace-text whole) (trace-text one))))))

(define (url-fixture-numbers pred)
  (let loop ((fs url-fixtures) (i 1) (acc '()))
    (cond ((null? fs) (reverse acc))
          ((pred (car fs)) (loop (cdr fs) (+ i 1) (cons i acc)))
          (else (loop (cdr fs) (+ i 1) acc)))))

(harness-group "upstream's noScan, against where the exception actually bites"
  (lambda ()
    (harness-case "the corpus still carries the four marks this rests on"
      (lambda ()
        ;; A refresh that dropped or added one changes what the group below
        ;; means, so the set is written down rather than derived twice.
        (check-equal "marked noScan"
                     (url-fixture-numbers
                      (lambda (f) (and (fixture-meta-ref f 'noScan #f) #t)))
                     '(3 15 20 21))))
    (harness-case "no url fixture diverges without being marked"
      (lambda ()
        ;; The load-bearing direction. An unmarked fixture is replayed at every
        ;; chunk size by the conformance driver and compared bit-exactly.
        (let ((diverging (url-fixture-numbers chunking-changes-the-trace?)))
          (check-equal "diverging and unmarked"
                       (filter (lambda (n) (not (memv n '(3 15 20 21)))) diverging)
                       '())
          (check-equal "diverging" diverging '(15 20 21)))))
    (harness-case "and one marked fixture does not need the mark"
      (lambda ()
        ;; `schema:/path...` -- the schema span is CLOSED before the error, so
        ;; no chunk boundary has an open span to flush early. Stated as a case
        ;; because the set above would otherwise look like an exact
        ;; correspondence, and it is not one.
        (check "3 is marked" (memv 3 '(3 15 20 21)))
        (check "3 does not diverge"
               (not (chunking-changes-the-trace? (list-ref url-fixtures 2))))))))

(harness-group "the shipped artifact and the grammar agree"
  (lambda ()
    (harness-case "both executors produce the same trace for every generated input"
      (lambda ()
        ;; The conformance lane makes this comparison over the corpus. Here it
        ;; is made where nothing recorded the answer, which is the only place
        ;; an emitter bug could survive that lane.
        (let loop ((cs cases) (bad '()) (checked (tally-new)) (cmode (mode-tally-new)))
          (cond
           ((null? cs)
            (check-equal "divergences" bad '())
            (tally-show "executor comparisons" checked)
            (tally-show "executor comparisons by mode" cmode)
            (for-each
             (lambda (m)
               (check (string-append "some " (symbol->string m) " comparisons happened")
                      (> (tally-ref cmode m) kind-floor)))
             modes)
            (for-each
             (lambda (k)
               (check (string-append "some " (symbol->string k) " comparisons happened")
                      (> (tally-ref checked k) kind-floor)))
             kinds))
           (else
            (let* ((c (car cs))
                   (bv (gen-case-bytes c))
                   (size (max 1 (bytevector-length bv)))
                   (a (drive-trace (generated-for (gen-case-kind c))
                                   (case-init c) bv size))
                   (b (drive-trace (interpreted-for (gen-case-kind c))
                                   (case-init c) bv size))
                   (same (cond ((and (drive-refusal? a) (drive-refusal? b))
                                (string=? (drive-refusal-detail a)
                                          (drive-refusal-detail b)))
                               ((or (drive-refusal? a) (drive-refusal? b)) #f)
                               (else (string=? (trace-text a) (trace-text b))))))
              (loop (cdr cs)
                    (if same bad (cons (describe c) bad))
                    (tally-add checked (gen-case-kind c))
                    (tally-add cmode (case-mode c)))))))))))

(harness-finish)
