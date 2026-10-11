# Parser state and the connection

After each message you make one decision: **keep the connection open** for
another message, or **close it**. The parser has the facts; llhttp has the
rules. This page shows how to read the first and apply the second.

## Reading what the parser knows

[`parser-field-ref`](reference.md#parser-field-ref-procedure) returns one of
the parser's fields as an integer:

```scheme
(parser-field-ref p 'status-code)   ; => 200
```

| Field             | What it holds                                              |
|:------------------|:-----------------------------------------------------------|
| `'method`         | the request method, as llhttp's method number              |
| `'status-code`    | the response's three-digit status                          |
| `'http-major`     | the major version: the first `1` of `HTTP/1.1`             |
| `'http-minor`     | the minor version: the second `1` of `HTTP/1.1`            |
| `'flags`          | llhttp's flag bits: framing, `Connection` values, and more |
| `'content-length` | how much of the body is **still to come**                  |
| `'upgrade`        | 1 if this message is an upgrade                            |

Three things to know:

- **The fields are read-only.** Nothing you do in a callback changes them.
- **An unknown name raises an error.** It is never quietly answered with 0.
- **`content-length` counts down** as the body arrives, as llhttp's does.
  Read it in `on-headers-complete` for the declared length; by
  `on-message-complete` it is 0.

To turn `'method` into a name such as `GET`, use
[`httparse-method-name`](reference.md#httparse-method-name-procedure). When
`'upgrade` is set, and how long it stays set, is in
[pausing.md](pausing.md#knowing-in-advance-the-upgrade-field).

## Keep the connection open?

`(httparse decisions)` gives you llhttp's own two rules:

| Procedure                                                        | Asks                                     | llhttp's version           |
|:-----------------------------------------------------------------|:-----------------------------------------|:---------------------------|
| [`should-keep-alive?`](reference.md#should-keep-alive-predicate) | can another message follow this one?     | `llhttp_should_keep_alive` |
| [`message-needs-eof?`](reference.md#message-needs-eof-predicate) | does this message end only at the close? | `llhttp_message_needs_eof` |

Call `should-keep-alive?` when a message completes:

```scheme
(import (httparse decisions))

(list 'on-message-complete
      (lambda (p ctx)
        (remember-keep-alive
         ctx
         (should-keep-alive? (parser-field-ref p 'http-major)
                             (parser-field-ref p 'http-minor)
                             'request    ; the type you gave make-parser
                             (parser-field-ref p 'status-code)
                             (parser-field-ref p 'flags)))
        callback-continue))
```

**Read the fields inside the callback.** Between one message and the next,
the parser clears `flags`, so read them in `on-headers-complete` or
`on-message-complete`, not later.

**Pass the type you chose**, `'request` or `'response`, the same one you
gave `make-parser` ([modes.md](modes.md)). An unknown type raises an error
rather than being treated as a response.

### How `should-keep-alive?` decides

It says yes only if both are true:

1. **The version and `Connection` header allow it.** HTTP/1.1 stays open
   unless the message said `Connection: close`. Anything else must have said
   `Connection: keep-alive`.
2. **The message does not need the connection to close** to end — that is,
   `message-needs-eof?` is false.

One surprise, matching llhttp exactly: "HTTP/1.1 or later" is llhttp's
literal test `major > 0 && minor > 0`. So `HTTP/2.0`, whose minor is 0, needs
an explicit `Connection: keep-alive`, where a test for "at least 1.1" would
not.

### When a message ends at the close

`message-needs-eof?` asks whether a message ends only when the connection
closes: a body with no stated length, which runs until the close. Such a
message completes at [`parser-finish!`](reference.md#parser-finish-procedure)
([usage.md](usage.md#4-finish)).

- **A request never does.**
- **A response does not** when it is `1xx`, `204` or `304`; when
  `F-SKIP-BODY` is set (the response to a `HEAD`); or when a
  `Content-Length` or a `chunked` coding gives its length.
- **A response does** otherwise — including one whose `Transfer-Encoding`
  does not end in `chunked`.

## The flag constants

`(httparse decisions)` also exports llhttp's flag bits, under llhttp's names
and values, so you can name a bit instead of writing `2`:

```scheme
(unless (zero? (bitwise-and (parser-field-ref p 'flags) F-CONNECTION-CLOSE))
  (note-close-requested ctx))
```

| Constant                  | Value | Set when the message                                     |
|:--------------------------|------:|:---------------------------------------------------------|
| `F-CONNECTION-KEEP-ALIVE` |     1 | says `Connection: keep-alive`                            |
| `F-CONNECTION-CLOSE`      |     2 | says `Connection: close`                                 |
| `F-CONNECTION-UPGRADE`    |     4 | says `Connection: upgrade`                               |
| `F-CHUNKED`               |     8 | is framed by `chunked`                                   |
| `F-UPGRADE`               |    16 | has an `Upgrade` header                                  |
| `F-CONTENT-LENGTH`        |    32 | has a `Content-Length` header                            |
| `F-SKIP-BODY`             |    64 | has no body: `on-headers-complete` returned `'skip-body` |
| `F-TRAILING`              |   128 | has reached its zero-size last chunk                     |
| `F-TRANSFER-ENCODING`     |   512 | has a `Transfer-Encoding` header                         |

256 is missing on purpose: llhttp leaves that bit unused. Neither decision
reads `F-TRAILING`.
