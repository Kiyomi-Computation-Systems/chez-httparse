;;; Compute the expected combined fingerprint of a manifest, at build time.
;;;
;;; Usage:
;;;   fingerprint-manifest.ss <library-root> <object-guard> <output> <source>...
;;;
;;; A lane prints the combined fingerprint of the sources it executed. Until
;;; something reads that value back it is a claim, not a check: two lanes can
;;; print different digests for text both say they ran, and a suite that only
;;; prints stays green. This produces the value each lane must agree with,
;;; computed by the build from the repository sources before anything is
;;; compiled from them.
;;;
;;; THE ALGORITHM IS NOT REIMPLEMENTED HERE
;;;
;;; (httparse test fingerprint) is imported -- the same library the
;;; harness re-exports to every lane -- so this program and the runner cannot
;;; drift apart. The import mechanism (library-directories set first, import
;;; mid-file under --script) is measured in upstream decision 0006. The root is paired
;;; with the always-empty object guard for the same reason chez-source.ss
;;; pairs its roots: the expectation must be computed from source text, and a
;;; compiled object beside the source must have nowhere to load from.

;;; Status 2 is the harness's "harness, configuration, or registration error",
;;; the same meaning the Chez source launcher gives it.
(define (die message)
  (display "httparse-fingerprint: HARNESS-ERROR " (current-error-port))
  (display message (current-error-port))
  (newline (current-error-port))
  (exit 2))

(define args (command-line-arguments))

(if (< (length args) 4)
    (die "usage: fingerprint-manifest.ss <library-root> <object-guard> <output> <source>..."))

(define library-root (list-ref args 0))
(define object-guard-dir (list-ref args 1))
(define output (list-ref args 2))
(define sources (list-tail args 3))

(if (not (file-directory? object-guard-dir))
    (die (string-append "object guard directory does not exist: " object-guard-dir)))

;; Asserted, not assumed, exactly as the launchers assert it: a guard
;; directory that has acquired a file is no longer a guard, and the
;; expectation would be computed from whatever was put there.
(if (not (null? (directory-list object-guard-dir)))
    (die (string-append "object guard directory must be empty but is not: "
                        object-guard-dir)))

(for-each
 (lambda (source)
   (if (not (file-exists? source))
       (die (string-append "manifest source does not exist: " source))))
 sources)

(compile-imported-libraries #f)
(source-directories '())
(library-directories (list (cons library-root object-guard-dir)))

(import (httparse test fingerprint))

(define combined
  (harness-fingerprint->string
   (harness-fingerprint-combine (map harness-fingerprint-file sources))))

;; No trailing newline. The reader trims whitespace anyway, but writing exactly
;; the value keeps the file's bytes equal to the string it represents.
(let ((port (open-file-output-port output (file-options no-fail))))
  (put-bytevector port (string->utf8 combined))
  (close-port port))

(display "httparse-fingerprint: ")
(display combined)
(newline)
(exit 0)
