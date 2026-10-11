;;; The runner's self-tests, as a program.

(import (rnrs) (httparse test harness))

(harness-begin "harness.self")

;;; Self-tests for the httparse private test runner. Plain R6RS.
;;;
;;; Every deliberate failure below runs inside harness-probe, which gives it a
;;; fresh isolated result state and suppresses its output. Without that, a
;;; self-test that proves failures are recorded would itself fail the run, and
;;; the log would teach readers to ignore FAIL lines.
;;;
;;; Every exported adapter name is referenced here, so a name missing from the
;;; adapter's export list is a load failure, not a silent gap.

;; Construct a bytevector from a length and a list of byte values, by hand
;; rather than through u8-list->bytevector. Under R6RS the two do the same
;; job; this form is kept because nothing depends on changing it, not because
;; anything forbids the alternative.
(define (harness-bytes length bytes)
  (let ((bv (make-bytevector length 0)))
    (let loop ((i 0) (rest bytes))
      (if (null? rest)
          bv
          (begin (bytevector-u8-set! bv i (car rest))
                 (loop (+ i 1) (cdr rest)))))))

(harness-group "assertions"
  (lambda ()

    (harness-case "check counts and passes a true value"
      (lambda ()
        (let ((p (harness-probe (lambda () (check "t" #t)))))
          (check-equal "one check counted" (probe-checks p) 1)
          (check-equal "no failure recorded" (probe-failures p) 0))))

    (harness-case "check records a failure for a false value"
      (lambda ()
        (let ((p (harness-probe (lambda () (check "f" #f)))))
          (check-equal "one check counted" (probe-checks p) 1)
          (check-equal "one failure recorded" (probe-failures p) 1))))

    (harness-case "check-equal compares with equal?"
      (lambda ()
        (let ((p (harness-probe
                  (lambda ()
                    (check-equal "lists" (list 1 2) (list 1 2))
                    (check-equal "strings" "a" "a")))))
          (check-equal "structural equality passes" (probe-failures p) 0))
        (let ((p (harness-probe (lambda () (check-equal "differ" 1 2)))))
          (check-equal "a difference fails" (probe-failures p) 1)
          (check-equal "still counted as a check" (probe-checks p) 1))))

    (harness-case "check-equal reports both values"
      (lambda ()
        (let* ((p (harness-probe (lambda () (check-equal "differ" 1 2))))
               (records (probe-failure-records p))
               (detail (failure-record-detail (car records))))
          (check "the expected value appears" (harness-string-contains? detail "2"))
          (check "the actual value appears" (harness-string-contains? detail "1"))
          (check-equal "the label is kept" (failure-record-what (car records)) "differ"))))

    ;; The five assertion procedures are documented as returning a boolean,
    ;; and nothing above reads one -- every probe above is inspected only
    ;; through its summary. A check-equal mutated to always return #f (or
    ;; always #t) would still fail (or pass) exactly the right cases and
    ;; leave every assertion above green. This is the one case that actually
    ;; looks at what the call handed back.
    (harness-case "check-equal returns a boolean for pass and fail"
      (lambda ()
        (check "a passing comparison returns #t"
               (check-equal "return true" 1 1))
        (let ((returned 'not-yet-run))
          (harness-probe
           (lambda ()
             (set! returned (check-equal "return false" 1 2))))
          (check-equal "a failing comparison returns #f" returned #f))))

    (harness-case "check-not-equal is the inverse"
      (lambda ()
        (let ((p (harness-probe (lambda () (check-not-equal "differ" 1 2)))))
          (check-equal "different values pass" (probe-failures p) 0)
          (check-equal "counted as a check" (probe-checks p) 1))
        (let ((p (harness-probe (lambda () (check-not-equal "same" 1 1)))))
          (check-equal "equal values fail" (probe-failures p) 1))))

    (harness-case "check-fail always fails and counts as a check"
      (lambda ()
        (let ((p (harness-probe (lambda () (check-fail "unreachable" "why")))))
          (check-equal "counted" (probe-checks p) 1)
          (check-equal "failed" (probe-failures p) 1))))

    (harness-case "check-raises passes only on a matching raise"
      (lambda ()
        (let ((p (harness-probe
                  (lambda ()
                    (check-raises "raises a symbol"
                                  (lambda (e) (eq? e 'boom))
                                  (lambda () (raise 'boom)))))))
          (check-equal "a matching raise passes" (probe-failures p) 0)
          (check-equal "counted as a check" (probe-checks p) 1))
        (let ((p (harness-probe
                  (lambda ()
                    (check-raises "returns instead"
                                  (lambda (e) #t)
                                  (lambda () 'no-raise))))))
          (check-equal "returning normally fails" (probe-failures p) 1))
        (let ((p (harness-probe
                  (lambda ()
                    (check-raises "wrong object"
                                  (lambda (e) (eq? e 'expected))
                                  (lambda () (raise 'other)))))))
          (check-equal "the wrong raise fails" (probe-failures p) 1))))))

(harness-group "cases"
  (lambda ()

    (harness-case "a raise inside a case is that case's failure"
      (lambda ()
        (let ((p (harness-probe
                  (lambda ()
                    (harness-case "raiser" (lambda () (raise 'boom)))
                    (harness-case "later" (lambda () (check "still runs" #t)))))))
          (check-equal "both cases ran" (probe-cases p) 2)
          (check-equal "one case failed" (probe-failed-cases p) 1)
          (check "the suite did not die" (not (probe-raised? p))))))

    (harness-case "a duplicate case id is an error, not a failure"
      (lambda ()
        (let ((p (harness-probe
                  (lambda ()
                    (harness-case "same" (lambda () (check "a" #t)))
                    (harness-case "same" (lambda () (check "b" #t)))))))
          (check-equal "the second registration did not run" (probe-cases p) 1)
          (check-equal "recorded as an error" (probe-errors p) 1)
          (check-equal "not recorded as a failure" (probe-failures p) 0))))

    (harness-case "a failing case is counted once however many checks fail"
      (lambda ()
        (let ((p (harness-probe
                  (lambda ()
                    (harness-case "two failures"
                      (lambda ()
                        (check "one" #f)
                        (check "two" #f)))))))
          (check-equal "two failures" (probe-failures p) 2)
          (check-equal "one failed case" (probe-failed-cases p) 1)
          ;; "one" and "two" differ only in which ran first: (car records) is
          ;; the same element whether or not harness-probe's `reverse` is
          ;; there unless order is actually checked against it.
          (check-equal "records come back oldest first"
                       (failure-record-what (car (probe-failure-records p)))
                       "one"))))

    (harness-case "groups prefix case ids"
      (lambda ()
        (let* ((p (harness-probe
                   (lambda ()
                     (harness-group "outer"
                       (lambda ()
                         (harness-group "inner"
                           (lambda ()
                             (harness-case "leaf" (lambda () (check "x" #f))))))))))
               (records (probe-failure-records p)))
          (check-equal "dotted from outermost in"
                       (failure-record-id (car records))
                       "outer.inner.leaf"))))

    (harness-case "a group unwinds its name when its body raises"
      (lambda ()
        (let ((p (harness-probe
                  (lambda ()
                    (guard (e (#t #t))
                      (harness-group "doomed" (lambda () (raise 'boom))))
                    (harness-case "after" (lambda () (check "x" #f)))))))
          (check-equal "the failed group left no prefix behind"
                       (failure-record-id (car (probe-failure-records p)))
                       "after"))))

    ;; A separate decision from the unwinding above, and not implied by it:
    ;; harness-group pops its name off the stack *before* it re-raises, so a
    ;; group that swallowed its body's condition outright would still leave no
    ;; prefix behind and still let "after" register at the top level. The case
    ;; above would pass unchanged -- its guard would simply never fire, which
    ;; nothing there can observe. Escaping is asserted here instead, by
    ;; recording which way harness-group returned rather than by catching the
    ;; raise and hoping the catch ran: a swallowed condition comes back as
    ;; 'returned and the comparison names the defect, where an unguarded (car
    ;; outcome) would only crash on a non-pair.
    (harness-case "a group re-raises its body's condition"
      (lambda ()
        (let ((outcome
               (guard (e (#t (list 'raised e)))
                 (list 'returned
                       (harness-group "doomed" (lambda () (raise 'boom)))))))
          (check-equal "the condition escaped the group"
                       (car outcome) 'raised)
          (check-equal "and it is the original condition, unchanged"
                       (car (cdr outcome)) 'boom))))))

(harness-group "cleanup"
  (lambda ()

    (harness-case "with-cleanup runs cleanup after a normal body"
      (lambda ()
        (let ((ran #f))
          (let ((value (with-cleanup (lambda () 'body)
                                     (lambda () (set! ran #t)))))
            (check-equal "the body's value is returned" value 'body)
            (check "cleanup ran" ran)))))

    (harness-case "with-cleanup runs cleanup after a raise and re-raises"
      (lambda ()
        (let ((ran #f))
          (let ((outcome (guard (e (#t (list 'raised e)))
                           (with-cleanup (lambda () (raise 'boom))
                                         (lambda () (set! ran #t))))))
            (check "cleanup ran" ran)
            (check "the original condition survives"
                   (and (eq? (car outcome) 'raised)
                        (eq? (car (cdr outcome)) 'boom)))))))

    (harness-case "a raising cleanup is recorded separately"
      (lambda ()
        (let ((p (harness-probe
                  (lambda ()
                    (harness-case "c"
                      (lambda ()
                        (with-cleanup (lambda () 'body)
                                      (lambda () (raise 'cleanup-boom)))))))))
          (check-equal "counted as a cleanup failure"
                       (probe-cleanup-failures p) 1)
          ;; harness-cleanup-failure-count is a side channel. What actually
          ;; fails the enclosing case -- the FAIL line, the FAIL-CONTEXT line,
          ;; and exit status 1 -- is with-cleanup also calling
          ;; harness-record-failure!, which neither counter proves by itself.
          (check-equal "also recorded as an ordinary failure"
                       (probe-failures p) 1)
          (check-equal "the enclosing case is marked failed"
                       (probe-failed-cases p) 1))))))

(harness-group "probe"
  (lambda ()

    ;; harness-restore-state! puts back thirteen fields; harness-counters
    ;; (used below for the bootstrap's own benefit) only observes three of
    ;; them. Comparing the full captured state closes that gap. The probed
    ;; thunk deliberately fails three cases, skips three cases, raises
    ;; inside two cleanups, and re-registers an already-used id three more
    ;; times -- an error, not a failure, per "a duplicate case id is an
    ;; error, not a failure" above -- and the ambient filter is set to a
    ;; real value beforehand, so that every field harness-clear-state!
    ;; would otherwise reset to the same default it already has ends up
    ;; somewhere else instead. Three-or-more is deliberate, not decorative:
    ;; every other probe in this file registers at most two inner cases or
    ;; one duplicate id, so a leaked, unrestored count from any of them
    ;; cannot coincidentally match this probe's own total the way a
    ;; smaller, more "natural" count could. The duplicates reuse
    ;; "inside-failing-1" instead of a fresh id so that only
    ;; harness-error-count moves: the duplicate branch of harness-case
    ;; never runs the thunk it is given and never touches harness-case-ids,
    ;; so case-count and check-count are exactly as they were already.
    (harness-case "a probe leaves the enclosing state untouched"
      (lambda ()
        (harness-set-filter! "ambient-marker")
        (with-cleanup
         (lambda ()
           (let ((before (harness-capture-state)))
             (harness-probe
              (lambda ()
                (harness-case "inside-failing-1" (lambda () (check "a" #f)))
                (harness-case "inside-failing-2" (lambda () (check "b" #f)))
                (harness-case "inside-failing-3" (lambda () (check "c" #f)))
                (harness-case "inside-passing" (lambda () (check "d" #t)))
                (harness-set-filter! "keep-only")
                (harness-case "keep-only" (lambda () (check "e" #t)))
                (harness-case "dropped-1" (lambda () (check "f" #t)))
                (harness-case "dropped-2" (lambda () (check "g" #t)))
                (harness-case "dropped-3" (lambda () (check "h" #t)))
                (harness-case "inside-failing-1" (lambda () (check "unreachable" #t)))
                (harness-case "inside-failing-1" (lambda () (check "unreachable" #t)))
                (harness-case "inside-failing-1" (lambda () (check "unreachable" #t)))
                (with-cleanup (lambda () 'body) (lambda () (raise 'cleanup-boom-1)))
                (with-cleanup (lambda () 'body) (lambda () (raise 'cleanup-boom-2)))))
             (check-equal "the enclosing state is unchanged"
                          (harness-capture-state) before)))
         (lambda () (harness-set-filter! #f)))))

    (harness-case "a probe reports whether its thunk raised"
      (lambda ()
        (check "a raising thunk is reported"
               (probe-raised? (harness-probe (lambda () (raise 'boom)))))
        (check "a normal thunk is not"
               (not (probe-raised? (harness-probe (lambda () 'fine)))))))

    ;; Unprotected, this would be exactly the silent-under-run risk this suite
    ;; exists to catch: if anything between setting the filter and resetting
    ;; it raised, "no-such-case" would stay the ambient filter for the rest of
    ;; the run, silently skipping every later case while the run still exited
    ;; 0. Restoration of the ambient filter across a probe boundary is
    ;; asserted separately, by "a probe leaves the enclosing state untouched";
    ;; this reset is a different concern -- not leaking this case's own
    ;; fixture filter into the rest of the suite -- so it stays, but guarded.
    (harness-case "a probe clears the ambient filter"
      (lambda ()
        (harness-set-filter! "no-such-case")
        (with-cleanup
         (lambda ()
           (let ((p (harness-probe
                     (lambda () (harness-case "inner" (lambda () (check "x" #t)))))))
             (check-equal "the inner case was not skipped" (probe-cases p) 1)))
         (lambda () (harness-set-filter! #f)))))))

(harness-group "filtering"
  (lambda ()

    (harness-case "a filter selects by substring and counts the rest as skipped"
      (lambda ()
        (let ((p (harness-probe
                  (lambda ()
                    (harness-set-filter! "keep")
                    (harness-case "keep-me" (lambda () (check "x" #t)))
                    (harness-case "drop-me" (lambda () (check "y" #t)))
                    ;; A filtered-out case still reserves its id before the
                    ;; selection check runs, so registering "drop-me" again is
                    ;; a harness error even though the first registration
                    ;; never ran its body.
                    (harness-case "drop-me" (lambda () (check "z" #t)))))))
          (check-equal "one selected" (probe-cases p) 1)
          (check-equal "one skipped" (probe-skipped p) 1)
          (check-equal "a filtered-out duplicate is still an error"
                       (probe-errors p) 1))))

    ;; harness-begin's HTTPARSE_TEST_FILTER handling is exercised
    ;; end-to-end by the empty-selection lane, but only for a non-empty value.
    ;; The empty-string branch has no observable effect on selection to check
    ;; instead -- harness-string-contains? treats an empty needle as matching
    ;; every id, so an empty filter and a normalised-away one select
    ;; identically either way -- so the normalisation rule is checked directly
    ;; here, on the pure function, rather than through a selection outcome.
    (harness-case "the environment filter is normalised"
      (lambda ()
        (check-equal "an empty string means no filter"
                     (harness-normalize-filter "") #f)
        (check-equal "an absent variable means no filter"
                     (harness-normalize-filter #f) #f)
        (check-equal "a real value passes through unchanged"
                     (harness-normalize-filter "keep") "keep")))))

(harness-group "adapter"
  (lambda ()

    (harness-case "the adapter reports this runtime"
      (lambda ()
        (check "the runtime names itself"
               (string=? (adapter-runtime-name) "chez"))
        (check "the version is bare and non-empty"
               (and (> (string-length (adapter-runtime-version)) 0)
                    (not (harness-string-contains? (adapter-runtime-version) "v"))))
        (check "the machine type is reported"
               (> (string-length (adapter-machine-type)) 0))
        (let ((expect-os (adapter-environment-variable "HTTPARSE_EXPECT_OS"))
              (expect-arch (adapter-environment-variable "HTTPARSE_EXPECT_ARCH")))
          (if (and expect-os (> (string-length expect-os) 0))
              (check-equal "the live os matches the cell" (adapter-os) expect-os)
              (check-not-equal "the os is identified" (adapter-os) "unknown"))
          (if (and expect-arch (> (string-length expect-arch) 0))
              (check-equal "the live architecture matches the cell"
                           (adapter-architecture) expect-arch)
              (check-not-equal "the architecture is identified"
                               (adapter-architecture) "unknown")))
        ;; The vocabulary, not a fixed mode. This program runs under more
        ;; than one lane, so an equality against any single mode
        ;; would be false on some lane that is behaving correctly. The narrower
        ;; claim -- that this lane really is the mode it declares -- is not
        ;; made here: this same program is also staged and run under the Scheme
        ;; mutation suite, inside
        ;; httparse.harness.scheme-mutation.cmake.direct, whose
        ;; registration hand-sets HTTPARSE_EXECUTION_MODE=source no matter
        ;; what it stages (its registration in test/CMakeLists.txt). A
        ;; name-versus-mode check here would be red on every baseline, not only
        ;; a broken one. The claim is carried instead by the lane's structure
        ;; (an aot lane cannot expand source) and proved by MutationSuite.cmake's
        ;; "execution mode is the literal source again" mutation, against the
        ;; registration's own mapping.
        (check "the mode is one the lane vocabulary defines"
               (harness-member? (adapter-execution-mode)
                                (list "source" "aot")))))

    (harness-case "machine types map to the expected os and architecture"
      (lambda ()
        (check-equal "tarm64osx arch" (adapter-machine-type->architecture "tarm64osx") "arm64")
        (check-equal "tarm64osx os"   (adapter-machine-type->os "tarm64osx") "darwin")
        (check-equal "ta6le arch"     (adapter-machine-type->architecture "ta6le") "amd64")
        (check-equal "ta6le os"       (adapter-machine-type->os "ta6le") "linux")
        (check-equal "tarm64le arch"  (adapter-machine-type->architecture "tarm64le") "arm64")
        (check-equal "tarm64le os"    (adapter-machine-type->os "tarm64le") "linux")
        (check-equal "ta6nt arch"     (adapter-machine-type->architecture "ta6nt") "amd64")
        (check-equal "ta6nt os"       (adapter-machine-type->os "ta6nt") "windows")
        (check-equal "unmapped arch"  (adapter-machine-type->architecture "zz99xx") "unknown")
        (check-equal "unmapped os"    (adapter-machine-type->os "zz99xx") "unknown")))

    ;; adapter-exit ends the process, so no assertion may call it. Naming it is
    ;; still load-bearing: a missing export is a load failure only because this
    ;; program references every adapter name. adapter-exit's only other uses
    ;; are inside the runner section of harness.sls, so they resolve whatever
    ;; the export list says; without this case, dropping it from the export
    ;; list would leave this program loading and passing.
    (harness-case "the adapter can end the process"
      (lambda ()
        (check "adapter-exit is reachable" (procedure? adapter-exit))))

    (harness-case "the adapter reaches the process environment"
      (lambda ()
        (check "the registration's test name is visible"
               (adapter-environment-variable "HTTPARSE_TEST_NAME"))
        (check "an unset variable reads as false"
               (not (adapter-environment-variable "HTTPARSE_NOT_SET_ANYWHERE")))))

    (harness-case "the adapter renders values and conditions"
      (lambda ()
        (check-equal "a list writes readably"
                     (adapter-value->string (list 1 2)) "(1 2)")
        (check-equal "a string writes with its quotes"
                     (adapter-value->string "a") "\"a\"")
        (let ((text (adapter-describe-condition (guard (e (#t e)) (car '())))))
          (check "a condition describes non-empty" (> (string-length text) 0))
          ;; Single-line, because it is appended to a one-line FAIL record.
          (check "on one line" (not (harness-string-contains? text "\n"))))))

    (harness-case "the shared subset's arithmetic is reachable"
      (lambda ()
        (check-equal "quotient" (quotient 7 2) 3)
        (check-equal "remainder" (remainder 7 2) 1)
        (check-equal "modulo" (modulo -7 2) 1)))

    ;; A literal #t can never fail, so the old case only "passed" because a
    ;; raise would have unwound past the check entirely, not because the
    ;; check evaluated anything. Wrapping the flush in a probe makes the
    ;; assertion depend on what adapter-flush-output actually does.
    (harness-case "output can be flushed"
      (lambda ()
        (let ((p (harness-probe (lambda () (adapter-flush-output)))))
          (check "flushing does not raise" (not (probe-raised? p))))))

    (harness-case "the status vocabulary is what the build expects"
      (lambda ()
        (check-equal "pass" harness-status-pass 0)
        (check-equal "failed" harness-status-failed 1)
        (check-equal "harness error" harness-status-harness-error 2)
        (check-equal "provenance, reserved" harness-status-provenance 3)))

    (harness-case "exit status follows error over failure"
      (lambda ()
        (let ((p (harness-probe
                  (lambda ()
                    (harness-case "d" (lambda () (check "x" #f)))
                    (harness-case "d" (lambda () (check "y" #t)))))))
          (check-equal "a failure was recorded" (probe-failures p) 1)
          (check-equal "an error was recorded" (probe-errors p) 1))
        ;; The precedence itself, read from the live accessor rather than
        ;; inferred: a harness error outranks a failure because a suite that
        ;; mis-registered cannot be trusted about what it did run.
        (let ((p (harness-probe
                  (lambda ()
                    (harness-case "e" (lambda () (check "x" #f)))
                    (check-equal "failure alone yields 1" (harness-exit-status) 1)
                    (harness-case "f" (lambda () (check "y" #t)))
                    (harness-case "f" (lambda () (check "z" #t)))
                    (check-equal "an error outranks it" (harness-exit-status) 2)))))
          (check-equal "the inner assertions held" (probe-failures p) 1))))))

(harness-group "empty selection"
  (lambda ()

    (harness-case "an empty selection is diagnosed from the counts"
      (lambda ()
        (check "a run that executed cases is fine"
               (not (harness-empty-selection-diagnosis 3 0)))
        ;; case-count=1 is exactly where (> case-count 0) flips from #f to
        ;; #t; 3 sits well clear of that boundary and cannot tell the real
        ;; predicate apart from a mutant such as (> case-count 1), which
        ;; agrees with it everywhere except at 1.
        (check "a single case is also fine, at the case-count boundary"
               (not (harness-empty-selection-diagnosis 1 0)))
        ;; (string? ...) is satisfied by any diagnosis text, including the
        ;; filter-skipped wording a mutant would produce here if
        ;; (> skipped-count 0) were loosened to (>= skipped-count 0) --
        ;; skipped-count=0 is that predicate's own boundary. Pin the exact
        ;; wording so that mutant is forced to disagree.
        (check-equal "no cases at all says exactly that"
                     (harness-empty-selection-diagnosis 0 0)
                     "the suite registered no cases")
        (check "a fully filtered run says the filter did it"
               (harness-string-contains?
                (harness-empty-selection-diagnosis 0 4) "filter"))
        (check "and says how many it skipped"
               (harness-string-contains?
                (harness-empty-selection-diagnosis 0 4) "4"))
        ;; The two empty states must not report the same thing: one is a typo in
        ;; the invocation, the other a program that failed to load.
        (check-not-equal "the two empty states read differently"
                         (harness-empty-selection-diagnosis 0 0)
                         (harness-empty-selection-diagnosis 0 4))))))

;; --- the content fingerprint ------------------------------------------------
;;
;; Every value below was measured on Chez 10.4.1. They are
;; literals rather than recomputations because a test that recomputes the
;; thing under test with the thing under test asserts only that it is
;; deterministic.

(harness-group "fingerprint"
  (lambda ()

    (harness-case "an empty bytevector folds to the seed"
      (lambda ()
        (check-equal "empty"
                     (harness-fingerprint->string
                      (harness-fingerprint-bytevector (harness-bytes 0 '())))
                     "3435eab979e3e0")))

    (harness-case "three ASCII bytes"
      (lambda ()
        (check-equal "abc"
                     (harness-fingerprint->string
                      (harness-fingerprint-bytevector (harness-bytes 3 '(97 98 99))))
                     "60b8174578c282d")))

    ;; The +1 on each byte exists for exactly this: without it a leading NUL is
    ;; absorbed and these three values collapse into one.
    (harness-case "leading zero bytes are significant"
      (lambda ()
        (let ((abc (harness-fingerprint->string
                    (harness-fingerprint-bytevector (harness-bytes 3 '(97 98 99)))))
              (one (harness-fingerprint->string
                    (harness-fingerprint-bytevector (harness-bytes 4 '(0 97 98 99)))))
              (two (harness-fingerprint->string
                    (harness-fingerprint-bytevector
                     (harness-bytes 5 '(0 0 97 98 99))))))
          (check-equal "one leading NUL" one "bac4261bdc123")
          (check-equal "two leading NULs" two "1b3297b7cc8f592c")
          (check-not-equal "one NUL differs from none" one abc)
          (check-not-equal "two NULs differ from one" two one))))

    (harness-case "combining is order sensitive"
      (lambda ()
        (check-equal "(1 2)"
                     (harness-fingerprint->string (harness-fingerprint-combine '(1 2)))
                     "3cabbf7defc450d")
        (check-equal "(2 1)"
                     (harness-fingerprint->string (harness-fingerprint-combine '(2 1)))
                     "3cabbf7df0b874f")))

    ;; Chez renders FF, not ff, for (number->string 255 16), so the rendering
    ;; cannot go through a radix conversion. This case is what notices if
    ;; someone ever changes it back.
    (harness-case "hex digits render lowercase"
      (lambda ()
        (check-equal "255" (harness-fingerprint->string 255) "ff")
        (check-equal "3735928559" (harness-fingerprint->string 3735928559) "deadbeef")
        (check-equal "zero" (harness-fingerprint->string 0) "0")))

    ;; adapter-file-bytes is called directly here, not only through
    ;; harness-fingerprint-file. A name used only inside harness.sls's own
    ;; runner section resolves internally regardless of the export list, so
    ;; testing it only indirectly would make its export-list mutation
    ;; undetectable.
    (harness-case "a file is read as its exact bytes"
      (lambda ()
        (let ((bv (adapter-file-bytes
                   (adapter-environment-variable "HTTPARSE_FINGERPRINT_SAMPLE"))))
          (check-equal "length" (bytevector-length bv) 14)
          (check-equal "first byte is c" (bytevector-u8-ref bv 0) 99)
          (check-equal "last byte is LF" (bytevector-u8-ref bv 13) 10))))

    (harness-case "harness-fingerprint-file matches the sample's recorded fingerprint"
      (lambda ()
        (check-equal "sample"
                     (harness-fingerprint->string
                      (harness-fingerprint-file
                       (adapter-environment-variable "HTTPARSE_FINGERPRINT_SAMPLE")))
                     "1f2902297117b4a3")))))

;; --- provenance, as a decision -----------------------------------------------
;;
;; The shell around this exits the process, so nothing inside a suite can
;; observe it. The rule itself is two values in and a diagnostic or #f out, and
;; that part is checkable here.

(harness-group "provenance"
  (lambda ()

    (harness-case "agreement is not a diagnosis"
      (lambda ()
        (check "identical values agree"
               (not (harness-provenance-diagnosis "abc123" "abc123")))))

    (harness-case "a mismatch names both values"
      (lambda ()
        (let ((d (harness-provenance-diagnosis "abc123" "def456")))
          (check "there is a diagnosis" (if d #t #f))
          (check "it names the expectation" (harness-string-contains? d "abc123"))
          (check "it names what was computed" (harness-string-contains? d "def456")))))

    (harness-case "a missing expectation is its own diagnosis"
      (lambda ()
        (let ((d (harness-provenance-diagnosis #f "abc123")))
          (check "there is a diagnosis" (if d #t #f))
          (check "it does not claim a mismatch"
                 (not (harness-string-contains? d "mismatch"))))))

    ;; Whitespace is trimmed at the ends only. A reader that also collapsed
    ;; interior space would make "dead beef" compare equal to "deadbeef", which
    ;; is the sort of leniency that turns a corrupted expectation into a passing
    ;; comparison.
    (harness-case "the expectation file's outer whitespace is trimmed"
      (lambda ()
        (check-equal "trailing newline"
                     (harness-bytes->string (harness-bytes 4 '(97 98 99 10)))
                     "abc")
        (check-equal "leading and trailing spaces"
                     (harness-bytes->string (harness-bytes 5 '(32 97 98 99 32)))
                     "abc")
        (check-equal "empty" (harness-bytes->string (harness-bytes 0 '())) "")
        (check-equal "interior space is kept"
                     (harness-bytes->string (harness-bytes 7 '(100 101 97 100 32 98 102)))
                     "dead bf")
        ;; All-whitespace input is the only way to reach the scan's base case
        ;; after consuming bytes rather than trivially. An off-by-one in the
        ;; termination logic would either read past the end or loop forever here.
        ;; This case also carries the only tab and carriage-return bytes tested.
        (check-equal "all whitespace, including tab and carriage return"
                     (harness-bytes->string (harness-bytes 4 '(32 9 10 13)))
                     "")))

    (harness-case "a manifest nothing verified is a defect"
      (lambda ()
        (let ((d (harness-provenance-reachability-diagnosis "a.scm|b.scm" #f)))
          (check "there is a diagnosis" (if d #t #f))
          (check "it says the check was not reached"
                 (harness-string-contains? d "never reached")))))

    (harness-case "a manifest that was verified is not a defect"
      (lambda ()
        (check "verified"
               (not (harness-provenance-reachability-diagnosis "a.scm" #t)))))

    ;; An absent or empty manifest means no lane registration started this
    ;; process. Skipping is correct there, so neither may be reported as a
    ;; defect -- and both spellings must agree, for the reason
    ;; harness-normalize-filter gives about a shell that writes VAR= .
    (harness-case "no manifest is not a defect, however it is spelled"
      (lambda ()
        (check "absent" (not (harness-provenance-reachability-diagnosis #f #f)))
        (check "empty" (not (harness-provenance-reachability-diagnosis "" #f)))))))

(harness-finish)
