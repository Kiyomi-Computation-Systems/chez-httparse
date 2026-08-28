;;; The failing body, as a program. Merged from its .chez.sps wrapper by the
;;; include collapse (decision 0006).

(import (rnrs) (httparse test harness))

(harness-begin "harness.failing")

;;; Deliberately fails one assertion so the process exits with status 1.
;;;
;;; A program cannot report its own exit status, so this one only fails; the
;;; registration compares the exact status from outside. Status 1 means an
;;; assertion failed and nothing else, and must stay distinguishable from the
;;; status 2 that harness-duplicate-case.sps produces.

(harness-case "an assertion that is meant to fail"
  (lambda ()
    (check "this check fails on purpose" #f)))

(harness-finish)
