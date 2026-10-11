;;; (httparse test reference): checks docs/reference.md against the real
;;; `(export ...)` forms of the libraries it documents.
;;;
;;; PURE. The caller reads the files; this library sees a page as a string and
;;; a library as the datum `read` returns. It parses a narrow authoring
;;; convention rather than Markdown in general:
;;;
;;;   ## Modules            a table whose rows start with | `(module name)`
;;;   ### `name` (kind)     one entry per documented binding
;;;   **Available from:**   one line per entry, naming modules in backticks
;;;   ## Alphabetical index one `- [`name`](#anchor)` line per entry, sorted
;;;
;;; Anything inside a fenced code block is opaque to that grammar.
;;;
;;; Two kinds of module are checked differently. An EXACT module must have an
;;; entry for every export and nothing else; this repository's libraries are
;;; exact. A SUBSET module's entries must each be a real export, and it must
;;; have at least one; the generator's runtime is a subset, because the page
;;; documents what an embedder calls, not the hooks generated code uses.
(library (httparse test reference)
  (export library-datum->api
          markdown->reference-analysis
          reference-analysis? reference-analysis-modules
          reference-analysis-entries reference-analysis-problems
          reference-analysis-index
          reference-entry? reference-entry-name reference-entry-kind
          reference-entry-heading reference-entry-modules
          reference-entry-body? reference-entry-availability-count
          reference-slug
          reference-diagnostics)
  (import (rnrs))

  (define-record-type reference-entry
    (fields name kind heading modules body? availability-count))

  (define-record-type reference-analysis
    (fields modules entries problems index))

  ;; --- small string operations -----------------------------------------

  (define (string-prefix? prefix s)
    (and (>= (string-length s) (string-length prefix))
         (string=? prefix (substring s 0 (string-length prefix)))))

  (define (space? c)
    (memv c '(#\space #\tab #\newline #\return)))

  (define (trim s)
    (let ((n (string-length s)))
      (let left ((a 0))
        (if (and (< a n) (space? (string-ref s a)))
            (left (+ a 1))
            (let right ((b n))
              (if (and (> b a) (space? (string-ref s (- b 1))))
                  (right (- b 1))
                  (substring s a b)))))))

  (define (blank? s) (string=? "" (trim s)))

  (define (string-find-char s wanted start)
    (let loop ((i start))
      (cond ((>= i (string-length s)) #f)
            ((char=? wanted (string-ref s i)) i)
            (else (loop (+ i 1))))))

  (define (string-lines s)
    (let ((n (string-length s)))
      (let loop ((start 0) (i 0) (out '()))
        (cond
          ((= i n) (reverse (cons (substring s start i) out)))
          ((char=? #\newline (string-ref s i))
           (loop (+ i 1) (+ i 1) (cons (substring s start i) out)))
          (else (loop start (+ i 1) out))))))

  (define (symbol<? a b)
    (string<? (symbol->string a) (symbol->string b)))

  (define (module<? a b)
    (cond ((null? a) (not (null? b)))
          ((null? b) #f)
          ((symbol<? (car a) (car b)) #t)
          ((symbol<? (car b) (car a)) #f)
          (else (module<? (cdr a) (cdr b)))))

  (define (read-one s)
    (guard (e (#t #f))
      (let ((x (read (open-string-input-port s))))
        (if (eof-object? x) #f x))))

  (define (library-name? x)
    (and (list? x) (not (null? x)) (for-all symbol? x)))

  ;; reference-slug : String -> String
  ;; GitHub's heading anchor: lowercase, keep letters, digits, `-`, `_` and
  ;; spaces, then turn each space into `-`. Headings here are ASCII.
  (define (reference-slug text)
    (list->string
     (let loop ((cs (string->list (string-downcase text))) (out '()))
       (cond ((null? cs) (reverse out))
             ((char=? (car cs) #\space) (loop (cdr cs) (cons #\- out)))
             ((or (char-alphabetic? (car cs)) (char-numeric? (car cs))
                  (memv (car cs) '(#\- #\_)))
              (loop (cdr cs) (cons (car cs) out)))
             (else (loop (cdr cs) out))))))

  ;; --- library export forms --------------------------------------------

  (define (find-export-form forms)
    (cond ((null? forms) #f)
          ((and (pair? (car forms)) (eq? 'export (caar forms))) (car forms))
          (else (find-export-form (cdr forms)))))

  (define (first-non-symbol xs)
    (cond ((null? xs) #f)
          ((symbol? (car xs)) (first-non-symbol (cdr xs)))
          (else (car xs))))

  ;; library-datum->api : Datum -> (Values (U LibraryName #f) (Listof Symbol) Problem)
  ;; The library's name and its exports in declaration order, and #f; or a
  ;; problem saying why the datum cannot be read that way. An export spec
  ;; that is not a plain identifier is refused rather than skipped, so the
  ;; check can never cover less than the library exports.
  (define (library-datum->api datum)
    (cond
      ((or (not (pair? datum))
           (not (eq? 'library (car datum)))
           (not (pair? (cdr datum)))
           (not (library-name? (cadr datum))))
       (values #f '() (list 'malformed-library-datum datum)))
      (else
       (let ((export-form (find-export-form (cddr datum))))
         (cond
           ((not export-form)
            (values (cadr datum) '() '(missing-export-form)))
           ((first-non-symbol (cdr export-form))
            => (lambda (bad)
                 (values (cadr datum) '() (list 'unsupported-export-spec bad))))
           (else (values (cadr datum) (cdr export-form) #f)))))))

  ;; --- the page --------------------------------------------------------

  (define kinds
    '("procedure" "predicate" "accessor" "constant" "value"
      "record constructor" "condition type"))

  ;; ### `name` (kind)  =>  (name kind-symbol heading-text), or #f.
  (define (heading-entry line)
    (let ((s (trim line)))
      (and (string-prefix? "### `" s)
           (let ((close (string-find-char s #\` 5)))
             (and close
                  (> close 5)
                  (let* ((name-text (substring s 5 close))
                         (tail (trim (substring s (+ close 1) (string-length s))))
                         (kind (find (lambda (k)
                                       (string=? tail (string-append "(" k ")")))
                                     kinds)))
                    (and kind
                         (list (string->symbol name-text)
                               (string->symbol kind)
                               (string-append name-text " " tail)))))))))

  (define (h2? line) (string-prefix? "## " (trim line)))
  (define (h3? line) (string-prefix? "### " (trim line)))

  (define (fence? line)
    (let ((s (trim line)))
      (or (string-prefix? "```" s) (string-prefix? "~~~" s))))

  (define (html-comment? line) (string-prefix? "<!--" (trim line)))

  (define (availability? line)
    (string-prefix? "**Available from:**" (trim line)))

  (define (code-library-names line)
    (let loop ((at 0) (out '()))
      (let ((open (string-find-char line #\` at)))
        (if (not open)
            (reverse out)
            (let ((close (string-find-char line #\` (+ open 1))))
              (if (not close)
                  (reverse out)
                  (let ((x (read-one (substring line (+ open 1) close))))
                    (loop (+ close 1) (if (library-name? x) (cons x out) out)))))))))

  (define (module-row line)
    (let ((s (trim line)))
      (and (string-prefix? "| `(" s)
           (let* ((open (string-find-char s #\` 0))
                  (close (string-find-char s #\` (+ open 1))))
             (and close
                  (let ((x (read-one (substring s (+ open 1) close))))
                    (and (library-name? x) x)))))))

  ;; - [`name`](#anchor)  =>  (name . "anchor"), or #f.
  (define (index-line line)
    (let ((s (trim line)))
      (and (string-prefix? "- [`" s)
           (let ((close (string-find-char s #\` 4)))
             (and close
                  (> close 4)
                  (let ((rest (substring s (+ close 1) (string-length s))))
                    (and (string-prefix? "](#" rest)
                         (let ((end (string-find-char rest #\) 3)))
                           (and end
                                (cons (string->symbol (substring s 4 close))
                                      (substring rest 3 end)))))))))))

  ;; A pending entry is a vector so the scan below can update it in place
  ;; without rebuilding a record per line: name kind heading modules body? count.
  (define (new-pending parsed)
    (vector (car parsed) (cadr parsed) (caddr parsed) '() #f 0))

  (define (finish-entry pending entries)
    (if pending
        (cons (make-reference-entry
               (vector-ref pending 0) (vector-ref pending 1)
               (vector-ref pending 2) (reverse (vector-ref pending 3))
               (vector-ref pending 4) (vector-ref pending 5))
              entries)
        entries))

  ;; markdown->reference-analysis : String -> ReferenceAnalysis
  (define (markdown->reference-analysis markdown)
    (let loop ((lines (string-lines markdown))
               (in-fence? #f)
               (section #f)          ; 'modules, 'index or #f
               (modules '())
               (entries '())
               (problems '())
               (index '())
               (pending #f))
      (if (null? lines)
          (make-reference-analysis (reverse modules)
                                   (reverse (finish-entry pending entries))
                                   (reverse problems)
                                   (reverse index))
          (let* ((line (car lines)) (s (trim line)))
            (define (next)
              (loop (cdr lines) in-fence? section modules entries problems
                    index pending))
            (cond
              ((fence? line)
               (when pending (vector-set! pending 4 #t))
               (loop (cdr lines) (not in-fence?) section modules entries
                     problems index pending))
              (in-fence?
               (when (and pending (not (blank? line))) (vector-set! pending 4 #t))
               (next))
              ((h2? line)
               (loop (cdr lines) #f
                     (cond ((string=? s "## Modules") 'modules)
                           ((string=? s "## Alphabetical index") 'index)
                           (else #f))
                     modules (finish-entry pending entries) problems index #f))
              ((h3? line)
               (let ((parsed (heading-entry line)))
                 (loop (cdr lines) #f #f modules
                       (finish-entry pending entries)
                       (if parsed
                           problems
                           (cons (cons 'malformed-entry-heading s) problems))
                       index
                       (and parsed (new-pending parsed)))))
              ((and (eq? section 'modules) (module-row line))
               => (lambda (name)
                    (loop (cdr lines) #f section (cons name modules) entries
                          problems index pending)))
              ((and (eq? section 'index) (string-prefix? "- " s))
               (let ((item (index-line line)))
                 (loop (cdr lines) #f section modules entries
                       (if item
                           problems
                           (cons (cons 'malformed-index-line s) problems))
                       (if item (cons item index) index)
                       pending)))
              ((and pending (availability? line))
               (vector-set! pending 3
                            (append (reverse (code-library-names line))
                                    (vector-ref pending 3)))
               (vector-set! pending 5 (+ 1 (vector-ref pending 5)))
               (next))
              ((and pending (not (blank? line)) (not (html-comment? line)))
               (vector-set! pending 4 #t)
               (next))
              (else (next)))))))

  ;; --- diagnostics -----------------------------------------------------

  (define (unique xs)
    (let loop ((rest xs) (out '()))
      (cond ((null? rest) (reverse out))
            ((member (car rest) out) (loop (cdr rest) out))
            (else (loop (cdr rest) (cons (car rest) out))))))

  (define (duplicates xs)
    (let loop ((rest xs) (seen '()) (dups '()))
      (cond ((null? rest) (reverse dups))
            ((member (car rest) seen)
             (loop (cdr rest) seen
                   (if (member (car rest) dups) dups (cons (car rest) dups))))
            (else (loop (cdr rest) (cons (car rest) seen) dups)))))

  (define (list-minus xs ys)
    (filter (lambda (x) (not (member x ys))) xs))

  (define (same-set? a b)
    (and (null? (list-minus a b)) (null? (list-minus b a))))

  (define (sort-symbols xs) (list-sort symbol<? xs))
  (define (sort-modules xs) (list-sort module<? xs))

  (define (problem-values tag problems)
    (map cdr (filter (lambda (p) (eq? tag (car p))) problems)))

  (define (modules-exporting name apis)
    (map car (filter (lambda (api) (memq name (cdr api))) apis)))

  (define (membership-mismatches entries known apis)
    (let loop ((rest entries) (out '()))
      (if (null? rest)
          (reverse out)
          (let* ((e (car rest)) (name (reference-entry-name e)))
            (if (and (memq name known)
                     (= 1 (reference-entry-availability-count e)))
                (let ((expected (sort-modules (unique (modules-exporting name apis))))
                      (actual (sort-modules (unique (reference-entry-modules e)))))
                  (loop (cdr rest)
                        (if (same-set? expected actual)
                            out
                            (cons (list name expected actual) out))))
                (loop (cdr rest) out))))))

  (define (adjacent-inversions names)
    (if (or (null? names) (null? (cdr names)))
        '()
        (let ((rest (adjacent-inversions (cdr names))))
          (if (symbol<? (cadr names) (car names))
              (cons (list (car names) (cadr names)) rest)
              rest))))

  (define (index-anchor-problems index entries)
    (filter (lambda (x) x)
            (map (lambda (item)
                   (let ((e (find (lambda (e) (eq? (car item) (reference-entry-name e)))
                                  entries)))
                     (and e
                          (let ((expected (reference-slug (reference-entry-heading e))))
                            (and (not (string=? expected (cdr item)))
                                 (list (car item) (cdr item) expected))))))
                 index)))

  (define (add tag values out)
    (if (null? values) out (cons (cons tag values) out)))

  ;; reference-diagnostics : (Listof Api) (Listof Api) ReferenceAnalysis -> Alist
  ;; where Api = (Pair LibraryName (Listof Symbol)). Every problem the page
  ;; has, as (tag . values) in a fixed order; '() for a complete page. The
  ;; `no-*` diagnostics make an empty side an error: a check that compared
  ;; nothing with nothing would otherwise pass.
  (define (reference-diagnostics exact-apis subset-apis analysis)
    (let* ((all-apis (append exact-apis subset-apis))
           (public-modules (map car all-apis))
           (required (unique (apply append (map cdr exact-apis))))
           (known (unique (apply append (map cdr all-apis))))
           (reference-modules (reference-analysis-modules analysis))
           (entries (reference-analysis-entries analysis))
           (names (map reference-entry-name entries))
           (index (reference-analysis-index analysis))
           (index-names (map car index))
           (problems (reference-analysis-problems analysis))
           (empty-subsets
            (filter (lambda (m)
                      (not (exists (lambda (e) (member m (reference-entry-modules e)))
                                   entries)))
                    (map car subset-apis))))
      (reverse
       (let* ((out '())
              (out (add 'no-public-modules (if (null? public-modules) '(empty) '()) out))
              (out (add 'no-public-bindings (if (null? required) '(empty) '()) out))
              (out (add 'no-reference-modules (if (null? reference-modules) '(empty) '()) out))
              (out (add 'no-reference-bindings (if (null? names) '(empty) '()) out))
              (out (add 'missing-modules
                        (sort-modules (list-minus (unique public-modules) reference-modules))
                        out))
              (out (add 'extra-modules
                        (sort-modules (list-minus (unique reference-modules) public-modules))
                        out))
              (out (add 'duplicate-modules (sort-modules (duplicates reference-modules)) out))
              (out (add 'missing-bindings (sort-symbols (list-minus required names)) out))
              (out (add 'extra-bindings (sort-symbols (list-minus (unique names) known)) out))
              (out (add 'duplicate-bindings (sort-symbols (duplicates names)) out))
              (out (add 'empty-subset-modules (sort-modules empty-subsets) out))
              (out (add 'empty-entry-bodies
                        (sort-symbols
                         (map reference-entry-name
                              (filter (lambda (e) (not (reference-entry-body? e))) entries)))
                        out))
              (out (add 'missing-availability
                        (sort-symbols
                         (map reference-entry-name
                              (filter (lambda (e) (= 0 (reference-entry-availability-count e)))
                                      entries)))
                        out))
              (out (add 'duplicate-availability
                        (sort-symbols
                         (map reference-entry-name
                              (filter (lambda (e) (> (reference-entry-availability-count e) 1))
                                      entries)))
                        out))
              (out (add 'module-membership-mismatches
                        (membership-mismatches entries known all-apis)
                        out))
              (out (add 'malformed-entry-headings
                        (list-sort string<? (problem-values 'malformed-entry-heading problems))
                        out))
              (out (add 'index-missing (sort-symbols (list-minus (unique names) index-names)) out))
              (out (add 'index-extra (sort-symbols (list-minus index-names names)) out))
              (out (add 'index-duplicates (sort-symbols (duplicates index-names)) out))
              (out (add 'index-unsorted (adjacent-inversions index-names) out))
              (out (add 'index-bad-anchors (index-anchor-problems index entries) out))
              (out (add 'malformed-index-lines
                        (problem-values 'malformed-index-line problems)
                        out)))
         out)))))
