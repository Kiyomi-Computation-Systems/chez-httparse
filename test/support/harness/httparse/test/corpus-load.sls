;;; (httparse test corpus-load): read vendored corpus files into fixture records.
;;;
;;; A fixture is a `meta` comment, an input block (```http or ```url) and an
;;; expected-trace block (```log). This turns a file's text into records; it
;;; does NOT decode the input -- that is (httparse test corpus-decode), kept
;;; separate so each is judged on its own.
;;;
;;; ASSOCIATION IS BY ORDER, AND THE ORDER IS CHECKED. Upstream's driver pairs
;;; blocks within a markdown section, and five fixtures in this corpus carry
;;; prose between their input and log blocks (four in request/connection.md,
;;; one in response/sample.md) -- so pairing on adjacency silently loses them.
;;; Rather than parse markdown headings, this pairs each input block with the
;;; next log block and REFUSES if that pattern ever breaks: two inputs before a
;;; log, a log with no pending input, or an unterminated fence. The alternation
;;; holds in all 23 vendored files today; the refusal is what keeps a future
;;; refresh from being read wrongly instead of loudly.
;;;
;;; EXPECTATIONS. Upstream expands \t and \f in the expected text, splits on
;;; newline and drops the trailing empty line. A line beginning with "/" is a
;;; regular expression, trimmed and stripped of its delimiters -- two exist,
;;; both in url.md. They are carried as pattern expectations rather than
;;; literals; a consumer that cannot evaluate one must say so rather than
;;; compare it as text, which would pass for the wrong reason.
;;;
;;; META is a flat JSON object of string and boolean values -- the only shapes
;;; the corpus uses (type, pause, noScan, skipBody). Numbers, null and nested
;;; objects are refused rather than approximated.
(library (httparse test corpus-load)
  (export corpus-parse-file
          fixture? fixture-line fixture-title fixture-kind fixture-meta
          fixture-input-text fixture-expected
          fixture-meta-ref
          expectation? expectation-pattern? expectation-text
          corpus-load-error? corpus-load-error-detail
          fixture-init-words fixture-lenient-flags
          ;; exported so the loader's own tests can judge them alone
          corpus-split-lines corpus-parse-meta)
  (import (rnrs))

  ;; fixture-init-words : Fixture -> (Listof Symbol)
  ;; A fixture's `type` meta, split on hyphens. That string names the INIT
  ;; HOOK upstream compiles in -- `-DLLPARSE__TEST_INIT=llhttp__test_init_
  ;; request_lenient_version` -- so its first word is the message kind and
  ;; the rest, after a `lenient` marker, name the flags that hook sets.
  (define (fixture-init-words f)
    (let ((type (fixture-meta-ref f 'type #f)))
      (if (not (string? type))
          '()
          (let ((n (string-length type)))
            (let loop ((i 0) (start 0) (acc '()))
              (cond ((= i n)
                     (reverse (cons (string->symbol (substring type start n)) acc)))
                    ((char=? (string-ref type i) #\-)
                     (loop (+ i 1) (+ i 1)
                           (cons (string->symbol (substring type start i)) acc)))
                    (else (loop (+ i 1) start acc))))))))

  ;; THE NINE `lenient_all` SETS, read out of
  ;; `llhttp__test_init_request_lenient_all`. It does NOT set
  ;; `spaces-after-chunk-size` or `header-value-relaxed`, which is why those
  ;; two have hooks of their own.
  (define corpus-lenient-all
    '(headers chunked-length keep-alive transfer-encoding version
      data-after-close optional-lf-after-cr optional-cr-before-lf
      optional-crlf-after-chunk))

  ;; fixture-lenient-flags : Fixture -> (Listof Symbol)
  ;; The lenient flags a fixture's init hook sets: empty for a strict one, one
  ;; name for a single hook, and nine for `lenient-all`. EXPANDED HERE rather
  ;; than by each caller, because SCOPE and RENAMING both need the same nine,
  ;; and two copies of a list read out of someone else's C are two chances to
  ;; mistype it.
  ;;
  ;; The flag's own name CONTAINS hyphens (`lenient-optional-lf-after-cr`), so
  ;; the words after `lenient` are rejoined rather than read one at a time.
  (define (fixture-lenient-flags f)
    (let ((ws (fixture-init-words f)))
      (if (not (and (pair? ws) (pair? (cdr ws)) (eq? (cadr ws) 'lenient)
                    (pair? (cddr ws))))
          '()
          (let ((name (string->symbol
                       (let join ((ns (cddr ws)) (acc ""))
                         (if (null? ns)
                             acc
                             (join (cdr ns)
                                   (if (string=? acc "")
                                       (symbol->string (car ns))
                                       (string-append acc "-"
                                                      (symbol->string (car ns))))))))))
            (if (eq? name 'all) corpus-lenient-all (list name))))))

  (define-condition-type &corpus-load &error
    make-corpus-load-error corpus-load-error? (detail corpus-load-error-detail))

  (define (load-refuse detail)
    (raise (condition (make-corpus-load-error detail)
                      (make-who-condition 'corpus-parse-file)
                      (make-message-condition detail))))

  (define-record-type fixture
    (fields line title kind meta input-text expected))

  (define-record-type expectation
    (fields pattern? text))

  ;; fixture-meta-ref : Fixture Symbol Any -> Any
  (define (fixture-meta-ref f key default)
    (let ((hit (assq key (fixture-meta f))))
      (if hit (cdr hit) default)))

  ;; corpus-split-lines : String -> (Listof String)
  ;; Splits on LF. A trailing LF yields a final empty string, which callers
  ;; that count lines rely on.
  (define (corpus-split-lines s)
    (let ((n (string-length s)))
      (let loop ((i 0) (start 0) (acc '()))
        (cond ((>= i n) (reverse (cons (substring s start n) acc)))
              ((char=? (string-ref s i) #\linefeed)
               (loop (+ i 1) (+ i 1) (cons (substring s start i) acc)))
              (else (loop (+ i 1) start acc))))))

  (define (string-prefix? prefix s)
    (and (>= (string-length s) (string-length prefix))
         (string=? (substring s 0 (string-length prefix)) prefix)))

  (define (string-suffix? suffix s)
    (and (>= (string-length s) (string-length suffix))
         (string=? (substring s (- (string-length s) (string-length suffix))
                              (string-length s))
                   suffix)))

  (define (whitespace? c)
    (or (char=? c #\space) (char=? c #\tab)
        (char=? c #\return) (char=? c #\linefeed)))

  (define (string-trim s)
    (let* ((n (string-length s))
           (a (let loop ((i 0)) (if (and (< i n) (whitespace? (string-ref s i))) (loop (+ i 1)) i)))
           (b (let loop ((i n)) (if (and (> i a) (whitespace? (string-ref s (- i 1)))) (loop (- i 1)) i))))
      (substring s a b)))

  ;; --- the meta object ------------------------------------------------------
  ;; corpus-parse-meta : String -> (Listof (Pair Symbol Any))
  (define (corpus-parse-meta text)
    (let* ((body (string-trim text))
           (n (string-length body)))
      (unless (and (> n 1) (char=? (string-ref body 0) #\{)
                   (char=? (string-ref body (- n 1)) #\}))
        (load-refuse (string-append "corpus meta is not a JSON object: " text)))
      (let loop ((i 1) (acc '()))
        (let ((i (skip-ws body i n)))
          (cond
           ((>= i (- n 1)) (reverse acc))
           ((char=? (string-ref body i) #\,) (loop (+ i 1) acc))
           ((char=? (string-ref body i) #\")
            (let-values (((key j) (read-json-string body i n)))
              (let ((j (skip-ws body j n)))
                (unless (and (< j n) (char=? (string-ref body j) #\:))
                  (load-refuse (string-append "corpus meta key without a colon: " text)))
                (let-values (((value k) (read-json-value body (skip-ws body (+ j 1) n) n text)))
                  (loop k (cons (cons (string->symbol key) value) acc))))))
           (else (load-refuse (string-append "corpus meta has an unexpected character: " text))))))))

  (define (skip-ws s i n)
    (if (and (< i n) (whitespace? (string-ref s i))) (skip-ws s (+ i 1) n) i))

  (define (read-json-string s i n)
    ;; s[i] is the opening quote
    (let loop ((j (+ i 1)) (acc '()))
      (cond
       ((>= j n) (load-refuse "corpus meta has an unterminated string"))
       ((char=? (string-ref s j) #\\)
        (if (>= (+ j 1) n)
            (load-refuse "corpus meta has a trailing backslash")
            (loop (+ j 2) (cons (string-ref s (+ j 1)) acc))))
       ((char=? (string-ref s j) #\") (values (list->string (reverse acc)) (+ j 1)))
       (else (loop (+ j 1) (cons (string-ref s j) acc))))))

  (define (read-json-value s i n whole)
    (cond
     ((>= i n) (load-refuse (string-append "corpus meta ends mid-value: " whole)))
     ((char=? (string-ref s i) #\") (read-json-string s i n))
     ((and (<= (+ i 4) n) (string=? (substring s i (+ i 4)) "true")) (values #t (+ i 4)))
     ((and (<= (+ i 5) n) (string=? (substring s i (+ i 5)) "false")) (values #f (+ i 5)))
     (else
      ;; Numbers, null and nested objects are refused rather than approximated:
      ;; no fixture uses them, and a wrong reading would be invisible.
      (load-refuse
       (string-append "corpus meta value is neither a string nor a boolean: " whole)))))

  ;; --- expectations ---------------------------------------------------------
  (define (expand-tab-and-formfeed s)
    (let ((n (string-length s)))
      (let loop ((i 0) (acc '()))
        (cond
         ((>= i n) (list->string (reverse acc)))
         ((and (char=? (string-ref s i) #\\) (< (+ i 1) n)
               (char=? (string-ref s (+ i 1)) #\t))
          (loop (+ i 2) (cons #\tab acc)))
         ((and (char=? (string-ref s i) #\\) (< (+ i 1) n)
               (char=? (string-ref s (+ i 1)) #\f))
          (loop (+ i 2) (cons (integer->char #x0C) acc)))
         (else (loop (+ i 1) (cons (string-ref s i) acc)))))))

  (define (make-expectation-line raw)
    (let ((line (expand-tab-and-formfeed raw)))
      (if (string-prefix? "/" line)
          (let ((trimmed (string-trim line)))
            (if (and (>= (string-length trimmed) 2) (string-suffix? "/" trimmed))
                (make-expectation #t (substring trimmed 1 (- (string-length trimmed) 1)))
                (make-expectation #t (substring trimmed 1 (string-length trimmed)))))
          (make-expectation #f line))))

  ;; --- the file -------------------------------------------------------------
  (define meta-open "<!-- meta=")
  (define meta-close "-->")

  ;; corpus-parse-file : String -> (Listof Fixture)
  (define (corpus-parse-file text)
    (let loop ((lines (corpus-split-lines text))
               (lineno 1)
               (title "")
               (pending-meta #f)
               (pending #f)          ; (list line title kind meta input-text)
               (acc '()))
      (if (null? lines)
          (begin
            (when pending
              (load-refuse
               (string-append "corpus file ends with an input block that has no log block, at line "
                              (number->string (car pending)))))
            (reverse acc))
          (let ((line (car lines)))
            (cond
             ;; a heading, kept only for diagnostics
             ((string-prefix? "#" line)
              (loop (cdr lines) (+ lineno 1) (string-trim line) #f pending acc))

             ((and (string-prefix? meta-open line) (string-suffix? meta-close (string-trim line)))
              (let* ((t (string-trim line))
                     (body (substring t (string-length meta-open)
                                      (- (string-length t) (string-length meta-close)))))
                (loop (cdr lines) (+ lineno 1) title (corpus-parse-meta body) pending acc)))

             ((or (string=? (string-trim line) "```http")
                  (string=? (string-trim line) "```url"))
              (when pending
                (load-refuse
                 (string-append "corpus file has two input blocks before a log block, at line "
                                (number->string lineno))))
              (let-values (((body rest consumed) (read-fence (cdr lines) lineno)))
                (loop rest (+ lineno 1 consumed) title #f
                      (list lineno title
                            (if (string=? (string-trim line) "```http") 'http 'url)
                            (or pending-meta '())
                            body)
                      acc)))

             ((string=? (string-trim line) "```log")
              (unless pending
                (load-refuse
                 (string-append "corpus file has a log block with no input block before it, at line "
                                (number->string lineno))))
              (let-values (((body rest consumed) (read-fence (cdr lines) lineno)))
                (let ((expected (map make-expectation-line (drop-last (corpus-split-lines body)))))
                  (loop rest (+ lineno 1 consumed) title #f #f
                        (cons (make-fixture (car pending) (cadr pending) (caddr pending)
                                            (cadddr pending) (car (cddddr pending))
                                            expected)
                              acc)))))

             (else (loop (cdr lines) (+ lineno 1) title pending-meta pending acc)))))))

  ;; Reads to the next bare ``` line. Returns the body text, the remaining
  ;; lines, and how many lines were consumed.
  (define (read-fence lines open-line)
    (let loop ((ls lines) (body '()) (consumed 0))
      (cond
       ((null? ls)
        (load-refuse (string-append "corpus file has an unterminated fence opened at line "
                                    (number->string open-line))))
       ((string=? (string-trim (car ls)) "```")
        (values (join-lines (reverse body)) (cdr ls) (+ consumed 1)))
       (else (loop (cdr ls) (cons (car ls) body) (+ consumed 1))))))

  ;; Every fence body line is re-joined with the LF that separated it, and the
  ;; body keeps its final LF -- the decoder's first pass is defined against a
  ;; block that ends with one.
  (define (join-lines ls)
    (if (null? ls)
        ""
        (let loop ((ls ls) (acc '()))
          (if (null? ls)
              (apply string-append (reverse acc))
              (loop (cdr ls) (cons (string-append (car ls) "\n") acc))))))

  (define (drop-last ls)
    (cond ((null? ls) '())
          ((null? (cdr ls)) '())
          (else (cons (car ls) (drop-last (cdr ls)))))))
