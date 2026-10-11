;;; The `upgrade` field: llhttp's `llhttp_get_upgrade`, read by an embedder.
;;;
;;; `docs/pausing.md` lists `upgrade` among the fields `parser-field-ref` reads, as
;;; the answer llhttp gives through `llhttp_get_upgrade`. This lane holds the
;;; COMMITTED parser to that, because the trace cannot: no callback line prints
;;; the field, and on a 101 nothing inside the machine reads it either (the
;;; body decision pauses a 101 by its own route), so a wrong value there
;;; survives every conformance lane.
;;;
;;; THE EXPECTATION COMES FROM THE FIXTURE, NOT FROM THIS PARSER. Every
;;; `headers complete` line in a log records the method or status and the flags
;;; llhttp held when it called `on_headers_complete`. `upgrade` is a function of
;;; exactly those, written by `llhttp__before_headers_complete`
;;; (`src/native/http.c:11-26`, v9.4.3):
;;;
;;;   both UPGRADE and CONNECTION_UPGRADE   ->  request, or status 101
;;;   otherwise                             ->  method is CONNECT
;;;
;;; so the expected value of each call is that rule applied to the oracle's own
;;; numbers. For requests a second, independent oracle agrees: the fixtures
;;; where some call expects 1 are exactly the fixtures whose logs record
;;; `Pause on CONNECT/Upgrade`.
;;;
;;; The lifetime cases at the end have no fixture -- the corpus never resumes
;;; and never resets. Their numbers were measured against llhttp built from
;;; `v9.4.3-1-gee51043`, the checkout the corpus came from, calling
;;; `llhttp_get_upgrade` from each callback.
(import (rnrs)
        (httparse test harness)
        (httparse test corpus-load)
        (httparse test corpus-decode)
        (httparse decisions)
        (httparse methods)
        (httparse modes)
        (generated httparse-message)
        (byte-machine runtime))

(define (read-text path)
  (utf8->string (call-with-port (open-file-input-port path) get-bytevector-all)))

(define corpus-dir (adapter-environment-variable "HTTPARSE_CORPUS_DIR"))

(define request-files
  '("request/connection.md" "request/content-length.md" "request/finish.md"
    "request/invalid.md" "request/lenient-header-value-relaxed.md"
    "request/lenient-headers.md" "request/lenient-version.md" "request/method.md"
    "request/pausing.md" "request/pipelining.md" "request/sample.md"
    "request/transfer-encoding.md" "request/uri.md"))

(define response-files
  '("response/connection.md" "response/content-length.md" "response/finish.md"
    "response/invalid.md" "response/lenient-version.md" "response/pausing.md"
    "response/pipelining.md" "response/sample.md" "response/transfer-encoding.md"))

;; fixtures-of-type : (Listof String) String -> (Listof (Pair String Fixture))
;; Every fixture in `files` whose `type` meta is exactly `type`, keyed by
;; `file#n`. Exactly, because a lenient or `-finish` type builds a different
;; binary upstream; the rule does not change, but the input set should be the
;; one plain strict parser an embedder gets from `make-parser`.
(define (fixtures-of-type files type)
  (apply append
         (map (lambda (rel)
                (let loop ((fs (corpus-parse-file
                                (read-text (string-append corpus-dir "/" rel))))
                           (i 1) (acc '()))
                  (cond ((null? fs) (reverse acc))
                        ((equal? (fixture-meta-ref (car fs) 'type #f) type)
                         (loop (cdr fs) (+ i 1)
                               (cons (cons (string-append rel "#" (number->string i))
                                           (car fs))
                                     acc)))
                        (else (loop (cdr fs) (+ i 1) acc)))))
              files)))

;; --- the oracle's side ------------------------------------------------------

(define (string-prefix? p s)
  (and (<= (string-length p) (string-length s))
       (string=? p (substring s 0 (string-length p)))))

(define (contains? s sub)
  (let ((n (string-length s)) (m (string-length sub)))
    (let loop ((i 0))
      (cond ((> (+ i m) n) #f)
            ((string=? (substring s i (+ i m)) sub) #t)
            (else (loop (+ i 1)))))))

;; words : String -> (Listof String)
(define (words s)
  (let loop ((cs (string->list s)) (cur '()) (acc '()))
    (define (flush) (if (null? cur) acc (cons (list->string (reverse cur)) acc)))
    (cond ((null? cs) (reverse (flush)))
          ((char=? (car cs) #\space) (loop (cdr cs) '() (flush)))
          (else (loop (cdr cs) (cons (car cs) cur) acc)))))

;; line-field : String String Nat -> (Option Nat)
;; The value of `key=` in a log line, read in `radix`. llhttp prints `flags`
;; in hex and `method`/`status` in decimal.
(define (line-field line key radix)
  (let loop ((ws (words line)))
    (cond ((null? ws) #f)
          ((string-prefix? (string-append key "=") (car ws))
           (string->number (substring (car ws) (+ 1 (string-length key))
                                      (string-length (car ws)))
                           radix))
          (else (loop (cdr ws))))))

;; headers-complete-lines : Fixture -> (Listof String)
(define (headers-complete-lines f)
  (filter (lambda (l) (contains? l " headers complete "))
          (map expectation-text
               (filter (lambda (e) (not (expectation-pattern? e)))
                       (fixture-expected f)))))

(define both-bits (bitwise-ior F-UPGRADE F-CONNECTION-UPGRADE))
(define CONNECT (httparse-method-number (quote CONNECT)))

;; llhttp-upgrade : Symbol Nat Nat Nat -> Nat
;; `llhttp__before_headers_complete`, transcribed. A response's `method` is 0.
(define (llhttp-upgrade type method status flags)
  (if (= (bitwise-and flags both-bits) both-bits)
      (if (or (eq? type 'request) (= status 101)) 1 0)
      (if (= method CONNECT) 1 0)))

;; expected-upgrades : Symbol Fixture -> (Listof Nat)
;; One value per `headers complete` line the fixture's log records.
(define (expected-upgrades type f)
  (map (lambda (line)
         (llhttp-upgrade type
                         (or (line-field line "method" 10) 0)
                         (or (line-field line "status" 10) 0)
                         (line-field line "flags" 16)))
       (headers-complete-lines f)))

(define (logs-upgrade-pause? f)
  (exists (lambda (e) (contains? (expectation-text e) "Pause on CONNECT/Upgrade"))
          (fixture-expected f)))

;; --- the parser's side ------------------------------------------------------

(define (ignore-event p ctx) callback-continue)
(define (ignore-span p ctx bv from to) callback-continue)

;; make-probe-parser : Symbol Boolean (Parser Symbol -> Void) -> Parser
;; A parser of `type` whose event callbacks report `(parser, callback-name)` to
;; `note!` -- which reads whatever field it likes -- and whose
;; `on-headers-complete` answers `skip-body` when `skip?` (a fixture's
;; `skipBody` meta, which is what upstream's harness does with it).
(define (make-probe-parser type skip? note!)
  (define (noting name)
    (lambda (p ctx) (note! p name) callback-continue))
  (make-parser
   httparse-message-machine
   (list (list 'on-method-data ignore-span)
         (list 'on-url-data ignore-span)
         (list 'on-header-field-data ignore-span)
         (list 'on-header-value-data ignore-span)
         (list 'on-header-value-complete ignore-event)
         (list 'on-reset ignore-event)
         (list 'on-message-begin (noting 'on-message-begin))
         (list 'on-method-complete ignore-event)
         (list 'on-url-complete ignore-event)
         (list 'on-protocol-data ignore-span)
         (list 'on-protocol-complete ignore-event)
         (list 'on-version-data ignore-span)
         (list 'on-version-complete ignore-event)
         (list 'on-status-data ignore-span)
         (list 'on-status-complete ignore-event)
         (list 'on-header-field-complete ignore-event)
         (list 'on-headers-complete
               (lambda (p ctx)
                 (note! p 'on-headers-complete)
                 (if skip? 'skip-body callback-continue)))
         (list 'on-body-data
               (lambda (p ctx bv from to) (note! p 'on-body-data) callback-continue))
         (list 'on-chunk-header ignore-event)
         (list 'on-chunk-extension-name-data ignore-span)
         (list 'on-chunk-extension-name-complete ignore-event)
         (list 'on-chunk-extension-value-data ignore-span)
         (list 'on-chunk-extension-value-complete ignore-event)
         (list 'on-chunk-complete ignore-event)
         (list 'on-message-complete (noting 'on-message-complete)))
   #f
   (list (cons 'type (httparse-message-type-value type)))))

;; feed-in-chunks! : Parser Bytevector Nat -> ParserResult
;; Feeds `bv` `size` bytes at a time (0 = whole) until it is taken or the parse
;; stops. A stop is where llhttp's log stops too: the corpus never resumes.
(define (feed-in-chunks! p bv size)
  (let ((n (bytevector-length bv)))
    (let loop ((at 0))
      (let* ((end (if (zero? size) n (min n (+ at size))))
             (r (parser-feed! p bv at end)))
        (if (and (eq? (parser-result-status r) 'need-input) (< end n))
            (loop end)
            r)))))

;; observed-upgrades : Symbol Fixture Nat -> (Listof Nat)
;; `upgrade` as `on-headers-complete` sees it, once per call.
(define (observed-upgrades type f size)
  (let* ((seen '())
         (p (make-probe-parser
             type (fixture-meta-ref f 'skipBody #f)
             (lambda (p name)
               (when (eq? name 'on-headers-complete)
                 (set! seen (cons (parser-field-ref p 'upgrade) seen)))))))
    (feed-in-chunks! p (corpus-decode-input (fixture-input-text f)) size)
    (reverse seen)))

;; trace-upgrades : Symbol String -> (Listof (Pair Symbol Nat))
;; `(callback . upgrade)` for every reported callback over a whole-buffer feed.
(define (trace-upgrades type input)
  (let* ((seen '())
         (p (make-probe-parser type #f
              (lambda (p name)
                (set! seen (cons (cons name (parser-field-ref p 'upgrade)) seen))))))
    (feed-in-chunks! p (string->utf8 input) 0)
    (reverse seen)))

;; --- the corpus sweep -------------------------------------------------------

(define requests (fixtures-of-type request-files "request"))
(define responses (fixtures-of-type response-files "response"))

;; mismatches : Symbol (Listof (Pair String Fixture)) Nat -> (Listof String)
(define (mismatches type fixtures size)
  (fold-right (lambda (entry acc)
                (if (equal? (observed-upgrades type (cdr entry) size)
                            (expected-upgrades type (cdr entry)))
                    acc
                    (cons (car entry) acc)))
              '() fixtures))

(define (count-calls type fixtures pred)
  (fold-left (lambda (acc entry)
               (+ acc (length (filter pred (expected-upgrades type (cdr entry))))))
             0 fixtures))

(harness-begin "unit.upgrade-field")

(harness-group "upgrade at on-headers-complete is llhttp's, over the corpus"
  (lambda ()
    (define (tally type fixtures)
      (display (string-append
                "httparse-harness: upgrade-field " (symbol->string type)
                " fixtures=" (number->string (length fixtures))
                " calls=" (number->string (count-calls type fixtures (lambda (v) #t)))
                " upgrade=1:" (number->string (count-calls type fixtures (lambda (v) (= v 1))))
                "\n")))
    (tally 'request requests)
    (tally 'response responses)

    (harness-case "requests, whole and a byte at a time"
      (lambda ()
        (check-equal "whole buffer" (mismatches 'request requests 0) '())
        (check-equal "one byte per feed" (mismatches 'request requests 1) '())))

    (harness-case "responses, whole and a byte at a time"
      (lambda ()
        (check-equal "whole buffer" (mismatches 'response responses 0) '())
        (check-equal "one byte per feed" (mismatches 'response responses 1) '())))

    ;; The rule above is a transcription, so it gets a second witness where one
    ;; exists. A request that upgrades always ends in the hand-off pause, and
    ;; one that does not never does, so the two sets must be the same set.
    (harness-case "for requests, 1 exactly where the log pauses for CONNECT/Upgrade"
      (lambda ()
        (let ((ids (lambda (pred) (map car (filter (lambda (e) (pred (cdr e))) requests)))))
          (check-equal "same fixtures"
                       (ids (lambda (f) (memv 1 (expected-upgrades 'request f))))
                       (ids logs-upgrade-pause?))
          ;; Vacuity: an empty set on both sides would agree about nothing.
          (check "some request upgrades" (pair? (ids logs-upgrade-pause?))))))

    ;; What makes the response half worth running: the corpus holds both bits
    ;; under a 101 AND both bits under something else, so the status test
    ;; decides a value on at least one call each way. Without both, a parser
    ;; that ignored the status -- or ignored the bits -- would pass the sweep.
    (harness-case "the corpus separates the response rule's two conditions"
      (lambda ()
        (define (calls pred)
          (apply append
                 (map (lambda (e)
                        (filter pred (headers-complete-lines (cdr e))))
                      responses)))
        (define (bits? line)
          (= (bitwise-and (line-field line "flags" 16) both-bits) both-bits))
        (define (status line) (line-field line "status" 10))
        (check "both bits under 101"
               (pair? (calls (lambda (l) (and (bits? l) (= (status l) 101))))))
        (check "both bits under another status"
               (pair? (calls (lambda (l) (and (bits? l) (not (= (status l) 101)))))))))))

;;; How long the answer lasts. llhttp writes `upgrade` in one place, just before
;;; `on_headers_complete`, and never clears it between messages -- so it is the
;;; CURRENT message's answer only from that callback on.
(harness-group "how long upgrade holds"
  (lambda ()
    (harness-case "from on-headers-complete to the end of the message"
      (lambda ()
        ;; llhttp: message_begin 0, headers_complete 1, body 1,
        ;; message_complete 1, then HPE_PAUSED_UPGRADE with upgrade 1.
        (let* ((seen '())
               (p (make-probe-parser 'request #f
                    (lambda (p name)
                      (set! seen (cons (cons name (parser-field-ref p 'upgrade)) seen)))))
               (bv (string->utf8
                    (string-append "GET / HTTP/1.1\r\nConnection: upgrade\r\n"
                                   "Upgrade: ws\r\nContent-Length: 4\r\n\r\nabcd")))
               (r (parser-feed! p bv 0 (bytevector-length bv))))
          (check-equal "per callback" (reverse seen)
                       '((on-message-begin . 0) (on-headers-complete . 1)
                         (on-body-data . 1) (on-message-complete . 1)))
          (check-equal "the hand-off" (parser-result-status r) 'paused)
          (check-equal "after the hand-off" (parser-field-ref p 'upgrade) 1))))

    (harness-case "the next message starts with the previous answer"
      (lambda ()
        ;; llhttp, CONNECT then resume then GET: message_begin 0,
        ;; headers_complete 1, message_complete 1, PAUSED_UPGRADE; then
        ;; message_begin 1 -- stale -- headers_complete 0, message_complete 0.
        (let* ((seen '())
               (p (make-probe-parser 'request #f
                    (lambda (p name)
                      (set! seen (cons (cons name (parser-field-ref p 'upgrade)) seen)))))
               (a (string->utf8 "CONNECT a:443 HTTP/1.1\r\n\r\n"))
               (b (string->utf8 "GET / HTTP/1.1\r\n\r\n"))
               (r1 (parser-feed! p a 0 (bytevector-length a))))
          (check-equal "CONNECT hands off" (parser-result-status r1) 'paused)
          (parser-resume! p)
          (parser-feed! p b 0 (bytevector-length b))
          (check-equal "per callback" (reverse seen)
                       '((on-message-begin . 0) (on-headers-complete . 1)
                         (on-message-complete . 1)
                         (on-message-begin . 1) (on-headers-complete . 0)
                         (on-message-complete . 0))))))

    (harness-case "parser-reset! returns it to 0"
      (lambda ()
        (let* ((p (make-probe-parser 'request #f (lambda (p name) #f)))
               (bv (string->utf8 "CONNECT a:443 HTTP/1.1\r\n\r\n")))
          (parser-feed! p bv 0 (bytevector-length bv))
          (check-equal "set" (parser-field-ref p 'upgrade) 1)
          (parser-reset! p)
          (check-equal "reset" (parser-field-ref p 'upgrade) 0))))

    (harness-case "a 101 without the upgrade headers hands off with upgrade 0"
      (lambda ()
        ;; llhttp: HPE_PAUSED_UPGRADE with upgrade 0. The hand-off result and
        ;; the field are separate answers; a 101 always switches protocol, but
        ;; only the headers make it an announced upgrade.
        (let* ((p (make-probe-parser 'response #f (lambda (p name) #f)))
               (bv (string->utf8 "HTTP/1.1 101 Switching Protocols\r\n\r\n"))
               (r (parser-feed! p bv 0 (bytevector-length bv))))
          (check-equal "hands off" (parser-result-status r) 'paused)
          (check-equal "upgrade" (parser-field-ref p 'upgrade) 0))))))

(harness-finish)
