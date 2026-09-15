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
          adapter-count-field adapter-finish-states adapter-finish-statuses
          adapter-message-type-callback adapter-message-types
          adapter-pause-points
          adapter-event-for adapter-error-event adapter-finish-event
          make-trace-recorder trace-recorder-bindings trace-recorder-events
          trace-recorder-note-error! trace-recorder-note-paused!
          trace-recorder-note-requested-pause!
          trace-recorder-note-finish!
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
    '(;; Between two messages on one connection, and never before the first.
      (on-reset             event "reset")
      (on-message-begin     event "message begin")
      (on-method-data       span  "method")
      (on-method-complete   event "method complete")
      (on-url-data          span  "url")
      (on-url-complete      event "url complete")
      (on-protocol-data     span  "protocol")
      (on-protocol-complete event "protocol complete")
      (on-version-data      span  "version")
      (on-version-complete  event "version complete")
      ;; A RESPONSE'S ONLY SPAN OF ITS OWN, and llhttp prints it under the
      ;; name of the field rather than of the production: `span[status]` is
      ;; the reason phrase, not the three digits, which are printed as part of
      ;; the `headers complete` line instead.
      (on-status-data       span  "status")
      (on-status-complete   event "status complete")
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
      ;; A COUNT LINE: the second kind of callback whose text carries a parser
      ;; field. llhttp's `on_chunk_header` prints `s->content_length` and
      ;; nothing else, so this reads that one field off the parser the way a
      ;; state line reads its five (decision 0014).
      (on-chunk-header           count-line "chunk header")
      (on-chunk-extension-name-data      span  "chunk_extension_name")
      (on-chunk-extension-name-complete  event "chunk_extension_name complete")
      (on-chunk-extension-value-data     span  "chunk_extension_value")
      (on-chunk-extension-value-complete event "chunk_extension_value complete")
      (on-chunk-complete         event      "chunk complete")
      (on-message-complete       event      "message complete")))

  ;; The fields a state line reads. llhttp's own callback reads SIX and
  ;; prints five of them: `s->type` chooses the line, and then either
  ;; `s->method` or `s->status_code` joins the three both kinds share. So all
  ;; six are read and the unused one is dropped by the renderer, which is what
  ;; keeps this a rename -- the alternative is to decide here which field
  ;; matters, and deciding is what decision 0014 forbids.
  (define adapter-state-fields
    '(type method status-code http-major http-minor flags content-length))

  ;; The two answers `on-message-type` may give. llhttp's harness sets
  ;; `s->type` in an init hook that prints NOTHING; this is that hook, and it
  ;; is the one binding with no trace row for exactly that reason.
  (define adapter-message-type-callback 'on-message-type)
  (define adapter-message-types '(request response))

  ;; The single field a count line reads. llhttp's chunk reader accumulates
  ;; the chunk size into the SAME field a Content-Length body uses, and its
  ;; callback prints that field, so there is one name here and it is that one.
  (define adapter-count-field 'content-length)

  ;; Our error code symbols to llhttp's ERROR numbers, one to one. A symbol
  ;; spanning two numbers, or absent here, is what decision 0013 forbids.
  ;; `unexpected-eof` has no row deliberately: llhttp reports nothing at all
  ;; when input runs out mid-token, so a trace can never carry one.
  (define adapter-error-codes
    '((strict                    . 2)
      (lf-expected               . 3)
      (unexpected-content-length . 4)
      (closed-connection         . 5)
      (invalid-method            . 6)
      (invalid-url               . 7)
      (invalid-constant          . 8)
      (invalid-version           . 9)
      (invalid-header-token      . 10)
      (invalid-content-length    . 11)
      (invalid-chunk-size        . 12)
      (invalid-status            . 13)
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

  ;; llhttp's own format strings, from its `llhttp__on_headers_complete`:
  ;;   "headers complete method=%d v=%d/%d flags=%x content_length=%llu"
  ;;   "headers complete status=%d v=%d/%d flags=%x content_length=%llu"
  ;; chosen by `s->type`, and identical after their first field. `%x` IS
  ;; LOWERCASE and Chez's `number->string` radix 16 is not, which the corpus
  ;; catches at `flags=20a`.
  ;;
  ;; llhttp HAS A THIRD ARM and it is refused here rather than rendered.
  ;; `invalid headers complete` is what its callback prints when the type is
  ;; neither -- reachable in llhttp because BOTH is its default, unreachable
  ;; here because the type arrives as a branch key and the branches are the
  ;; only writers of the field. No fixture records that line, so rendering it
  ;; would be an untested arm; refusing makes it an assertion instead.
  (define (state-line-text name fields)
    (let ((type (field-value fields 'type)))
      (string-append
       name
       (cond ((= type 1) (string-append " method=" (number->string (field-value fields 'method))))
             ((= type 2) (string-append " status=" (number->string (field-value fields 'status-code))))
             (else (adapter-refuse 'adapter-event-for
                     "the parser reached headers complete without a message type")))
       " v=" (number->string (field-value fields 'http-major))
       "/" (number->string (field-value fields 'http-minor))
       " flags=" (string-downcase (number->string (field-value fields 'flags) 16))
       " content_length=" (number->string (field-value fields 'content-length)))))

  ;; llhttp's own `llhttp__on_chunk_header`:
  ;;   "chunk header len=%d", (int) s->content_length
  ;; `%d` ON AN `(int)` CAST, not the `%llu` the state line uses. No fixture in
  ;; the corpus carries a chunk larger than 51, so nothing records what llhttp
  ;; prints for a size above INT_MAX and there is nothing here to reproduce --
  ;; this renders the field, which is what the corpus can judge.
  (define (count-line-text name fields)
    (string-append name " len="
                   (number->string (field-value fields adapter-count-field))))

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
          ((count-line)
           (when bytes
             (adapter-refuse 'adapter-event-for
               (string-append "count-line callback " (symbol->string callback)
                              " was given span bytes")))
           (make-trace-mark offset (count-line-text name fields)))
          (else (adapter-refuse 'adapter-event-for "unknown callback kind"))))))

  ;; llhttp's FINISH states. A fourth value is one this layer cannot spell --
  ;; `llhttp_finish` itself calls `abort()` on one -- so it is refused rather
  ;; than printed.
  (define adapter-finish-states '(0 1 2))

  ;; adapter-finish-event : ExactInteger -> Event
  ;; `off=NULL finish=N`, which is what llhttp's fixture harness prints once
  ;; the input runs out. NOT A CALLBACK AND NOT AN OUTCOME: the hook reads
  ;; `s->finish` and prints it with a NULL position, so there is no offset and
  ;; the number is a parser field like the five on a state line.
  (define (adapter-finish-event value)
    (unless (and (integer? value) (exact? value) (memv value adapter-finish-states))
      (adapter-refuse 'adapter-finish-event
        "the parser's finish field is not one of llhttp's three states"))
    (make-trace-mark-at-null (string-append "finish=" (number->string value))))

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
  ;; `armed` is the harness mode the recorder was BOUND with, and it starts as
  ;; `unbound` rather than `#f` so "nobody asked for a pause" and "nobody has
  ;; bound this recorder yet" stay distinguishable -- the second is a
  ;; sequencing mistake and the first is the ordinary case.
  (define-record-type recorder (fields (mutable reversed) (mutable armed)))

  (define (make-trace-recorder) (make-recorder '() 'unbound))

  (define (recorder-push! r event)
    (recorder-reversed-set! r (cons event (recorder-reversed r))))

  ;; trace-recorder-events : Recorder -> (Listof Event)
  (define (trace-recorder-events r) (reverse (recorder-reversed r)))

  ;; THE PAUSE POINTS UPSTREAM DECLARES, read out of llhttp's
  ;; `test/fixtures/extra.c` at v9.4.3-1-gee51043 by listing the function each
  ;; `#ifdef LLHTTP__TEST_PAUSE_*` sits inside. A fixture's `pause` meta names
  ;; the MACRO, so the key here is upstream's spelling and the value is the
  ;; callback this project binds.
  ;;
  ;; TWO ROWS ARE NOT A FOLD OF THEIR KEY. `on_chunk_extension_name` guards the
  ;; macro inside `llhttp__on_chunk_extension_name_complete`, not inside the
  ;; span callback of the same name, and likewise for the value. Deriving this
  ;; table by replacing underscores with hyphens would arm a span callback --
  ;; a callback upstream never pauses in, and one that takes five arguments
  ;; where a pausing callback takes two.
  ;;
  ;; `on_reset` is here because upstream declares it. No vendored fixture uses
  ;; it, and a table that held only the used rows would be a table of this
  ;; corpus rather than of llhttp's harness.
  (define adapter-pause-points
    '(("on_message_begin"          . on-message-begin)
      ("on_reset"                  . on-reset)
      ("on_method_complete"        . on-method-complete)
      ("on_url_complete"           . on-url-complete)
      ("on_protocol_complete"      . on-protocol-complete)
      ("on_version_complete"       . on-version-complete)
      ("on_status_complete"        . on-status-complete)
      ("on_header_field_complete"  . on-header-field-complete)
      ("on_header_value_complete"  . on-header-value-complete)
      ("on_headers_complete"       . on-headers-complete)
      ("on_chunk_header"           . on-chunk-header)
      ("on_chunk_extension_name"   . on-chunk-extension-name-complete)
      ("on_chunk_extension_value"  . on-chunk-extension-value-complete)
      ("on_chunk_complete"         . on-chunk-complete)
      ("on_message_complete"       . on-message-complete)))

  ;; The callback whose RETURN VALUE upstream reads, and the only one: the
  ;; `skip body` line and the 1 that follows it are both inside
  ;; `llhttp__on_headers_complete`.
  (define adapter-skip-body-callback 'on-headers-complete)

  ;; checked-mode : Any -> HarnessMode
  ;; `#f` is the plain harness; `(pause <llhttp name>)` arms one callback;
  ;; `(skip-body)` makes the headers-complete callback answer 1. Anything else
  ;; is refused rather than read as the plain harness, because a mode that
  ;; quietly armed nothing would give a fixture that must pause a clean
  ;; unpaused trace and a diff that names the wrong thing.
  ;;
  ;; THE TWO ARE EXCLUSIVE BY CONSTRUCTION, which is upstream's own shape:
  ;; `extra.c` guards `on_headers_complete` with
  ;; `#ifdef ..._PAUSE_ON_HEADERS_COMPLETE / #elif defined(..._SKIP_BODY)`, so
  ;; a build is never both and neither is a mode here.
  (define (checked-mode mode)
    (cond
     ((eq? mode #f) #f)
     ((and (pair? mode) (eq? (car mode) 'pause)
           (pair? (cdr mode)) (null? (cddr mode))
           (string? (cadr mode)))
      (unless (assoc (cadr mode) adapter-pause-points)
        (adapter-refuse 'trace-recorder-bindings
          (string-append "llhttp declares no pause macro for " (cadr mode))))
      mode)
     ((and (pair? mode) (eq? (car mode) 'skip-body) (null? (cdr mode))) mode)
     (else (adapter-refuse 'trace-recorder-bindings
             "a harness mode is #f, (pause <llhttp callback name>) or (skip-body)"))))

  ;; mode-pause-callback : HarnessMode -> (Option Symbol)
  (define (mode-pause-callback mode)
    (and (pair? mode) (eq? (car mode) 'pause)
         (cdr (assoc (cadr mode) adapter-pause-points))))

  ;; mode-skip-body? : HarnessMode -> Boolean
  (define (mode-skip-body? mode)
    (and (pair? mode) (eq? (car mode) 'skip-body)))

  ;; push-event! : Recorder Symbol Symbol Parser -> Void
  ;; The event one of the three NON-SPAN kinds records. A pausing callback
  ;; records through this too, so what it prints is produced by the same
  ;; construction an unpaused one uses -- a second copy would be a second
  ;; answer to "what does this callback print", and no trace could tell the
  ;; two apart until they disagreed.
  (define (push-event! r callback kind p)
    (recorder-push!
     r (case kind
         ((event) (adapter-event-for callback (parser-stream-offset p) #f #f))
         ;; The only arm that reads parser STATE rather than callback
         ;; arguments. It reads the five fields llhttp's own callback reads and
         ;; hands them to the pure half, which owns the format -- so a wrong
         ;; number here is a wrong number in the parser, not in the rendering.
         ((state-line)
          (adapter-event-for callback (parser-stream-offset p) #f
                             (map (lambda (f) (cons f (parser-field-ref p f)))
                                  adapter-state-fields)))
         ;; The same read as the state-line arm, over one name.
         ((count-line)
          (adapter-event-for callback (parser-stream-offset p) #f
                             (list (cons adapter-count-field
                                         (parser-field-ref p adapter-count-field)))))
         (else (adapter-refuse 'push-event! "unknown callback kind")))))

  ;; A span fragment's ABSOLUTE start is the stream offset minus its length: the
  ;; callback fires having already advanced past the bytes it is handed, so
  ;; `from` is the absolute offset only when the feed started at zero.
  ;; trace-recorder-bindings : Recorder Symbol HarnessMode
  ;;                           -> (Listof (List Symbol Procedure))
  ;; THE TYPE IS A REQUIRED ARGUMENT, and that is the point: llhttp's harness
  ;; cannot build a parser without saying what it is parsing either. A default
  ;; here would silently make every response a request.
  ;;
  ;; SO IS THE MODE, for the same reason: upstream bakes it into the binary as
  ;; a `-D` define and caches one binary per mode, so a parser that has not
  ;; been told its mode does not exist over there either.
  ;;
  ;; THE PAUSING CALLBACK RECORDS FIRST AND PAUSES SECOND. Every guarded
  ;; callback in `test/fixtures/extra.c` calls `llparse__print` and only then
  ;; returns `LLPARSE__ERROR_PAUSE`, so the event and the pause land at the
  ;; same offset with the event ahead. Here that ordering is structural: the
  ;; two arms differ only in the value they answer with.
  (define (trace-recorder-bindings r type mode)
    (unless (memq type adapter-message-types)
      (adapter-refuse 'trace-recorder-bindings
        "a recorder was asked to bind a parser that is neither a request nor a response"))
    (for-each (lambda (row)
                (unless (memq (cadr row) '(event state-line count-line span))
                  (adapter-refuse 'trace-recorder-bindings "unknown callback kind")))
              adapter-trace-names)
    (recorder-armed-set! r (checked-mode mode))
    (let ((pause-at (mode-pause-callback (recorder-armed r)))
          (skip-at (and (mode-skip-body? (recorder-armed r))
                        adapter-skip-body-callback)))
      (cons
       (list adapter-message-type-callback (lambda (p ctx) type))
       (map (lambda (row)
              (let ((callback (car row)) (kind (cadr row)))
                (list callback
                      (if (eq? kind 'span)
                          (lambda (p ctx bv from to)
                            (let* ((len (- to from))
                                   (b (make-bytevector len)))
                              (bytevector-copy! bv from b 0 len)
                              (recorder-push!
                               r (adapter-event-for callback
                                                    (- (parser-stream-offset p) len) b #f)))
                            callback-continue)
                          ;; THREE ARMS THAT DIFFER ONLY IN THE ANSWER, and
                          ;; one that prints a second line before giving it.
                          ;; Upstream's skip-body callback calls
                          ;; `llparse__print(p, endp, "skip body")` and THEN
                          ;; returns 1, so `skip body` is the callback's own
                          ;; output and lands at the offset its event did --
                          ;; unlike `pause`, which the driver prints.
                          (let ((answer (cond ((eq? callback pause-at) callback-pause)
                                              ((eq? callback skip-at) 'skip-body)
                                              (else callback-continue))))
                            (lambda (p ctx)
                              (push-event! r callback kind p)
                              (when (eq? callback skip-at)
                                (recorder-push!
                                 r (make-trace-mark (parser-stream-offset p) "skip body")))
                              answer))))))
            adapter-trace-names))))

  ;; trace-recorder-note-requested-pause! : Recorder Nat -> Void
  ;; `off=N pause`, the line upstream's driver prints when a callback answers
  ;; `LLPARSE__ERROR_PAUSE`. It is a rename of a pause this harness ASKED FOR,
  ;; which is why an unarmed recorder refuses: a parser that stopped where
  ;; llhttp does not would otherwise render a trace that looks deliberate, and
  ;; a reasonless pause is exactly the shape that has nothing else to rename.
  (define (trace-recorder-note-requested-pause! r offset)
    (unless (pair? (recorder-armed r))
      (adapter-refuse 'trace-recorder-note-requested-pause!
        "the parser paused with no reason and this harness asked for no pause"))
    (recorder-push! r (make-trace-mark offset "pause")))

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

  ;; The outcomes a `*-finish` fixture is recorded ending in. All four in the
  ;; corpus run out of input cleanly, so those are the ones this layer can
  ;; spell.
  (define adapter-finish-statuses '(need-input stopped finished))

  ;; trace-recorder-note-finish! : Recorder Parser (Option Symbol) -> Void
  ;; Reads the parser's own `finish` field, the way the state-line arm reads
  ;; its five. Called once, after the last feed, and only for the fixture
  ;; types whose harness asks for it.
  ;;
  ;; AN ERRORED `*-finish` PARSE IS REFUSED, NOT GUESSED. `llhttp__test_finish`
  ;; prints unconditionally, but whether llparse's driver still calls it after
  ;; a failed `llparse_execute` is not visible from the vendored sources, and
  ;; every `*-finish` fixture in the corpus parses cleanly -- so no trace
  ;; records the combination. Like every other row with nothing to rename,
  ;; this refuses, which makes the fixture fail rather than the lane crash.
  (define (trace-recorder-note-finish! r p status)
    (unless (or (not status) (memq status adapter-finish-statuses))
      (adapter-refuse 'trace-recorder-note-finish!
        (string-append "a *-finish fixture ended in `" (symbol->string status)
                       "`, which the oracle never records")))
    (recorder-push! r (adapter-finish-event (parser-field-ref p 'finish))))

  ;; trace-recorder-note-error! : Recorder ParserError -> Void
  (define (trace-recorder-note-error! r e)
    (recorder-push! r (adapter-error-event (parser-error-code e)
                                           (parser-error-reason e)
                                           (parser-error-offset e)))))
