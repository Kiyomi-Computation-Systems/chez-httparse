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
  (export adapter-trace-names adapter-error-codes adapter-state-fields
          adapter-event-for adapter-error-event
          make-trace-recorder trace-recorder-bindings trace-recorder-events
          trace-recorder-note-error! trace-recorder-note-paused!
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
      (on-version-complete  event "version complete")
      (on-header-field-data      span  "header_field")
      (on-header-field-complete  event "header_field complete")
      (on-header-value-data      span  "header_value")
      (on-header-value-complete  event "header_value complete")
      ;; A STATE LINE: an event whose text carries parser fields. llhttp's own
      ;; callback prints `s->method, s->http_major, s->http_minor, s->flags,
      ;; s->content_length` and nothing else, so reading the same five fields
      ;; off the parser is the closest correspondence there is -- and it keeps
      ;; this layer a rename, because not one of the numbers is reconstructed
      ;; from the headers that produced them (decision 0014).
      (on-headers-complete       state-line "headers complete")
      (on-body-data              span       "body")
      (on-message-complete       event      "message complete")))

  ;; The fields a state line reads, in llhttp's print order. Exported so the
  ;; set is assertable without a parser.
  (define adapter-state-fields '(method http-major http-minor flags content-length))

  ;; Our error code symbols to llhttp's ERROR numbers, one to one. A symbol
  ;; spanning two numbers, or absent here, is what decision 0013 forbids.
  ;; `unexpected-eof` has no row deliberately: llhttp reports nothing at all
  ;; when input runs out mid-token, so a trace can never carry one.
  (define adapter-error-codes
    '((strict                    . 2)
      (lf-expected               . 3)
      (unexpected-content-length . 4)
      (invalid-method            . 6)
      (invalid-url               . 7)
      (invalid-constant          . 8)
      (invalid-version           . 9)
      (invalid-header-token      . 10)
      (invalid-content-length    . 11)
      (invalid-transfer-encoding . 15)
      ;; PRI's h2 preface is an ERROR in llhttp, not a pause -- `p.error(
      ;; ERROR.PAUSED_H2_UPGRADE, ...)` -- so unlike code 22 it has a code and
      ;; a reason to rename, and a row here.
      (paused-upgrade            . 22)
      (paused-h2-upgrade         . 23)
      (cr-expected               . 25)
      (unexpected-space          . 30)))

  ;; field-value : (Listof (Pair Symbol ExactInteger)) Symbol -> ExactInteger
  ;; No default and no coercion: a field the parser did not supply, or supplied
  ;; as something other than a non-negative exact integer, is a refusal.
  (define (field-value fields name)
    (let ((row (and (list? fields) (assq name fields))))
      (unless (and row (integer? (cdr row)) (exact? (cdr row)) (>= (cdr row) 0))
        (adapter-refuse 'adapter-event-for
          (string-append "no parser field " (symbol->string name)
                         " for a state line")))
      (cdr row)))

  ;; llhttp's own format string, from its `llhttp__on_headers_complete`:
  ;;   "headers complete method=%d v=%d/%d flags=%x content_length=%llu"
  ;; `%x` IS LOWERCASE and Chez's `number->string` radix 16 is not, which the
  ;; corpus catches at `flags=20a`.
  (define (state-line-text name fields)
    (string-append
     name
     " method=" (number->string (field-value fields 'method))
     " v=" (number->string (field-value fields 'http-major))
     "/" (number->string (field-value fields 'http-minor))
     " flags=" (string-downcase (number->string (field-value fields 'flags) 16))
     " content_length=" (number->string (field-value fields 'content-length))))

  ;; adapter-event-for : Symbol Nat (Option Bytevector)
  ;;                     (Option (Listof (Pair Symbol ExactInteger))) -> Event
  ;; `bytes` is the fragment for a span callback and #f otherwise; `fields` is
  ;; the parser's own field values for a state-line callback and #f otherwise.
  ;; Both are REQUIRED arguments: an argument a caller must pass is a check,
  ;; and an omitted one would be a default.
  (define (adapter-event-for callback offset bytes fields)
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
          ((state-line)
           (when bytes
             (adapter-refuse 'adapter-event-for
               (string-append "state-line callback " (symbol->string callback)
                              " was given span bytes")))
           (make-trace-mark offset (state-line-text name fields)))
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
                         r (adapter-event-for callback (parser-stream-offset p) #f #f))
                        callback-continue))
                     ;; The only arm that reads parser STATE rather than
                     ;; callback arguments. It reads the five fields llhttp's
                     ;; own callback reads and hands them to the pure half,
                     ;; which owns the format -- so a wrong number here is a
                     ;; wrong number in the parser, not in the rendering.
                     ((state-line)
                      (lambda (p ctx)
                        (recorder-push!
                         r (adapter-event-for
                            callback (parser-stream-offset p) #f
                            (map (lambda (f) (cons f (parser-field-ref p f)))
                                 adapter-state-fields)))
                        callback-continue))
                     ((span)
                      (lambda (p ctx bv from to)
                        (let* ((len (- to from))
                               (b (make-bytevector len)))
                          (bytevector-copy! bv from b 0 len)
                          (recorder-push!
                           r (adapter-event-for callback
                                                (- (parser-stream-offset p) len) b #f)))
                        callback-continue))
                     (else (adapter-refuse 'trace-recorder-bindings
                                           "unknown callback kind"))))))
         adapter-trace-names))

  ;; trace-recorder-note-paused! : Recorder (Option ParserError) -> Void
  ;; A RENAME LIKE EVERY OTHER ROW. llhttp prints a
  ;; pause the way it prints an error, and a pause now carries the same
  ;; (code, reason) an error does -- so this reads them off the parser's own
  ;; value and renames the code, exactly as `trace-recorder-note-error!` does.
  ;;
  ;; A pause with NO declared reason is still a refusal, not a guess: the
  ;; reason is optional upstream, and a parser that pauses without saying why
  ;; has produced something this vocabulary cannot spell.
  (define (trace-recorder-note-paused! r pause)
    (unless (parser-error? pause)
      (adapter-refuse 'trace-recorder-note-paused!
        "the parser paused without a declared reason, so there is nothing to rename"))
    (recorder-push! r (adapter-error-event (parser-error-code pause)
                                           (parser-error-reason pause)
                                           (parser-error-offset pause))))

  ;; trace-recorder-note-error! : Recorder ParserError -> Void
  (define (trace-recorder-note-error! r e)
    (recorder-push! r (adapter-error-event (parser-error-code e)
                                           (parser-error-reason e)
                                           (parser-error-offset e)))))
