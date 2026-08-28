;;; Chez ahead-of-time compilation step.
;;;
;;; Usage:
;;;   chez-compile.ss --library-root <dir> [--library-root <dir> ...]
;;;                   --object-dir <dir>   [--object-dir <dir> ...]
;;;                   --program <path> --output <path>
;;;
;;; The nth --object-dir pairs with the nth --library-root. The pairing is
;;; positional because library-directories is a list of pairs and there is no
;;; flag spelling of a pair; the counts are asserted equal below, because a
;;; silent mismatch would compile some libraries into a directory the AOT
;;; launcher never puts on its library path, and that lane would then fail at
;;; run time with an unbound library rather than here with a sentence.
;;;
;;; WHY THE FLAG BLOCK BELOW IS A THIRD COPY
;;;
;;; known-flags, required-flags, single-valued-flags and the three loops under
;;; them are the same code chez-source.ss carries. The duplication is
;;; deliberate and it is not a candidate for extraction -- but not because a
;;; --script program has nowhere to `load` a shared file from. Measured
;;; against Chez 10.4.1 on 2026-08-17: under --script, (car (command-line))
;;; is this script's own path, so the absolute directory to `load` a sibling
;;; file from is derivable with no bootstrap argument. Chez's own defaults
;;; for both library-directories and source-directories are CWD-relative --
;;; (("." . ".")) and (".") respectively, measured 2026-08-17 -- and a
;;; launcher must never inherit either, whatever directory a lane happens to
;;; launch from. Sharing this block would make every launcher's
;;; correctness depend on `load`ing another launcher file: a load-order
;;; dependency between files that stand alone today, with its own new failure
;;; mode -- a `load` of the wrong file rather than a named refusal. That is
;;; not worth what sharing would save.
;;;
;;; The cost of the copy is that a flag-vocabulary decision fixed in one
;;; launcher is not fixed in the others: the copies are independent
;;; decisions, not one decision spelled three times. That independence is
;;; now partially witnessed: SchemeMutationSuite.cmake mutates this file's
;;; own refusal -- pass 29, the unpaired-roots check. Passes 26-28 --
;;; chez-aot.ss's library-path pairing, source-directories, missing-program,
;;; and dirty-source-guard refusals -- mutate that file instead. The
;;; verbatim flag-block loops below this decision remain witnessed only in
;;; chez-source.ss's copy; a defect introduced into one copy alone would not
;;; be caught here, and that residual is accepted, recorded here rather than
;;; left implied.
;;;
;;; WHY compile-imported-libraries IS ON HERE AND OFF THERE
;;;
;;; This step exists to produce the objects; the run must never produce one.
;;; A run that compiled would be doing at run time what this step claims to
;;; have done at build time, and the lane would pass having proved nothing
;;; about the artifact.

;; Status 2 is the harness's "harness, configuration, or registration error".
;; A launcher that could not set up the lane has not run a test at all, and
;; must not be mistaken for one that ran and failed.
(define (die message)
  (display "httparse-launcher: HARNESS-ERROR " (current-error-port))
  (display message (current-error-port))
  (newline (current-error-port))
  (exit 2))

;; Renders "1 root" and "2 roots", "1 object directory" and "2 object
;; directories" -- the pairing-count refusal below names both counts, and
;; either can legitimately be 1.
(define (count-noun n singular plural)
  (string-append (number->string n) " " (if (= n 1) singular plural)))

;; --- the flag vocabulary ---------------------------------------------------
;;
;; required-flags is data, not control flow, so that dropping an entry is its
;; own defect with its own lane rather than a silent widening of what a valid
;; invocation looks like.

(define known-flags
  (list "--library-root" "--object-dir" "--program" "--output"))

;; One per line, in a different order from known-flags, so each entry is
;; unique text in this file and can be removed by a mutation of its own.
;; Dropping an entry is a real defect with a real consequence -- an
;; invocation missing that flag stops being refused -- and it is invisible to
;; every lane but the one that omits it.
(define required-flags
  (list "--output"
        "--program"
        "--object-dir"
        "--library-root"))

(define single-valued-flags (list "--program" "--output"))

(define args (command-line-arguments))

;; Decision 1: every argument is a known flag followed by a value.
(let loop ((rest args))
  (cond ((null? rest) #t)
        ((not (member (car rest) known-flags))
         (die (string-append "unknown flag: " (car rest))))
        ((null? (cdr rest))
         (die (string-append "flag has no value: " (car rest))))
        (else (loop (cddr rest)))))

;; Safe only after decision 1: the list is known to be flag/value pairs.
(define (flag-values flag)
  (let loop ((rest args) (found (list)))
    (cond ((null? rest) (reverse found))
          ((string=? (car rest) flag) (loop (cddr rest) (cons (cadr rest) found)))
          (else (loop (cddr rest) found)))))

;; Decision 2: every required flag appears.
(for-each
 (lambda (flag)
   (if (null? (flag-values flag))
       (die (string-append "missing required flag: " flag))))
 required-flags)

;; Decision 3: a single-valued flag appears at most once. flag-values returns
;; every occurrence in command-line order, and (car (flag-values flag)) below
;; always takes the first, so without this check the first occurrence would
;; silently win: a repeat would compile a different program, or write the
;; result to a different output path, than a later occurrence on the command
;; line says, with nothing to say the earlier one was the one that ran.
(for-each
 (lambda (flag)
   (if (> (length (flag-values flag)) 1)
       (die (string-append "flag given more than once: " flag))))
 single-valued-flags)

(define library-roots (flag-values "--library-root"))
(define object-dirs (flag-values "--object-dir"))
(define program (car (flag-values "--program")))
(define output (car (flag-values "--output")))

(if (not (= (length library-roots) (length object-dirs)))
    (die (string-append "each --library-root needs one --object-dir, but there are "
                        (count-noun (length library-roots) "root" "roots")
                        " and "
                        (count-noun (length object-dirs) "object directory" "object directories"))))

(compile-imported-libraries #t)

;; Declined, not merely left at its default: whole-program optimisation would
;; add a second compiled-artifact shape (a .wpo file) for the fingerprint
;; binding mechanism to track, and a portability proof does not need the
;; extra optimisation it buys. See "Explicitly deferred" in the slice
;; design, docs/plans/milestone-0-slice-5b-5c-compiled-lanes.md section 10.
(generate-wpo-files #f)

;; Nothing includes, so nothing resolves through source-directories at all
;; (decision 0006; measured inert for the aot launcher as mutation C3b, and
;; extended here by the absence of any include form). Emptied rather than
;; left at Chez's CWD-containing default: it still narrows what a later
;; top-level load or include added to this file could reach, and an empty
;; list costs nothing to state.
(source-directories '())
(library-directories (map cons library-roots object-dirs))

(compile-program program output)

(display "httparse-launcher: compiled ")
(display output)
(newline)
(flush-output-port (current-output-port))
(exit 0)
