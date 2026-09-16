;;; Emit one of this project's parsers as a checked-in derived artifact.
;;;
;;; Usage:
;;;   chez --libdirs <src>:<generator-src> --script tools/emit-machine.ss \
;;;        --machine message --output src/generated/httparse-message.sls
;;;   chez --libdirs <src>:<generator-src> --script tools/emit-machine.ss \
;;;        --machine url --output src/generated/httparse-url.sls
;;;
;;; This is the ONLY way either artifact is written. `make parser-refresh` runs
;;; it once per machine and `httparse.determinism.generated-artifact.chez.source`
;;; runs it again and compares, so a grammar edit that is not followed by a
;;; refresh reddens rather than shipping an artifact that no longer matches its
;;; source.
;;;
;;; TWO MACHINES AND ONE SCRIPT, because they differ only in which builder is
;;; called. The library each writes is `(generated <machine name>)` -- the
;;; collection is the machine's own name, which the generator chooses -- and
;;; both import `(byte-machine runtime)` and nothing above it.
(import (rnrs) (chezscheme) (httparse grammar) (httparse url-grammar)
        (byte-machine compile))

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
(define which (or (flag-value "--machine") (die "--machine is required")))

;; The export name is the machine's name with `-machine` appended, which is the
;; convention `(generated httparse-message)` already follows.
(define bytes
  (cond ((string=? which "message")
         (render-machine (compile-machine (make-message-machine) '())
                         'httparse-message-machine))
        ((string=? which "url")
         (render-machine (compile-machine (make-url-machine) '())
                         'httparse-url-machine))
        (else (die (string-append "unknown machine " which
                                  " (expected `message` or `url`)")))))

(when (file-exists? out) (delete-file out))
(call-with-port (open-file-output-port out (file-options no-fail))
  (lambda (p) (put-bytevector p bytes)))
(display (string-append "httparse-emit: wrote " (number->string (bytevector-length bytes))
                        " bytes to " out "\n"))
