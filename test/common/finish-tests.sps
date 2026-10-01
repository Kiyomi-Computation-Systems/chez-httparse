;;; parser-finish! and the completion the corpus cannot see.
;;;
;;; A response with neither Content-Length nor Transfer-Encoding (and not
;;; 1xx/204/304) is delimited by the connection closing. llhttp's parser raises
;;; `finish` to SAFE_WITH_CB -- a state that means "complete, but only once
;;; someone says the input stopped" -- then opens the body span once a byte
;;; arrives and consumes for ever.
;;; The someone is `llhttp_finish`, and `src/native/api.c:143-150` (v9.4.3) runs
;;; `on_message_complete` for SAFE_WITH_CB, propagates a non-OK return from it,
;;; and only then answers OK.
;;;
;;; THE CORPUS IS BLIND HERE. Its driver never calls `parser-finish!` (decision
;;; 0016), so `response/finish.md#1` records `off=NULL finish=1` and stops --
;;; the FIELD that promises the callback, not the callback. That fixture is the
;;; mutation witness for the state; this lane is the witness for the callback
;;; the state promises. It drives the COMMITTED parser -- the one an embedder
;;; loads -- so a grammar edit that dropped the completion from the finish path
;;; reddens here even though every recorded trace stays green.
(import (rnrs)
        (httparse test harness)
        (generated httparse-message)
        (httparse modes)
        (byte-machine runtime))

;; make-recording-parser : Symbol (Listof Symbol) CallbackOutcome
;;                         -> (values Parser (-> String) (-> Nat) (-> (Option String))
;;                                    (-> (Listof Nat)))
;; A parser of `type` under the lenient `flags`, with every declared callback
;; bound (a hole is refused at `make-parser`, not ignored). `on-body-data`
;; accumulates the body and records each fragment's length; the completion
;; callback counts its firings, snapshots the body as it stood when it fired,
;; and returns `complete-outcome` -- `callback-continue` for the ordinary case,
;; `callback-pause` to check that a non-OK answer comes back out of
;; `parser-finish!`. The four readers close over the mutable state.
(define (make-recording-parser type flags complete-outcome)
  (let ((body "") (body-calls '()) (complete-count 0) (body-at-complete #f))
    (define (ignore-event p ctx) callback-continue)
    (define (ignore-span p ctx bv from to) callback-continue)
    (define (text bv from to)
      (let ((b (make-bytevector (- to from))))
        (bytevector-copy! bv from b 0 (- to from))
        (utf8->string b)))
    (let ((parser
           (make-parser
            httparse-message-machine
            (list
             ;; A request's two spans never fire for a response, but every
             ;; declared callback must still be bound.
             (list 'on-method-data ignore-span)
             (list 'on-url-data ignore-span)
             (list 'on-header-field-data ignore-span)
             (list 'on-header-value-data ignore-span)
             (list 'on-header-value-complete ignore-event)
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
             (list 'on-headers-complete ignore-event)
             (list 'on-body-data
                   (lambda (p ctx bv from to)
                     (set! body (string-append body (text bv from to)))
                     (set! body-calls (cons (- to from) body-calls))
                     callback-continue))
             (list 'on-chunk-header ignore-event)
             (list 'on-chunk-extension-name-data ignore-span)
             (list 'on-chunk-extension-name-complete ignore-event)
             (list 'on-chunk-extension-value-data ignore-span)
             (list 'on-chunk-extension-value-complete ignore-event)
             (list 'on-chunk-complete ignore-event)
             (list 'on-message-complete
                   (lambda (p ctx)
                     (set! complete-count (+ complete-count 1))
                     (set! body-at-complete body)
                     complete-outcome)))
            #f
            ;; The kind is the caller's: a response for a close-delimited body,
            ;; a request for the unsafe-finish cases below.
            (list (cons 'type (httparse-message-type-value type))
                  (cons 'lenient-flags (httparse-lenient-flags-value flags))))))
      (values parser
              (lambda () body)
              (lambda () complete-count)
              (lambda () body-at-complete)
              (lambda () (reverse body-calls))))))

;; make-parser-of-type : Symbol CallbackOutcome -> (values Parser (-> String) (-> Nat) (-> (Option String)))
;; The strict parser the cases below were written against, without the
;; fragment log.
(define (make-parser-of-type type complete-outcome)
  (let-values (((p get-body get-count get-at get-calls)
                (make-recording-parser type '() complete-outcome)))
    (values p get-body get-count get-at)))

;; feed-all! : Parser Bytevector Nat -> ParserResult
;; `size` bytes at a time, 0 for the whole buffer, until the input is taken or
;; the parse stops.
(define (feed-all! p bv size)
  (let ((n (bytevector-length bv)))
    (let loop ((at 0))
      (let* ((end (if (zero? size) n (min n (+ at size))))
             (r (parser-feed! p bv at end)))
        (if (and (eq? (parser-result-status r) 'need-input) (< end n))
            (loop end)
            r)))))

(define (utf8 s) (string->utf8 s))

;; unsafe-finish-error : String -> ParserError
;; The error a finish returns from an UNSAFE state (mid-message). The callbacks
;; do not matter here -- the parse errors rather than completing -- so a plain
;; request parser that would continue on completion is enough.
(define (unsafe-finish-error input)
  (let-values (((p get-body get-count get-at)
                (make-parser-of-type 'request callback-continue)))
    (let ((bv (utf8 input)))
      (parser-feed! p bv 0 (bytevector-length bv))
      (parser-result-error (parser-finish! p)))))

(harness-begin "unit.finish")

(harness-group "a close-delimited response completes on parser-finish!"
  (lambda ()
    (harness-case "the body arrives, then on-message-complete fires once"
      (lambda ()
        ;; `response/sample.md#19`'s shape: a 200 with no framing header, whose
        ;; body is whatever precedes the close. The feed cannot end the message
        ;; -- the body runs to EOF -- so it asks for more; `parser-finish!` is
        ;; what says the input stopped.
        (let-values (((p get-body get-count get-at)
                      (make-parser-of-type 'response callback-continue)))
          (let* ((bv (utf8 "HTTP/1.1 200 OK\r\n\r\nhello world"))
                 (fed (parser-feed! p bv 0 (bytevector-length bv)))
                 (fin (parser-finish! p)))
            (check-equal "the feed wants more" (parser-result-status fed) 'need-input)
            (check-equal "the finish is finished" (parser-result-status fin) 'finished)
            (check-equal "on-message-complete fired exactly once" (get-count) 1)
            (check-equal "the whole body was delivered" (get-body) "hello world")
            ;; ORDER: the body callback runs before the completion. Its bytes
            ;; arrive with the feed that carried them -- llhttp delivers them
            ;; at the end of each execute, not at the finish -- and the
            ;; completion fires only once the finish says the input stopped.
            (check-equal "and it was whole by the time completion fired"
                         (get-at) "hello world")))))
    (harness-case "an empty close-delimited body still completes once"
      (lambda ()
        ;; `response/finish.md#1` exactly: `HTTP/1.1 200 OK\r\n\r\n`, content
        ;; length 0, close-delimited. The corpus stops at `finish=1`; here the
        ;; embedder finishes and the completion fires with an empty body.
        (let-values (((p get-body get-count get-at)
                      (make-parser-of-type 'response callback-continue)))
          (let* ((bv (utf8 "HTTP/1.1 200 OK\r\n\r\n"))
                 (fed (parser-feed! p bv 0 (bytevector-length bv)))
                 (fin (parser-finish! p)))
            (check-equal "the feed wants more" (parser-result-status fed) 'need-input)
            (check-equal "the finish is finished" (parser-result-status fin) 'finished)
            (check-equal "on-message-complete fired exactly once" (get-count) 1)
            (check-equal "the body is empty" (get-body) "")))))))

(harness-group "the completion callback's outcome comes back out of parser-finish!"
  (lambda ()
    (harness-case "a pause returned by on-message-complete surfaces as a pause"
      (lambda ()
        ;; api.c propagates a non-OK return from the SAFE_WITH_CB callback
        ;; before answering OK. A callback answering `callback-pause` must
        ;; therefore make `parser-finish!` answer `paused`, not `finished` --
        ;; and it must still have fired.
        (let-values (((p get-body get-count get-at)
                      (make-parser-of-type 'response callback-pause)))
          (let* ((bv (utf8 "HTTP/1.1 200 OK\r\n\r\nhello world"))
                 (fed (parser-feed! p bv 0 (bytevector-length bv)))
                 (fin (parser-finish! p)))
            (check-equal "the finish surfaces the pause" (parser-result-status fin) 'paused)
            (check-equal "on-message-complete still fired once" (get-count) 1)))))

    ;; The same answer when the body had no bytes, which reaches the
    ;; completion by another edge: llhttp answers HPE_PAUSED here too, having
    ;; fired `on_message_complete` once and `on_body` never.
    (harness-case "a pause surfaces the same way when the body had no bytes"
      (lambda ()
        (let-values (((p get-body get-count get-at get-calls)
                      (make-recording-parser 'response '() callback-pause)))
          (let* ((bv (utf8 "HTTP/1.1 200 OK\r\n\r\n"))
                 (fed (parser-feed! p bv 0 (bytevector-length bv)))
                 (fin (parser-finish! p)))
            (check-equal "the finish surfaces the pause" (parser-result-status fin) 'paused)
            (check-equal "on-message-complete still fired once" (get-count) 1)
            (check-equal "no body callback" (get-calls) '())))))))

;;; WHICH BODY CALLBACKS A BODY THE CONNECTION ENDS GETS, AND WHEN. llhttp's
;;; public API, built from the checkout the corpus came from
;;; (`v9.4.3-1-gee51043`), answers every row: `on_body` fires during the
;;; feeds, once for each run of bytes a feed carried, and never at
;;; `llhttp_finish`, which runs `on_message_complete` alone. With no body bytes
;;; `on_body` never fires at all. llparse's span start waits for a byte -- its
;;; `if (p == endp) return` precedes `_span_pos0 = p` -- so a body span that
;;; gets none never opens, and there is nothing for a feed's end to flush or
;;; for the finish to close.
;;;
;;; THREE FRAMINGS LEAD HERE: no framing header on a response, a coding that
;;; does not end in `chunked` on a response, and the same coding on a request
;;; under either lenient flag that permits it, `transfer-encoding` or
;;; `chunked-length` (strict, llhttp refuses that request,
;;; HPE_INVALID_TRANSFER_ENCODING). They meet at one node; the rows hold each
;;; route, so splitting it cannot drop one.
;;;
;;; Each row: label, kind, lenient flags, input, then the body fragments'
;;; lengths fed whole and fed a byte at a time.
(define close-delimited-rows
  (list
   (list "no framing header, no body bytes"
         'response '() "HTTP/1.1 200 OK\r\n\r\n" '() '())
   (list "a response coding that is not chunked, no body bytes"
         'response '() "HTTP/1.1 200 OK\r\nTransfer-Encoding: gzip\r\n\r\n" '() '())
   (list "that coding on a request, lenient transfer-encoding, no body bytes"
         'request '(transfer-encoding) "POST / HTTP/1.1\r\nTransfer-Encoding: gzip\r\n\r\n"
         '() '())
   (list "that coding on a request, lenient chunked-length, no body bytes"
         'request '(chunked-length) "POST / HTTP/1.1\r\nTransfer-Encoding: gzip\r\n\r\n"
         '() '())
   (list "no framing header, eleven body bytes"
         'response '() "HTTP/1.1 200 OK\r\n\r\nhello world"
         '(11) '(1 1 1 1 1 1 1 1 1 1 1))))

(harness-group "a body the connection ends gets a callback only for its bytes"
  (lambda ()
    (for-each
     (lambda (row)
       (let ((label (list-ref row 0)) (type (list-ref row 1)) (flags (list-ref row 2))
             (input (list-ref row 3)))
         (harness-case label
           (lambda ()
             (for-each
              (lambda (size expected)
                (let-values (((p get-body get-count get-at get-calls)
                              (make-recording-parser type flags callback-continue)))
                  (let* ((how (if (zero? size) "whole" "a byte at a time"))
                         (fed (feed-all! p (utf8 input) size))
                         (at-feeds (get-calls))
                         (fin (parser-finish! p)))
                    (check-equal (string-append how ": the feeds want more")
                                 (parser-result-status fed) 'need-input)
                    (check-equal (string-append how ": body fragments during the feeds")
                                 at-feeds expected)
                    (check-equal (string-append how ": the finish is finished")
                                 (parser-result-status fin) 'finished)
                    (check-equal (string-append how ": none at the finish")
                                 (get-calls) expected)
                    (check-equal (string-append how ": on-message-complete fired once")
                                 (get-count) 1))))
              (list 0 1)
              (list (list-ref row 4) (list-ref row 5)))))))
     close-delimited-rows)))

(harness-group "the completion fires only for the framing that promises it"
  (lambda ()
    (harness-case "finishing an idle parser does not fire on-message-complete"
      (lambda ()
        ;; `parser-finish!` on a parser that has seen no bytes runs the EOF
        ;; chain from `start`, which reaches `clean-eof` -- a bare finish. No
        ;; message began, so none completes: the new callback is on the
        ;; close-delimited path alone, not on every finish.
        (let-values (((p get-body get-count get-at)
                      (make-parser-of-type 'response callback-continue)))
          (let ((fin (parser-finish! p)))
            (check-equal "the finish is finished" (parser-result-status fin) 'finished)
            (check-equal "nothing completed" (get-count) 0)))))))

(harness-group "an unsafe finish is llhttp's Invalid EOF state"
  (lambda ()
    ;; `parser-finish!` from a state that is not a clean boundary is llhttp's
    ;; HTTP_FINISH_UNSAFE: `llhttp_finish` answers HPE_INVALID_EOF_STATE (code
    ;; 14, `api.c:152`), reason "Invalid EOF state" verbatim -- see #42. The
    ;; corpus cannot witness it (its driver never finishes, decision 0016), so
    ;; this lane pins it. llhttp switches on the `finish` FIELD, not the open
    ;; span, so EVERY unsafe state answers the ONE identity -- the four below
    ;; span method, header field, header value and body to hold that uniform.
    (harness-case "mid-header-value -- request/finish.md#2 (off=NULL finish=2)"
      (lambda ()
        (let ((e (unsafe-finish-error "PUT / HTTP/1.1\r\nContent-Length: 100")))
          (check-equal "code" (parser-error-code e) 'invalid-eof-state)
          (check-equal "reason" (parser-error-reason e) "Invalid EOF state"))))
    (harness-case "mid-header-field -- request/finish.md#3 (off=NULL finish=2)"
      (lambda ()
        (let ((e (unsafe-finish-error "PUT / HTTP/1.1\r\nContent-Leng")))
          (check-equal "code" (parser-error-code e) 'invalid-eof-state)
          (check-equal "reason" (parser-error-reason e) "Invalid EOF state"))))
    (harness-case "mid-method"
      (lambda ()
        (let ((e (unsafe-finish-error "GE")))
          (check-equal "code" (parser-error-code e) 'invalid-eof-state)
          (check-equal "reason" (parser-error-reason e) "Invalid EOF state"))))
    (harness-case "mid-body"
      (lambda ()
        (let ((e (unsafe-finish-error "PUT / HTTP/1.1\r\nContent-Length: 5\r\n\r\nab")))
          (check-equal "code" (parser-error-code e) 'invalid-eof-state)
          (check-equal "reason" (parser-error-reason e) "Invalid EOF state"))))))

(harness-finish)
