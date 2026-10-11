;;; (httparse methods): llhttp's method table, judged as pure data.
;;;
;;; THE NUMBERS ARE ASSERTED AGAINST llhttp, NOT AGAINST THIS PARSER. Every
;;; expectation below is read from llhttp's `METHODS` map (`src/llhttp/http.ts`,
;;; assembled from METHODS_HTTP / METHODS_RTSP / METHODS_ICECAST) -- not from a
;;; run of the machine these names configure, which would be the parser grading
;;; its own homework. The grammar lane (`unit.request-line`) still exercises the
;;; same two tables through the machine; this lane is the pure one, the ONE
;;; source both the grammar and an embedder import.
(import (rnrs)
        (httparse test harness)
        (httparse methods))

;; A refusal from this library, distinguished from any other exception: the
;; condition type is its own, so a `&assertion` from a genuine bug in the thunk
;; cannot read as the refusal being tested.
(define (refuses? thunk)
  (call/cc (lambda (k)
             (with-exception-handler
              (lambda (e) (k (httparse-methods-error? e)))
              (lambda () (thunk) #f)))))

;; 0..n as an ascending list, for the density check.
(define (upto n)
  (let loop ((i n) (acc '())) (if (< i 0) acc (loop (- i 1) (cons i acc)))))

(harness-begin "unit.methods")

(harness-group "llhttp's 47 method names"
  (lambda ()
    (harness-case "forty-seven, and no duplicate"
      (lambda ()
        (check-equal "count" (length httparse-method-names) 47)
        ;; A duplicated name would make two methods one and pass every fixture
        ;; that used either -- so it is caught here, on the table itself.
        (check "distinct"
               (let loop ((ns httparse-method-names) (seen '()))
                 (cond ((null? ns) #t)
                       ((member (car ns) seen) #f)
                       (else (loop (cdr ns) (cons (car ns) seen))))))))
    (harness-case "kept in llhttp's own spelling, hyphen and underscore included"
      (lambda ()
        ;; These three are the load-bearing punctuation: `M-SEARCH` is llhttp's
        ;; only quoted key, and `GET_PARAMETER` / `SET_PARAMETER` are RFC 2326's
        ;; underscores. No fixture uses either _PARAMETER name, so the
        ;; plausible hyphenated spelling would pass every other check.
        (check "M-SEARCH" (member "M-SEARCH" httparse-method-names))
        (check "GET_PARAMETER" (member "GET_PARAMETER" httparse-method-names))
        (check "SET_PARAMETER" (member "SET_PARAMETER" httparse-method-names))))))

(harness-group "llhttp's method numbers"
  (lambda ()
    (harness-case "every name has a number and every number a name"
      (lambda ()
        ;; The map was extracted by script, so it gets the two invariants a
        ;; hand-copy could violate. A dropped sub-map shows up as a name with
        ;; no number here rather than in whichever fixture happened to use it.
        (check-equal "names with no number"
                     (filter (lambda (n) (not (assoc n httparse-method-numbers)))
                             httparse-method-names)
                     '())
        (check-equal "numbers with no name"
                     (filter (lambda (row) (not (member (car row) httparse-method-names)))
                             httparse-method-numbers)
                     '())))
    (harness-case "the values are exactly 0..46, no gap and no repeat"
      (lambda ()
        ;; A dense range: a dropped sub-map would leave a hole even if every
        ;; remaining pair were right, and a duplicated value would collide two
        ;; methods onto one number.
        (check-equal "count" (length httparse-method-numbers) 47)
        (check-equal "sorted values"
                     (list-sort < (map cdr httparse-method-numbers))
                     (upto 46))))
    (harness-case "the numbers llhttp pins, spot-checked against its map"
      (lambda ()
        ;; A handful read straight from llhttp: the low HTTP block is dense from
        ;; DELETE, and QUERY is the highest number the map assigns.
        (check-equal "DELETE" (cdr (assoc "DELETE" httparse-method-numbers)) 0)
        (check-equal "GET" (cdr (assoc "GET" httparse-method-numbers)) 1)
        (check-equal "HEAD" (cdr (assoc "HEAD" httparse-method-numbers)) 2)
        (check-equal "POST" (cdr (assoc "POST" httparse-method-numbers)) 3)
        (check-equal "PUT" (cdr (assoc "PUT" httparse-method-numbers)) 4)
        (check-equal "CONNECT" (cdr (assoc "CONNECT" httparse-method-numbers)) 5)
        (check-equal "OPTIONS" (cdr (assoc "OPTIONS" httparse-method-numbers)) 6)
        (check-equal "TRACE" (cdr (assoc "TRACE" httparse-method-numbers)) 7)
        (check-equal "GET_PARAMETER" (cdr (assoc "GET_PARAMETER" httparse-method-numbers)) 41)
        (check-equal "M-SEARCH" (cdr (assoc "M-SEARCH" httparse-method-numbers)) 24)
        (check-equal "QUERY" (cdr (assoc "QUERY" httparse-method-numbers)) 46)))))

(harness-group "httparse-method-number : Symbol -> Nat"
  (lambda ()
    (harness-case "a method symbol becomes llhttp's number"
      (lambda ()
        (check-equal "GET" (httparse-method-number 'GET) 1)
        (check-equal "DELETE" (httparse-method-number 'DELETE) 0)
        ;; The two punctuated names as symbols: underscore and hyphen both
        ;; survive `symbol->string` unchanged, which is what makes them findable.
        (check-equal "GET_PARAMETER" (httparse-method-number 'GET_PARAMETER) 41)
        (check-equal "M-SEARCH" (httparse-method-number 'M-SEARCH) 24)
        (check-equal "QUERY" (httparse-method-number 'QUERY) 46)))
    (harness-case "a symbol llhttp does not declare is refused, not defaulted"
      (lambda ()
        ;; NO DEFAULT. Zero is DELETE, a real method, so a typo read as zero
        ;; would route rather than error -- the one thing this table cannot do.
        (check "a made-up method" (refuses? (lambda () (httparse-method-number 'FROB))))
        ;; Symbols are case-sensitive here, and llhttp's names are upper-case.
        (check "the wrong case" (refuses? (lambda () (httparse-method-number 'get))))
        (check "a string is not a symbol"
               (refuses? (lambda () (httparse-method-number "GET"))))))))

(harness-group "httparse-method-name : Nat -> Symbol"
  (lambda ()
    (harness-case "a number becomes the method symbol llhttp names it"
      (lambda ()
        (check-equal "0" (httparse-method-name 0) 'DELETE)
        (check-equal "1" (httparse-method-name 1) 'GET)
        (check-equal "41" (httparse-method-name 41) 'GET_PARAMETER)
        (check-equal "24" (httparse-method-name 24) 'M-SEARCH)
        (check-equal "46" (httparse-method-name 46) 'QUERY)))
    (harness-case "a number the table never assigns is refused"
      (lambda ()
        (check "one past the end" (refuses? (lambda () (httparse-method-name 47))))
        (check "negative" (refuses? (lambda () (httparse-method-name -1))))
        (check "not an integer" (refuses? (lambda () (httparse-method-name 'GET))))))))

(harness-group "the two accessors are inverse across the whole table"
  (lambda ()
    (harness-case "name . number pairs round-trip both ways"
      (lambda ()
        ;; Walks all 47, so a single mis-wired pair fails here rather than in a
        ;; fixture that happens to use that method.
        (check-equal "a pair the accessors disagree on"
                     (filter
                      (lambda (row)
                        (let ((name (car row)) (num (cdr row)))
                          (not (and (eqv? (httparse-method-number
                                           (string->symbol name))
                                          num)
                                    (eq? (httparse-method-name num)
                                         (string->symbol name))))))
                      httparse-method-numbers)
                     '())))
    (harness-case "number -> name -> number is the identity on 0..46"
      (lambda ()
        (check-equal "n that did not survive the round trip"
                     (filter (lambda (n)
                               (not (eqv? (httparse-method-number
                                           (httparse-method-name n))
                                          n)))
                             (upto 46))
                     '())))))

(harness-finish)
