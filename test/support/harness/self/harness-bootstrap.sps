;;; The bootstrap body, as a program. Merged from its .chez.sps wrapper by
;;; the include collapse (upstream decision 0006).
;;;
;;; harness-begin is deliberately not called: the bootstrap judges the
;;; runner without using its suite lifecycle.

(import (rnrs) (httparse test harness))

;;; Bootstrap verification of the runner's primitives. Plain R6RS.
;;;
;;; The runner cannot be the only witness to its own correctness, so this
;;; program judges it with raw conditionals and its own counter. It uses no
;;; assertion, case, group, or summary facility from the runner; it calls the
;;; primitives under test and inspects what they return. It answers "does check
;;; actually check?" without using check to ask.
;;;
;;; It exits 1 on any failure and 0 otherwise, by hand, because harness-finish
;;; is one of the things it is not allowed to trust.

(define bootstrap-failures 0)

(define (bootstrap-assert name value)
  (if value
      (begin (display "bootstrap: ok   ") (display name) (newline))
      (begin
        (set! bootstrap-failures (+ bootstrap-failures 1))
        (display "bootstrap: FAIL ") (display name) (newline))))

;; The one runner facility this program uses before judging any of them. It is
;; here because the bootstrap does not call harness-begin -- the suite
;; lifecycle is among the things it is not allowed to trust -- and a provenance
;; check that lived only in harness-begin would leave these two lanes the only
;; ones in the tree running text nothing verified. It either returns or ends
;; the process, so it cannot report a false negative into the counter below.
(harness-verify-provenance!)

;; --- pure helpers ----------------------------------------------------------

(bootstrap-assert "contains: middle" (harness-string-contains? "abcdef" "cd"))
(bootstrap-assert "contains: prefix" (harness-string-contains? "abcdef" "abc"))
(bootstrap-assert "contains: suffix" (harness-string-contains? "abcdef" "def"))
(bootstrap-assert "contains: absent" (not (harness-string-contains? "abcdef" "z")))
(bootstrap-assert "contains: empty needle" (harness-string-contains? "abc" ""))
(bootstrap-assert "contains: needle longer than haystack"
                  (not (harness-string-contains? "ab" "abc")))

(bootstrap-assert "join: several" (string=? (harness-join '("a" "b" "c") ".") "a.b.c"))
(bootstrap-assert "join: one" (string=? (harness-join '("x") ".") "x"))
(bootstrap-assert "join: none" (string=? (harness-join '() ".") ""))

(bootstrap-assert "split: several"
                  (equal? (harness-split "a.b.c" #\.) '("a" "b" "c")))
(bootstrap-assert "split: no separator"
                  (equal? (harness-split "abc" #\.) '("abc")))
(bootstrap-assert "split: trailing separator keeps the empty field"
                  (equal? (harness-split "a." #\.) '("a" "")))

(bootstrap-assert "take: fewer than available"
                  (equal? (harness-take '(1 2 3 4) 2) '(1 2)))
(bootstrap-assert "take: all" (equal? (harness-take '(1 2) 2) '(1 2)))
(bootstrap-assert "take: none" (equal? (harness-take '(1 2) 0) '()))
(bootstrap-assert "take: more than available"
                  (equal? (harness-take '(1 2) 5) '(1 2)))

(bootstrap-assert "member: present" (harness-member? "b" '("a" "b")))
(bootstrap-assert "member: absent" (not (harness-member? "z" '("a" "b"))))
(bootstrap-assert "member: empty" (not (harness-member? "a" '())))

;; --- the assertion primitive ------------------------------------------------
;;
;; The point of this file. A `check` that always returned a true value would
;; make every test in every later milestone pass, and no test written with
;; `check` could notice.

(bootstrap-assert "check: a true value returns true" (eq? (check "true" #t) #t))
(bootstrap-assert "check: a non-#f value returns true" (eq? (check "zero" 0) #t))

;; A deliberately failing check must be observed without it counting against
;; anything. harness-probe would do this, but the probe is itself part of what
;; the bootstrap is not allowed to trust, so the counters are saved and restored
;; by hand. Asserting only the return value would pass even if
;; harness-restore-counters! silently did nothing, so this also proves the
;; counters moved while the failing check ran and landed back on the exact
;; saved values afterward.
(let* ((saved (harness-counters))
       (result (check "deliberate" #f))
       (moved (harness-counters)))
  (harness-restore-counters! saved)
  (bootstrap-assert "check: a false value returns false" (eq? result #f))
  ;; Per counter, not merely "something moved". A runner that had stopped
  ;; counting failures would still bump the check count and still set the case
  ;; flag, so a "the counters moved" assertion passes while the defect that
  ;; matters most is present: failures print, nothing counts them, and every
  ;; suite in every later milestone exits 0. Nothing written with `check` can
  ;; report that -- recording a failure is the mechanism that would be broken --
  ;; so this lane, which counts its own failures and exits by hand, is the only
  ;; witness there is. harness-counters is
  ;; (failure-count check-count current-case-failed).
  (bootstrap-assert "check: a deliberate failure counts one failure"
                    (= (list-ref moved 0) (+ (list-ref saved 0) 1)))
  (bootstrap-assert "check: a deliberate failure counts one check"
                    (= (list-ref moved 1) (+ (list-ref saved 1) 1)))
  (bootstrap-assert "check: a deliberate failure marks the case failed"
                    (list-ref moved 2))
  (bootstrap-assert "check: restore returns the counters to the saved values"
                    (equal? (harness-counters) saved)))

;; --- adapter protocol -------------------------------------------------------
;;
;; Every adapter procedure is called, so a name missing from the adapter's
;; export list is a load failure rather than a silent gap.

(bootstrap-assert "adapter: runtime name is chez"
                  (string=? (adapter-runtime-name) "chez"))
(bootstrap-assert "adapter: version is non-empty"
                  (> (string-length (adapter-runtime-version)) 0))
(bootstrap-assert "adapter: machine type is non-empty"
                  (> (string-length (adapter-machine-type)) 0))
(let ((expect-os (adapter-environment-variable "HTTPARSE_EXPECT_OS"))
      (expect-arch (adapter-environment-variable "HTTPARSE_EXPECT_ARCH")))
  (bootstrap-assert "adapter: os matches the cell or is at least known"
                    (if (and expect-os (> (string-length expect-os) 0))
                        (string=? (adapter-os) expect-os)
                        (not (string=? (adapter-os) "unknown"))))
  (bootstrap-assert "adapter: architecture matches the cell or is at least known"
                    (if (and expect-arch (> (string-length expect-arch) 0))
                        (string=? (adapter-architecture) expect-arch)
                        (not (string=? (adapter-architecture) "unknown")))))
(bootstrap-assert "adapter: execution mode is one the lane vocabulary defines"
                  (harness-member? (adapter-execution-mode)
                                   (list "source" "aot")))
(bootstrap-assert "adapter: an unset variable reads as false"
                  (not (adapter-environment-variable "HTTPARSE_NOT_SET_ANYWHERE")))
(bootstrap-assert "adapter: value->string writes readably"
                  (string=? (adapter-value->string (list 1 2)) "(1 2)"))
(bootstrap-assert "adapter: a condition describes as a non-empty single line"
                  (let ((text (adapter-describe-condition
                               (guard (e (#t e)) (car '())))))
                    (and (> (string-length text) 0)
                         (not (harness-string-contains? text "\n")))))
(bootstrap-assert "adapter: r5rs arithmetic is reachable"
                  (and (= (quotient 7 2) 3)
                       (= (remainder 7 2) 1)
                       (= (modulo -7 2) 1)))

(adapter-flush-output)

(display "bootstrap: failures=")
(display bootstrap-failures)
(newline)

(adapter-exit (if (= bootstrap-failures 0) 0 1))
