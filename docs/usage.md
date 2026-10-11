# Usage

This page assumes the libraries already import; see
[installing.md](installing.md) if they don't yet.

The parser is a state machine plus a binding list. You hand it bytes and it
calls you back. It allocates nothing per byte, copies no spans and keeps no
buffer of its own, which is why a span callback receives bounds into *your*
bytevector rather than a string.

## Getting started

```scheme
(import (rnrs)
        (generated httparse-message)
        (httparse modes)
        (byte-machine runtime))

;; Copy a span out of the buffer you fed. Nothing is retained after the
;; callback returns, so take what you need before returning.
(define (text bv from to)
  (let ((b (make-bytevector (- to from))))
    (bytevector-copy! bv from b 0 (- to from))
    (utf8->string b)))

(define (ignore-event p ctx) callback-continue)
(define (ignore-span p ctx bv from to) callback-continue)

(define target "")

(define parser
  (make-parser
   httparse-message-machine
   (list
    ;; A span can arrive in several pieces when the input is split across
    ;; feeds, so append rather than assign.
    (list 'on-url-data
          (lambda (p ctx bv from to)
            (set! target (string-append target (text bv from to)))
            callback-continue))
    (list 'on-message-begin ignore-event)
    (list 'on-method-data ignore-span)
    ;; ... and every other callback, bound the same way. All 25 are
    ;; required: a binding list with a hole is refused here.
    )
   #f
   ;; Request or response: nothing in the bytes says which is coming.
   (list (cons 'type (httparse-message-type-value 'request)))))

(define request
  (string->utf8 "GET /index.html HTTP/1.1\r\nHost: example.com\r\n\r\n"))

(parser-result-status
 (parser-feed! parser request 0 (bytevector-length request)))
;; => need-input, and target is "/index.html"
```

The complete, runnable version is
[`test/common/example-tests.sps`](../test/common/example-tests.sps). The
test suite runs it, so it cannot drift from the library; it binds all 25
callbacks, feeds a request in three pieces, reads parser fields and reads an
error.

The callbacks and their arguments are [callbacks.md](callbacks.md). The
modes are [modes.md](modes.md). Errors are [errors.md](errors.md), and
pauses and upgrade hand-offs are [pausing.md](pausing.md).

## What to import

```scheme
(import (generated httparse-message)   ; httparse-message-machine
        (httparse modes)               ; the mode tables, pure
        (httparse methods)             ; the method table, pure
        (httparse decisions)           ; keep-alive / needs-eof, pure
        (byte-machine runtime))        ; make-parser, parser-feed!, ...
```

| Library                         | You need it to                                             |
|---------------------------------|------------------------------------------------------------|
| `(generated httparse-message)`  | get [`httparse-message-machine`](reference.md#httparse-message-machine-value), the parser itself |
| `(byte-machine runtime)`        | make a parser, feed it, and read results and errors        |
| `(httparse modes)`              | spell `make-parser`'s fourth argument                      |
| `(httparse methods)`            | turn the method number a message reports into a name      |
| `(httparse decisions)`          | decide keep-alive or close after a message                 |

`src/generated/httparse-message.sls` is a derived file, emitted from
`src/httparse/grammar.sls` and committed, so what ships is reviewable as a
diff and loads without running a generator. It depends on
`(byte-machine runtime)` and nothing else.

`(httparse modes)` is pure and depends on nothing. It is llhttp's two mode
tables and the arithmetic over them. The integers are llhttp's own, so a
caller that already has one may pass it directly.

`(httparse methods)` is pure in the same way: llhttp's 47 method names and
the number it prints for each. A message reports its method as that number;
[`httparse-method-name`](reference.md#httparse-method-name-procedure) turns
it into a symbol for logging or routing, and
[`httparse-method-number`](reference.md#httparse-method-number-procedure)
goes back. An unknown name or number is refused, never defaulted: zero is
`DELETE`, a real method, so a typo must not read as one.

`(httparse decisions)` is covered in [connection.md](connection.md).

## Making a parser

[`make-parser`](reference.md#make-parser-procedure) takes up to four
arguments:

| Argument          | What it is                                                     |
|-------------------|----------------------------------------------------------------|
| machine           | `httparse-message-machine`                                     |
| bindings          | a list of `(list 'callback-name procedure)`, one per callback  |
| user context      | any value; handed back to every callback as `ctx`             |
| field initials    | optional; an alist that sets the modes                         |

Use the user context for the connection state you would otherwise close
over. `#f` is fine.

**Every callback must be bound.** All 25 are required, and a binding list
with a hole is refused when the parser is made, not quietly ignored. A
parser that silently dropped `on-body-data` would look like a message with
no body.

The fourth argument is where the modes go: request or response, and any of
llhttp's eleven lenient flags. Request-or-response has no safe default, so
always pass it. See [modes.md](modes.md).

## Feeding bytes

```scheme
(parser-feed! parser bv start end)
```

[`parser-feed!`](reference.md#parser-feed-procedure) consumes the half-open
range `[start, end)` of `bv`. Feed as much or as little as you have. The
parser resumes exactly where it stopped, and a token, a header or a body
split across any number of feeds produces the same result as one whole
buffer. One exception is measured and documented in
[conformance.md](conformance.md).

Each feed returns a result.

## Reading the result

| Accessor                       | What it gives                                    |
|--------------------------------|--------------------------------------------------|
| [`parser-result-status`](reference.md#parser-result-status-accessor)         | one of the statuses below                        |
| [`parser-result-consumed`](reference.md#parser-result-consumed-accessor)       | bytes taken from this feed                       |
| [`parser-result-next`](reference.md#parser-result-next-accessor)           | where to resume in this buffer                   |
| [`parser-result-stream-offset`](reference.md#parser-result-stream-offset-accessor)  | bytes taken since the parser was made            |
| [`parser-result-error`](reference.md#parser-result-error-accessor)          | a `ParserError` when the status is `'error`      |
| [`parser-result-pause`](reference.md#parser-result-pause-accessor)          | the pause reason when the status is `'paused`    |

`parser-result-next` shares the coordinates of the `start` and `end` you
passed, so it feeds straight back in. `parser-result-stream-offset` is the
absolute count, and is what you log.

| Status                   | Meaning                                                          |
|--------------------------|------------------------------------------------------------------|
| `'need-input`            | The range is consumed; feed more.                                |
| `'error`                 | The message is malformed, a callback failed, or the HTTP/2 preface handed off. |
| `'paused`                | A callback returned `callback-pause`, or a CONNECT/Upgrade hand-off. |
| `'finished` / `'stopped` | The machine reached a terminal state.                            |

`'need-input` is the ordinary outcome, including **after a complete
message**: a connection may carry another one, so a completed message is
not a status of its own. You learn of it from `on-message-complete`.

On `'error`, `parser-result-error` carries the detail, and for a
malformation the parser makes no further progress. Read its code, reason
and offset as [errors.md](errors.md) describes.

On `'paused`, call `parser-resume!` and feed again from
`parser-result-next`. The resume loop, and how to tell an ordinary pause
from an upgrade hand-off, are in [pausing.md](pausing.md). The HTTP/2
preface hands off on the `'error` channel instead, and pausing.md covers
that too.

```scheme
(let ((r (parser-feed! parser chunk 0 (bytevector-length chunk))))
  (case (parser-result-status r)
    ((need-input) 'feed-more)
    ((error) (parser-error-reason (parser-result-error r)))
    (else (parser-result-status r))))
```

## Lifecycle

Three procedures move a parser between parses, past a pause, and to the end
of its input.

### Reset

[`parser-reset!`](reference.md#parser-reset-procedure) returns the parser to
its just-constructed state, fields included. They are restored to the
initials the parser was **built with**: yours for the two modes, the
machine's declared ones for everything else. Not to zero, and not back to
the machine's defaults, so a reset keeps the request-or-response mode you
chose.

### Resume

[`parser-resume!`](reference.md#parser-resume-procedure) changes the
lifecycle only. No callback runs, no input is read, and it returns an
acknowledgement symbol rather than a result. Feed or finish again
afterwards. Feeding a paused parser without resuming it raises.

### Finish

[`parser-finish!`](reference.md#parser-finish-procedure) says the input has
ended and asks whether stopping here is legal. It runs the machine with
input exhausted, taking each state's end-of-input route, and returns a
result whose status is `'finished`, `'error` or `'paused`. A finish reads no
bytes, so its result's `consumed` is 0 and `next` repeats the stream
offset.

Finishing from an unsafe, mid-message state is llhttp's
`invalid-eof-state`, "Invalid EOF state" (code 14), the same from every such
state.

A body the **connection** delimits is the one message that completes at
`parser-finish!` and nowhere else: its body runs to the close, so no feed
can end it. That is:

- a response with neither `Content-Length` nor `Transfer-Encoding`
- a response whose `Transfer-Encoding` does not end in `chunked`
- a request whose `Transfer-Encoding` does not end in `chunked`, under the
  `transfer-encoding` or `chunked-length` lenient flag

`on-message-complete` fires on that finish, mirroring llhttp's
`llhttp_finish` for a `SAFE_WITH_CB` body, and a pause or failure that
callback returns is what the finish result carries.

It is the only callback a finish runs. The body's bytes arrive with the
feeds that carried them, which is where llhttp delivers them too, so by the
finish every one has been through `on-body-data`. A body that got no bytes
gets no `on-body-data` at all, not an empty one at the finish; llhttp's
`on_body` does not fire for it either.

llhttp's conformance corpus never calls `llhttp_finish`, so a finish's
outcome carries no corpus evidence. The behaviour above is pinned by
[`test/common/finish-tests.sps`](../test/common/finish-tests.sps) instead.
Pauses from a feed are different: 24 corpus fixtures record one, and this
parser matches all of them at every chunk size.

Whether a message is close-delimited is the `message-needs-eof?` decision;
see [connection.md](connection.md).
