;;; (httparse test corpus-decode): the vendored corpus' input decoder.
;;;
;;; A fixture's ```http block is not the bytes the parser sees. Upstream's
;;; driver (test/md-test.ts) applies a fixed sequence of textual transforms
;;; first, and the recorded traces' offsets are measured against the result --
;;; so a decoder that is off by one byte makes every offset in that fixture
;;; wrong, and the failure looks like a parser bug.
;;;
;;; THE PASSES, IN ORDER. Order is load-bearing; each is a separate pass in the
;;; reference and a separate pass here, so no equivalence argument is needed:
;;;
;;;   1. strip exactly ONE newline, at the very end. JS `.replace(/\n$/, '')`
;;;      has no `g` flag and `$` matches only end-of-input. (A regex engine
;;;      whose `$` also matches before a trailing newline strips two, which
;;;      shortens nearly every fixture in this corpus by a byte.)
;;;   2. delete a backslash followed by a line break -- the line continuation
;;;      that lets a fixture wrap without introducing bytes.
;;;   3. normalise every CRLF, CR and LF to CRLF.
;;;   4. expand \r \n \t \f. AFTER pass 3, so a literal \n escape is one LF
;;;      byte and NOT a CRLF -- that difference is the point of the ordering.
;;;   5. expand \xH... -- greedy over hex digits, as the reference's
;;;      /\\x([0-9a-fA-F]+)/ is.
;;;   6. expand \N, \NN, \NNN octal -- greedy up to three digits.
;;;
;;; THE RESULT IS CODE POINTS, THEN UTF-8. Passes 5 and 6 yield a *code point*,
;;; not a byte: the reference builds a JavaScript string and the process
;;; receives it UTF-8 encoded, so `\xff` reaches the parser as the two bytes
;;; C3 BF. This is not a guess. `request/sample.md` records
;;; `off=49 len=8 span[header_value]="<y-diaeresis>Value2"` -- eight bytes for
;;; seven characters -- and across all 253 fixtures the UTF-8 reading produces
;;; no offset exceeding its fixture's length while the raw-byte reading
;;; produces four.
;;;
;;; WHAT IS REFUSED. The reference also evaluates ${...} as JavaScript. No
;;; fixture in the vendored corpus uses it, so decision 0007 item 5 refuses it
;;; rather than implementing it: if upstream adds one, this raises instead of
;;; silently decoding the literal text. A code point that is a surrogate or out
;;; of range is refused for the same reason -- guessing there would differ from
;;; the reference invisibly.
(library (httparse test corpus-decode)
  (export corpus-decode-input
          corpus-decode-error? corpus-decode-error-detail
          ;; exported for the decoder's own tests: each pass is judged alone,
          ;; so a failure names the pass rather than the composition.
          corpus-strip-one-trailing-newline
          corpus-remove-escaped-newlines
          corpus-normalize-newlines
          corpus-expand-char-escapes
          corpus-expand-hex-escapes
          corpus-expand-octal-escapes)
  (import (rnrs))

  (define-condition-type &corpus-decode &error
    make-corpus-decode-error corpus-decode-error?
    (detail corpus-decode-error-detail))

  (define (decode-refuse who detail)
    (raise (condition (make-corpus-decode-error detail)
                      (make-who-condition who)
                      (make-message-condition detail))))

  ;; --- pass 1 ---------------------------------------------------------------
  ;; corpus-strip-one-trailing-newline : String -> String
  (define (corpus-strip-one-trailing-newline s)
    (let ((n (string-length s)))
      (if (and (> n 0) (char=? (string-ref s (- n 1)) #\linefeed))
          (substring s 0 (- n 1))
          s)))

  ;; A line break at index i: returns its length in characters, or 0.
  (define (line-break-length s i n)
    (cond ((>= i n) 0)
          ((and (char=? (string-ref s i) #\return)
                (< (+ i 1) n)
                (char=? (string-ref s (+ i 1)) #\linefeed)) 2)
          ((char=? (string-ref s i) #\return) 1)
          ((char=? (string-ref s i) #\linefeed) 1)
          (else 0)))

  ;; --- pass 2 ---------------------------------------------------------------
  ;; corpus-remove-escaped-newlines : String -> String
  (define (corpus-remove-escaped-newlines s)
    (let ((n (string-length s)))
      (let loop ((i 0) (acc '()))
        (if (>= i n)
            (list->string (reverse acc))
            (let ((c (string-ref s i)))
              (if (char=? c #\\)
                  (let ((brk (line-break-length s (+ i 1) n)))
                    (if (> brk 0)
                        (loop (+ i 1 brk) acc)
                        (loop (+ i 1) (cons c acc))))
                  (loop (+ i 1) (cons c acc))))))))

  ;; --- pass 3 ---------------------------------------------------------------
  ;; corpus-normalize-newlines : String -> String
  (define (corpus-normalize-newlines s)
    (let ((n (string-length s)))
      (let loop ((i 0) (acc '()))
        (if (>= i n)
            (list->string (reverse acc))
            (let ((brk (line-break-length s i n)))
              (if (> brk 0)
                  (loop (+ i brk) (cons #\linefeed (cons #\return acc)))
                  (loop (+ i 1) (cons (string-ref s i) acc))))))))

  ;; --- pass 4 ---------------------------------------------------------------
  ;; One escape letter per call, applied left to right without rescanning the
  ;; replacement -- the reference runs four separate global replaces.
  ;; replace-escape : String Char Char -> String
  (define (replace-escape s letter replacement)
    (let ((n (string-length s)))
      (let loop ((i 0) (acc '()))
        (if (>= i n)
            (list->string (reverse acc))
            (if (and (char=? (string-ref s i) #\\)
                     (< (+ i 1) n)
                     (char=? (string-ref s (+ i 1)) letter))
                (loop (+ i 2) (cons replacement acc))
                (loop (+ i 1) (cons (string-ref s i) acc)))))))

  ;; corpus-expand-char-escapes : String -> String
  (define (corpus-expand-char-escapes s)
    (replace-escape
     (replace-escape
      (replace-escape
       (replace-escape s #\r #\return)
       #\n #\linefeed)
      #\t #\tab)
     #\f (integer->char #x0C)))

  ;; --- code points ----------------------------------------------------------
  (define (code-point->char who value)
    (when (or (> value #x10FFFF)
              (and (>= value #xD800) (<= value #xDFFF)))
      (decode-refuse who
        (string-append "corpus fixture escape is not a scalar value: "
                       (number->string value))))
    (integer->char value))

  (define (hex-digit-value c)
    (cond ((and (char>=? c #\0) (char<=? c #\9)) (- (char->integer c) 48))
          ((and (char>=? c #\a) (char<=? c #\f)) (+ 10 (- (char->integer c) 97)))
          ((and (char>=? c #\A) (char<=? c #\F)) (+ 10 (- (char->integer c) 65)))
          (else #f)))

  (define (octal-digit-value c)
    (and (char>=? c #\0) (char<=? c #\7) (- (char->integer c) 48)))

  ;; --- pass 5 ---------------------------------------------------------------
  ;; corpus-expand-hex-escapes : String -> String
  (define (corpus-expand-hex-escapes s)
    (let ((n (string-length s)))
      (let loop ((i 0) (acc '()))
        (cond
         ((>= i n) (list->string (reverse acc)))
         ((and (char=? (string-ref s i) #\\)
               (< (+ i 1) n)
               (char=? (string-ref s (+ i 1)) #\x)
               (< (+ i 2) n)
               (hex-digit-value (string-ref s (+ i 2))))
          ;; greedy: consume every hex digit, as /[0-9a-fA-F]+/ does
          (let scan ((j (+ i 2)) (value 0))
            (if (and (< j n) (hex-digit-value (string-ref s j)))
                (scan (+ j 1) (+ (* value 16) (hex-digit-value (string-ref s j))))
                (loop j (cons (code-point->char 'corpus-expand-hex-escapes value) acc)))))
         (else (loop (+ i 1) (cons (string-ref s i) acc)))))))

  ;; --- pass 6 ---------------------------------------------------------------
  ;; corpus-expand-octal-escapes : String -> String
  (define (corpus-expand-octal-escapes s)
    (let ((n (string-length s)))
      (let loop ((i 0) (acc '()))
        (cond
         ((>= i n) (list->string (reverse acc)))
         ((and (char=? (string-ref s i) #\\)
               (< (+ i 1) n)
               (octal-digit-value (string-ref s (+ i 1))))
          ;; greedy, but at most three digits: /[0-7]{1,3}/
          (let scan ((j (+ i 1)) (taken 0) (value 0))
            (if (and (< j n) (< taken 3) (octal-digit-value (string-ref s j)))
                (scan (+ j 1) (+ taken 1)
                      (+ (* value 8) (octal-digit-value (string-ref s j))))
                (loop j (cons (code-point->char 'corpus-expand-octal-escapes value) acc)))))
         (else (loop (+ i 1) (cons (string-ref s i) acc)))))))

  ;; --- the whole decoder ----------------------------------------------------
  ;; corpus-decode-input : String -> Bytevector
  (define (corpus-decode-input text)
    (when (substring-present? text "${")
      (decode-refuse 'corpus-decode-input
        "corpus fixture uses the ${...} JavaScript escape, which is refused (decision 0007 item 5)"))
    (string->utf8
     (corpus-expand-octal-escapes
      (corpus-expand-hex-escapes
       (corpus-expand-char-escapes
        (corpus-normalize-newlines
         (corpus-remove-escaped-newlines
          (corpus-strip-one-trailing-newline text))))))))

  (define (substring-present? s sub)
    (let ((n (string-length s)) (m (string-length sub)))
      (let loop ((i 0))
        (cond ((> (+ i m) n) #f)
              ((string=? (substring s i (+ i m)) sub) #t)
              (else (loop (+ i 1))))))))
