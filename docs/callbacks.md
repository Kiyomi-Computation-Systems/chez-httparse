# Callbacks

The parser tells you what it reads by calling your procedures — its
*callbacks*. There are 25. You bind every one when you make the parser
([usage.md](usage.md)), and each returns a value that tells the parser what
to do next.

## Two kinds

An **event** says "this just happened": a message began, the headers ended.
A **span** hands you bytes: the method, a header name, a piece of the body.

```scheme
(lambda (parser ctx) outcome)              ; event
(lambda (parser ctx bv from to) outcome)   ; span
```

| Argument | What it is                                    |
|:---------|:----------------------------------------------|
| `parser` | the parser that is calling you                |
| `ctx`    | the user context you passed to `make-parser`  |
| `bv`     | the bytevector *you* passed to `parser-feed!` |
| `from`   | where the bytes start in `bv`                 |
| `to`     | where they end in `bv` (not included)         |

## A span points into your buffer

A span does not copy anything. `bv` is your own bytevector, and the bytes
are `from` up to `to`. The parser does not keep them either, so if you need
them later, copy them before you return:

```scheme
(list 'on-header-value-data
      (lambda (p ctx bv from to)
        (let ((b (make-bytevector (- to from))))
          (bytevector-copy! bv from b 0 (- to from))
          (collect-value! ctx b))   ; your code
        callback-continue))
```

**A span can arrive in pieces.** If a header value is split across two
feeds, you get two calls. Append the pieces rather than replacing them. Most
spans have a matching `-complete` event, which tells you the span has ended.

## What a callback returns

Every callback returns one of three outcomes:

| Return                                                      | What the parser does                                      |
|:------------------------------------------------------------|:----------------------------------------------------------|
| [`callback-continue`](reference.md#callback-continue-value) | keeps parsing                                             |
| [`callback-pause`](reference.md#callback-pause-value)       | stops this feed with status `'paused`                     |
| `(make-callback-failure code detail)`                       | stops with status `'error`, carrying your code and detail |

`callback-continue` and `callback-pause` are values, not procedures: return
them, don't call them. How to carry on after a pause is in
[pausing.md](pausing.md).

[`make-callback-failure`](reference.md#make-callback-failure-procedure)
takes a symbol and any detail you like, or `#f`. The feed then fails with
your code and detail, and the reason `"callback failure"`. Return anything
else and the feed fails with the code `callback-contract-violation`.
[errors.md](errors.md) covers reading errors.

## Skipping a body: `on-headers-complete`

`on-headers-complete` is the one callback that makes a decision. As well as
the three outcomes, it may return `'skip-body` to say this message has no
body to read — useful, for example, for the response to a `HEAD` request,
which carries a `Content-Length` but no body. Return `callback-continue` to
let the headers decide as usual.

It may also pause. When you resume, the parser picks the body decision up
exactly where it would have without the pause.

## Inside a callback

- **You may read the parser's fields** with
  [`parser-field-ref`](reference.md#parser-field-ref-procedure), such as the
  method, the status code or the framing flags. They are read-only.
  [connection.md](connection.md) lists the useful ones.
- **You may not feed or reset the parser that is calling you.** Either one
  raises an error.

## Where am I in the stream?

`from` and `to` say where bytes are in **this** buffer. To know where you
are in the whole stream, call
[`parser-stream-offset`](reference.md#parser-stream-offset-procedure). It
counts every byte the parser has read since it was made or reset, across
every feed and every message.

The two kinds of callback see it slightly differently:

- **An event** reads the number of bytes read *before* it. That is the
  position llhttp's traces print as `off=`, and it does not depend on how
  the input was split.
- **A span** reads the position of its piece's *end*. So the piece starts
  at `(- (parser-stream-offset p) (- to from))`. That holds for every piece,
  including one cut short because a feed ended mid-span, and an empty one.

Here is the corpus's first request, `request/sample.md#1`, fed in one piece.
The number is what `parser-stream-offset` returns inside each callback, and
`\t` is a tab:

```text
OPTIONS /url HTTP/1.1
  on-method-data       "OPTIONS"  7   starts at 7 - 7 = 0
  on-method-complete              7   the space is not read yet
  on-url-data          "/url"    12   starts at 12 - 4 = 8
  on-url-complete                13   the space is already read
...
Header2:\t Value2
  on-header-field-complete       48   the colon is read
  on-header-value-data "Value2"  56   starts at 56 - 6 = 50
```

So an event does not always sit where the span before it ended: which side
of a delimiter it lands on is llhttp's choice, event by event, and this
parser matches it.

Bytes no callback reports — whitespace, delimiters — lie between one
callback's position and the next. Their length is the difference: the tab
and the space before `Value2` are 50 − 48 = 2 bytes. Blank lines before the
first request line come before `on-message-begin`; between two messages
they come between `on-message-complete` and the next `on-reset`.

The `unit.stream-offset` test lane checks all of this on every fixture in
llhttp's corpus, feeding each chunk from a separate buffer.

## All 25 callbacks

Ten spans. Every one except `on-body-data` has an event that closes it:

| Span                            | Closed by                           |
|:--------------------------------|:------------------------------------|
| `on-method-data`                | `on-method-complete`                |
| `on-url-data`                   | `on-url-complete`                   |
| `on-protocol-data`              | `on-protocol-complete`              |
| `on-version-data`               | `on-version-complete`               |
| `on-status-data`                | `on-status-complete`                |
| `on-header-field-data`          | `on-header-field-complete`          |
| `on-header-value-data`          | `on-header-value-complete`          |
| `on-body-data`                  |                                     |
| `on-chunk-extension-name-data`  | `on-chunk-extension-name-complete`  |
| `on-chunk-extension-value-data` | `on-chunk-extension-value-complete` |

And six events that stand alone:

| Event                 | Fires when                                           |
|:----------------------|:-----------------------------------------------------|
| `on-message-begin`    | a message starts                                     |
| `on-headers-complete` | the headers have ended; it may return `'skip-body`   |
| `on-chunk-header`     | a chunk's size line has been read                    |
| `on-chunk-complete`   | a chunk has ended                                    |
| `on-message-complete` | a message has ended                                  |
| `on-reset`            | one message has ended and the next is about to begin |

That is all of them. Request-or-response and the lenient flags are not
callbacks; they are modes, set when you make the parser ([modes.md](modes.md)).

## The request target is checked

`on-url-data` hands you the whole request target as one span, but the
parser also checks its structure the way llhttp does, and refuses a target
llhttp would refuse:

```text
OPTIONS a.com:443 HTTP/1.1
  ->  error code 7, "Unexpected char in url schema", at offset 9
```

It runs llhttp's own URL rules over the target: the authority form
(`host:port`) for `CONNECT`, the general form for everything else. A bad
target fails with one of llhttp's `invalid-url` reasons. No `on-url-data`
fires before such an error: an error drops a span that is still open rather
than delivering it.

One case that looks wrong but is right: a target with **two `@` that are not
next to each other** is accepted, because llhttp accepts it —
`http://a@b@c/p` has the host `a@b@c`. Only `@@` is an error,
`Double @ in url`.

To split a target into schema, host, path, query and fragment, use the
separate URL parser: [url.md](url.md).
