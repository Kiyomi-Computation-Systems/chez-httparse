;;; (httparse test adapter): rename this parser's callbacks and errors into
;;; llhttp's trace vocabulary.
;;;
;;; Decision 0008 item 2: this layer may RENAME, never COMPUTE. Both tables
;;; below are total over a closed set with NO DEFAULT -- a callback or an error
;;; code with no row raises rather than falling back -- because a default is
;;; precisely what would let a wrong parser render a right-looking trace. The
;;; offsets, the span bytes and the reason string all arrive from the parser and
;;; leave untouched; nothing here reconstructs any of them.
;;;
;;; Decision 0013: an error's identity is the (code, reason) PAIR, because the
;;; corpus has reasons sharing a code and one reason under two codes. Only the
;;; code is renamed here -- to llhttp's integer -- and the reason passes through,
;;; which is the least this layer can do and still be a rename.
;;;
;;; THE TWO HALVES ARE EXPORTED SEPARATELY. The tables are pure and are judged
;;; on hand-built input, before any parser runs; the recorder is the shell that
;;; drives them from the generated runtime's callback protocol. An uncalibrated
;;; instrument cannot measure a parser (decision 0008 item 4).
(library (httparse test adapter)
  (export adapter-trace-names adapter-error-codes
          adapter-event-for adapter-error-event
          make-trace-recorder trace-recorder-bindings trace-recorder-events
          trace-recorder-note-error!
          adapter-error? adapter-error-detail)
  (import (rnrs) (httparse test trace-format) (byte-machine runtime))

  (define-condition-type &adapter &error
    make-adapter-error adapter-error? (detail adapter-error-detail))

  (define (adapter-refuse who detail)
    (raise (condition (make-adapter-error detail)
                      (make-who-condition who)
                      (make-message-condition detail))))

  ;; (callback-name kind trace-name), where kind is 'event or 'span and
  ;; trace-name is the text llhttp prints -- `off=N method complete` for an
  ;; event, `span[method]` for a span.
  (define adapter-trace-names
    '((on-message-begin     event "message begin")
      (on-method-data       span  "method")
      (on-method-complete   event "method complete")
      (on-url-data          span  "url")
      (on-url-complete      event "url complete")
      (on-protocol-data     span  "protocol")
      (on-protocol-complete event "protocol complete")
      (on-version-data      span  "version")
      (on-version-complete  event "version complete")))

  ;; Our error code symbols to llhttp's ERROR numbers, one to one. A symbol
  ;; spanning two numbers, or absent here, is what decision 0013 forbids.
  ;; `unexpected-eof` has no row deliberately: llhttp reports nothing at all
  ;; when input runs out mid-token, so a trace can never carry one.
  (define adapter-error-codes
    '((strict           . 2)
      (invalid-method   . 6)
      (invalid-url      . 7)
      (invalid-constant . 8)
      (invalid-version  . 9)))

  ;; adapter-event-for : Symbol Nat (Option Bytevector) -> Event
  ;; `bytes` is the fragment for a span callback and #f for an event one.
  (define (adapter-event-for callback offset bytes)
    (let ((row (assq callback adapter-trace-names)))
      (unless row
        (adapter-refuse 'adapter-event-for
          (string-append "no trace name for callback " (symbol->string callback))))
      (let ((kind (cadr row)) (name (caddr row)))
        (case kind
          ((event)
           (when bytes
             (adapter-refuse 'adapter-event-for
               (string-append "event callback " (symbol->string callback)
                              " was given span bytes")))
           (make-trace-mark offset name))
          ((span)
           (unless bytes
             (adapter-refuse 'adapter-event-for
               (string-append "span callback " (symbol->string callback)
                              " was given no bytes")))
           (make-trace-span name offset bytes))
          (else (adapter-refuse 'adapter-event-for "unknown callback kind"))))))

  ;; adapter-error-event : Symbol String Nat -> Event
  ;; `off=N error code=C reason="R"`, the shape llhttp's driver prints.
  (define (adapter-error-event code reason offset)
    (let ((row (assq code adapter-error-codes)))
      (unless row
        (adapter-refuse 'adapter-error-event
          (string-append "no llhttp error number for code " (symbol->string code))))
      (make-trace-mark offset
                       (string-append "error code=" (number->string (cdr row))
                                      " reason=\"" reason "\""))))

  ;; The shell. A recorder holds the events in arrival order and hands out the
  ;; binding list a parser needs -- every declared callback, because they are
  ;; declared `required?` and a parser refuses a partial list.
  (define-record-type recorder (fields (mutable reversed)))

  (define (make-trace-recorder) (make-recorder '()))

  (define (recorder-push! r event)
    (recorder-reversed-set! r (cons event (recorder-reversed r))))

  ;; trace-recorder-events : Recorder -> (Listof Event)
  (define (trace-recorder-events r) (reverse (recorder-reversed r)))

  ;; A span fragment's ABSOLUTE start is the stream offset minus its length: the
  ;; callback fires having already advanced past the bytes it is handed, so
  ;; `from` is the absolute offset only when the feed started at zero.
  (define (trace-recorder-bindings r)
    (map (lambda (row)
           (let ((callback (car row)) (kind (cadr row)))
             (list callback
                   (case kind
                     ((event)
                      (lambda (p ctx)
                        (recorder-push!
                         r (adapter-event-for callback (parser-stream-offset p) #f))
                        callback-continue))
                     ((span)
                      (lambda (p ctx bv from to)
                        (let* ((len (- to from))
                               (b (make-bytevector len)))
                          (bytevector-copy! bv from b 0 len)
                          (recorder-push!
                           r (adapter-event-for callback
                                                (- (parser-stream-offset p) len) b)))
                        callback-continue))
                     (else (adapter-refuse 'trace-recorder-bindings
                                           "unknown callback kind"))))))
         adapter-trace-names))

  ;; trace-recorder-note-error! : Recorder ParserError -> Void
  (define (trace-recorder-note-error! r e)
    (recorder-push! r (adapter-error-event (parser-error-code e)
                                           (parser-error-reason e)
                                           (parser-error-offset e)))))
