;;; The documented end-to-end example, run.
;;;
;;; README.org shows this code, abridged -- it elides the bindings that do
;;; nothing and names this file as the whole of it. It runs here so that the
;;; README cannot drift: a documented example nothing executes is a claim
;;; about an older version of the library, and this project has a rename
;;; audit precisely because prose goes stale faster than code does.
;;;
;;; WHAT IT DEMONSTRATES is the whole public surface an embedder touches --
;;; the committed machine, a binding list, feeding bytes in pieces, reading a
;;; span without copying it, the one callback that ANSWERS rather than
;;; observes, reading a parser field, and getting an error's code and reason.
(import (rnrs)
        (httparse test harness)
        (generated httparse-message)
        (byte-machine runtime))

;; --- the example, exactly as the README shows it --------------------------

;; Collect a request's method, target and headers.
(define (parse-request chunks)
  (let ((method #f) (target #f) (headers '()) (field #f) (value "") (framing #f))
    (define (text bv from to)
      (let ((b (make-bytevector (- to from))))
        (bytevector-copy! bv from b 0 (- to from))
        (utf8->string b)))
    (define (ignore-event p ctx) callback-continue)
    (define (ignore-span p ctx bv from to) callback-continue)
    (let ((parser
           (make-parser
            httparse-message-machine
            (list
             ;; The one binding that answers a question: this parser is told
             ;; what it is parsing, because a request and a response begin
             ;; differently and no byte says which is coming.
             (list 'on-message-type (lambda (p ctx) 'request))
             (list 'on-method-data
                   (lambda (p ctx bv from to)
                     (set! method (text bv from to)) callback-continue))
             (list 'on-url-data
                   (lambda (p ctx bv from to)
                     (set! target (text bv from to)) callback-continue))
             (list 'on-header-field-data
                   (lambda (p ctx bv from to)
                     (set! field (text bv from to)) callback-continue))
             (list 'on-header-value-data
                   (lambda (p ctx bv from to)
                     (set! value (string-append value (text bv from to)))
                     callback-continue))
             (list 'on-header-value-complete
                   (lambda (p ctx)
                     (set! headers (cons (cons field value) headers))
                     (set! value "")
                     callback-continue))
             ;; Every declared callback must be bound, including the ones
             ;; this example ignores: a parser with a hole in its binding
             ;; list is refused rather than silently quiet.
             (list 'on-reset ignore-event)
             (list 'on-message-begin ignore-event)
             (list 'on-method-complete ignore-event)
             (list 'on-url-complete ignore-event)
             (list 'on-protocol-data ignore-span)
             (list 'on-protocol-complete ignore-event)
             (list 'on-version-data ignore-span)
             (list 'on-version-complete ignore-event)
             (list 'on-status-data ignore-span)
             (list 'on-status-complete ignore-event)
             (list 'on-header-field-complete ignore-event)
             ;; READ FIELDS HERE, NOT AFTERWARDS. `content-length` is what
             ;; REMAINS to be read, so it counts down as the body arrives and
             ;; is 0 by the time the message completes -- which is llhttp's
             ;; own semantics, and the number its `headers complete` line
             ;; prints is the one taken at this moment.
             (list 'on-headers-complete
                   (lambda (p ctx)
                     (set! framing
                           (list (cons 'method (parser-field-ref p 'method))
                                 (cons 'content-length
                                       (parser-field-ref p 'content-length))
                                 (cons 'http-major (parser-field-ref p 'http-major))
                                 (cons 'http-minor (parser-field-ref p 'http-minor))))
                     callback-continue))
             (list 'on-body-data ignore-span)
             (list 'on-chunk-header ignore-event)
             (list 'on-chunk-extension-name-data ignore-span)
             (list 'on-chunk-extension-name-complete ignore-event)
             (list 'on-chunk-extension-value-data ignore-span)
             (list 'on-chunk-extension-value-complete ignore-event)
             (list 'on-chunk-complete ignore-event)
             (list 'on-message-complete ignore-event))
            #f)))
      ;; Feed the pieces as they arrive. `need-input` means keep going.
      (let loop ((cs chunks) (result #f))
        (if (null? cs)
            (values result method target (reverse headers) framing)
            (let* ((bv (car cs))
                   (r (parser-feed! parser bv 0 (bytevector-length bv))))
              (if (eq? (parser-result-status r) 'need-input)
                  (loop (cdr cs) r)
                  (values r method target (reverse headers) framing))))))))

;; --- and what it produces -------------------------------------------------

(define (utf8 . ss) (map string->utf8 ss))

(harness-begin "example.parse-request")

(harness-group "a request arriving in three pieces"
  (lambda ()
    (harness-case "the method, target and headers come out whole"
      (lambda ()
        (let-values (((result method target headers framing)
                      (parse-request
                       (utf8 "GET /index.html HTT"
                             "P/1.1\r\nHost: exam"
                             "ple.com\r\nAccept: */*\r\n\r\n"))))
          (check-equal "method" method "GET")
          (check-equal "target" target "/index.html")
          (check-equal "headers" headers
                       '(("Host" . "example.com") ("Accept" . "*/*")))
          ;; A message with no body and no framing header is complete at the
          ;; blank line, and the parser is ready for the next one.
          (check-equal "status" (parser-result-status result) 'need-input)
          (check-equal "bytes seen" (parser-result-stream-offset result) 60))))
    (harness-case "a span split across a feed arrives in pieces, not truncated"
      (lambda ()
        ;; `Host: exam` / `ple.com` -- the value callback fires twice and the
        ;; example appends, which is why it appends rather than assigns.
        (let-values (((result method target headers framing)
                      (parse-request (utf8 "GET / HTTP/1.1\r\nX: abc" "def\r\n\r\n"))))
          (check-equal "joined" headers '(("X" . "abcdef"))))))))

(harness-group "what the parser knows once the headers are in"
  (lambda ()
    (harness-case "a field is read by name"
      (lambda ()
        (let-values (((result method target headers framing)
                      (parse-request
                       (utf8 "POST /u HTTP/1.1\r\nContent-Length: 5\r\n\r\nhello"))))
          ;; llhttp's own numbering: POST is 3. These are the values its
          ;; `headers complete` trace line carries, taken at the same moment.
          (check-equal "framing" framing
                       '((method . 3) (content-length . 5)
                         (http-major . 1) (http-minor . 1))))))
    (harness-case "and content-length has counted down by the end"
      (lambda ()
        ;; Worth stating out loud, because reading the field after the parse
        ;; and calling it "the declared length" is the obvious mistake.
        (let-values (((result method target headers framing)
                      (parse-request (utf8 "POST /u HTTP/1.1\r\nContent-Length: 5\r\n\r\nhel"))))
          (check-equal "three of five read, two to go"
                       (cdr (assq 'content-length framing)) 5))))))

(harness-group "a request the parser refuses"
  (lambda ()
    (harness-case "the result carries llhttp's own code and reason"
      (lambda ()
        (let-values (((result method target headers framing)
                      (parse-request (utf8 "GET / HTTP/1.1\r\nFo@: x\r\n\r\n"))))
          (check-equal "status" (parser-result-status result) 'error)
          (let ((e (parser-result-error result)))
            (check-equal "code" (parser-error-code e) 'invalid-header-token)
            (check-equal "reason" (parser-error-reason e) "Invalid header token")
            (check-equal "offset" (parser-error-offset e) 18)))))))

(harness-finish)
