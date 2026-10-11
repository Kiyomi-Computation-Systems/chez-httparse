;;; (site-test): the few SRFI-64 forms the site suites use, over this
;;; repository's harness.
;;;
;;; The suites under test/site/ are copied from chez-cmark-gfm, where they
;;; run on SRFI-64. This project does not vendor SRFI-64, so these forms map
;;; onto (httparse test harness) and leave the suites' bodies unchanged.
;;;
;;; ONE DIFFERENCE, AND IT IS STRICTER: these are procedures, so a test's
;;; actual expression is evaluated before the case runs. An exception there
;;; ends the program with a non-zero exit rather than being recorded as a
;;; failed case -- SRFI-64 turns it into `#f`, which can let a broken
;;; expression pass a negative test.
(library (site-test)
  (export test-runner-simple test-runner-current test-runner-fail-count
          test-begin test-end test-equal test-assert)
  (import (rnrs) (httparse test harness))

  (define status 0)

  ;; test-runner-simple : -> Symbol
  ;; test-runner-current : Any -> Void
  ;; The harness keeps one runner per program; these exist so the copied
  ;; suites' set-up lines run unchanged.
  (define (test-runner-simple) 'harness)
  (define (test-runner-current runner) (if #f #f))

  ;; test-begin : String -> Void
  (define (test-begin name) (harness-begin name))

  ;; test-equal : String Any Any -> Void
  ;; SRFI-64's argument order: the name, the EXPECTED value, then the actual.
  (define (test-equal name expected actual)
    (harness-case name (lambda () (check-equal name actual expected))))

  ;; test-assert : String Any -> Void
  (define (test-assert name value)
    (harness-case name (lambda () (check name value))))

  ;; test-end : String -> Void
  ;; Prints the harness summary and records its exit status.
  (define (test-end name) (set! status (harness-summary)))

  ;; test-runner-fail-count : Any -> ExactInteger
  ;; The harness exit status: 0 when every case passed.
  (define (test-runner-fail-count runner) status))
