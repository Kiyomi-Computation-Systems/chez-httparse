;;; Report the identity of this Chez runtime for build-time validation.
;;;
;;; Printed as key=value lines so CMake can parse without a shell. The banner is
;;; reported whole rather than pre-parsed: it is the only field that says whether
;;; this is Petite, and discovery needs to make that judgement itself.
;;;
;;; `threaded` is reported but is not a gate. httparse has no threads; the
;;; flag is recorded because portability evidence names the exact runtime that
;;; produced it.
(display "full-version=") (display (scheme-version)) (newline)
(display "machine-type=") (display (machine-type)) (newline)
(display "threaded=") (display (if (threaded?) "yes" "no")) (newline)
(exit 0)
