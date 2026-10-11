;;; Tests for (httparse test corpus-decode): the vendored corpus' input decoder.
;;;
;;; Every case is an input and its expected bytes. Nothing here reads a comment,
;;; a name, or a docstring; the decoder is judged only by what it returns.
;;;
;;; The expected bytes were taken from the reference semantics in upstream's
;;; test/md-test.ts, and the UTF-8 reading of \xHH and \NNN is corroborated by
;;; the corpus itself -- request/sample.md records len=8 for the seven-character
;;; value "<y-diaeresis>Value2".
(import (rnrs)
        (httparse test harness)
        (httparse test corpus-decode))

(define (bv . bytes) (u8-list->bytevector bytes))

(harness-begin "unit.corpus-decode")

(harness-group "pass 1: strip one trailing newline"
  (lambda ()
    (harness-case "strips exactly one newline at the very end"
      (lambda ()
        (check-equal "one" (corpus-strip-one-trailing-newline "a\n") "a")))
    (harness-case "leaves the second trailing newline alone"
      (lambda ()
        ;; The trap this guards against: a regex whose $ also matches before a
        ;; trailing newline strips two, shortening nearly every fixture by a byte.
        (check-equal "two" (corpus-strip-one-trailing-newline "a\n\n") "a\n")))
    (harness-case "leaves a string with no trailing newline alone"
      (lambda ()
        (check-equal "none" (corpus-strip-one-trailing-newline "a") "a")))
    (harness-case "leaves the empty string alone"
      (lambda ()
        (check-equal "empty" (corpus-strip-one-trailing-newline "") "")))
    (harness-case "does not strip a trailing carriage return"
      (lambda ()
        (check-equal "cr" (corpus-strip-one-trailing-newline "a\r") "a\r")))))

(harness-group "pass 2: remove escaped newlines"
  (lambda ()
    (harness-case "a backslash before LF vanishes with the LF"
      (lambda ()
        (check-equal "lf" (corpus-remove-escaped-newlines "ab\\\ncd") "abcd")))
    (harness-case "a backslash before CRLF consumes both"
      (lambda ()
        (check-equal "crlf" (corpus-remove-escaped-newlines "ab\\\r\ncd") "abcd")))
    (harness-case "a backslash before CR consumes the CR"
      (lambda ()
        (check-equal "cr" (corpus-remove-escaped-newlines "ab\\\rcd") "abcd")))
    (harness-case "a backslash before anything else survives"
      (lambda ()
        (check-equal "other" (corpus-remove-escaped-newlines "ab\\ncd") "ab\\ncd")))
    (harness-case "a bare newline is untouched by this pass"
      (lambda ()
        (check-equal "bare" (corpus-remove-escaped-newlines "ab\ncd") "ab\ncd")))))

(harness-group "pass 3: normalize newlines"
  (lambda ()
    (harness-case "LF becomes CRLF"
      (lambda ()
        (check-equal "lf" (corpus-normalize-newlines "a\nb") "a\r\nb")))
    (harness-case "CR becomes CRLF"
      (lambda ()
        (check-equal "cr" (corpus-normalize-newlines "a\rb") "a\r\nb")))
    (harness-case "CRLF stays one CRLF and is not doubled"
      (lambda ()
        (check-equal "crlf" (corpus-normalize-newlines "a\r\nb") "a\r\nb")))
    (harness-case "consecutive breaks each become a CRLF"
      (lambda ()
        (check-equal "blank line" (corpus-normalize-newlines "a\n\nb") "a\r\n\r\nb")))))

(harness-group "pass 4: character escapes"
  (lambda ()
    (harness-case "backslash-r is a carriage return"
      (lambda ()
        (check-equal "r" (corpus-expand-char-escapes "a\\rb") "a\rb")))
    (harness-case "backslash-n is a line feed and NOT a CRLF"
      (lambda ()
        ;; This is why pass 4 runs after pass 3. If the order were reversed, or
        ;; if normalisation ran again afterwards, this would be two bytes.
        (check-equal "n" (corpus-expand-char-escapes "a\\nb") "a\nb")))
    (harness-case "backslash-t is a tab"
      (lambda ()
        (check-equal "t" (corpus-expand-char-escapes "a\\tb") "a\tb")))
    (harness-case "backslash-f is a form feed"
      (lambda ()
        (check-equal "f" (corpus-expand-char-escapes "a\\fb")
                     (string-append "a" (string (integer->char #x0C)) "b"))))))

(harness-group "pass 5: hex escapes"
  (lambda ()
    (harness-case "two hex digits"
      (lambda ()
        (check-equal "x41" (corpus-expand-hex-escapes "\\x41") "A")))
    (harness-case "is greedy over every hex digit that follows"
      (lambda ()
        ;; /[0-9a-fA-F]+/ does not stop at two. 41B is three hex digits.
        (check-equal "x41B" (corpus-expand-hex-escapes "\\x41B")
                     (string (integer->char #x41B)))))
    (harness-case "stops at the first non-hex character"
      (lambda ()
        (check-equal "xffValue"
                     (corpus-expand-hex-escapes "\\xffValue2")
                     (string-append (string (integer->char #xFF)) "Value2"))))
    (harness-case "a backslash-x with no hex digit survives"
      (lambda ()
        (check-equal "no digits" (corpus-expand-hex-escapes "a\\xz") "a\\xz")))))

(harness-group "pass 6: octal escapes"
  (lambda ()
    (harness-case "one digit"
      (lambda ()
        (check-equal "\\1" (corpus-expand-octal-escapes "\\1")
                     (string (integer->char 1)))))
    (harness-case "three digits"
      (lambda ()
        (check-equal "\\033" (corpus-expand-octal-escapes "\\033")
                     (string (integer->char #x1B)))))
    (harness-case "takes at most three digits"
      (lambda ()
        ;; /[0-7]{1,3}/ -- the fourth digit is literal text.
        (check-equal "\\0651" (corpus-expand-octal-escapes "\\0651")
                     (string-append (string (integer->char #o065)) "1"))))
    (harness-case "stops at a non-octal digit"
      (lambda ()
        (check-equal "\\19" (corpus-expand-octal-escapes "\\19")
                     (string-append (string (integer->char 1)) "9"))))))

(harness-group "the whole decoder, to bytes"
  (lambda ()
    (harness-case "the empty block decodes to no bytes"
      (lambda ()
        (check-equal "empty" (corpus-decode-input "") (bv))))
    (harness-case "a one-line block loses its single trailing newline"
      (lambda ()
        (check-equal "a" (corpus-decode-input "a\n") (bv #x61))))
    (harness-case "a blank line survives as CRLF"
      (lambda ()
        (check-equal "a+blank" (corpus-decode-input "a\n\n") (bv #x61 #x0D #x0A))))
    (harness-case "a fixture-shaped request decodes to CRLF framing"
      (lambda ()
        (check-equal "request"
                     (corpus-decode-input "GET /\nHost: x\n\n\n")
                     (bv #x47 #x45 #x54 #x20 #x2F #x0D #x0A
                         #x48 #x6F #x73 #x74 #x3A #x20 #x78 #x0D #x0A
                         #x0D #x0A))))
    (harness-case "a literal backslash-n escape is one LF byte"
      (lambda ()
        (check-equal "esc n" (corpus-decode-input "a\\nb") (bv #x61 #x0A #x62))))
    (harness-case "a bare newline is two bytes"
      (lambda ()
        (check-equal "bare n" (corpus-decode-input "a\nb") (bv #x61 #x0D #x0A #x62))))
    (harness-case "line continuation contributes no bytes"
      (lambda ()
        (check-equal "cont" (corpus-decode-input "ab\\\ncd")
                     (bv #x61 #x62 #x63 #x64))))
    (harness-case "\\xff is the two UTF-8 bytes of U+00FF, not the byte FF"
      (lambda ()
        ;; Corroborated by request/sample.md: len=8 for "<y-diaeresis>Value2".
        (check-equal "xff" (corpus-decode-input "\\xff") (bv #xC3 #xBF))))
    (harness-case "\\325 is the two UTF-8 bytes of U+00D5"
      (lambda ()
        (check-equal "o325" (corpus-decode-input "\\325") (bv #xC3 #x95))))
    (harness-case "\\033 is one byte"
      (lambda ()
        (check-equal "o033" (corpus-decode-input "\\033") (bv #x1B))))))

(harness-group "refusals"
  (lambda ()
    (harness-case "the ${...} JavaScript escape is refused, not decoded"
      (lambda ()
        (check-raises "dollar-brace" corpus-decode-error?
          (lambda () (corpus-decode-input "a${1+1}b")))))
    (harness-case "a hex escape naming a surrogate is refused"
      (lambda ()
        (check-raises "surrogate" corpus-decode-error?
          (lambda () (corpus-decode-input "\\xD800")))))
    (harness-case "a hex escape out of Unicode range is refused"
      (lambda ()
        (check-raises "too large" corpus-decode-error?
          (lambda () (corpus-decode-input "\\x110000")))))
    (harness-case "an ordinary fixture does not raise"
      (lambda ()
        ;; A refusal predicate that fires on everything would make the three
        ;; cases above pass regardless, so this pins the other side.
        (check-equal "ordinary" (corpus-decode-input "GET /\n\n") 
                     (bv #x47 #x45 #x54 #x20 #x2F #x0D #x0A))))))

(harness-finish)
