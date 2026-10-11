;;; docs.reference: docs/reference.md against the libraries' real exports.
;;;
;;; The reference is authored prose; its COMPLETENESS is checked here. The
;;; synthetic cases pin each diagnostic, and a clean document must produce
;;; none, so a checker that reports everything is caught as surely as one
;;; that reports nothing. The last group reads the real page and the real
;;; `(export ...)` forms.
;;;
;;; This repository's modules are checked EXACTLY: every export has one entry
;;; and nothing else does. The generator's runtime is checked as a SUBSET:
;;; the page documents the procedures an embedder calls, and each must be a
;;; real export.
(import (rnrs)
        (httparse test harness)
        (httparse test reference))

(define (read-text path)
  (utf8->string
   (call-with-port (open-file-input-port path) get-bytevector-all)))

(define (read-library path)
  (call-with-input-file path read))

(define (split-paths s)
  (let loop ((i 0) (start 0) (out '()))
    (cond ((= i (string-length s))
           (reverse (if (> i start) (cons (substring s start i) out) out)))
          ((char=? #\| (string-ref s i))
           (loop (+ i 1) (+ i 1)
                 (if (> i start) (cons (substring s start i) out) out)))
          (else (loop (+ i 1) start out)))))

(define (lines . ls)
  (apply string-append (map (lambda (l) (string-append l "\n")) ls)))

;; A small, valid page over one exact module `(a b)` exporting `f` and `g`,
;; and one subset module `(rt)`, of whose exports it documents `run`.
(define exact-apis '(((a b) f g)))
(define subset-apis '(((rt) run stop)))

(define (entry name kind modules . body)
  (append (list (string-append "### `" name "` (" kind ")") "")
          body
          (list ""
                (string-append "**Available from:** " modules)
                "")))

(define (page modules entries index)
  (apply lines
         (append '("# API reference" "" "## Modules" ""
                   "| Module | Purpose |" "|---|---|")
                 modules
                 '("" "## Things" "")
                 (apply append entries)
                 '("## Alphabetical index" "")
                 index)))

(define good-modules '("| `(a b)` | exact |" "| `(rt)` | subset |"))
(define good-entries
  (list (entry "f" "procedure" "`(a b)`" "`(f x) -> y`")
        (entry "g" "constant" "`(a b)`" "A number.")
        (entry "run" "procedure" "`(rt)`" "Runs it.")))
(define good-index
  '("- [`f`](#f-procedure)" "- [`g`](#g-constant)" "- [`run`](#run-procedure)"))

(define (diagnose text)
  (reference-diagnostics exact-apis subset-apis
                         (markdown->reference-analysis text)))

(harness-begin "docs.reference")

(harness-group "reading an export form"
  (lambda ()
    (harness-case "the name and the exports, in declaration order"
      (lambda ()
        (let-values (((name exports problem)
                      (library-datum->api
                       '(library (x y) (export b a c) (import (rnrs))))))
          (check-equal "name" name '(x y))
          (check-equal "exports" exports '(b a c))
          (check-equal "no problem" problem #f))))
    (harness-case "a rename spec is refused, not skipped"
      (lambda ()
        (let-values (((name exports problem)
                      (library-datum->api
                       '(library (x) (export (rename (a b))) (import (rnrs))))))
          (check-equal "problem" problem '(unsupported-export-spec (rename (a b)))))))
    (harness-case "no export form is a problem"
      (lambda ()
        (let-values (((name exports problem)
                      (library-datum->api '(library (x) (import (rnrs))))))
          (check-equal "problem" problem '(missing-export-form)))))
    (harness-case "a datum that is not a library is a problem"
      (lambda ()
        (let-values (((name exports problem) (library-datum->api '(define x 1))))
          (check-equal "name" name #f)
          (check-equal "tag" (car problem) 'malformed-library-datum))))))

(harness-group "reading the page"
  (lambda ()
    (harness-case "module rows count only under ## Modules"
      (lambda ()
        (let ((a (markdown->reference-analysis
                  (lines "## Modules" "| `(a b)` | x |" "## Other" "| `(c)` | y |"))))
          (check-equal "modules" (reference-analysis-modules a) '((a b))))))
    (harness-case "an entry keeps its name, kind and modules"
      (lambda ()
        (let* ((a (markdown->reference-analysis
                   (apply lines (entry "f" "procedure" "`(a b)`, `(c)`" "Body."))))
               (e (car (reference-analysis-entries a))))
          (check-equal "name" (reference-entry-name e) 'f)
          (check-equal "kind" (reference-entry-kind e) 'procedure)
          (check-equal "modules" (reference-entry-modules e) '((a b) (c)))
          (check "has a body" (reference-entry-body? e)))))
    (harness-case "a heading inside a fence is not an entry"
      (lambda ()
        (let ((a (markdown->reference-analysis
                  (lines "```markdown" "### `f` (procedure)" "```"))))
          (check-equal "entries" (reference-analysis-entries a) '()))))
    (harness-case "a closed fence hands the page back to the grammar"
      (lambda ()
        (let ((a (markdown->reference-analysis
                  (lines "```text" "### `x` (procedure)" "```" "### `f` (procedure)"))))
          (check-equal "entries" (map reference-entry-name (reference-analysis-entries a))
                       '(f)))))
    (harness-case "a malformed ### line is reported verbatim"
      (lambda ()
        (let ((a (markdown->reference-analysis (lines "### f (procedure)"))))
          (check-equal "problems" (reference-analysis-problems a)
                       '((malformed-entry-heading . "### f (procedure)"))))))
    (harness-case "an unknown kind is malformed"
      (lambda ()
        (let ((a (markdown->reference-analysis (lines "### `f` (macro)"))))
          (check-equal "entries" (reference-analysis-entries a) '())
          (check-equal "problems" (length (reference-analysis-problems a)) 1))))
    (harness-case "index lines are read in order, with their anchors"
      (lambda ()
        (let ((a (markdown->reference-analysis
                  (lines "## Alphabetical index" ""
                         "- [`b`](#b-value)" "- [`a`](#a-procedure)"))))
          (check-equal "index" (reference-analysis-index a)
                       '((b . "b-value") (a . "a-procedure"))))))))

(harness-group "GitHub heading anchors"
  (lambda ()
    (harness-case "punctuation drops and spaces become hyphens"
      (lambda ()
        (check-equal "bang" (reference-slug "parser-feed! (procedure)")
                     "parser-feed-procedure")
        (check-equal "predicate" (reference-slug "httparse-modes-error? (predicate)")
                     "httparse-modes-error-predicate")
        (check-equal "case" (reference-slug "F-CHUNKED (constant)")
                     "f-chunked-constant")
        (check-equal "two words" (reference-slug "make-x (record constructor)")
                     "make-x-record-constructor")))))

(harness-group "diagnostics"
  (lambda ()
    (harness-case "a complete page has none"
      (lambda ()
        (check-equal "clean" (diagnose (page good-modules good-entries good-index)) '())))
    (harness-case "a subset module need not cover its exports"
      (lambda ()
        ;; `stop` is exported by (rt) and has no entry, and that is fine.
        (check "no missing-bindings"
               (not (assq 'missing-bindings
                          (diagnose (page good-modules good-entries good-index)))))))
    (harness-case "an exact export with no entry"
      (lambda ()
        (check-equal "missing"
                     (cdr (assq 'missing-bindings
                                (diagnose (page good-modules
                                                (list (car good-entries) (caddr good-entries))
                                                '("- [`f`](#f-procedure)" "- [`run`](#run-procedure)")))))
                     '(g))))
    (harness-case "an entry nothing exports"
      (lambda ()
        (check-equal "extra"
                     (cdr (assq 'extra-bindings
                                (diagnose (page good-modules
                                                (append good-entries
                                                        (list (entry "zap" "procedure" "`(rt)`" "No.")))
                                                (append good-index '("- [`zap`](#zap-procedure)"))))))
                     '(zap))))
    (harness-case "a subset entry the subset module does not export"
      (lambda ()
        (let ((d (diagnose (page good-modules
                                 (list (car good-entries) (cadr good-entries)
                                       (entry "walk" "procedure" "`(rt)`" "No."))
                                 '("- [`f`](#f-procedure)" "- [`g`](#g-constant)"
                                   "- [`walk`](#walk-procedure)")))))
          (check-equal "extra" (cdr (assq 'extra-bindings d)) '(walk)))))
    (harness-case "a subset module with no entries"
      (lambda ()
        (check-equal "empty subset"
                     (cdr (assq 'empty-subset-modules
                                (diagnose (page good-modules
                                                (list (car good-entries) (cadr good-entries))
                                                '("- [`f`](#f-procedure)" "- [`g`](#g-constant)")))))
                     '((rt)))))
    (harness-case "two entries for one binding"
      (lambda ()
        (check-equal "duplicate"
                     (cdr (assq 'duplicate-bindings
                                (diagnose (page good-modules
                                                (append good-entries (list (car good-entries)))
                                                good-index))))
                     '(f))))
    (harness-case "an entry with only its availability line"
      (lambda ()
        (check-equal "empty body"
                     (cdr (assq 'empty-entry-bodies
                                (diagnose (page good-modules
                                                (list (entry "f" "procedure" "`(a b)`")
                                                      (cadr good-entries) (caddr good-entries))
                                                good-index))))
                     '(f))))
    (harness-case "an entry with no availability line"
      (lambda ()
        (check-equal "missing availability"
                     (cdr (assq 'missing-availability
                                (diagnose (page good-modules
                                                (list '("### `f` (procedure)" "" "Body." "")
                                                      (cadr good-entries) (caddr good-entries))
                                                good-index))))
                     '(f))))
    (harness-case "an entry with two availability lines"
      (lambda ()
        (check-equal "duplicate availability"
                     (cdr (assq 'duplicate-availability
                                (diagnose (page good-modules
                                                (list (append (car good-entries)
                                                              '("**Available from:** `(a b)`" ""))
                                                      (cadr good-entries) (caddr good-entries))
                                                good-index))))
                     '(f))))
    (harness-case "an entry naming the wrong module"
      (lambda ()
        (check-equal "mismatch"
                     (cdr (assq 'module-membership-mismatches
                                (diagnose (page good-modules
                                                (list (entry "f" "procedure" "`(rt)`" "Body.")
                                                      (cadr good-entries) (caddr good-entries))
                                                good-index))))
                     '((f ((a b)) ((rt)))))))
    (harness-case "a module with no row, and a row with no module"
      (lambda ()
        (let ((d (diagnose (page '("| `(a b)` | x |" "| `(zz)` | y |")
                                 good-entries good-index))))
          (check-equal "missing" (cdr (assq 'missing-modules d)) '((rt)))
          (check-equal "extra" (cdr (assq 'extra-modules d)) '((zz))))))
    (harness-case "a malformed heading"
      (lambda ()
        (check-equal "malformed"
                     (cdr (assq 'malformed-entry-headings
                                (diagnose (page good-modules
                                                (append good-entries '(("### f (procedure)" "" "x" "")))
                                                good-index))))
                     '("### f (procedure)"))))
    (harness-case "nothing on either side is never clean"
      (lambda ()
        (let ((d (reference-diagnostics '() '() (markdown->reference-analysis ""))))
          (check "no-public-modules" (assq 'no-public-modules d))
          (check "no-public-bindings" (assq 'no-public-bindings d))
          (check "no-reference-modules" (assq 'no-reference-modules d))
          (check "no-reference-bindings" (assq 'no-reference-bindings d)))))))

(harness-group "the alphabetical index"
  (lambda ()
    (harness-case "an entry the index leaves out"
      (lambda ()
        (check-equal "missing"
                     (cdr (assq 'index-missing
                                (diagnose (page good-modules good-entries (cdr good-index)))))
                     '(f))))
    (harness-case "an index line for no entry"
      (lambda ()
        (check-equal "extra"
                     (cdr (assq 'index-extra
                                (diagnose (page good-modules good-entries
                                                (append good-index '("- [`zz`](#zz-value)"))))))
                     '(zz))))
    (harness-case "an index out of order"
      (lambda ()
        (check-equal "unsorted"
                     (cdr (assq 'index-unsorted
                                (diagnose (page good-modules good-entries
                                                (list (cadr good-index) (car good-index)
                                                      (caddr good-index))))))
                     '((g f)))))
    (harness-case "an index line repeated"
      (lambda ()
        (check-equal "duplicate"
                     (cdr (assq 'index-duplicates
                                (diagnose (page good-modules good-entries
                                                (cons (car good-index) good-index)))))
                     '(f))))
    (harness-case "an index link to the wrong anchor"
      (lambda ()
        (check-equal "bad anchor"
                     (cdr (assq 'index-bad-anchors
                                (diagnose (page good-modules good-entries
                                                (list "- [`f`](#f-function)"
                                                      (cadr good-index) (caddr good-index))))))
                     '((f "f-function" "f-procedure")))))))

(harness-group "the real page against the real exports"
  (lambda ()
    (harness-case "docs/reference.md covers every export, and no more"
      (lambda ()
        (let* ((doc (adapter-environment-variable "HTTPARSE_REFERENCE_DOC"))
               (exact (split-paths
                       (adapter-environment-variable "HTTPARSE_REFERENCE_EXACT_SOURCES")))
               (subset (split-paths
                        (adapter-environment-variable "HTTPARSE_REFERENCE_SUBSET_SOURCES")))
               (apis (lambda (paths)
                       (map (lambda (path)
                              (let-values (((name exports problem)
                                            (library-datum->api (read-library path))))
                                (check-equal (string-append "export form of " path)
                                             problem #f)
                                (cons name exports)))
                            paths)))
               (exact-apis (apis exact))
               (subset-apis (apis subset))
               (analysis (markdown->reference-analysis (read-text doc))))
          (check-equal "diagnostics"
                       (reference-diagnostics exact-apis subset-apis analysis)
                       '())
          (display (string-append
                    "httparse-reference: "
                    (number->string (+ (length exact-apis) (length subset-apis)))
                    " modules, "
                    (number->string (length (reference-analysis-entries analysis)))
                    " entries\n")))))))

(harness-finish)
