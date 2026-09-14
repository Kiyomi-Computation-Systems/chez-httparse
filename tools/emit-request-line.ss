;;; Emit the request-line parser as a checked-in derived artifact.
;;;
;;; Usage:
;;;   chez --libdirs <src>:<generator-src> --script tools/emit-request-line.ss \
;;;        --output src/generated/httparse-request-line.sls
;;;
;;; This is the ONLY way the artifact is written. `make parser-refresh` runs it
;;; and `httparse.determinism.request-line.chez.source` runs it again and
;;; compares, so a grammar edit that is not followed by a refresh reddens rather
;;; than shipping an artifact that no longer matches its source.
;;;
;;; The library it writes is `(generated httparse-request-line)` -- the
;;; collection is the machine's own name, which the generator chooses -- and it
;;; imports `(byte-machine runtime)` and nothing above it.
(import (rnrs) (chezscheme) (httparse grammar) (byte-machine compile))

(define (die message)
  (display (string-append "httparse-emit: " message "\n") (current-error-port))
  (exit 2))

(define (flag-value name)
  (let loop ((args (cdr (command-line))))
    (cond ((null? args) #f)
          ((string=? (car args) name)
           (if (null? (cdr args)) (die (string-append name " needs a value")) (cadr args)))
          (else (loop (cdr args))))))

(define out (or (flag-value "--output") (die "--output is required")))

(define bytes
  (render-machine (compile-machine (make-request-line-machine) '())
                  'httparse-request-line-machine))

(when (file-exists? out) (delete-file out))
(call-with-port (open-file-output-port out (file-options no-fail))
  (lambda (p) (put-bytevector p bytes)))
(display (string-append "httparse-emit: wrote " (number->string (bytevector-length bytes))
                        " bytes to " out "\n"))
