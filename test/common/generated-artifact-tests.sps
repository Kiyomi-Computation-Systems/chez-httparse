;;; The checked-in generated parsers are fresh, deterministic, self-contained.
;;;
;;; `src/generated/httparse-message.sls` and `src/generated/httparse-url.sls`
;;; are DERIVED artifacts: emitted from `(httparse grammar)` and
;;; `(httparse url-grammar)` by `tools/emit-machine.ss` and committed so that
;;; what this project ships is reviewable as a diff and loadable without a
;;; generator. A derived file in the tree is a file that can silently stop
;;; describing its source, so this lane re-emits and compares BYTES.
;;;
;;; BOTH ARE CHECKED IN ONE LANE on purpose: one `make parser-refresh` writes
;;; both, so a lane per artifact would let a refresh that only reached one of
;;; them pass half the time.
;;;
;;; It is deliberately not a test of the parser's behaviour. The artifact's own
;;; code is exercised by the conformance lanes, which run IT rather than a
;;; re-derivation from the grammar -- otherwise an emitter that wrote a
;;; wrong-but-well-formed artifact would survive, because nothing read what it
;;; wrote.
(import (rnrs)
        (httparse test harness)
        (httparse grammar)
        (httparse url-grammar)
        (byte-machine compile))

(define artifact-path (adapter-environment-variable "HTTPARSE_GENERATED_PARSER"))
(define url-artifact-path (adapter-environment-variable "HTTPARSE_GENERATED_URL_PARSER"))

(define (read-bytes path)
  (call-with-port (open-file-input-port path) get-bytevector-all))

(define (emit)
  (render-machine (compile-machine (make-message-machine) '())
                  'httparse-message-machine))

(define (emit-url)
  (render-machine (compile-machine (make-url-machine) '())
                  'httparse-url-machine))

(define committed (read-bytes artifact-path))
(define url-committed (read-bytes url-artifact-path))

(define (text) (utf8->string committed))
(define (url-text) (utf8->string url-committed))

(define (find-substring s sub)
  (let ((n (string-length s)) (m (string-length sub)))
    (let loop ((i 0))
      (cond ((> (+ i m) n) #f)
            ((string=? (substring s i (+ i m)) sub) i)
            (else (loop (+ i 1)))))))

(define (integer-after s sub)
  (let ((at (find-substring s sub)))
    (and at
         (let* ((start (+ at (string-length sub)))
                (end (let scan ((j start))
                       (if (and (< j (string-length s))
                                (char<=? #\0 (string-ref s j))
                                (char<=? (string-ref s j) #\9))
                           (scan (+ j 1))
                           j))))
           (and (> end start) (string->number (substring s start end)))))))

(harness-begin "determinism.generated-artifact")

(harness-group "the committed artifact still describes the grammar"
  (lambda ()
    (harness-case "re-emitting reproduces it byte for byte"
      (lambda ()
        ;; If this fails the grammar moved and the artifact did not:
        ;;   make parser-refresh
        (check-equal "bytes" (emit) committed)))
    (harness-case "emission is deterministic across two runs in one process"
      (lambda ()
        (check-equal "two renders" (emit) (emit))))))

(harness-group "the artifact is what a consumer can load"
  (lambda ()
    (harness-case "it imports the runtime and nothing above it"
      (lambda ()
        (let ((s (text)))
          (check "imports the runtime" (find-substring s "(byte-machine runtime)"))
          (check "not the builder" (not (find-substring s "(byte-machine graph)")))
          (check "not the compiler" (not (find-substring s "(byte-machine compile)")))
          (check "not the verifier" (not (find-substring s "(byte-machine verify)")))
          (check "not the interpreter" (not (find-substring s "(byte-machine interpret)"))))))
    (harness-case "it names the generated ABI this repository targets"
      (lambda ()
        ;; Read out of the committed text, not remembered -- the same rule
        ;; decision 0005 item 5 puts on the generator lane, applied to the
        ;; artifact that actually ships.
        (check-equal "abi"
                     (integer-after (text) "(byte-machine-make-compiled-machine ")
                     9)))
    (harness-case "it is the library the conformance lanes import"
      (lambda ()
        (let ((s (text)))
          (check "library name" (find-substring s "(library (generated httparse-message)"))
          (check "export" (find-substring s "(export httparse-message-machine)")))))))

(harness-group "and so does the url sub-parser's"
  (lambda ()
    (harness-case "re-emitting reproduces it byte for byte"
      (lambda ()
        ;; If this fails the url grammar moved and the artifact did not:
        ;;   make parser-refresh
        (check-equal "bytes" (emit-url) url-committed)))
    (harness-case "emission is deterministic across two runs in one process"
      (lambda ()
        (check-equal "two renders" (emit-url) (emit-url))))
    (harness-case "it imports the runtime and nothing above it"
      (lambda ()
        (let ((s (url-text)))
          (check "imports the runtime" (find-substring s "(byte-machine runtime)"))
          (check "not the builder" (not (find-substring s "(byte-machine graph)")))
          (check "not the compiler" (not (find-substring s "(byte-machine compile)")))
          (check "not the verifier" (not (find-substring s "(byte-machine verify)")))
          (check "not the interpreter" (not (find-substring s "(byte-machine interpret)"))))))
    (harness-case "it names the same ABI as its sibling"
      (lambda ()
        ;; One pin, one ABI. Two artifacts emitted at two versions would be a
        ;; build that ran the emitter twice against two trees.
        (check-equal "abi"
                     (integer-after (url-text) "(byte-machine-make-compiled-machine ")
                     9)))
    (harness-case "it is a DIFFERENT library, not a second copy of the first"
      (lambda ()
        (let ((s (url-text)))
          (check "library name" (find-substring s "(library (generated httparse-url)"))
          (check "export" (find-substring s "(export httparse-url-machine)"))
          ;; The two machines share no state and no callback. A url artifact
          ;; naming a message callback would mean the emitter was handed the
          ;; wrong builder -- which a byte comparison alone would not say,
          ;; since it would then match its own re-emission perfectly.
          (check "no message callback"
                 (not (find-substring s "on-header-field-data")))
          (check "its own spans"
                 (find-substring s "on-url-schema-data")))))))

(harness-finish)
