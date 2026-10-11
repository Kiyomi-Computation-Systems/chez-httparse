;;; Chez runtime adapter for the httparse private test runner.
;;;
;;; This is the only place in the harness where runtime-specific identifiers
;;; may appear. Its export list is checked by mutation: deleting a load-bearing
;;; export here must make the self-tests fail.
;;;
;;; The library contains its own text -- the adapter section first, the
;;; runner below it, with no shared include body -- and imports (httparse test
;;; fingerprint). Nothing here resolves through source-directories.

(library (httparse test harness)
  (export
    ;; suite lifecycle
    harness-begin harness-finish harness-summary harness-exit-status
    harness-status-pass harness-status-failed
    harness-status-harness-error harness-status-provenance
    harness-empty-selection-error harness-empty-selection-diagnosis
    ;; structure
    harness-group harness-case
    ;; assertions
    check check-equal check-not-equal check-fail check-raises with-cleanup
    ;; self-testing
    harness-probe harness-set-filter!
    probe-cases probe-failed-cases probe-checks probe-failures
    probe-errors probe-skipped probe-cleanup-failures probe-raised?
    probe-failure-records
    failure-record-id failure-record-what failure-record-detail
    ;; pure helpers, exported so the runner's own tests can reach them
    harness-string-contains? harness-join harness-split harness-take
    harness-member? harness-failure-context harness-normalize-filter
    harness-counters harness-restore-counters! harness-capture-state
    ;; content fingerprint and provenance
    harness-fingerprint-bytevector harness-fingerprint-combine
    harness-fingerprint->string harness-fingerprint-file
    harness-bytes->string harness-provenance-diagnosis
    harness-verify-provenance! harness-provenance-reachability-diagnosis
    ;; adapter protocol
    adapter-runtime-name adapter-runtime-version adapter-machine-type
    adapter-os adapter-architecture adapter-execution-mode
    adapter-environment-variable adapter-exit
    adapter-value->string adapter-describe-condition adapter-file-bytes
    adapter-run-command adapter-bytes-allocated adapter-real-time
    adapter-flush-output
    adapter-machine-type->os adapter-machine-type->architecture
    ;; arithmetic harness-self-tests.sps and harness-bootstrap.sps call
    ;; directly, not the runner section below -- R6RS keeps it outside (rnrs)
    modulo quotient remainder)

  (import
    (rnrs)
    (httparse test fingerprint)
    (only (rnrs r5rs) modulo quotient remainder)
    (only (chezscheme)
          machine-type scheme-version getenv system
          statistics sstats-bytes real-time
          with-output-to-string display-condition))

  ;; --- runtime identity ----------------------------------------------------

  (define (adapter-runtime-name) "chez")

  ;; (scheme-version) is "Chez Scheme Version 10.4.1"; evidence records compare
  ;; the bare number, so take the final whitespace-delimited token.
  (define (adapter-runtime-version)
    (let* ((full (scheme-version))
           (n (string-length full)))
      (let loop ((i (- n 1)))
        (cond ((< i 0) full)
              ((char=? (string-ref full i) #\space) (substring full (+ i 1) n))
              (else (loop (- i 1)))))))

  (define (adapter-machine-type) (symbol->string (machine-type)))

  ;; --- OS and architecture, derived from the machine type ------------------
  ;;
  ;; Chez's machine type names the target the runtime was actually built for,
  ;; which is what a portability claim needs: an observed architecture, not a
  ;; configure-time guess. A threaded build carries a leading "t".

  (define (adapter-machine-type-strip-t m)
    (if (and (> (string-length m) 0) (char=? (string-ref m 0) #\t))
        (substring m 1 (string-length m))
        m))

  (define (adapter-string-starts-with? s prefix)
    (let ((sn (string-length s)) (pn (string-length prefix)))
      (and (>= sn pn)
           (string=? (substring s 0 pn) prefix))))

  (define adapter-architecture-table
    '(("arm64" . "arm64")
      ("arm32" . "arm32")
      ("a6" . "amd64")
      ("i3" . "x86")
      ("ppc32" . "ppc32")
      ("rv64" . "riscv64")
      ("la64" . "loongarch64")))

  (define adapter-os-table
    '(("le" . "linux")
      ("osx" . "darwin")
      ("nt" . "windows")
      ("fb" . "freebsd")
      ("ob" . "openbsd")
      ("nb" . "netbsd")
      ("s2" . "solaris")
      ("qnx" . "qnx")
      ("ti" . "ios")
      ("a" . "android")))

  (define (adapter-lookup-prefix table s)
    (cond ((null? table) #f)
          ((adapter-string-starts-with? s (car (car table))) (car table))
          (else (adapter-lookup-prefix (cdr table) s))))

  (define (adapter-machine-type->architecture machine-type)
    (let ((hit (adapter-lookup-prefix adapter-architecture-table
                                      (adapter-machine-type-strip-t machine-type))))
      (if hit (cdr hit) "unknown")))

  (define (adapter-machine-type->os machine-type)
    (let* ((body (adapter-machine-type-strip-t machine-type))
           (arch-hit (adapter-lookup-prefix adapter-architecture-table body)))
      (if (not arch-hit)
          "unknown"
          (let* ((rest (substring body (string-length (car arch-hit))
                                  (string-length body)))
                 (os-hit (adapter-lookup-prefix adapter-os-table rest)))
            (if os-hit (cdr os-hit) "unknown")))))

  (define (adapter-architecture)
    (adapter-machine-type->architecture (adapter-machine-type)))

  (define (adapter-os)
    (adapter-machine-type->os (adapter-machine-type)))

  ;; The lane registration declares the execution mode; the launcher never
  ;; touches this variable. The launcher's object guard is what makes the
  ;; declaration unfalsifiable: it makes a compiled object impossible to load.
  (define (adapter-execution-mode)
    (let ((m (getenv "HTTPARSE_EXECUTION_MODE")))
      (if (and m (not (string=? m ""))) m "unknown")))

  ;; --- services ------------------------------------------------------------

  (define (adapter-environment-variable name) (getenv name))

  (define (adapter-exit code) (exit code))

  (define (adapter-value->string v)
    (with-output-to-string (lambda () (write v))))

  (define (adapter-describe-condition obj)
    (if (condition? obj)
        (with-output-to-string (lambda () (display-condition obj)))
        (with-output-to-string (lambda () (write obj)))))

  ;; A binary port, so the value is bytes rather than decoded characters --
  ;; and so an LF is an LF on a platform whose text ports would translate it.
  ;; get-bytevector-all returns the EOF object for an empty file rather than a
  ;; zero-length bytevector, so an empty expectation file reads as empty
  ;; rather than raising.
  (define (adapter-file-bytes path)
    (let* ((port (open-file-input-port path))
           (bytes (get-bytevector-all port)))
      (close-port port)
      (if (eof-object? bytes) (make-bytevector 0) bytes)))

  ;; adapter-run-command : String -> Nat
  ;; Run a command and return its exit status. The ONE lane that needs this is
  ;; the live-llhttp differential, whose oracle is a separate program; it lives
  ;; here because this is the only module allowed to name a runtime-specific
  ;; identifier, not because running commands is an ordinary thing for a lane
  ;; to do.
  ;;
  ;; THE COMMAND GOES THROUGH A SHELL, so a caller may only build one out of
  ;; paths it controls. Nothing generated is ever interpolated into it: the
  ;; differential's inputs cross to its runner as hex in a file, for exactly
  ;; this reason.
  (define (adapter-run-command command) (system command))

  ;; adapter-bytes-allocated : -> Nat
  ;; Total bytes this process has allocated so far, CUMULATIVELY. Only a
  ;; difference across a measured region means anything; the absolute value
  ;; counts everything since startup, including loading the libraries.
  ;;
  ;; NOT THE OBVIOUS PROCEDURE. Chez's `bytes-allocated` reports what is
  ;; allocated RIGHT NOW, so a collection inside the measured region makes
  ;; the difference NEGATIVE -- a region can report -33122 bytes. The
  ;; statistics record's byte count is the running total and does not fall
  ;; when memory is reclaimed.
  (define (adapter-bytes-allocated) (sstats-bytes (statistics)))

  ;; adapter-real-time : -> Nat
  ;; Milliseconds on a monotonic clock. Wall time, so a benchmark reading it
  ;; is reporting what a caller would feel rather than what the CPU did.
  (define (adapter-real-time) (real-time))

  (define (adapter-flush-output) (flush-output-port (current-output-port)))

;; ---------------------------------------------------------------------------
;; The runner. Everything below stays plain R6RS out of habit and stability,
;; not law: records as tagged lists, no hash tables, no define-record-type.
;; Free identifiers used below and defined above (the adapter procedures) or
;; imported (the fingerprint library, r5rs arithmetic) are bound by this
;; library; a name bound nowhere kills the library at import.
;;
;; PROCESS STATUS
;;
;;   0  every selected case passed
;;   1  one or more assertions failed
;;   2  harness, configuration, or registration error
;;   3  reserved: the run could not confirm it executed the intended text
;;
;; Status is computed once, at the end, rather than chosen at each throw site,
;; so a new error path cannot forget to change it.

(define harness-status-pass 0)
(define harness-status-failed 1)
(define harness-status-harness-error 2)
(define harness-status-provenance 3)

;; ---------------------------------------------------------------------------
;; Pure helpers
;; ---------------------------------------------------------------------------

(define (harness-join parts separator)
  (if (null? parts)
      ""
      (let loop ((rest (cdr parts)) (acc (car parts)))
        (if (null? rest)
            acc
            (loop (cdr rest) (string-append acc separator (car rest)))))))

(define (harness-string-contains? haystack needle)
  (let ((hn (string-length haystack))
        (nn (string-length needle)))
    (let outer ((start 0))
      (cond ((> (+ start nn) hn) #f)
            ((let inner ((i 0))
               (cond ((= i nn) #t)
                     ((char=? (string-ref haystack (+ start i))
                              (string-ref needle i))
                      (inner (+ i 1)))
                     (else #f)))
             #t)
            (else (outer (+ start 1)))))))

;; A trailing separator yields a trailing empty field, deliberately: dropping it
;; would make "a." and "a" split alike, and a filter written against the
;; difference would silently stop distinguishing them.
(define (harness-split text separator)
  (let ((n (string-length text)))
    (let loop ((i 0) (start 0) (acc '()))
      (cond ((= i n) (reverse (cons (substring text start n) acc)))
            ((char=? (string-ref text i) separator)
             (loop (+ i 1) (+ i 1) (cons (substring text start i) acc)))
            (else (loop (+ i 1) start acc))))))

(define (harness-take lst count)
  (if (or (= count 0) (null? lst))
      '()
      (cons (car lst) (harness-take (cdr lst) (- count 1)))))

(define (harness-member? x lst)
  (cond ((null? lst) #f)
        ((equal? x (car lst)) #t)
        (else (harness-member? x (cdr lst)))))

;; An empty HTTPARSE_TEST_FILTER and an absent one must mean the same
;; thing -- no filter -- because a shell that writes `VAR=` and one that never
;; sets VAR at all are otherwise indistinguishable in intent. Pure, and kept
;; separate from harness-begin's environment read, so the rule is directly
;; testable: harness-string-contains? treats an empty needle as matching every
;; id anyway, so an empty and an unnormalised "" filter select identically and
;; no case-selection outcome could ever tell the two apart from the outside.
(define (harness-normalize-filter value)
  (if (and value (string=? value "")) #f value))

;; Decode a bytevector as ASCII, trimming whitespace at the ends only. The
;; expectation file is written without a trailing newline, but an editor, a
;; shell redirect, or a future writer may add one, and a comparison that failed
;; on a newline would be a provenance failure reported for the wrong reason.
;;
;; Interior whitespace is deliberately kept. Collapsing it would make
;; "dead beef" compare equal to "deadbeef" -- leniency that turns a corrupted
;; expectation into a passing comparison, which is the one outcome this whole
;; mechanism exists to prevent.
(define (harness-whitespace-byte? b)
  (or (= b 32) (= b 9) (= b 10) (= b 13)))

(define (harness-bytes->string bv)
  (let ((n (bytevector-length bv)))
    (let find-start ((start 0))
      (cond
        ((= start n) "")
        ((harness-whitespace-byte? (bytevector-u8-ref bv start))
         (find-start (+ start 1)))
        (else
         (let find-end ((end n))
           (if (harness-whitespace-byte? (bytevector-u8-ref bv (- end 1)))
               (find-end (- end 1))
               (let loop ((i start) (acc (list)))
                 (if (= i end)
                     (list->string (reverse acc))
                     (loop (+ i 1)
                           (cons (integer->char (bytevector-u8-ref bv i))
                                 acc)))))))))))

;; The provenance rule, as a function of two values. `expected` is #f when the
;; build supplied nothing at all, which is a different defect from a mismatch:
;; one means the lane ran text nobody measured, the other means it ran the wrong
;; text. Reporting them the same way would send a reader to the wrong file.
(define (harness-provenance-diagnosis expected computed)
  (cond
    ((not expected)
     (string-append
      "no expectation was supplied, so nothing can say whether this run "
      "executed the text it was supposed to. This run computed " computed "."))
    ((string=? expected computed) #f)
    (else
     (string-append
      "fingerprint mismatch: the build expected " expected
      " but this run computed " computed
      ". Either this lane executed different text from the one the build "
      "measured, or it is running a stale artifact."))))

;; A lane whose build declared a manifest, in a run where nothing verified it.
;;
;; SOURCES being required makes the environment unforgeable; it says
;; nothing about whether anything read it. The check is reached from
;; harness-begin, or by a hand-placed call -- which is what harness-bootstrap
;; needed, having deliberately no harness-begin. Forget that line in a future
;; program and the lane runs un-provenanced with nothing failing, which is the
;; one remaining way V9's guarantee can be true at configure time and false at
;; run time.
;;
;; Pure, and separate from the summary's read of the live flag, for the reason
;; harness-empty-selection-diagnosis is: a run in this state cannot assert
;; anything about itself from the inside, so the rule has to be checkable as a
;; function of two values.
;;
;; An absent or empty manifest is not this defect. It means no lane
;; registration started this process, and skipping is then correct -- see
;; harness-verify-provenance!.
(define (harness-provenance-reachability-diagnosis manifest checked?)
  (if (and manifest (not (string=? manifest "")) (not checked?))
      (string-append
       "the build declared a manifest for this run and nothing verified it. "
       "harness-verify-provenance! was never reached, so this suite's result "
       "says nothing about whether it executed the text it was given.")
      #f))

;; ---------------------------------------------------------------------------
;; Mutable result state (the imperative shell of the runner)
;; ---------------------------------------------------------------------------

;; Capture and restore the three pieces of state a failing `check` mutates:
;; harness-failure-count, harness-check-count, harness-current-case-failed.
;; Exported for the bootstrap, which must undo its own deliberately failing
;; check without depending on harness-probe -- itself one of the things the
;; bootstrap exists to check. The two must stay symmetric: restoring less
;; than capture saved could silently erase a real prior failure's flag.
(define (harness-counters)
  (list harness-failure-count harness-check-count harness-current-case-failed))

(define (harness-restore-counters! saved)
  (set! harness-failure-count (car saved))
  (set! harness-check-count (car (cdr saved)))
  (set! harness-current-case-failed (car (cdr (cdr saved)))))

(define harness-suite-name "(none)")
(define harness-group-stack '())
(define harness-case-ids '())
(define harness-current-case #f)
(define harness-current-case-failed #f)
(define harness-case-count 0)
(define harness-failed-case-count 0)
(define harness-check-count 0)
(define harness-failure-count 0)
(define harness-error-count 0)
(define harness-skipped-count 0)
(define harness-cleanup-failure-count 0)
(define harness-failures '())
(define harness-filter #f)
(define harness-verbose #f)
(define harness-probe-depth 0)

;; Set by harness-verify-provenance! itself, so "unset" means the procedure was
;; never called -- not that it ran and found nothing. Deliberately outside
;; harness-clear-state! and the probe's captured state: harness-begin verifies
;; before it clears, and a probe restoring this would erase the fact that the
;; check happened.
(define harness-provenance-checked #f)
(define harness-provenance-unreached #f)

(define (harness-quiet?) (> harness-probe-depth 0))

;; Flushed per line rather than at the summary. Standard output is block
;; buffered when it is not a terminal, so a process killed by a supervisor loses
;; everything it had written -- and the run whose output matters most is the one
;; that was killed before it could finish.
(define (harness-say line)
  (if (not (harness-quiet?))
      (begin (display line) (newline) (adapter-flush-output))))

(define (harness-say-always line)
  (display line) (newline) (adapter-flush-output))

;; ---------------------------------------------------------------------------
;; Failure and error recording
;; ---------------------------------------------------------------------------

;; Emitted per failure rather than once per run, because a log is usually read
;; at the failure rather than from the top. The id and the artifact path are
;; quoted because a case name and a filesystem path may both contain spaces,
;; which would otherwise make a key=value line ambiguous to parse.
(define (harness-failure-context id)
  (string-append
   "httparse-harness: FAIL-CONTEXT id=\"" id "\""
   " test=" (let ((t (adapter-environment-variable "HTTPARSE_TEST_NAME")))
              (if t t "(unregistered)"))
   " backend=" (adapter-runtime-name)
   " mode=" (adapter-execution-mode)
   " os=" (adapter-os)
   " architecture=" (adapter-architecture)
   " runtime-version=" (adapter-runtime-version)
   " machine-type=" (adapter-machine-type)
   " artifacts=\"" (let ((d (adapter-environment-variable "HTTPARSE_TEST_TMPDIR")))
                     (if d d "(none)"))
   "\""))

(define (harness-record-failure! what detail)
  (set! harness-failure-count (+ harness-failure-count 1))
  (set! harness-current-case-failed #t)
  (let ((id (if harness-current-case harness-current-case "(no case)")))
    (set! harness-failures (cons (list id what detail) harness-failures))
    (harness-say (string-append "httparse-harness: FAIL " id ": " what
                                (if (string=? detail "")
                                    ""
                                    (string-append " -- " detail))))
    (harness-say (harness-failure-context id))))

(define (harness-record-error! detail)
  (set! harness-error-count (+ harness-error-count 1))
  (harness-say (string-append "httparse-harness: HARNESS-ERROR " detail)))

;; ---------------------------------------------------------------------------
;; Assertions
;; ---------------------------------------------------------------------------

(define (harness-count-check!)
  (set! harness-check-count (+ harness-check-count 1)))

(define (check what value)
  (harness-count-check!)
  (if value
      #t
      (begin (harness-record-failure! what "expected a true value") #f)))

(define (check-equal what actual expected)
  (harness-count-check!)
  (if (equal? actual expected)
      #t
      (begin
        (harness-record-failure!
         what
         (string-append "expected " (adapter-value->string expected)
                        ", got " (adapter-value->string actual)))
        #f)))

(define (check-not-equal what actual unexpected)
  (harness-count-check!)
  (if (equal? actual unexpected)
      (begin
        (harness-record-failure!
         what
         (string-append "expected any value other than "
                        (adapter-value->string unexpected)))
        #f)
      #t))

(define (check-fail what detail)
  (harness-count-check!)
  (harness-record-failure! what detail)
  #f)

;; Run `thunk`; the check passes only when it raises an object satisfying
;; `predicate`. Returning normally is a failure, and so is raising the wrong
;; thing -- an expected error may match only its declared category.
(define (check-raises what predicate thunk)
  (harness-count-check!)
  (let ((outcome (guard (e (#t (list 'raised e)))
                   (list 'returned (thunk)))))
    (cond
      ((eq? (car outcome) 'returned)
       (harness-record-failure!
        what
        (string-append "expected a raise, but the thunk returned "
                       (adapter-value->string (car (cdr outcome)))))
       #f)
      ((predicate (car (cdr outcome))) #t)
      (else
       (harness-record-failure!
        what
        (string-append "raised object did not satisfy the predicate: "
                       (adapter-describe-condition (car (cdr outcome)))))
       #f))))

;; Run `body`, then always run `cleanup`. A failure inside cleanup is reported
;; separately and never replaces the original failure, which is re-raised
;; unchanged: the first condition is the one that explains the defect.
(define (with-cleanup body cleanup)
  (let ((outcome (guard (e (#t (list 'raised e)))
                   (list 'value (body)))))
    (let ((cleanup-outcome (guard (e (#t (list 'raised e)))
                             (list 'value (cleanup)))))
      (if (eq? (car cleanup-outcome) 'raised)
          (begin
            (set! harness-cleanup-failure-count
                  (+ harness-cleanup-failure-count 1))
            (harness-record-failure!
             "cleanup raised"
             (adapter-describe-condition (car (cdr cleanup-outcome)))))))
    (if (eq? (car outcome) 'raised)
        (raise (car (cdr outcome)))
        (car (cdr outcome)))))

;; ---------------------------------------------------------------------------
;; Groups and cases
;; ---------------------------------------------------------------------------

(define (harness-current-prefix)
  (if (null? harness-group-stack)
      ""
      (string-append (harness-join (reverse harness-group-stack) ".") ".")))

(define (harness-group name thunk)
  (set! harness-group-stack (cons name harness-group-stack))
  (let ((outcome (guard (e (#t (list 'raised e)))
                   (list 'value (thunk)))))
    (set! harness-group-stack (cdr harness-group-stack))
    (if (eq? (car outcome) 'raised)
        (raise (car (cdr outcome)))
        (car (cdr outcome)))))

(define (harness-selected? id)
  (if harness-filter
      (harness-string-contains? id harness-filter)
      #t))

;; Exported so the self-tests can exercise filtering without depending on the
;; process environment.
(define (harness-set-filter! value) (set! harness-filter value))

;; A raise inside a case is that case's failure, not the suite's death.
;; Otherwise the first broken case hides every case after it, and the log names
;; one defect where there may be five.
(define (harness-case name thunk)
  (let ((id (string-append (harness-current-prefix) name)))
    (cond
      ;; A duplicate id means one registration silently became unreachable:
      ;; coverage lost with no signal at all. That is a defect in the suite, not
      ;; a failing assertion, so it is an error and not a failure.
      ((harness-member? id harness-case-ids)
       (harness-record-error! (string-append "duplicate case id " id)))
      (else
       (set! harness-case-ids (cons id harness-case-ids))
       (if (not (harness-selected? id))
           (set! harness-skipped-count (+ harness-skipped-count 1))
           (begin
             (set! harness-case-count (+ harness-case-count 1))
             (set! harness-current-case id)
             (set! harness-current-case-failed #f)
             (let ((outcome (guard (e (#t (list 'raised e)))
                              (list 'value (thunk)))))
               (if (eq? (car outcome) 'raised)
                   (harness-record-failure!
                    "case raised"
                    (adapter-describe-condition (car (cdr outcome))))))
             (if harness-current-case-failed
                 (set! harness-failed-case-count (+ harness-failed-case-count 1))
                 (if harness-verbose
                     (harness-say (string-append "httparse-harness: pass " id))))
             (set! harness-current-case #f)))))))

;; ---------------------------------------------------------------------------
;; Probes
;; ---------------------------------------------------------------------------
;;
;; A probe runs a thunk against a fresh, isolated result state and returns what
;; happened, without disturbing the enclosing suite. This is how the runner
;; tests itself: a self-test needs to observe a *failing* check being recorded
;; without that failure counting against the run. Output is suppressed so an
;; expected failure cannot be mistaken for a real one in the log.

(define (harness-capture-state)
  (list harness-group-stack harness-case-ids harness-current-case
        harness-current-case-failed harness-case-count harness-failed-case-count
        harness-check-count harness-failure-count harness-error-count
        harness-skipped-count harness-cleanup-failure-count harness-failures
        harness-filter))

(define (harness-restore-state! s)
  (set! harness-group-stack (list-ref s 0))
  (set! harness-case-ids (list-ref s 1))
  (set! harness-current-case (list-ref s 2))
  (set! harness-current-case-failed (list-ref s 3))
  (set! harness-case-count (list-ref s 4))
  (set! harness-failed-case-count (list-ref s 5))
  (set! harness-check-count (list-ref s 6))
  (set! harness-failure-count (list-ref s 7))
  (set! harness-error-count (list-ref s 8))
  (set! harness-skipped-count (list-ref s 9))
  (set! harness-cleanup-failure-count (list-ref s 10))
  (set! harness-failures (list-ref s 11))
  (set! harness-filter (list-ref s 12)))

(define (harness-probe thunk)
  (let ((saved (harness-capture-state)))
    (harness-clear-state!)
    (set! harness-probe-depth (+ harness-probe-depth 1))
    (let ((raised (guard (e (#t #t)) (thunk) #f)))
      (let ((summary (list 'probe
                           harness-case-count
                           harness-failed-case-count
                           harness-check-count
                           harness-failure-count
                           harness-error-count
                           harness-skipped-count
                           harness-cleanup-failure-count
                           raised
                           (reverse harness-failures))))
        (set! harness-probe-depth (- harness-probe-depth 1))
        (harness-restore-state! saved)
        summary))))

(define (probe-cases p) (list-ref p 1))
(define (probe-failed-cases p) (list-ref p 2))
(define (probe-checks p) (list-ref p 3))
(define (probe-failures p) (list-ref p 4))
(define (probe-errors p) (list-ref p 5))
(define (probe-skipped p) (list-ref p 6))
(define (probe-cleanup-failures p) (list-ref p 7))
(define (probe-raised? p) (list-ref p 8))
(define (probe-failure-records p) (list-ref p 9))
(define (failure-record-id r) (list-ref r 0))
(define (failure-record-what r) (list-ref r 1))
(define (failure-record-detail r) (list-ref r 2))

;; ---------------------------------------------------------------------------
;; Suite lifecycle
;; ---------------------------------------------------------------------------

(define (harness-clear-state!)
  (set! harness-group-stack '())
  (set! harness-case-ids '())
  (set! harness-current-case #f)
  (set! harness-current-case-failed #f)
  (set! harness-case-count 0)
  (set! harness-failed-case-count 0)
  (set! harness-check-count 0)
  (set! harness-failure-count 0)
  (set! harness-error-count 0)
  (set! harness-skipped-count 0)
  (set! harness-cleanup-failure-count 0)
  (set! harness-failures '())
  (set! harness-filter #f))

(define (harness-banner)
  (harness-say-always
   (string-append "httparse-harness: suite=" harness-suite-name))
  (harness-say-always
   (string-append "httparse-harness: runtime=" (adapter-runtime-name)
                  " version=" (adapter-runtime-version)
                  " machine=" (adapter-machine-type)
                  " mode=" (adapter-execution-mode)
                  " os=" (adapter-os)
                  " architecture=" (adapter-architecture))))

;; ---------------------------------------------------------------------------
;; Provenance
;; ---------------------------------------------------------------------------
;;
;; A provenance failure ends the run there and then, rather than recording an
;; error and continuing. Recording is not enough, for the reason status 3
;; exists at all: a program that goes on to hang satisfies a timeout
;; expectation whether or not an error was recorded first, so a
;; recorded-and-continued failure is invisible to every lane whose expected
;; outcome does not depend on reaching the summary. Beyond that, continuing is
;; pointless -- a run that cannot show it is executing the intended text says
;; nothing meaningful afterwards.

(define (harness-provenance-failure! detail)
  (harness-say-always
   (string-append "httparse-harness: PROVENANCE-ERROR " detail))
  (harness-say-always
   (string-append
    "httparse-harness: summary suite=" harness-suite-name
    " runtime=" (adapter-runtime-name)
    " mode=" (adapter-execution-mode)
    " os=" (adapter-os)
    " architecture=" (adapter-architecture)
    " cases=0 status=" (number->string harness-status-provenance)))
  (adapter-flush-output)
  (adapter-exit harness-status-provenance))

;; A source named in the manifest that cannot be read is a provenance failure,
;; not an I/O accident to propagate. Without this the raise escapes the runner
;; and takes the process out through a status outside this file's four-value
;; vocabulary, with no summary line and a message about a file handle -- which
;; the exact-status helper would then report as an out-of-vocabulary status, a
;; true statement about the wrong thing.
(define (harness-fingerprint-file-checked path)
  (let ((h (guard (e (#t #f)) (harness-fingerprint-file path))))
    (if h
        h
        (harness-provenance-failure!
         (string-append
          "cannot read " path
          ", which this run is supposed to have executed. The build tree is "
          "incomplete; build before running the tests.")))))

;; Returns the expected value as a string, or #f. #f covers both an unset
;; variable and a build that never produced the file; harness-provenance-
;; diagnosis reports either as "no expectation was supplied", since from the
;; run's side they are the same condition.
(define (harness-expected-fingerprint)
  (let ((path (adapter-environment-variable "HTTPARSE_EXPECT_FINGERPRINT_FILE")))
    (if (or (not path) (string=? path ""))
        #f
        (let ((bytes (guard (e (#t #f)) (adapter-file-bytes path))))
          (if bytes (harness-bytes->string bytes) #f)))))

;; Fingerprint each manifest entry, report the values, then check the combined
;; one. Printing alone would not be a check: a digest nothing reads is a claim.
;;
;; AN ABSENT MANIFEST IS NOT A FAILURE
;;
;; An unset or empty HTTPARSE_FINGERPRINT_FILES means this process was not
;; started by a lane registration, and the only things that start a harness
;; program any other way are a developer running one by hand and the Scheme
;; mutation suite. The second is not optional: httparse_mutation_run
;; requires every spec to exit 0 unmutated on the staged tree, and it runs its
;; verify commands with no environment at all, so refusing here would fail
;; every one of the mutation suite's baselines before a single mutation ran.
;;
;; Nothing is lost by skipping. SOURCES is a required argument of
;; httparse_add_scheme_lane, so a registered lane always has a manifest and
;; there is no reachable path by which a real lane silently loses provenance.
;; The guarantee lives at configure time, where it cannot be forged; a run-time
;; refusal would add only a rule this repository's own tooling cannot satisfy.
(define (harness-verify-provenance!)
  (set! harness-provenance-checked #t)
  (let ((raw (adapter-environment-variable "HTTPARSE_FINGERPRINT_FILES")))
    (if (or (not raw) (string=? raw ""))
        #t
        (let loop ((rest (harness-split raw #\|)) (acc '()))
          (if (null? rest)
              (let ((combined (harness-fingerprint->string
                               (harness-fingerprint-combine (reverse acc)))))
                (harness-say-always
                 (string-append "httparse-harness: fingerprint combined="
                                combined))
                (let ((d (harness-provenance-diagnosis
                          (harness-expected-fingerprint) combined)))
                  (if d
                      (harness-provenance-failure! d)
                      (harness-say-always
                       "httparse-harness: fingerprint verified against the build manifest"))))
              (let ((h (harness-fingerprint-file-checked (car rest))))
                (harness-say-always
                 (string-append "httparse-harness: fingerprint "
                                (car rest) "="
                                (harness-fingerprint->string h)))
                (loop (cdr rest) (cons h acc))))))))

(define (harness-begin suite-name)
  (set! harness-suite-name suite-name)
  ;; Before anything else a suite might report. A run that cannot show it
  ;; executed the intended text must not first print a banner implying it did.
  (harness-verify-provenance!)
  (harness-clear-state!)
  (set! harness-filter
        (harness-normalize-filter
         (adapter-environment-variable "HTTPARSE_TEST_FILTER")))
  ;; An empty value means unset, matching adapter-execution-mode: the same
  ;; variable emptied by a shell (HTTPARSE_TEST_VERBOSE=) must not mean
  ;; opposite things in the same harness.
  (let ((v (adapter-environment-variable "HTTPARSE_TEST_VERBOSE")))
    (set! harness-verbose (if (and v (not (string=? v ""))) #t #f)))
  (harness-banner))

;; CTest refuses an empty selection with execution.noTestsAction, and a suite
;; that ran nothing must not report success one layer down either.
;;
;; Split into a pure rule and a reader of the live counters, per AGENTS.md's
;; functional core / imperative shell rule. The split is not ceremony here: the
;; rule's interesting states are "no cases ran" and "every case was filtered
;; out", and a suite in either state cannot assert anything about itself from
;; the inside. As a function of two numbers it is directly testable.
;;
;; The two are distinguished because they are different bugs: a filter that
;; matched nothing is usually a typo in the invocation, while a suite with no
;; cases at all is usually a program that failed to load what it meant to.
(define (harness-empty-selection-diagnosis case-count skipped-count)
  (cond
    ((> case-count 0) #f)
    ((> skipped-count 0)
     (string-append "no case was selected: the filter skipped all "
                    (number->string skipped-count)
                    " registered cases"))
    (else "the suite registered no cases")))

(define (harness-empty-selection-error)
  (harness-empty-selection-diagnosis harness-case-count harness-skipped-count))

(define (harness-exit-status)
  (cond (harness-provenance-unreached harness-status-provenance)
        ((> harness-error-count 0) harness-status-harness-error)
        ((> harness-failure-count 0) harness-status-failed)
        (else harness-status-pass)))

(define (harness-summary)
  (let ((empty (harness-empty-selection-error)))
    (if empty (harness-record-error! empty)))
  (let ((unreached (harness-provenance-reachability-diagnosis
                    (adapter-environment-variable "HTTPARSE_FINGERPRINT_FILES")
                    harness-provenance-checked)))
    (if unreached
        (begin
          (set! harness-provenance-unreached #t)
          (harness-say-always
           (string-append "httparse-harness: PROVENANCE-ERROR " unreached)))))
  (let ((status (harness-exit-status)))
    (harness-say-always
     (string-append
      "httparse-harness: summary suite=" harness-suite-name
      " runtime=" (adapter-runtime-name)
      " mode=" (adapter-execution-mode)
      " cases=" (number->string harness-case-count)
      " failed-cases=" (number->string harness-failed-case-count)
      " checks=" (number->string harness-check-count)
      " failures=" (number->string harness-failure-count)
      " cleanup-failures=" (number->string harness-cleanup-failure-count)
      " skipped=" (number->string harness-skipped-count)
      " errors=" (number->string harness-error-count)
      " status=" (number->string status)))
    (adapter-flush-output)
    status))

;; Print the summary and exit with the status it reports.
(define (harness-finish)
  (adapter-exit (harness-summary)))
)
