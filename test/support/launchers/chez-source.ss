;;; Chez source-mode launcher.
;;;
;;; Usage:
;;;   chez-source.ss --library-root <dir> [--library-root <dir> ...]
;;;                  --object-guard <dir> --program <path>
;;;
;;; WHY FLAGS RATHER THAN POSITIONS
;;;
;;; A lane needs one library root per library family it imports, and the count
;;; grows as library families are added. A positional protocol renumbers every
;;; caller each time. A separator-joined list is ruled out: it would need a
;;; path separator that is `:` on Unix and `;` on Windows, a portability
;;; question this launcher gains nothing by having to answer.
;;;
;;; THE OBJECT GUARD
;;;
;;; Chez looks for a library's compiled object only in the object half of a
;;; library-directories pair. Pairing every root with a directory the build
;;; keeps empty therefore makes a .so left beside the sources impossible to
;;; load, which is what lets this lane call itself "source" honestly. Pointing
;;; library-directories at the source roots alone would do the opposite: the
;;; object would be looked for next to the source and silently preferred.
;;;
;;; WHAT THIS LAUNCHER DELIBERATELY DOES NOT CHECK
;;;
;;; Petite, and whether the build is threaded. Discovery rejects Petite at
;;; configure time and re-probes the exact binary registered here, and the
;;; toolchain layer does not gate on threading because httparse has no
;;; threads. A second copy of either rule would be a requirement inherited
;;; rather than owned.
;;;
;;; Also not checked: that --library-root names directories that exist. The
;;; object guard gets exactly this check (file-directory?, below) because an
;;; absent or dirty guard is the one thing that makes "source" a false claim;
;;; a mistyped library root is a different failure with no honesty claim
;;; riding on it. The cost is that a build-layer typo is not named at the
;;; harness's own status-2 boundary: it surfaces however Chez happens to fail
;;; once library-directories can't resolve what was asked of it -- an unbound
;;; library, an uncaught condition -- which is Chez's own exit 255, not this
;;; launcher's HARNESS-ERROR. Adding the check is a new decision needing a
;;; new lane and a new mutation, not a fix to something this file already
;;; tries and fails to do.

;; Status 2 is the harness's "harness, configuration, or registration error".
;; A launcher that could not set up the lane has not run a test at all, and must
;; not be mistaken for one that ran and failed.
(define (die message)
  (display "httparse-launcher: HARNESS-ERROR " (current-error-port))
  (display message (current-error-port))
  (newline (current-error-port))
  (exit 2))

;; --- the flag vocabulary ---------------------------------------------------
;;
;; required-flags is data, not control flow, so that dropping an entry is its
;; own defect with its own lane rather than a silent widening of what a valid
;; invocation looks like.

(define known-flags
  (list "--library-root" "--object-guard" "--program"))

;; One per line, and in a different order from known-flags, so that each entry
;; is unique text in this file and can be removed by a mutation of its own.
;; Dropping an entry is a real defect with a real consequence -- an invocation
;; missing that flag stops being refused -- and it is invisible to every lane
;; but the one that omits it.
(define required-flags
  (list "--program"
        "--object-guard"
        "--library-root"))

(define single-valued-flags
  (list "--object-guard" "--program"))

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
;; silently win: a repeat would run a different program, or guard a different
;; directory, than a later occurrence on the command line says, with nothing
;; to say the earlier one was the one that ran.
(for-each
 (lambda (flag)
   (if (> (length (flag-values flag)) 1)
       (die (string-append "flag given more than once: " flag))))
 single-valued-flags)

(define library-roots (flag-values "--library-root"))
(define object-guard-dir (car (flag-values "--object-guard")))
(define program (car (flag-values "--program")))

(if (not (file-directory? object-guard-dir))
    (die (string-append "object guard directory does not exist: " object-guard-dir)))

;; Asserted, not assumed. A guard directory that has acquired a file is no
;; longer a guard, and the lane would go on reporting "source" while loading
;; whatever was put there.
(if (not (null? (directory-list object-guard-dir)))
    (die (string-append "object guard directory must be empty but is not: "
                        object-guard-dir)))

(compile-imported-libraries #f)

;; Nothing includes, so nothing resolves through source-directories at all
;; (measured inert for the aot launcher by SchemeMutationSuite.cmake's
;; "source-directories is not emptied" mutation, and extended here by the
;; absence of any include form).
;; Emptied rather than left at Chez's CWD-containing default: it still
;; narrows what a later top-level load or include added to this file could
;; reach, and an empty list costs nothing to state.
(source-directories '())

;; Every root is paired with the same always-empty guard directory.
(library-directories
 (map (lambda (root) (cons root object-guard-dir)) library-roots))

(load-program program)
