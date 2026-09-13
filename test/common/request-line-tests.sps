;;; Tests for (httparse grammar)'s request line.
;;;
;;; Every expectation is an event name and a byte offset, taken from the
;;; vendored corpus's own recorded traces rather than from what the grammar
;;; happens to do. `request/sample.md` records, for `OPTIONS /url HTTP/1.1`:
;;;
;;;   off=0 message begin / off=0 len=7 span[method]="OPTIONS" /
;;;   off=7 method complete / off=8 len=4 span[url]="/url" / off=13 url complete /
;;;   off=13 len=4 span[protocol]="HTTP" / off=17 protocol complete /
;;;   off=18 len=3 span[version]="1.1" / off=21 version complete
;;;
;;; The grammar runs here through the REFERENCE INTERPRETER. The generated lane
;;; and the conformance driver arrive with the slice that emits the parser.
(import (rnrs)
        (httparse test harness)
        (httparse grammar)
        (byte-machine verify)
        (byte-machine interpret)
        (byte-machine runtime))

(define compiled (make-interpreted-machine (verify-machine (make-request-line-machine))))

;; Runs `input` and returns (values status events), where an event is
;;   (name offset)                       an event callback
;;   (name start length text)            a span fragment, `start` ABSOLUTE
;; A span fragment's absolute start is the stream offset minus its length: the
;; callback fires having already advanced past the bytes it is handed.
(define (run input)
  (let ((events '()))
    (define (ev name)
      (lambda (p ctx)
        (set! events (cons (list name (parser-stream-offset p)) events))
        callback-continue))
    (define (span name)
      (lambda (p ctx bv from to)
        (let ((text (let ((b (make-bytevector (- to from))))
                      (bytevector-copy! bv from b 0 (- to from))
                      (utf8->string b))))
          (set! events (cons (list name (- (parser-stream-offset p) (- to from))
                                   (- to from) text)
                             events)))
        callback-continue))
    (let* ((p (make-parser compiled
                           (list (list 'on-message-begin (ev 'message-begin))
                                 (list 'on-method-data (span 'method))
                                 (list 'on-method-complete (ev 'method-complete))
                                 (list 'on-url-data (span 'url))
                                 (list 'on-url-complete (ev 'url-complete))
                                 (list 'on-protocol-data (span 'protocol))
                                 (list 'on-protocol-complete (ev 'protocol-complete))
                                 (list 'on-version-data (span 'version))
                                 (list 'on-version-complete (ev 'version-complete)))
                           #f))
           (bv (string->utf8 input))
           (r (parser-feed! p bv 0 (bytevector-length bv))))
      (values r (reverse events)))))

(define (events-of input) (let-values (((r e) (run input))) e))

;; Every callback is declared `required?`, so a parser must bind all of them
;; even when a case ignores what they report. (Learned from the parser
;; refusing an empty binding list, which is the declaration doing its job.)
(define (ignoring-bindings)
  (define (ignore-event p ctx) callback-continue)
  (define (ignore-span p ctx bv from to) callback-continue)
  (list (list 'on-message-begin ignore-event)
        (list 'on-method-data ignore-span)
        (list 'on-method-complete ignore-event)
        (list 'on-url-data ignore-span)
        (list 'on-url-complete ignore-event)
        (list 'on-protocol-data ignore-span)
        (list 'on-protocol-complete ignore-event)
        (list 'on-version-data ignore-span)
        (list 'on-version-complete ignore-event)))
(define (status-of input) (let-values (((r e) (run input))) (parser-result-status r)))
(define (error-code-of input)
  (let-values (((r e) (run input)))
    (and (eq? (parser-result-status r) 'error)
         (parser-error-code (parser-result-error r)))))
(define (error-offset-of input)
  (let-values (((r e) (run input)))
    (and (eq? (parser-result-status r) 'error)
         (parser-error-offset (parser-result-error r)))))

(harness-begin "unit.request-line")

(harness-group "the machine itself"
  (lambda ()
    (harness-case "it verifies"
      (lambda ()
        (check "verify-machine returns" (verify-machine (make-request-line-machine)))))))

(harness-group "a complete request line, at the corpus's own offsets"
  (lambda ()
    (harness-case "OPTIONS /url HTTP/1.1 produces exactly the recorded events"
      (lambda ()
        (check-equal "events"
                     (events-of "OPTIONS /url HTTP/1.1\r\n")
                     '((message-begin 0)
                       (method 0 7 "OPTIONS")
                       (method-complete 7)
                       (url 8 4 "/url")
                       (url-complete 13)
                       (protocol 13 4 "HTTP")
                       (protocol-complete 17)
                       (version 18 3 "1.1")
                       (version-complete 21)))))
    (harness-case "HEAD /url HTTP/1.1 produces exactly the recorded events"
      (lambda ()
        ;; request/sample.md, "Request with method starting with `H`".
        (check-equal "events"
                     (events-of "HEAD /url HTTP/1.1\r\n")
                     '((message-begin 0)
                       (method 0 4 "HEAD")
                       (method-complete 4)
                       (url 5 4 "/url")
                       (url-complete 10)
                       (protocol 10 4 "HTTP")
                       (protocol-complete 14)
                       (version 15 3 "1.1")
                       (version-complete 18)))))
    (harness-case "the request line stops at the end of its CRLF"
      (lambda ()
        (let-values (((r e) (run "GET / HTTP/1.1\r\n")))
          (check-equal "status" (parser-result-status r) 'stopped)
          (check-equal "next" (parser-result-next r) 16))))))

(harness-group "the offsets are asymmetric, deliberately"
  (lambda ()
    (harness-case "method complete fires AT its space, which is unconsumed"
      (lambda ()
        ;; "GET / HTTP/1.1": G=0 E=1 T=2, SP=3.
        (check-equal "at the space"
                     (cadr (assq 'method-complete (events-of "GET / HTTP/1.1\r\n")))
                     3)))
    (harness-case "url complete fires one byte PAST its space, which is consumed"
      (lambda ()
        ;; url span is 4..4 ("/"), its SP is at 5, and the event lands at 6.
        ;; Making this uniform with the other three would shift every url
        ;; offset in the corpus by one.
        (check-equal "past the space"
                     (cadr (assq 'url-complete (events-of "GET / HTTP/1.1\r\n")))
                     6)))
    (harness-case "protocol complete fires AT its slash, which is unconsumed"
      (lambda ()
        (check-equal "at the slash"
                     (cadr (assq 'protocol-complete (events-of "GET / HTTP/1.1\r\n")))
                     10)))
    (harness-case "version complete fires AT the CR, which is unconsumed"
      (lambda ()
        (check-equal "at the CR"
                     (cadr (assq 'version-complete (events-of "GET / HTTP/1.1\r\n")))
                     14)))))

(harness-group "spans end before their delimiter"
  (lambda ()
    (harness-case "the method span excludes its space"
      (lambda ()
        (check-equal "method" (assq 'method (events-of "POST / HTTP/1.1\r\n"))
                     '(method 0 4 "POST"))))
    (harness-case "the url span excludes its space"
      (lambda ()
        (check-equal "url" (assq 'url (events-of "GET /abc HTTP/1.1\r\n"))
                     '(url 4 4 "/abc"))))
    (harness-case "the version span excludes the CR"
      (lambda ()
        (check-equal "version" (assq 'version (events-of "GET / HTTP/1.0\r\n"))
                     '(version 11 3 "1.0"))))))

(harness-group "rejections"
  (lambda ()
    (harness-case "an empty method is rejected before any span opens"
      (lambda ()
        ;; `method = 1*tchar`. The leading space is not a tchar, so `start`
        ;; rejects at offset 0 and no method span is ever opened.
        (check-equal "code" (error-code-of " / HTTP/1.1\r\n") 'invalid-method)
        (check-equal "offset" (error-offset-of " / HTTP/1.1\r\n") 0)
        (check-equal "no events" (events-of " / HTTP/1.1\r\n") '())))
    (harness-case "a method not followed by a space is rejected at that byte"
      (lambda ()
        ;; The method span closes, `method complete` fires, and the dispatch
        ;; then reads a byte that is not SP.
        (check-equal "code" (error-code-of "GET\t/ HTTP/1.1\r\n") 'invalid-method)
        (check-equal "offset" (error-offset-of "GET\t/ HTTP/1.1\r\n") 3)))
    (harness-case "a bare LF after the version is a line-ending error"
      (lambda ()
        (check-equal "code" (error-code-of "GET / HTTP/1.1\n") 'invalid-line-ending)
        (check-equal "offset" (error-offset-of "GET / HTTP/1.1\n") 14)))
    (harness-case "a CR not followed by LF is a line-ending error"
      (lambda ()
        (check-equal "code" (error-code-of "GET / HTTP/1.1\rX") 'invalid-line-ending)
        (check-equal "offset" (error-offset-of "GET / HTTP/1.1\rX") 15)))
    (harness-case "a protocol not followed by a slash is rejected"
      (lambda ()
        (check-equal "code" (error-code-of "GET / HTTP 1.1\r\n") 'invalid-constant)))
    (harness-case "end of input inside the method is unexpected-eof"
      (lambda ()
        (let* ((bv (string->utf8 "GE"))
               (p (make-parser compiled (ignoring-bindings) #f)))
          (parser-feed! p bv 0 2)
          (check-equal "code" (parser-error-code (parser-result-error (parser-finish! p)))
                       'unexpected-eof))))
    (harness-case "end of input before any byte finishes cleanly"
      (lambda ()
        ;; Between messages, clean end of input is `finished`, not an error --
        ;; which is what lets the message loop terminate in a later milestone.
        (check-equal "status"
                     (parser-result-status
                      (parser-finish! (make-parser compiled (ignoring-bindings) #f)))
                     'finished)))))

(harness-group "the result does not depend on how the input is split"
  (lambda ()
    (harness-case "byte-at-a-time feeding produces the same events"
      (lambda ()
        ;; The corpus replays every fixture at every chunk size; this is the
        ;; same property on one input, before the conformance driver exists.
        (let ((input "OPTIONS /url HTTP/1.1\r\n")
              (events '()))
          (define (ev name)
            (lambda (p ctx)
              (set! events (cons (list name (parser-stream-offset p)) events))
              callback-continue))
          (define (span name)
            (lambda (p ctx bv from to)
              (set! events (cons (list name (- (parser-stream-offset p) (- to from))
                                       (- to from))
                                 events))
              callback-continue))
          (let* ((bv (string->utf8 input))
                 (p (make-parser compiled
                                 (list (list 'on-message-begin (ev 'message-begin))
                                       (list 'on-method-data (span 'method))
                                       (list 'on-method-complete (ev 'method-complete))
                                       (list 'on-url-data (span 'url))
                                       (list 'on-url-complete (ev 'url-complete))
                                       (list 'on-protocol-data (span 'protocol))
                                       (list 'on-protocol-complete (ev 'protocol-complete))
                                       (list 'on-version-data (span 'version))
                                       (list 'on-version-complete (ev 'version-complete)))
                                 #f)))
            (let loop ((i 0))
              (when (< i (bytevector-length bv))
                (parser-feed! p bv i (+ i 1))
                (loop (+ i 1))))
            ;; Fragmented feeding splits each span into one fragment per byte,
            ;; so the events are compared by their non-span members: the
            ;; coalescing that rejoins fragments is the trace formatter's job.
            (check-equal "event offsets"
                         (map (lambda (e) (list (car e) (cadr e)))
                              (filter (lambda (e) (= (length e) 2)) (reverse events)))
                         '((message-begin 0) (method-complete 7) (url-complete 13)
                           (protocol-complete 17) (version-complete 21)))))))))

(harness-group "the method table"
  (lambda ()
    (harness-case "every method in the table parses as itself"
      (lambda ()
        ;; 47 names, each fed as a complete request line. A trie that dropped or
        ;; mis-wired one name would show up here rather than in whichever
        ;; fixture happened to use it.
        (check-equal "methods that did not round-trip"
                     (filter
                      (lambda (name)
                        (let ((events (events-of (string-append name " / HTTP/1.1\r\n"))))
                          (not (equal? (assq 'method events)
                                       (list 'method 0 (string-length name) name)))))
                      httparse-method-names)
                     '())))
    (harness-case "the table is the one llhttp knows"
      (lambda ()
        (check-equal "count" (length httparse-method-names) 47)))
    (harness-case "MKCOLA matches MKCOL and then rejects the A"
      (lambda ()
        ;; request/invalid.md: `off=0 len=5 span[method]="MKCOL"`,
        ;; `off=5 method complete`, `off=5 error`. A tchar loop would take
        ;; MKCOLA whole and accept it, which is the point of the table.
        (check-equal "events"
                     (events-of "MKCOLA / HTTP/1.1\r\n")
                     '((message-begin 0)
                       (method 0 5 "MKCOL")
                       (method-complete 5)))
        (check-equal "status" (status-of "MKCOLA / HTTP/1.1\r\n") 'error)
        (check-equal "offset" (error-offset-of "MKCOLA / HTTP/1.1\r\n") 5)))
    (harness-case "GET-PARAMETER matches whole, though GET is a proper prefix of it"
      (lambda ()
        ;; This pair is why the table is a trie: make-sequence-dispatch-node
        ;; rejects a case list where one entry is a proper prefix of another.
        (check-equal "method" (assq 'method (events-of "GET-PARAMETER / HTTP/1.1\r\n"))
                     '(method 0 13 "GET-PARAMETER"))))
    (harness-case "GET followed by a space matches GET, not the longer name"
      (lambda ()
        (check-equal "method" (assq 'method (events-of "GET / HTTP/1.1\r\n"))
                     '(method 0 3 "GET"))))
    (harness-case "a hyphenated method matches"
      (lambda ()
        (check-equal "method" (assq 'method (events-of "M-SEARCH * HTTP/1.1\r\n"))
                     '(method 0 8 "M-SEARCH"))))
    (harness-case "an unknown method is rejected inside the table walk"
      (lambda ()
        ;; `F` begins FLUSH, so the trie advances one byte and then finds no
        ;; continuation for `O`.
        (check-equal "status" (status-of "FOO / HTTP/1.1\r\n") 'error)
        (check-equal "no method span"
                     (filter (lambda (e) (eq? (car e) 'method))
                             (events-of "FOO / HTTP/1.1\r\n"))
                     '())))
    (harness-case "a method that is only a prefix of a real one is rejected"
      (lambda ()
        ;; `MKCO` is a prefix of MKCOL but is not itself a method.
        (check-equal "status" (status-of "MKCO / HTTP/1.1\r\n") 'error)))))

(harness-finish)
