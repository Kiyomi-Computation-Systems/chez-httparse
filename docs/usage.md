# Usage

You give the parser bytes. It reads them and calls your functions —
*callbacks* — to tell you what it found: here is the method, here is a
header name, the message is complete. It never copies your bytes and never
keeps them, so a callback gets a position in **your** bytevector, not a
string.

This page assumes the libraries already import; if they don't, start with
[installing.md](installing.md).

## The four steps

1. **Make a parser**, once per connection.
2. **Feed it bytes** as they arrive, in pieces of any size.
3. **Read the result** of each feed: carry on, stop on an error, or handle a
   pause.
4. **Finish** when the connection closes.

## A first parse

```scheme
(import (rnrs)
        (generated httparse-message)
        (httparse modes)
        (byte-machine runtime))

;; Copy a span out of the bytevector you fed.
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
    ;; A span can arrive in pieces when the input does, so append.
    (list 'on-url-data
          (lambda (p ctx bv from to)
            (set! target (string-append target (text bv from to)))
            callback-continue))
    (list 'on-message-begin ignore-event)
    (list 'on-method-data ignore-span)
    ;; ... and the other 22 callbacks, bound the same way.
    )
   #f
   (list (cons 'type (httparse-message-type-value 'request)))))

(define request
  (string->utf8 "GET /index.html HTTP/1.1\r\nHost: example.com\r\n\r\n"))

(parser-result-status
 (parser-feed! parser request 0 (bytevector-length request)))
;; => need-input, and target is now "/index.html"
```

The example leaves out most callbacks to stay short. The full, runnable
version is [`test/common/example-tests.sps`](../test/common/example-tests.sps);
the test suite runs it, so it always matches the library.

## 1. Make a parser

[`make-parser`](reference.md#make-parser-procedure) takes four arguments:

| Argument       | What to pass                                                          |
|:---------------|:----------------------------------------------------------------------|
| machine        | `httparse-message-machine`                                            |
| bindings       | one `(list 'callback-name procedure)` for each of the 25 callbacks    |
| user context   | anything you like; every callback receives it as `ctx`. `#f` is fine. |
| field initials | the modes: request or response, and any lenient flags                 |

**Bind every callback.** All 25 are required. If one is missing,
`make-parser` refuses rather than quietly ignoring it — a parser that
silently dropped `on-body-data` would look like a message with no body.
[callbacks.md](callbacks.md) lists them.

**Always say request or response.** Nothing in the bytes tells the parser
which is coming, so there is no safe default. [modes.md](modes.md) covers
this and the lenient flags.

**Keep one parser per connection.** It parses one message after another, so
you build it once. Building one costs about 1.6–1.8 µs, which matters if you
make one per message ([performance.md](performance.md)).

## 2. Feed it bytes

```scheme
(parser-feed! parser bv start end)
```

[`parser-feed!`](reference.md#parser-feed-procedure) reads the bytes of
`bv` from `start` up to, not including, `end`. Feed whatever you have — a
whole request, one byte, anything between. The parser picks up exactly where
it stopped, and the result is the same as if all the bytes had come in one
piece. (One rare exception, involving errors, is described in
[conformance.md](conformance.md).)

## 3. Read the result

Every feed returns a result. Its status tells you what to do next:

| Status                   | What happened                                               | What you do                                                         |
|:-------------------------|:------------------------------------------------------------|:--------------------------------------------------------------------|
| `'need-input`            | It read everything you gave it.                             | Feed more when it arrives.                                          |
| `'error`                 | The message is malformed, or a callback reported a failure. | Read the error ([errors.md](errors.md)).                            |
| `'paused`                | A callback asked to pause, or the request wants an upgrade. | Resume, then feed from where it stopped ([pausing.md](pausing.md)). |
| `'finished` / `'stopped` | The parser reached an end state.                            | Stop feeding.                                                       |

`'need-input` is the normal answer, **even after a complete message**: the
connection may carry another one. You learn that a message is complete from
the `on-message-complete` callback, not from the status.

A result carries more than its status:

| Accessor                                                                           | What it tells you                               |
|:-----------------------------------------------------------------------------------|:------------------------------------------------|
| [`parser-result-status`](reference.md#parser-result-status-accessor)               | one of the statuses above                       |
| [`parser-result-consumed`](reference.md#parser-result-consumed-accessor)           | how many bytes this feed read                   |
| [`parser-result-next`](reference.md#parser-result-next-accessor)                   | where to start the next feed in this bytevector |
| [`parser-result-stream-offset`](reference.md#parser-result-stream-offset-accessor) | how many bytes it has read since it was made    |
| [`parser-result-error`](reference.md#parser-result-error-accessor)                 | the error, when the status is `'error`          |
| [`parser-result-pause`](reference.md#parser-result-pause-accessor)                 | why it paused, when the status is `'paused`     |

`parser-result-next` counts in the same positions as the `start` and `end`
you passed, so you can feed it straight back in. The stream offset counts
from the first byte the parser ever saw, which makes it the number to log.

A typical feed loop looks like this:

```scheme
(let ((r (parser-feed! parser chunk 0 (bytevector-length chunk))))
  (case (parser-result-status r)
    ((need-input) 'read-more-from-the-socket)
    ((error) (parser-error-reason (parser-result-error r)))
    (else (parser-result-status r))))
```

## 4. Finish

When the connection closes, call
[`parser-finish!`](reference.md#parser-finish-procedure). It tells the
parser no more bytes are coming and asks: is it all right to stop here? The
result's status is `'finished`, `'error` or `'paused`. A finish reads no
bytes, so the result's consumed count is 0.

- **Stopped cleanly between messages** — the status is `'finished`.
- **Stopped halfway through a message** — the status is `'error`, with
  llhttp's `invalid-eof-state`, "Invalid EOF state" (code 14).
- **A body that runs until the connection closes** — this message completes
  here, at the finish, and nowhere else. `on-message-complete` fires during
  the finish. These are:
  - a response with neither `Content-Length` nor `Transfer-Encoding`
  - a response whose `Transfer-Encoding` does not end in `chunked`
  - a request whose `Transfer-Encoding` does not end in `chunked`, with the
    `transfer-encoding` or `chunked-length` lenient flag set

The body's bytes still arrive through `on-body-data` during the feeds that
carried them; the finish runs `on-message-complete` and nothing else. A body
that received no bytes gets no `on-body-data` call at all, not an empty one.

[`message-needs-eof?`](reference.md#message-needs-eof-predicate) says in
advance whether a message ends this way; see [connection.md](connection.md).

llhttp's test corpus never finishes a parse, so none of this is checked
against llhttp's own traces.
[`test/common/finish-tests.sps`](../test/common/finish-tests.sps) pins it
instead.

## Starting over: reset and resume

- [`parser-reset!`](reference.md#parser-reset-procedure) puts the parser
  back the way it was when you made it, so you can use it for a new
  connection. The modes you chose stay: they reset to what you passed to
  `make-parser`, not to zero.
- [`parser-resume!`](reference.md#parser-resume-procedure) lets a paused
  parser continue. It reads nothing itself — feed or finish afterwards.
  Feeding a paused parser without resuming it raises an error.
  [pausing.md](pausing.md) has the full loop.

## What to import

```scheme
(import (generated httparse-message)   ; the HTTP parser
        (byte-machine runtime)         ; make-parser, parser-feed!, results
        (httparse modes)               ; request or response, lenient flags
        (httparse methods)             ; method numbers <-> names
        (httparse decisions))          ; keep-alive or close
```

| Library                        | You need it to                                                                            |
|:-------------------------------|:------------------------------------------------------------------------------------------|
| `(generated httparse-message)` | get [`httparse-message-machine`](reference.md#httparse-message-machine-value), the parser |
| `(byte-machine runtime)`       | make a parser, feed it, and read results and errors                                       |
| `(httparse modes)`             | say request or response, and choose lenient flags                                         |
| `(httparse methods)`           | turn the method number a message reports into a name                                      |
| `(httparse decisions)`         | decide keep-alive or close after a message                                                |

The last three are plain tables and small functions; they load nothing else.
`(httparse methods)` refuses an unknown name or number rather than guessing:
method 0 is `DELETE`, so a typo must not quietly become one.

`src/generated/httparse-message.sls` is generated from
`src/httparse/grammar.sls` and checked in, so you can read the parser that
ships and load it without running the generator.
