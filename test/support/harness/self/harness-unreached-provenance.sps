;;; The unreached-provenance body, as a program.

(import (rnrs) (httparse test harness))

;;; A suite that was given a manifest and never verified it. Plain R6RS.
;;;
;;; Every other program in this tree reaches harness-verify-provenance! through
;;; harness-begin -- or, in the bootstrap's case, calls it by hand, having
;;; deliberately no harness-begin. This one does neither, so the check is never
;;; reached -- and its lane is registered with a real manifest, so the build
;;; did declare text this run was supposed to verify. That combination is the
;;; defect: provenance configured and not performed.
;;;
;;; It still reaches harness-summary, which is where the guard lives. A program
;;; that reached neither could not be caught this way, which is stated at the
;;; guard itself.

(harness-case "a case runs, so the suite is not empty"
  (lambda ()
    (check "this assertion is beside the point; reaching the summary is not" #t)))

(harness-finish)
