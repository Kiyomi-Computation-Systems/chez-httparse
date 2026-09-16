;;; (httparse modes): the two integers an embedder chooses before the first
;;; byte, and llhttp's own numbering for both.
;;;
;;; THIS LIBRARY IS PURE AND DEPENDS ON NOTHING. Not on byte-machine, not on
;;; the generated parser, not on the harness -- it is a table and the
;;; arithmetic over it. That is what lets the three consumers that must agree
;;; import ONE source: the grammar declares the fields, the test harness
;;; builds a parser per fixture, and an embedder writes the `field-initials`
;;; argument. Before byte-machine v0.5.0 the agreement was between a grammar
;;; and a harness that each kept their own list.
;;;
;;; The numbers are llhttp's, not this project's. `lenient_flags` is its
;;; `enum llhttp_lenient_flags` (`src/native/api.c`, `LENIENT_HEADERS = 1 << 0`
;;; onward) and `type` is its `enum llhttp_type`. A caller that already knows
;;; llhttp can pass the integer it already has.
(library (httparse modes)
  (export httparse-lenient-flag-bits httparse-lenient-flag-names
          httparse-lenient-bit httparse-lenient-flags-value
          httparse-lenient-flags-width
          httparse-message-type-names httparse-message-type-value
          httparse-modes-error? httparse-modes-error-detail)
  (import (rnrs))

  (define-condition-type &httparse-modes &error
    make-httparse-modes-error httparse-modes-error?
    (detail httparse-modes-error-detail))

  ;; A NAME WITH NO ROW RAISES; there is no default. A mode silently read as
  ;; "off" is the one failure this table cannot afford, because every strict
  ;; fixture would still pass and only the lenient ones would move.
  (define (refuse who detail)
    (raise (condition (make-httparse-modes-error detail)
                      (make-who-condition who)
                      (make-message-condition detail))))

  ;; llhttp's eleven LENIENT_FLAGS in its own bit order. They correspond
  ;; one-for-one to its `llhttp_set_lenient_*` functions.
  (define httparse-lenient-flag-bits
    '((headers                      1)
      (chunked-length               2)
      (keep-alive                   4)
      (transfer-encoding            8)
      (version                     16)
      (data-after-close            32)
      (optional-lf-after-cr        64)
      (optional-crlf-after-chunk  128)
      (optional-cr-before-lf      256)
      (spaces-after-chunk-size    512)
      (header-value-relaxed      1024)))

  (define httparse-lenient-flag-names (map car httparse-lenient-flag-bits))

  ;; The width the `lenient-flags` field must be declared at for every bit
  ;; above to fit. The grammar declares 16 and a unit case checks it against
  ;; this, so adding a twelfth flag cannot quietly overflow the field.
  (define httparse-lenient-flags-width 16)

  ;; httparse-lenient-bit : Symbol -> Nat
  (define (httparse-lenient-bit name)
    (let ((row (assq name httparse-lenient-flag-bits)))
      (unless row
        (refuse 'httparse-lenient-bit
                (string-append "llhttp declares no lenient flag named "
                               (symbol->string name))))
      (cadr row)))

  ;; httparse-lenient-flags-value : (Listof Symbol) -> Nat
  ;; The integer for `(lenient-flags . N)`. The empty list is 0, which is
  ;; strict -- llhttp's default and this parser's declared initial, so an
  ;; embedder that wants strict parsing may pass this or pass nothing.
  (define (httparse-lenient-flags-value names)
    (unless (list? names)
      (refuse 'httparse-lenient-flags-value "a lenient-flag list, not an atom"))
    (fold-left (lambda (acc name) (bitwise-ior acc (httparse-lenient-bit name)))
               0 names))

  ;; llhttp's `enum llhttp_type`. `both` is llhttp's default and NOT this
  ;; parser's supported mode: its `start_req_or_res` sniffs the first bytes
  ;; and v0.1 does not, so a parser left at `both` errors at the first byte
  ;; rather than guessing.
  (define httparse-message-types '((both 0) (request 1) (response 2)))
  (define httparse-message-type-names (map car httparse-message-types))

  ;; httparse-message-type-value : Symbol -> Nat
  (define (httparse-message-type-value name)
    (let ((row (assq name httparse-message-types)))
      (unless row
        (refuse 'httparse-message-type-value
                (string-append "llhttp declares no message type named "
                               (symbol->string name))))
      (cadr row))))
