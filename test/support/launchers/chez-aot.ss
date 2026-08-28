;;; Chez ahead-of-time launcher.
;;;
;;; Usage:
;;;   chez-aot.ss --object-dir <dir> [--object-dir <dir> ...]
;;;               --source-guard <dir> --program <compiled>
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
;;; own refusals and decisions -- passes 26-28: the library-path pairing and
;;; source-directories (pass 26), the missing-program refusal (pass 27), and
;;; the dirty-source-guard refusal (pass 28). Pass 29, chez-compile.ss's
;;; unpaired-roots refusal, mutates that file instead. The verbatim
;;; flag-block loops below these decisions remain witnessed only in
;;; chez-source.ss's copy; a defect introduced into one copy alone would not
;;; be caught here, and that residual is accepted, recorded here rather than
;;; left implied.
;;;
;;; WHY THE LIBRARY PATH PAIRS EVERY OBJECT DIRECTORY WITH AN EMPTY SOURCE
;;; GUARD
;;;
;;; Measured against Chez 10.4.1 on 2026-08-17: a bare string handed to
;;; library-directories becomes BOTH halves of the pair --
;;; (library-directories '("/a" "/b")) reads back as
;;; (("/a" . "/a") ("/b" . "/b")). Passed one bare string per object
;;; directory, as this launcher used to, every object directory is therefore
;;; also a SOURCE directory: Chez looks for a .sls/.ss/.scm/.sch there and
;;; expands what it finds -- the source if there is no object, the newer of
;;; the two if there is both. --source-guard pairs every object directory's
;;; SOURCE half with one directory the build keeps empty instead, which is
;;; the exact inverse of chez-source.ss's object guard: that file pairs every
;;; source root's OBJECT half with an always-empty directory so no compiled
;;; object can be preferred over source; this one pairs every object
;;; directory's SOURCE half with an always-empty directory so no source can
;;; be preferred over -- or found instead of -- the compiled object. Checked
;;; below the same way chez-source.ss checks its own guard: asserted to be a
;;; directory, asserted to be empty, so there is nowhere for a library's
;;; source to resolve from no matter what an object directory alongside it
;;; happens to hold.
;;;
;;; What kept this lane honest before this guard existed, unnamed in this
;;; file until now: load-program of a compile-program output refuses a
;;; library that re-expands from source, with "yielded a different
;;; compilation instance of ... from that required by compiled program", and
;;; exits 255 -- reproduced against a scratch library and program, compiled
;;; and loaded the way this launcher does, on 2026-08-17. That is why a bare
;;; object directory could not become a SILENT source lane; it is not why the
;;; source could not be read at all, which is what the guard above actually
;;; prevents and the backstop does not. What the guard does not settle:
;;; whether Chez can still judge a correctly-paired, genuinely-compiled
;;; object stale by some rule of its own and act on that -- protium records a
;;; locatability rule for this, decision record 0004 records a timestamp
;;; rule, the two are different, and neither has been reproduced in this
;;; repository. Section 5.3 of the slice design tracks it as unmeasured.
;;;
;;; WHY source-directories IS ALSO EMPTIED
;;;
;;; Measured against Chez 10.4.1 on 2026-08-17: this launcher's own load,
;;; run once with (source-directories '()) and once left at Chez's unset
;;; default ((".")), produces byte-identical outcomes. Library resolution
;;; goes through library-directories, not source-directories, and no Scheme
;;; file in this tree includes another (decision 0006) -- so nothing this
;;; launcher does today depends on the line above. It is kept anyway: it
;;; still narrows what a `load` or top-level `include` added to this file
;;; later could reach, and an empty list costs nothing to state. It is not,
;;; on its own, what makes this lane honest -- the source guard above is.

;; Status 2 is the harness's "harness, configuration, or registration error".
;; A launcher that could not set up the lane has not run a test at all, and
;; must not be mistaken for one that ran and failed.
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

(define known-flags (list "--object-dir" "--program" "--source-guard"))

;; One per line, in a different order from known-flags, so each entry is
;; unique text in this file and can be removed by a mutation of its own.
;; Dropping an entry is a real defect with a real consequence -- an
;; invocation missing that flag stops being refused -- and it is invisible to
;; every lane but the one that omits it.
(define required-flags
  (list "--source-guard"
        "--program"
        "--object-dir"))

(define single-valued-flags (list "--source-guard" "--program"))

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
;; silently win: a repeat would run a different program, or guard a
;; different directory, than a later occurrence on the command line says,
;; with nothing to say the earlier one was the one that ran.
(for-each
 (lambda (flag)
   (if (> (length (flag-values flag)) 1)
       (die (string-append "flag given more than once: " flag))))
 single-valued-flags)

(define object-dirs (flag-values "--object-dir"))
(define program (car (flag-values "--program")))
(define source-guard-dir (car (flag-values "--source-guard")))

;; Asserted, not assumed. Without the object this lane cannot run at all, and
;; the failure Chez gives for a missing program file says nothing about which
;; build step should have produced it.
(if (not (file-exists? program))
    (die (string-append "compiled program does not exist: " program)))

(if (not (file-directory? source-guard-dir))
    (die (string-append "source guard directory does not exist: " source-guard-dir)))

;; Asserted, not assumed. A guard directory that has acquired a file is no
;; longer a guard: it would become a second SOURCE directory on every object
;; directory's library-directories pair (see WHY THE LIBRARY PATH PAIRS
;; ... above), and this lane would go on reporting "aot" while whatever was
;; put there could be expanded instead of the compiled object.
(if (not (null? (directory-list source-guard-dir)))
    (die (string-append "source guard directory must be empty but is not: "
                        source-guard-dir)))

(compile-imported-libraries #f)
(source-directories '())

;; Every object directory is paired with the same always-empty guard
;; directory as its SOURCE half -- a library-directories entry is a
;; (source . object) pair, and a bare string becomes both halves of one (see
;; above), so pairing is what stops an object directory from also acting as a
;; source directory.
(library-directories
 (map (lambda (dir) (cons source-guard-dir dir)) object-dirs))

(load-program program)
