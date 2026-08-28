;;; The empty-selection body, as a program. Merged from its .chez.sps
;;; wrapper by the include collapse (decision 0006).

(import (rnrs) (httparse test harness))

(harness-begin "harness.empty-selection")

;;; Registers one case that the ambient filter cannot select, so the run
;;; selects nothing and must exit 2.
;;;
;;; CTest fails an empty selection with execution.noTestsAction, and a suite
;;; that ran nothing must not report success one layer down either. The filter
;;; arrives from HTTPARSE_TEST_FILTER, set by this lane's registration.

(harness-case "never-selected" (lambda () (check "unreachable" #t)))

(harness-finish)
