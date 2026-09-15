;;; Lenient modes: the eleven questions the embedder is asked once.
;;;
;;; Upstream decides these before the first byte. `test/md-test.ts` turns a
;;; fixture's type into `-DLLPARSE__TEST_INIT=llhttp__test_init_<type>`, and
;;; that hook writes both halves at once:
;;;
;;;   void llhttp__test_init_request_lenient_version(llparse_t* s) {
;;;     llhttp__test_init_request(s);
;;;     s->lenient_flags |= LENIENT_VERSION;
;;;   }
;;;
;;; A PARSER HERE CANNOT BE STARTED IN A MODE. `make-parser` fills every field
;;; from the machine's declarations and `parser-field-ref` has no mutating
;;; sibling, so each flag arrives as an OPTIONAL decision callback the machine
;;; asks before `start`. Unbound means the declared default, which is strict —
;;; which is why the 216 strict fixtures need no lenient binding at all, and
;;; why a default that stopped meaning strict would break all of them.
;;;
;;; THE ASKS RUN ONCE PER PARSER, NOT ONCE PER MESSAGE. They are the machine's
;;; ENTRY, ahead of `start`; the restart between two messages re-enters at
;;; `start`, below them. No fixture pipelines a lenient message, so the case
;;; that says so is here rather than in the corpus.
(import (rnrs)
        (httparse test harness)
        (httparse test adapter)
        (httparse test drive)
        (httparse test trace-format)
        (httparse grammar)
        (byte-machine verify)
        (byte-machine interpret)
        (byte-machine runtime))

(define machine
  (make-interpreted-machine (verify-machine (make-message-machine))))

;; trace : Init String -> (Listof String)
(define (trace init input)
  (let* ((r (make-trace-recorder))
         (p (make-parser machine (trace-recorder-bindings r init #f) #f))
         (bv (string->utf8 input))
         (refused
          (call/cc
           (lambda (k)
             (with-exception-handler
              (lambda (e) (if (adapter-error? e) (k #t) (raise e)))
              (lambda ()
                (let ((res (drive-feed! r p bv 0 (bytevector-length bv))))
                  (when (eq? (parser-result-status res) 'error)
                    (trace-recorder-note-error! r (parser-result-error res)))
                  #f)))))))
    (append (map utf8->string (trace-format (trace-recorder-events r)))
            (if refused '("(refused)") '()))))

(harness-begin "unit.lenient")

(harness-group "the same bytes, strict and lenient"
  (lambda ()
    (harness-case "a version no pair accepts is an error when strict"
      (lambda ()
        ;; request/invalid.md, "Invalid HTTP version", copied entire. The
        ;; span is delivered and the error lands PAST the minor digit.
        (check-equal "the fixture's own trace"
                     (trace '(request) "GET / HTTP/5.6\r\n")
                     '("off=0 message begin"
                       "off=0 len=3 span[method]=\"GET\""
                       "off=3 method complete"
                       "off=4 len=1 span[url]=\"/\""
                       "off=6 url complete"
                       "off=6 len=4 span[protocol]=\"HTTP\""
                       "off=10 protocol complete"
                       "off=11 len=3 span[version]=\"5.6\""
                       "off=14 error code=9 reason=\"Invalid HTTP version\""))))
    (harness-case "and is parsed, and PRINTED, when the flag is on"
      (lambda ()
        ;; request/lenient-version.md, copied entire. `v=5/6` is the half a
        ;; store-then-check version subgraph exists for: a digit belonging to
        ;; no accepted pair still has to reach the headers-complete line.
        (check-equal "the fixture's own trace"
                     (trace '(request version) "GET / HTTP/5.6\r\n\r\n")
                     '("off=0 message begin"
                       "off=0 len=3 span[method]=\"GET\""
                       "off=3 method complete"
                       "off=4 len=1 span[url]=\"/\""
                       "off=6 url complete"
                       "off=6 len=4 span[protocol]=\"HTTP\""
                       "off=10 protocol complete"
                       "off=11 len=3 span[version]=\"5.6\""
                       "off=14 version complete"
                       "off=18 headers complete method=1 v=5/6 flags=0 content_length=0"
                       "off=18 message complete"))))
    (harness-case "a response reads the same flag"
      (lambda ()
        ;; response/lenient-version.md. One version subgraph serves both
        ;; start lines, so one flag test serves both too.
        (check-equal "status=200 v=5/6"
                     (list-tail (trace '(response version) "HTTP/5.6 200 OK\r\n\r\n") 7)
                     '("off=19 headers complete status=200 v=5/6 flags=0 content_length=0"))))
    (harness-case "another flag does not turn this one on"
      (lambda ()
        ;; THE CASE THAT STOPS ONE ASK ANSWERING FOR ALL ELEVEN. A chain that
        ;; set every bit, or read the wrong one, would pass both cases above.
        (check-equal "still the strict error"
                     (list-tail (trace '(request headers) "GET / HTTP/5.6\r\n") 8)
                     '("off=14 error code=9 reason=\"Invalid HTTP version\""))))))

(harness-group "the asks happen once, ahead of everything"
  (lambda ()
    (harness-case "the flag survives the restart between two messages"
      (lambda ()
        ;; NO FIXTURE PIPELINES A LENIENT MESSAGE. If the ask chain sat inside
        ;; the message loop the embedder would be asked again; if the flag
        ;; lived in `flags` the restart would store zero over it. Either way
        ;; the SECOND message would be strict, and this is what says it is
        ;; not.
        (let ((ls (trace '(request version)
                         (string-append "GET / HTTP/5.6\r\n\r\n"
                                        "GET / HTTP/5.6\r\n\r\n"))))
          (check-equal "both messages complete"
                       (length (filter (lambda (l) (string=? l "off=18 message complete"))
                                       ls))
                       1)
          (check-equal "the second is lenient too"
                       (list-tail ls (- (length ls) 2))
                       '("off=36 headers complete method=1 v=5/6 flags=0 content_length=0"
                         "off=36 message complete")))))
    (harness-case "the embedder is asked once, however many messages arrive"
      (lambda ()
        ;; THE CLAIM THE FOURTH UPSTREAM BRIEF MAKES, as a count rather than
        ;; a comment. The asks are idempotent, so a chain that ran per message
        ;; would produce IDENTICAL traces -- the only thing that changes is
        ;; how often the embedder is asked, and nothing but a count can see
        ;; it. Moving the chain into the restart is caught here and nowhere
        ;; else.
        (let* ((asked 0)
               (r (make-trace-recorder))
               (bindings
                (cons (list 'on-lenient-version
                            (lambda (p ctx) (set! asked (+ asked 1)) 'yes))
                      (trace-recorder-bindings r '(request) #f)))
               (p (make-parser machine bindings #f))
               (bv (string->utf8 (string-append "GET / HTTP/5.6\r\n\r\n"
                                                "GET / HTTP/5.6\r\n\r\n"
                                                "GET / HTTP/5.6\r\n\r\n"))))
          (parser-feed! p bv 0 (bytevector-length bv))
          (check-equal "three messages parsed"
                       (length (filter (lambda (l)
                                         (and (> (string-length l) 16)
                                              (string=? (substring l (- (string-length l) 16)
                                                                   (string-length l))
                                                        "message complete")))
                                       (map utf8->string
                                            (trace-format (trace-recorder-events r)))))
                       3)
          (check-equal "asked once" asked 1))))
    (harness-case "no lenient binding at all is the strict parser"
      (lambda ()
        ;; The default path, named. Every one of the 216 strict fixtures runs
        ;; this way -- with no lenient callback bound and the machine taking
        ;; each declared default -- so it is already the most-exercised path
        ;; in the tree; what it has not had is a case that says so.
        (check-equal "strict"
                     (list-tail (trace '(request) "GET / HTTP/5.6\r\n") 8)
                     '("off=14 error code=9 reason=\"Invalid HTTP version\""))))))

;;; This one is not about a trace. It is the property the fourth upstream
;;; brief now cites, and a brief that cites a measurement this tree does not
;;; keep is a claim with nothing behind it.
(harness-group "a reset re-asks rather than forgetting"
  (lambda ()
    (harness-case "the mode is restored by being asked again"
      (lambda ()
        ;; `parser-reset!` restores every field to its DECLARED initial, so
        ;; the mode field goes back to zero -- and the next feed re-enters the
        ;; machine's entry, which is the ask chain, and sets it again. The
        ;; chain's position is what makes that true: inside the message loop
        ;; it would be re-asked per message, and after `start` it would never
        ;; be re-asked at all.
        (let* ((r (make-trace-recorder))
               (p (make-parser machine
                               (trace-recorder-bindings r '(request version) #f) #f))
               (bv (string->utf8 "GET / HTTP/5.6\r\n\r\n"))
               (read-flags (lambda () (parser-field-ref p 'lenient-flags))))
          (check-equal "nothing is set before the first feed" (read-flags) 0)
          (parser-feed! p bv 0 (bytevector-length bv))
          (check-equal "the ask set it" (read-flags) 16)
          (parser-reset! p)
          (check-equal "the reset cleared it" (read-flags) 0)
          (let ((res (parser-feed! p bv 0 (bytevector-length bv))))
            (check-equal "and the re-ask set it again" (read-flags) 16)
            ;; The half that matters to an embedder: the second parse is
            ;; still lenient, so `HTTP/5.6` does not become an error.
            (check "the reset parser is still lenient"
                   (not (eq? (parser-result-status res) 'error)))))))))

(harness-finish)
