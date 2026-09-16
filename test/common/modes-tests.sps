;;; (httparse modes): llhttp's two mode tables, judged as pure data.
;;;
;;; THE NUMBERS ARE ASSERTED AGAINST llhttp, NOT AGAINST THIS PARSER. Every
;;; expectation below is read from `src/llhttp/constants.ts`
;;; (`enum LENIENT_FLAGS`, bits 0 through 10) and `include/llhttp.h`
;;; (`enum llhttp_type`) -- not from a run of the machine these numbers
;;; configure, which would be the parser grading its own homework.
;;;
;;; This table is the ONE source three consumers read: the grammar places a
;;; branch on a bit, the harness builds a parser per fixture, and an embedder
;;; writes the initials. A lane on the table itself is what lets the other
;;; three stop carrying copies.
(import (rnrs)
        (httparse test harness)
        (httparse modes))

;; A refusal from this library, distinguished from any other exception: the
;; condition type is its own, so a `&assertion` from a genuine bug in the
;; thunk cannot read as the refusal being tested.
(define (refuses? thunk)
  (call/cc (lambda (k)
             (with-exception-handler
              (lambda (e) (k (httparse-modes-error? e)))
              (lambda () (thunk) #f)))))

(harness-begin "unit.modes")

(harness-group "llhttp's LENIENT_FLAGS"
  (lambda ()
    (harness-case "eleven flags, in llhttp's own bit order"
      (lambda ()
        (check-equal "count" (length httparse-lenient-flag-bits) 11)
        (check-equal "the names, in order"
                     httparse-lenient-flag-names
                     '(headers chunked-length keep-alive transfer-encoding
                       version data-after-close optional-lf-after-cr
                       optional-crlf-after-chunk optional-cr-before-lf
                       spaces-after-chunk-size header-value-relaxed))))
    (harness-case "each is 1 << its position, and no two share a bit"
      (lambda ()
        ;; `LENIENT_HEADERS = 1 << 0` onward. A duplicated bit would make two
        ;; flags one flag, and every fixture typed for either would still
        ;; pass -- which is why this is checked here and not left to a trace.
        (let loop ((names httparse-lenient-flag-names) (i 0) (seen 0))
          (if (null? names)
              (check-equal "the union is 2^11 - 1" seen 2047)
              (let ((bit (httparse-lenient-bit (car names))))
                (check-equal (symbol->string (car names)) bit (expt 2 i))
                (check "not already taken" (zero? (bitwise-and seen bit)))
                (loop (cdr names) (+ i 1) (bitwise-ior seen bit)))))))
    (harness-case "every bit fits the width the field is declared at"
      (lambda ()
        ;; The grammar declares `lenient-flags` at this width, so the check
        ;; is that the table cannot outgrow its own field: a twelfth flag
        ;; added here without widening the field is caught before the
        ;; generated parser silently truncates an override.
        (check "width is one the generator accepts"
               (memv httparse-lenient-flags-width '(8 16 32 64)))
        (check "every combination is representable"
               (< (httparse-lenient-flags-value httparse-lenient-flag-names)
                  (expt 2 httparse-lenient-flags-width)))))
    (harness-case "a list of names becomes the integer llhttp would write"
      (lambda ()
        (check-equal "none is strict" (httparse-lenient-flags-value '()) 0)
        (check-equal "one" (httparse-lenient-flags-value '(version)) 16)
        ;; `lenient_all` sets nine of the eleven, and three fixtures use it.
        (check-equal "two, or'd"
                     (httparse-lenient-flags-value '(headers version)) 17)
        (check-equal "order does not matter"
                     (httparse-lenient-flags-value '(header-value-relaxed headers))
                     (httparse-lenient-flags-value '(headers header-value-relaxed)))
        ;; `|=` is idempotent over there; so is this.
        (check-equal "a repeat is not a double"
                     (httparse-lenient-flags-value '(version version)) 16)))
    (harness-case "a name llhttp does not declare is refused, not zero"
      (lambda ()
        ;; NO DEFAULT. A typo read as "off" would leave every strict fixture
        ;; passing and only the lenient ones moving -- a diff that names the
        ;; version rather than the table.
        (check "a near miss"
               (refuses? (lambda () (httparse-lenient-bit 'versions))))
        (check "llhttp's own spelling, which is not ours"
               (refuses? (lambda () (httparse-lenient-bit 'lenient_version))))
        (check "inside a list"
               (refuses? (lambda () (httparse-lenient-flags-value '(version nope)))))
        (check "not a list at all"
               (refuses? (lambda () (httparse-lenient-flags-value 'version))))))))

(harness-group "llhttp's enum llhttp_type"
  (lambda ()
    (harness-case "the three numbers llhttp uses"
      (lambda ()
        (check-equal "HTTP_BOTH" (httparse-message-type-value 'both) 0)
        (check-equal "HTTP_REQUEST" (httparse-message-type-value 'request) 1)
        (check-equal "HTTP_RESPONSE" (httparse-message-type-value 'response) 2)
        (check-equal "and no fourth" (length httparse-message-type-names) 3)))
    (harness-case "`both` is declared here and unsupported by the grammar"
      (lambda ()
        ;; It is in the table because it is the field's DECLARED initial --
        ;; the value a parser told nothing starts at, and the one the
        ;; grammar routes to `unexpected-message-type`. Leaving it out would
        ;; make that initial a number with no name.
        (check "named" (memq 'both httparse-message-type-names))
        (check-equal "and it is the zero" (httparse-message-type-value 'both) 0)))
    (harness-case "a kind llhttp does not declare is refused"
      (lambda ()
        (check "a near miss"
               (refuses? (lambda () (httparse-message-type-value 'requests))))
        (check "a lenient flag is not a type"
               (refuses? (lambda () (httparse-message-type-value 'version))))))))

(harness-finish)
