;;; Tests for (httparse test ratchet) and the checked-in ratchet manifest.
;;;
;;; The manifest is the milestone exit criterion in file form, so this lane
;;; judges it against the corpus itself rather than against a written-down
;;; count: every fixture appears exactly once, every entry names a fixture that
;;; exists, and every entry's in-scope/deferred class matches the one derived
;;; from the fixture's own meta.
(import (rnrs)
        (httparse test harness)
        (httparse test corpus-load)
        (httparse test ratchet))

(define (read-text path)
  (utf8->string (call-with-port (open-file-input-port path) get-bytevector-all)))

(define corpus-dir (adapter-environment-variable "HTTPARSE_CORPUS_DIR"))
(define ratchet-path (adapter-environment-variable "HTTPARSE_RATCHET_FILE"))

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

;; (id . fixture) for every fixture in the vendored corpus
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

(define (entries) (ratchet-parse (read-text ratchet-path)))

(harness-begin "unit.ratchet")

(harness-group "parsing"
  (lambda ()
    (harness-case "comments and blank lines are ignored"
      (lambda ()
        (check-equal "none" (length (ratchet-parse "# a comment\n\n   \n")) 0)))
    (harness-case "a status and an id are read"
      (lambda ()
        (let ((e (car (ratchet-parse "not-yet  a.md#1\n"))))
          (check-equal "status" (ratchet-entry-status e) 'not-yet)
          (check-equal "id" (ratchet-entry-id e) "a.md#1"))))
    (harness-case "a deferred entry keeps its reason word"
      (lambda ()
        (check-equal "note" (ratchet-entry-note (car (ratchet-parse "deferred a.md#1 pausing\n")))
                     "pausing")))
    (harness-case "an unknown status is refused"
      (lambda ()
        (check-raises "typo" ratchet-error?
          (lambda () (ratchet-parse "passng a.md#1\n")))))
    (harness-case "a repeated fixture id is refused"
      (lambda ()
        ;; Two entries for one fixture would let a `passing` line sit beside a
        ;; `not-yet` line for the same thing, and whichever was read last would
        ;; decide.
        (check-raises "dup" ratchet-error?
          (lambda () (ratchet-parse "not-yet a.md#1\npassing a.md#1\n")))))
    (harness-case "a status with no id is refused"
      (lambda ()
        (check-raises "no id" ratchet-error?
          (lambda () (ratchet-parse "not-yet\n")))))))

(harness-group "the checked-in manifest against the corpus"
  (lambda ()
    (harness-case "the lane was given both paths"
      (lambda ()
        (check "corpus dir" (and corpus-dir (not (string=? corpus-dir ""))))
        (check "ratchet file" (and ratchet-path (not (string=? ratchet-path ""))))))
    (harness-case "every fixture in the corpus has exactly one entry"
      (lambda ()
        (let ((ids (map ratchet-entry-id (entries))))
          (check-equal "fixtures with no entry"
                       (length (filter (lambda (p) (not (member (car p) ids))) (corpus-index)))
                       0))))
    (harness-case "every entry names a fixture that exists"
      (lambda ()
        (let ((index (corpus-index)))
          (check-equal "entries with no fixture"
                       (length (filter (lambda (e) (not (assoc (ratchet-entry-id e) index)))
                                       (entries)))
                       0))))
    (harness-case "the manifest covers the corpus exactly, 274 entries"
      (lambda ()
        (check-equal "entries" (length (entries)) 274)
        (check-equal "fixtures" (length (corpus-index)) 274)))
    (harness-case "every entry's class matches the one derived from the fixture"
      (lambda ()
        ;; Decision 0009's split is computed from each fixture's own meta, so a
        ;; refresh cannot smuggle a lenient fixture in as `not-yet`.
        (let ((index (corpus-index)))
          (check-equal "class disagreements"
                       (length
                        (filter (lambda (e)
                                  (let* ((f (cdr (assoc (ratchet-entry-id e) index)))
                                         (derived (ratchet-fixture-class f))
                                         (declared (if (eq? (ratchet-entry-status e) 'deferred)
                                                       'deferred 'in-scope)))
                                    (not (eq? derived declared))))
                                (entries)))
                       0))))
    (harness-case "39 fixtures are deferred and 235 are in scope"
      (lambda ()
        ;; Decision 0009's bar was 84 and 190. M9 moved the 24 `pausing` and
        ;; 2 `skipBody` fixtures across; M10 moves the lenient ones a FLAG at
        ;; a time, so these two numbers change together once per slice and
        ;; every change is a reviewed diff rather than a drift.
        (let ((es (entries)))
          (check-equal "deferred"
                       (length (filter (lambda (e) (eq? (ratchet-entry-status e) 'deferred)) es))
                       39)
          (check-equal "in scope"
                       (length (filter (lambda (e) (memq (ratchet-entry-status e)
                                                         '(passing not-yet))) es))
                       235))))
    (harness-case "no deferred entry is missing its reason word"
      (lambda ()
        (check-equal "reasonless deferrals"
                     (length (filter (lambda (e)
                                       (and (eq? (ratchet-entry-status e) 'deferred)
                                            (string=? (ratchet-entry-note e) "")))
                                     (entries)))
                     0)))))

(harness-finish)
