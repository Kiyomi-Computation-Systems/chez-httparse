;;; The pinned generator is importable, emits the ABI this repository targets,
;;; and the machines it builds actually run.
;;;
;;; Decision 0005 item 5: "The ABI number is re-read, never remembered. The
;;; slice that wires the submodule asserts the version it finds against the
;;; version it emits, as a check in the tree." This is that check. Decision
;;; 0002's ABI clause went stale unnoticed for three weeks because it lived
;;; only in prose; a lane cannot go stale unnoticed.
;;;
;;; The machine is the smallest one that exercises a byte dispatch, an accept,
;;; a reject and an EOF route. It is NOT the HTTP grammar -- this lane answers
;;; "is the dependency wired up and speaking the ABI we expect", and nothing
;;; about HTTP.
(import (rnrs)
        (httparse test harness)
        (byte-machine graph)
        (byte-machine verify)
        (byte-machine compile)
        (byte-machine interpret)
        (byte-machine runtime))

;; The generated-runtime ABI this repository targets (decision 0015, amending
;; decision 0012 item 1, which amended decision 0005 item 2). Upstream bumped
;; 5 -> 6 for the keyword-table lowering and 6 -> 7 when a pause gained a
;; reason -- the emitted paused-outcome's error slot goes from always-#f to
;; `#f | ParserError`. This lane has named both moves AT THE PIN rather than at
;; load time in some later slice, which is what decision 0005 item 5 is for.
(define expected-abi 7)

(define (substring-at? s i sub)
  (and (<= (+ i (string-length sub)) (string-length s))
       (string=? (substring s i (+ i (string-length sub))) sub)))

(define (find-substring s sub)
  (let loop ((i 0))
    (cond ((> (+ i (string-length sub)) (string-length s)) #f)
          ((substring-at? s i sub) i)
          (else (loop (+ i 1))))))

;; The integer that follows `sub` in `s`, or #f.
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

(define (smoke-machine)
  (make-machine 'abi-smoke 'start '() '() '()
    (list (make-error-declaration 'eof 'unexpected-eof "unexpected end of input" #f)
          (make-error-declaration 'rejected 'unexpected-byte "expected 0x41" #f))
    (list (make-byte-dispatch-node 'start
            (list (make-byte-case (make-exact-byte-matcher #x41)
                                  (make-edge 'accept 'advance) #f))
            (make-edge 'reject 'reexecute) 'eof-stop #f)
          (make-stop-node 'accept #f)
          (make-error-node 'reject 'rejected #f)
          (make-error-node 'eof-stop 'eof #f))
    'eof #f))

(define (rendered)
  (utf8->string (render-machine (compile-machine (smoke-machine) '()) 'smoke-parser)))

(harness-begin "unit.generator-abi")

(harness-group "the pinned generator"
  (lambda ()
    (harness-case "a machine built through the public API verifies and compiles"
      (lambda ()
        (check "compilation-ok?" (compilation-ok? (compile-machine (smoke-machine) '())))))
    (harness-case "the emitted library names the ABI this repository targets"
      (lambda ()
        ;; Read from the emitted text, not remembered. If upstream bumps the
        ;; ABI, this fails here rather than at load time in some later slice.
        (check-equal "abi version"
                     (integer-after (rendered) "(byte-machine-make-compiled-machine ")
                     expected-abi)))
    (harness-case "the emitted library imports the runtime and nothing else above it"
      (lambda ()
        (let ((text (rendered)))
          (check "imports the runtime" (find-substring text "(byte-machine runtime)"))
          (check "does not import the builder" (not (find-substring text "(byte-machine graph)")))
          (check "does not import the compiler" (not (find-substring text "(byte-machine compile)")))
          (check "does not import the verifier" (not (find-substring text "(byte-machine verify)"))))))
    (harness-case "the retired ABI constructors are not emitted"
      (lambda ()
        ;; Decision 0002 targeted /v2, which upstream has since retired to a
        ;; tombstone that refuses every version. Emitting either would mean the
        ;; pin moved somewhere unexpected.
        (let ((text (rendered)))
          (check "no /v1" (not (find-substring text "byte-machine-make-compiled-machine/v1")))
          (check "no /v2" (not (find-substring text "byte-machine-make-compiled-machine/v2"))))))
    (harness-case "emission is byte-identical across two renderings"
      (lambda ()
        (check-equal "deterministic"
                     (render-machine (compile-machine (smoke-machine) '()) 'smoke-parser)
                     (render-machine (compile-machine (smoke-machine) '()) 'smoke-parser))))))

(harness-group "a machine from the pinned generator runs"
  (lambda ()
    (harness-case "the accepted byte stops after one byte"
      (lambda ()
        (let* ((cm (make-interpreted-machine (verify-machine (smoke-machine))))
               (r (parser-feed! (make-parser cm '() #f) (u8-list->bytevector '(#x41)) 0 1)))
          (check-equal "status" (parser-result-status r) 'stopped)
          (check-equal "consumed" (parser-result-consumed r) 1))))
    (harness-case "any other byte is rejected at that byte"
      (lambda ()
        (let* ((cm (make-interpreted-machine (verify-machine (smoke-machine))))
               (r (parser-feed! (make-parser cm '() #f) (u8-list->bytevector '(#x42)) 0 1)))
          (check-equal "status" (parser-result-status r) 'error)
          (check-equal "code" (parser-error-code (parser-result-error r)) 'unexpected-byte)
          (check-equal "offset" (parser-error-offset (parser-result-error r)) 0))))
    (harness-case "end of input before the byte is unexpected-eof"
      (lambda ()
        (let* ((cm (make-interpreted-machine (verify-machine (smoke-machine))))
               (r (parser-finish! (make-parser cm '() #f))))
          (check-equal "status" (parser-result-status r) 'error)
          (check-equal "code" (parser-error-code (parser-result-error r)) 'unexpected-eof))))))

(harness-finish)
