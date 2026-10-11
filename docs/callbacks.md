# Callbacks

The parser reports what it reads by calling procedures you bind when you
make it. There are 25, every one is required, and each returns an outcome
that tells the parser whether to go on. Making a parser and feeding it is
[usage.md](usage.md).

## Two shapes

An **event** callback marks a point in the message. A **span** callback
delivers bytes.

```scheme
(lambda (parser ctx) outcome)              ; event
(lambda (parser ctx bv from to) outcome)   ; span
```

| Argument | What it is                                    |
|:---------|:----------------------------------------------|
| `parser` | the parser that is running                    |
| `ctx`    | the user context you passed to `make-parser`  |
| `bv`     | the bytevector *you* passed to `parser-feed!` |
| `from`   | where this fragment starts in `bv`            |
| `to`     | where it ends in `bv`, exclusive              |

The bytes in `[from, to)` are not copied and are not retained. Copy what
you need before returning:

```scheme
(list 'on-header-value-data
      (lambda (p ctx bv from to)
        (let ((b (make-bytevector (- to from))))
          (bytevector-copy! bv from b 0 (- to from))
          (collect-value! ctx b))   ; your code
        callback-continue))
```

A span split across feeds can arrive as several fragments, so append them
rather than assign. Where a span has a `-complete` event, that event says
the span has ended.

A callback may read the parser's fields with
[`parser-field-ref`](reference.md#parser-field-ref-procedure), which is
read-only; [connection.md](connection.md) covers the fields worth reading.
A callback may not feed or reset the parser it is running inside: either
raises.

## Outcomes

Every callback returns one of three outcomes:

| Outcome                                                     | Effect                                                   |
|:------------------------------------------------------------|:---------------------------------------------------------|
| [`callback-continue`](reference.md#callback-continue-value) | carry on parsing                                         |
| [`callback-pause`](reference.md#callback-pause-value)       | stop this feed with status `'paused`                     |
| `(make-callback-failure code detail)`                       | stop with status `'error`, carrying your code and detail |

`callback-continue` and `callback-pause` are values, not procedures:
return them, don't call them. Resuming after a pause is
[pausing.md](pausing.md).

[`make-callback-failure`](reference.md#make-callback-failure-procedure)
takes a symbol and any detail you like, or `#f`. The feed's error then
carries your code and detail under the reason `"callback failure"`. A
callback that returns anything else fails the same way under the code
`callback-contract-violation`. Reading an error is [errors.md](errors.md).

## The one callback that answers

`on-headers-complete` is a **decision**. Besides the three outcomes above,
it may return `'skip-body`, which tells the parser the message has no body
to read. Return `callback-continue` to let the headers decide.

Pausing is allowed there, because a resumed run re-enters the body decision
exactly where an unpaused one would.

It is the only one. Whether a request or a response is coming is not a
callback but the `type` mode; see [modes.md](modes.md).

## Where a callback is in the stream

`from` and `to` place a span's bytes in the buffer you fed and say nothing
about the stream, and an event is handed no position at all. For the
stream, read
[`parser-stream-offset`](reference.md#parser-stream-offset-procedure): the
bytes the parser has taken since it was made or last reset, counted across
feeds and across every message parsed on it. Between feeds it is the number
`parser-result-stream-offset` reported.

Inside a callback it says where that callback is, and the two shapes answer
differently:

- **An event callback** reads the bytes taken before it. That is the
  position llhttp's traces print as `off=` for the event, and it is the
  same however the input was split across feeds.
- **A span callback** reads the position of its fragment's **end**, so the
  fragment starts at `(- (parser-stream-offset p) (- to from))`. That holds
  whichever feed delivered the fragment, including one cut off because a
  feed ended with the span still open, and an empty one, which starts where
  it ends.

The corpus's first request, `request/sample.md#1`, shows both, fed in one
piece (`\t` is a tab):

```text
OPTIONS /url HTTP/1.1
  on-method-data            "OPTIONS"  reads  7   it starts at 7 - 7 = 0
  on-method-complete                   reads  7   the space after OPTIONS is not yet taken
  on-url-data               "/url"     reads 12   it starts at 12 - 4 = 8
  on-url-complete                      reads 13   the space after /url is already taken
...
Header2:\t Value2
  on-header-field-complete             reads 48   the colon is taken
  on-header-value-data      "Value2"   reads 56   it starts at 56 - 6 = 50
```

So an event does not always sit where the span before it ended. Which side
of a delimiter it lands on is llhttp's choice, made event by event, and the
corpus's logs record every one.

A run of bytes no callback covers lies between one callback's position and
the next one's, so its length is the difference: the tab and the space
before `Value2` are 50 - 48 = 2 bytes. Blank lines before the first request
line are the bytes taken before `on-message-begin`. Between two messages
they lie between `on-message-complete` and the `on-reset` that follows it.

`unit.stream-offset` holds the parser to all of this over every fixture in
the corpus, feeding each chunk from a buffer of its own.

## The full list

Ten spans, each but `on-body-data` with an event that closes it:

| Span                            | Event                               |
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

And six events with no span: `on-message-begin`, `on-headers-complete`,
`on-chunk-header`, `on-chunk-complete`, `on-message-complete`, `on-reset`.

That is the whole list: **twenty-five, all required**. Request-or-response
and the lenient flags are modes, not callbacks.

`on-reset` fires between pipelined messages on one parser, before
`on-message-begin` of the next.

## The request target is checked, not just captured

`on-url-data` delivers the **whole** target as one span, but a target whose
structure llhttp rejects is an error here too:

```text
OPTIONS a.com:443 HTTP/1.1
  ->  error code 7, "Unexpected char in url schema", at offset 9
```

The parser runs llhttp's own URL machine over the target, entering it at
the authority form for `CONNECT` and at the general form for everything
else. Such a message is refused, with one of llhttp's `invalid-url`
reasons. No `on-url-data` fires before such an error: the span is open when
the refusal happens, and an error abandons an open span rather than
flushing it.

A target with **two userinfo `@` that are not adjacent** is accepted,
because llhttp accepts it: `http://a@b@c/p` is a host of `a@b@c`. Only `@@`
is `Double @ in url`.

If you want the target broken into schema, host, path, query and fragment,
that is a separate parser; see [url.md](url.md).
