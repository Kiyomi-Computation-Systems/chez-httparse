# Parser state and the connection

After a message, you decide whether the connection stays open for another. You
read what the parser learned with
[`parser-field-ref`](reference.md#parser-field-ref-procedure), and pass it to
llhttp's own two decisions in `(httparse decisions)`.

## Reading parser state

`(parser-field-ref parser name)` returns a field's current value as an
integer. The message parser exposes these:

| Field             | Value                                                     |
|-------------------|-----------------------------------------------------------|
| `'method`         | llhttp's method number, not an index into any list here   |
| `'status-code`    | a response's three digits                                 |
| `'http-major`     | the major version                                         |
| `'http-minor`     | the minor version                                         |
| `'flags`          | llhttp's flag bits                                        |
| `'content-length` | *what remains to be read*, not what was declared          |
| `'upgrade`        | 1 if this message upgrades, as `llhttp_get_upgrade`       |

A name the machine does not declare raises; it is never answered with a
default. The access is read-only: nothing sets a field from a callback.

`content-length` counts *down* as the body arrives, which is llhttp's own
behaviour. Read it inside `on-headers-complete` if you want the declared
length; by `on-message-complete` it is zero.

To turn `method` into a symbol, use `httparse-method-name` from
`(httparse methods)`. For when `upgrade` is set and how long it holds, see
[pausing.md](pausing.md#does-this-message-upgrade).

## Deciding keep-alive vs close

`(httparse decisions)` is pure and turns those fields into llhttp's own two
after-a-message decisions:

| Procedure                                                          | Arguments                                   | Mirrors                      |
|--------------------------------------------------------------------|---------------------------------------------|------------------------------|
| [`should-keep-alive?`](reference.md#should-keep-alive-predicate)    | major, minor, type, status code, flags      | `llhttp_should_keep_alive`   |
| [`message-needs-eof?`](reference.md#message-needs-eof-predicate)    | type, status code, flags                    | `llhttp_message_needs_eof`   |

They mirror llhttp exactly. `should-keep-alive?` is the version and
`Connection` gate *and* not needing eof, so it takes both the version and
`message-needs-eof?`'s inputs.

```scheme
(import (httparse decisions))

(list 'on-message-complete
      (lambda (p ctx)
        (define keep?
          (should-keep-alive? (parser-field-ref p 'http-major)
                              (parser-field-ref p 'http-minor)
                              response-or-request        ; the symbol you passed
                              (parser-field-ref p 'status-code)
                              (parser-field-ref p 'flags)))
        (remember-keep-alive ctx keep?)
        callback-continue))
```

### Read the flags in time

Read the flags inside `on-headers-complete` or `on-message-complete`. The
reset between messages zeroes `flags` before the next one begins.

### Pass the type symbol you chose

Pass `'request` or `'response`, the same type you gave `make-parser` (see
[modes.md](modes.md)). An unknown type is *refused, never defaulted*: both
procedures raise rather than treat it as a response.

### The version test is llhttp's, not `>= 1.1`

The gate is llhttp's literal `major > 0 && minor > 0`. An HTTP/1.1-or-later
message stays alive unless it said `Connection: close`; anything else must
have said `Connection: keep-alive`. So HTTP/2.0 (minor 0) needs an explicit
`keep-alive` where a naive `>= 1.1` would not.

### When a message needs eof

`message-needs-eof?` asks whether this message ends only when the connection
closes. A request never does. A response does not when it is 1xx, 204 or 304,
when `F-SKIP-BODY` is set (a HEAD response), or when a content length or a
chunked coding frames it. A transfer coding that is *not* chunked leaves it
framed by eof.

## The flag constants

The library exports llhttp's `F-*` flag bits under llhttp's names and values,
so you can name a bit rather than hard-code `2`. The grammar imports the same
definitions.

| Constant                  | Value |
|---------------------------|-------|
| `F-CONNECTION-KEEP-ALIVE` | 1     |
| `F-CONNECTION-CLOSE`      | 2     |
| `F-CONNECTION-UPGRADE`    | 4     |
| `F-CHUNKED`               | 8     |
| `F-UPGRADE`               | 16    |
| `F-CONTENT-LENGTH`        | 32    |
| `F-SKIP-BODY`             | 64    |
| `F-TRAILING`              | 128   |
| `F-TRANSFER-ENCODING`     | 512   |

256 is deliberately absent: llhttp leaves that bit unused. `F-TRAILING` is
set by the zero chunk, not by a header, and neither decision reads it.

```scheme
(when (not (zero? (bitwise-and (parser-field-ref p 'flags)
                               F-CONNECTION-CLOSE)))
  (note-close-requested ctx))
```
