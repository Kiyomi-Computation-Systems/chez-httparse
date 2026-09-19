;;; (httparse methods): llhttp's method table -- the 47 names it matches on a
;;; request line and the number it prints for each -- as pure data any consumer
;;; can read at RUN time.
;;;
;;; THIS LIBRARY IS PURE AND DEPENDS ON NOTHING. Not on byte-machine, not on the
;;; generated parser, not on the harness -- it is two tables and the arithmetic
;;; over them. That is what lets the consumers that must agree import ONE source
;;; rather than each keeping a copy: the grammar builds the byte matcher from
;;; these names and stores the number, and an embedder that routes on a method
;;; symbol or logs a method number reads the same two tables. `(httparse modes)`
;;; is threaded into the grammar the same way, for the same reason.
;;;
;;; THE NAMES AND NUMBERS ARE llhttp's, NOT THIS PROJECT'S. The number is the
;;; method's value in llhttp's own `METHODS` map -- what `headers complete`
;;; prints as `method=%d` -- and NOT its position in the alphabetical name list.
;;; A caller that already holds llhttp's integer can pass it to
;;; `httparse-method-name`; one that holds a symbol can pass it to
;;; `httparse-method-number`.
(library (httparse methods)
  (export httparse-method-names httparse-method-numbers
          httparse-method-name httparse-method-number
          httparse-methods-error? httparse-methods-error-detail)
  (import (rnrs))

  ;; A refusal from this library, its own condition type so a `&assertion` from
  ;; an unrelated bug cannot read as the refusal a caller is testing for --
  ;; exactly as `(httparse modes)` does. A method silently read as the wrong
  ;; number is the one failure this table cannot afford: `0` is DELETE, so a
  ;; routing typo defaulting to zero would route to a real method, not an error.
  (define-condition-type &httparse-methods &error
    make-httparse-methods-error httparse-methods-error?
    (detail httparse-methods-error-detail))

  (define (refuse who detail)
    (raise (condition (make-httparse-methods-error detail)
                      (make-who-condition who)
                      (make-message-condition detail))))

  ;; The 47 names llhttp matches, RTSP and HTTP/2 included: its `METHODS` map is
  ;; the union of METHODS_HTTP, METHODS_RTSP and METHODS_ICECAST. The grammar
  ;; matches the method against this TABLE, not against `1*tchar`, which is why
  ;; `MKCOLA` closes its span at `MKCOL` and then fails rather than being taken
  ;; whole. Kept in llhttp's own `M-SEARCH` / `GET_PARAMETER` spelling -- the
  ;; hyphen and the underscore are load-bearing, so these are the exact strings
  ;; the byte matcher and the symbol accessors below round-trip through.
  (define httparse-method-names
    '("ACL" "ANNOUNCE" "BIND" "CHECKOUT" "CONNECT" "COPY" "DELETE" "DESCRIBE"
      "FLUSH" "GET" "GET_PARAMETER" "HEAD" "LINK" "LOCK" "M-SEARCH" "MERGE"
      "MKACTIVITY" "MKCALENDAR" "MKCOL" "MOVE" "NOTIFY" "OPTIONS" "PATCH"
      "PAUSE" "PLAY" "POST" "PRI" "PROPFIND" "PROPPATCH" "PURGE" "PUT" "QUERY"
      "REBIND" "RECORD" "REDIRECT" "REPORT" "SEARCH" "SET_PARAMETER" "SETUP"
      "SOURCE" "SUBSCRIBE" "TEARDOWN" "TRACE" "UNBIND" "UNLINK" "UNLOCK"
      "UNSUBSCRIBE"))

  ;; THE NUMBER llhttp PRINTS. `headers complete` carries `method=%d`, and the
  ;; number is the method's value in llhttp's own `METHODS` map -- NOT its
  ;; position in the list above, which is alphabetical. The map is assembled
  ;; from eight sub-maps with explicit values and one alias, so the pairs are
  ;; extracted by script and given two invariants to violate: the key set must
  ;; equal `httparse-method-names`, and the values must be exactly 0..46 with no
  ;; gap or repeat. The unit lane checks both; the conformance corpus is the
  ;; third and strongest check, since sixteen fixtures print a method span and a
  ;; `method=` on the same trace.
  (define httparse-method-numbers
    '(("ACL" . 19) ("ANNOUNCE" . 36) ("BIND" . 16) ("CHECKOUT" . 22)
      ("CONNECT" . 5) ("COPY" . 8) ("DELETE" . 0) ("DESCRIBE" . 35)
      ("FLUSH" . 45) ("GET" . 1) ("GET_PARAMETER" . 41) ("HEAD" . 2)
      ("LINK" . 31) ("LOCK" . 9) ("M-SEARCH" . 24) ("MERGE" . 23)
      ("MKACTIVITY" . 21) ("MKCALENDAR" . 30) ("MKCOL" . 10) ("MOVE" . 11)
      ("NOTIFY" . 25) ("OPTIONS" . 6) ("PATCH" . 28) ("PAUSE" . 39)
      ("PLAY" . 38) ("POST" . 3) ("PRI" . 34) ("PROPFIND" . 12)
      ("PROPPATCH" . 13) ("PURGE" . 29) ("PUT" . 4) ("QUERY" . 46)
      ("REBIND" . 17) ("RECORD" . 44) ("REDIRECT" . 43) ("REPORT" . 20)
      ("SEARCH" . 14) ("SET_PARAMETER" . 42) ("SETUP" . 37) ("SOURCE" . 33)
      ("SUBSCRIBE" . 26) ("TEARDOWN" . 40) ("TRACE" . 7) ("UNBIND" . 18)
      ("UNLINK" . 32) ("UNLOCK" . 15) ("UNSUBSCRIBE" . 27)))

  ;; httparse-method-number : Symbol -> Nat
  ;; The number llhttp assigns a method named as a SYMBOL ('GET, 'GET_PARAMETER,
  ;; 'M-SEARCH -- llhttp's own spelling, and symbols are case-sensitive here).
  ;; Refuses -- never defaults -- a symbol llhttp does not declare, so a routing
  ;; typo cannot read as method 0 (DELETE) and slip past.
  (define (httparse-method-number name)
    (unless (symbol? name)
      (refuse 'httparse-method-number "a method name is a symbol"))
    (let ((row (assoc (symbol->string name) httparse-method-numbers)))
      (unless row
        (refuse 'httparse-method-number
                (string-append "llhttp declares no method named "
                               (symbol->string name))))
      (cdr row)))

  ;; httparse-method-name : Nat -> Symbol
  ;; The inverse: the method llhttp numbers `n`, as a symbol for routing and
  ;; logging. Refuses an `n` that is not one of the dense 0..46 the table
  ;; assigns, rather than returning #f a caller might route on.
  (define (httparse-method-name n)
    (unless (and (integer? n) (exact? n) (>= n 0))
      (refuse 'httparse-method-name "a method number is a non-negative exact integer"))
    (let loop ((rows httparse-method-numbers))
      (cond ((null? rows)
             (refuse 'httparse-method-name
                     (string-append "llhttp assigns no method the number "
                                    (number->string n))))
            ((eqv? (cdar rows) n) (string->symbol (caar rows)))
            (else (loop (cdr rows)))))))
