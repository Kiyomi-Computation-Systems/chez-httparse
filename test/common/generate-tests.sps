;;; Tests for (httparse test generate): the seeded input generator.
;;;
;;; THE GENERATOR IS AN INSTRUMENT, so it is calibrated before anything is
;;; measured with it. Two of its properties are load-bearing and neither is
;;; visible from a passing differential run: a run must replay exactly from its
;;; seed, and every byte it emits must be one the live oracle can actually be
;;; given. A generator that quietly shrank to nothing, or that emitted a byte
;;; argv mangles, would leave both the property and differential lanes green
;;; while comparing less -- or comparing two different inputs.
(import (rnrs)
        (httparse test harness)
        (httparse test generate)
        (httparse modes))

(define (bytes . xs) (u8-list->bytevector xs))
(define (text bv) (utf8->string bv))

(define (all? p xs) (for-all p xs))

(define (remove-duplicates xs)
  (cond ((null? xs) '())
        ((memq (car xs) (cdr xs)) (remove-duplicates (cdr xs)))
        (else (cons (car xs) (remove-duplicates (cdr xs))))))

(define sample-bases
  (list (cons 'request (cons "b1" (string->utf8 "GET / HTTP/1.1\r\n\r\n")))
        (cons 'response (cons "b2" (string->utf8 "HTTP/1.1 200 OK\r\n\r\n")))))

(harness-begin "unit.generate")

(harness-group "a seed names a run"
  (lambda ()
    (harness-case "the same seed produces the same cases, byte for byte"
      (lambda ()
        (let ((a (generate-structured 7 20))
              (b (generate-structured 7 20)))
          (check-equal "kinds" (map gen-case-kind a) (map gen-case-kind b))
          (check-equal "bytes" (map gen-case-bytes a) (map gen-case-bytes b))
          (check-equal "origins" (map gen-case-origin a) (map gen-case-origin b)))))
    (harness-case "a different seed produces different cases"
      (lambda ()
        ;; Not a strong claim about randomness -- just that the seed reaches
        ;; the output at all, which a generator ignoring it would fail.
        (check-not-equal "7 vs 8"
                         (map gen-case-bytes (generate-structured 7 20))
                         (map gen-case-bytes (generate-structured 8 20)))))
    (harness-case "the count is the number of cases"
      (lambda ()
        (check-equal "0" (length (generate-structured 1 0)) 0)
        (check-equal "37" (length (generate-structured 1 37)) 37)))
    (harness-case "a mutant run replays from its seed too"
      (lambda ()
        (check-equal "bytes"
                     (map gen-case-bytes (generate-mutants 3 15 sample-bases))
                     (map gen-case-bytes (generate-mutants 3 15 sample-bases)))))))

(harness-group "every byte is one the oracle can be given"
  (lambda ()
    (harness-case "structured output stays inside [1,127]"
      (lambda ()
        ;; Several seeds, because a single seed may never reach the arm that
        ;; would break this.
        (for-each
         (lambda (seed)
           (check (string-append "seed " (number->string seed))
                  (all? (lambda (c) (generate-safe-bytes? (gen-case-bytes c)))
                        (generate-structured seed 60))))
         '(1 2 3 11 101 9973))))
    (harness-case "mutant output stays inside [1,127]"
      (lambda ()
        (for-each
         (lambda (seed)
           (check (string-append "seed " (number->string seed))
                  (all? (lambda (c) (generate-safe-bytes? (gen-case-bytes c)))
                        (generate-mutants seed 60 sample-bases))))
         '(1 2 3 11 101 9973))))
    (harness-case "the predicate itself rejects NUL and the high half"
      (lambda ()
        (check "nul" (not (generate-safe-byte? 0)))
        (check "1" (generate-safe-byte? 1))
        (check "127" (generate-safe-byte? 127))
        (check "128" (not (generate-safe-byte? 128)))
        (check "255" (not (generate-safe-byte? 255)))
        (check "a bytevector with one high byte" 
               (not (generate-safe-bytes? (bytes 65 200 66))))
        (check "an empty bytevector is safe" (generate-safe-bytes? (bytes)))))
    (harness-case "a base carrying a byte it may not emit is refused"
      (lambda ()
        ;; Silently skipping it would make the run shorter with no sign of it.
        (check-raises "high byte in base" generate-error?
          (lambda ()
            (generate-mutants 1 5 (list (cons 'request (cons "bad" (bytes 71 69 200)))))))))
    (harness-case "no bases at all is refused, not an empty run"
      (lambda ()
        (check-raises "empty" generate-error?
          (lambda () (generate-mutants 1 5 '())))))))

(harness-group "each mutation does one named thing"
  (lambda ()
    ;; Exact bytes, so the table is judged on what it produces rather than on
    ;; a whole run's shape.
    (define base (string->utf8 "ABCDE"))
    (harness-case "substitute replaces the byte at the index"
      (lambda ()
        (check-equal "at 2" (text (generate-mutate 'substitute base 2 122)) "ABzDE")))
    (harness-case "delete removes it"
      (lambda ()
        (check-equal "at 2" (text (generate-mutate 'delete base 2 122)) "ABDE")))
    (harness-case "insert puts a byte before it"
      (lambda ()
        (check-equal "at 2" (text (generate-mutate 'insert base 2 122)) "ABzCDE")))
    (harness-case "truncate keeps the prefix"
      (lambda ()
        (check-equal "at 2" (text (generate-mutate 'truncate base 2 122)) "AB")
        (check-equal "at 0" (text (generate-mutate 'truncate base 0 122)) "")))
    (harness-case "swap exchanges it with its neighbour"
      (lambda ()
        (check-equal "at 1" (text (generate-mutate 'swap base 1 122)) "ACBDE")))
    (harness-case "swap at the last byte has no neighbour and changes nothing"
      (lambda ()
        ;; Stated as a case because a run that produced it would otherwise look
        ;; like a mutation that the parser failed to notice.
        (check-equal "at 4" (text (generate-mutate 'swap base 4 122)) "ABCDE")))
    (harness-case "duplicate repeats it"
      (lambda ()
        (check-equal "at 2" (text (generate-mutate 'duplicate base 2 122)) "ABCCDE")))
    (harness-case "an unknown mutation is refused"
      (lambda ()
        (check-raises "nope" generate-error?
          (lambda () (generate-mutate 'reverse base 0 1)))))
    (harness-case "every name in the table is one the mutator implements"
      (lambda ()
        ;; The list drives the generator, so a name with no arm would raise
        ;; mid-run at whatever seed first reached it.
        (for-each
         (lambda (op)
           (check (symbol->string op)
                  (bytevector? (generate-mutate op base 1 122))))
         generate-mutations)))))

(harness-group "what a structured run contains"
  (lambda ()
    (harness-case "both kinds appear"
      (lambda ()
        (let ((kinds (map gen-case-kind (generate-structured 5 60))))
          (check "requests" (memq 'request kinds) )
          (check "responses" (memq 'response kinds)))))
    (harness-case "a kind is always one of the two"
      (lambda ()
        (check "only request and response"
               (all? (lambda (c) (memq (gen-case-kind c) '(request response)))
                     (generate-structured 5 60)))))
    (harness-case "some cases are cut short"
      (lambda ()
        ;; The truncation arm is where a resumable parser's offsets are most
        ;; likely to disagree, so a run with none of them is a weaker run.
        (check "a cut case"
               (exists (lambda (c)
                         (harness-string-contains? (gen-case-origin c) "cut="))
                       (generate-structured 5 60)))))
    (harness-case "some cases carry a complete message"
      (lambda ()
        (check "an uncut case"
               (exists (lambda (c)
                         (not (harness-string-contains? (gen-case-origin c) "cut=")))
                       (generate-structured 5 60)))))
    (harness-case "every framing choice is reachable"
      (lambda ()
        (let ((origins (map gen-case-origin (generate-structured 5 200))))
          (for-each
           (lambda (f)
             (check f (exists (lambda (o)
                                (harness-string-contains? o (string-append "framing=" f)))
                              origins)))
           '("none" "length" "chunked" "both" "te-identity")))))
    (harness-case "an origin names the seed and the case"
      (lambda ()
        (let ((c (car (generate-structured 42 3))))
          (check "seed" (harness-string-contains? (gen-case-origin c) "seed=42"))
          (check "index" (harness-string-contains? (gen-case-origin c) "n=0")))))))

(harness-group "what a mutant run contains"
  (lambda ()
    (harness-case "a mutant keeps its base's kind"
      (lambda ()
        ;; The embedder tells the parser what it is parsing; changing a byte
        ;; does not change that, and a mutant parsed as the other kind would
        ;; compare two different questions.
        (let ((cases (generate-mutants 9 60 sample-bases)))
          (for-each
           (lambda (c)
             (check "b1 is a request"
                    (if (harness-string-contains? (gen-case-origin c) "base=b1")
                        (eq? (gen-case-kind c) 'request)
                        #t))
             (check "b2 is a response"
                    (if (harness-string-contains? (gen-case-origin c) "base=b2")
                        (eq? (gen-case-kind c) 'response)
                        #t)))
           cases))))
    (harness-case "every mutation appears over a long enough run"
      (lambda ()
        (let ((origins (map gen-case-origin (generate-mutants 9 200 sample-bases))))
          (for-each
           (lambda (op)
             (check (symbol->string op)
                    (exists (lambda (o)
                              (harness-string-contains? o (symbol->string op)))
                            origins)))
           generate-mutations))))
    (harness-case "an origin names the base and the index it touched"
      (lambda ()
        (let ((c (car (generate-mutants 9 1 sample-bases))))
          (check "base" (harness-string-contains? (gen-case-origin c) "base="))
          (check "at" (harness-string-contains? (gen-case-origin c) "@")))))))

;;; THE URL GENERATOR IS A SECOND INSTRUMENT and is calibrated the same way.
;;; It exists because the message generator reaches almost none of the url
;;; sub-parser: a request target is one field out of ten and its pool is ten
;;; fixed strings, so the machine spliced in by decision 0023 is exercised by
;;; a handful of shapes and none of its error arms.
(harness-group "a url run replays from its seed"
  (lambda ()
    (harness-case "the same seed produces the same cases, byte for byte"
      (lambda ()
        (check-equal "bytes"
                     (map gen-case-bytes (generate-urls 7 20))
                     (map gen-case-bytes (generate-urls 7 20)))
        (check-equal "origins"
                     (map gen-case-origin (generate-urls 7 20))
                     (map gen-case-origin (generate-urls 7 20)))))
    (harness-case "a different seed produces different cases"
      (lambda ()
        (check-not-equal "7 vs 8"
                         (map gen-case-bytes (generate-urls 7 20))
                         (map gen-case-bytes (generate-urls 8 20)))))
    (harness-case "the count is the number of cases"
      (lambda ()
        (check-equal "0" (length (generate-urls 1 0)) 0)
        (check-equal "37" (length (generate-urls 1 37)) 37)))
    (harness-case "its output stays inside [1,127]"
      (lambda ()
        ;; Tab and form feed ARE emitted -- they are inside the range and they
        ;; are the only way to reach `Invalid characters in url`. What is
        ;; excluded is NUL and the high half, for the argv reason above.
        (for-each
         (lambda (seed)
           (check (string-append "seed " (number->string seed))
                  (all? (lambda (c) (generate-safe-bytes? (gen-case-bytes c)))
                        (generate-urls seed 60))))
         '(1 2 3 11 101 9973))))))

(harness-group "what a url run contains"
  (lambda ()
    (harness-case "every case is a url and nothing else"
      (lambda ()
        ;; The kind picks the oracle binary and the machine on this side. A
        ;; url case that called itself a request would compare two parsers
        ;; that were never meant to agree.
        (check "only url"
               (all? (lambda (c) (eq? (gen-case-kind c) 'url))
                     (generate-urls 5 60)))))
    (harness-case "both forms appear"
      (lambda ()
        ;; `http://h/p` enters at the schema; `/p` enters at the path. They
        ;; are different first edges out of `start` and neither implies the
        ;; other.
        ;; `forms=` is one letter per url in the input, so the FIRST letter
        ;; is what these two look at -- enough to say both edges are reached
        ;; without asserting a distribution the seed decides.
        (let ((origins (map gen-case-origin (generate-urls 5 60))))
          (check "absolute"
                 (exists (lambda (o) (harness-string-contains? o "forms=a")) origins))
          (check "relative"
                 (exists (lambda (o) (harness-string-contains? o "forms=r")) origins)))))
    (harness-case "every separator is reachable"
      (lambda ()
        ;; THE TEST BUILD LOOPS ITS EXITS BACK TO THE ENTRY, so what separates
        ;; two urls is a graph edge and not punctuation. Each of these names a
        ;; different one, and three of them are error arms.
        (let ((origins (map gen-case-origin (generate-urls 5 300))))
          (for-each
           (lambda (name)
             (check name
                    (exists (lambda (o)
                              (harness-string-contains? o (string-append "sep=" name)))
                            origins)))
           '("none" "space" "crlf" "lf" "cr" "tab" "ff")))))
    (harness-case "some inputs hold more than one url"
      (lambda ()
        (let ((origins (map gen-case-origin (generate-urls 5 60))))
          (check "one" (exists (lambda (o) (harness-string-contains? o "urls=1")) origins))
          (check "several"
                 (exists (lambda (o)
                           (or (harness-string-contains? o "urls=2")
                               (harness-string-contains? o "urls=3")))
                         origins)))))
    (harness-case "some cases are cut short and some are not"
      (lambda ()
        (let ((origins (map gen-case-origin (generate-urls 5 60))))
          (check "a cut case"
                 (exists (lambda (o) (harness-string-contains? o "cut=")) origins))
          (check "an uncut case"
                 (exists (lambda (o) (not (harness-string-contains? o "cut="))) origins)))))
    (harness-case "an origin names the seed and the case"
      (lambda ()
        (let ((c (car (generate-urls 42 3))))
          (check "seed" (harness-string-contains? (gen-case-origin c) "seed=42"))
          (check "index" (harness-string-contains? (gen-case-origin c) "n=0")))))
    (harness-case "no case is empty"
      (lambda ()
        ;; A zero-length url is a run that compares nothing, and the pools can
        ;; produce one: an empty path, no query and no fragment. The generator
        ;; must not emit it.
        (check "every case has bytes"
               (all? (lambda (c) (> (bytevector-length (gen-case-bytes c)) 0))
                     (generate-urls 5 200)))))))

;;; THE LENIENT GENERATOR IS ABOUT COMBINATIONS, and that is what its schedule
;;; has to guarantee. Upstream's harness has one init hook per (kind, single
;;; flag), so a PAIR of flags is something llhttp's own corpus tests exactly
;;; three times -- the `*-lenient-all` fixtures -- and those set nine of the
;;; eleven flags, leaving `spaces-after-chunk-size` and
;;; `header-value-relaxed` combined with nothing anywhere.
;;;
;;; A random draw over 55 pairs needs hundreds of cases to cover them, and
;;; "probably covered" is not a coverage claim. So the subsets walk a fixed
;;; schedule and the cases below assert the walk rather than a distribution.
(define (subset-of c) (gen-case-flags c))

(define (pairs-of flags)
  (if (null? flags)
      '()
      (append (map (lambda (b) (list (car flags) b)) (cdr flags))
              (pairs-of (cdr flags)))))

(define all-flags httparse-lenient-flag-names)
(define all-pairs (pairs-of all-flags))

(harness-group "a lenient run replays from its seed"
  (lambda ()
    (harness-case "the same seed produces the same cases, byte for byte"
      (lambda ()
        (check-equal "bytes"
                     (map gen-case-bytes (generate-lenient 7 30))
                     (map gen-case-bytes (generate-lenient 7 30)))
        (check-equal "flags"
                     (map gen-case-flags (generate-lenient 7 30))
                     (map gen-case-flags (generate-lenient 7 30)))))
    (harness-case "a different seed produces different inputs"
      (lambda ()
        ;; The SUBSETS are scheduled and so do not move with the seed; the
        ;; inputs they are paired with do, which is the point of running it
        ;; at more than one seed.
        (check-not-equal "7 vs 8"
                         (map gen-case-bytes (generate-lenient 7 30))
                         (map gen-case-bytes (generate-lenient 8 30)))
        (check-equal "same schedule"
                     (map gen-case-flags (generate-lenient 7 30))
                     (map gen-case-flags (generate-lenient 8 30)))))
    (harness-case "the count is the number of cases"
      (lambda ()
        (check-equal "0" (length (generate-lenient 1 0)) 0)
        (check-equal "37" (length (generate-lenient 1 37)) 37)))
    (harness-case "its output stays inside [1,127]"
      (lambda ()
        (for-each
         (lambda (seed)
           (check (string-append "seed " (number->string seed))
                  (all? (lambda (c) (generate-safe-bytes? (gen-case-bytes c)))
                        (generate-lenient seed 67))))
         '(1 2 3 11 101 9973))))))

(harness-group "what a lenient run contains"
  (lambda ()
    (harness-case "a lenient case is a message, never a url"
      (lambda ()
        ;; The flags are the MESSAGE parser's field. llhttp's url binary is
        ;; built with no init hook at all, so a lenient url is not a thing
        ;; either side can be asked for.
        (check "only request and response"
               (all? (lambda (c) (memq (gen-case-kind c) '(request response)))
                     (generate-lenient 5 67)))))
    (harness-case "every flag the parser knows appears alone"
      (lambda ()
        ;; Drawn from `(httparse modes)` rather than a list written here, so
        ;; a flag added to the parser enters the schedule instead of being
        ;; silently skipped.
        (let ((subsets (map subset-of (generate-lenient 5 67))))
          (for-each
           (lambda (f)
             (check (symbol->string f) (member (list f) subsets)))
           all-flags))))
    (harness-case "EVERY PAIR OF FLAGS APPEARS, and there are 55 of them"
      (lambda ()
        ;; The whole reason this producer exists. Decision 0020 found two
        ;; cross-flag interactions the hard way -- an invalid-transfer-encoding
        ;; refusal suppressed by EITHER of two flags, and a chunk-size arm
        ;; that needs BOTH of two others -- so the pairs are not a hypothesis.
        (check-equal "pairs of eleven flags" (length all-pairs) 55)
        (let ((subsets (map subset-of (generate-lenient 5 67))))
          (check-equal "pairs the schedule missed"
                       (filter (lambda (p)
                                 (not (exists (lambda (s)
                                                (and (= (length s) 2)
                                                     (memq (car p) s)
                                                     (memq (cadr p) s)))
                                              subsets)))
                               all-pairs)
                       '()))))
    (harness-case "and so does the whole set, which upstream has no hook for"
      (lambda ()
        ;; `lenient_all` is a misnomer over there: it sets nine of eleven.
        (let ((subsets (map subset-of (generate-lenient 5 67))))
          (check "all eleven"
                 (exists (lambda (s) (= (length s) (length all-flags))) subsets)))))
    (harness-case "no subset names a flag twice or a flag the parser lacks"
      (lambda ()
        (for-each
         (lambda (c)
           (let ((s (subset-of c)))
             (check "known" (for-all (lambda (f) (memq f all-flags)) s))
             (check "distinct" (= (length s) (length (remove-duplicates s))))))
         (generate-lenient 5 67))))
    (harness-case "half the cases match their malformations to their subset"
      (lambda ()
        ;; MEASURED, and the reason the split exists: drawn freely, 4 of 134
        ;; lenient inputs parsed without an error, because an input dies at
        ;; the first thing its subset cannot excuse -- and fragmentation
        ;; invariance is a property of parses that reach NO error. A matched
        ;; case offers a malformation only when the flag that excuses it is in
        ;; the subset; a free case draws them independently, which is where
        ;; both of this producer's first two findings came from.
        (let ((origins (map gen-case-origin (generate-lenient 5 67))))
          (check "matched"
                 (exists (lambda (o) (harness-string-contains? o " matched")) origins))
          (check "free"
                 (exists (lambda (o) (harness-string-contains? o " free")) origins)))))
    (harness-case "a matched case never carries a malformation its flags cannot excuse"
      (lambda ()
        ;; The two the origin can be read for. A matched case with a bare LF
        ;; and no lf flags, or a padded chunk size and no
        ;; `spaces-after-chunk-size`, would be a free case wearing the wrong
        ;; label -- and the error-free floor in the property lane would drop
        ;; without anything saying why.
        (for-each
         (lambda (c)
           (let ((o (gen-case-origin c)) (fs (gen-case-flags c)))
             (when (harness-string-contains? o " matched")
               (check "eol"
                      (or (harness-string-contains? o "eol=crlf")
                          (and (memq 'optional-cr-before-lf fs)
                               (memq 'optional-lf-after-cr fs))))
               (check "chunk pad"
                      (or (harness-string-contains? o "chunk=none/")
                          (memq 'spaces-after-chunk-size fs))))))
         (generate-lenient 5 201))))
    (harness-case "an origin names the seed, the case and the subset"
      (lambda ()
        (let ((c (car (generate-lenient 42 3))))
          (check "seed" (harness-string-contains? (gen-case-origin c) "seed=42"))
          (check "index" (harness-string-contains? (gen-case-origin c) "n=0"))
          (check "flags" (harness-string-contains? (gen-case-origin c) "flags=")))))
    (harness-case "the other producers carry no flags at all"
      (lambda ()
        ;; A strict case that quietly acquired a flag would be compared
        ;; against the wrong oracle binary.
        (check "structured"
               (all? (lambda (c) (null? (gen-case-flags c)))
                     (generate-structured 5 20)))
        (check "urls"
               (all? (lambda (c) (null? (gen-case-flags c)))
                     (generate-urls 5 20)))
        (check "mutants"
               (all? (lambda (c) (null? (gen-case-flags c)))
                     (generate-mutants 5 20 sample-bases)))))))

(harness-finish)
