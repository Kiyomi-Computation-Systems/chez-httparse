# Modes

Two settings are fixed before the parser reads its first byte:

- **`type`**: does it read requests or responses?
- **`lenient-flags`**: which of llhttp's rule-bending options are on?

You set both when you make the parser, and they last for its whole life.

## Setting them

Pass them as [`make-parser`](reference.md#make-parser-procedure)'s fourth
argument, a list of `(name . value)` pairs:

```scheme
(import (generated httparse-message)
        (httparse modes)
        (byte-machine runtime))

(make-parser httparse-message-machine bindings #f
             (list (cons 'type (httparse-message-type-value 'request))
                   (cons 'lenient-flags
                         (httparse-lenient-flags-value '(headers version)))))
```

The values are llhttp's own numbers. `(httparse modes)` turns names into
those numbers; if you already have llhttp's number, pass it directly.

**Mistakes are refused, not guessed.** `make-parser` rejects an unknown
setting, a setting that cannot be set, the same setting twice, and a value
too large for the setting. The helpers
[`httparse-message-type-value`](reference.md#httparse-message-type-value-procedure)
and [`httparse-lenient-flags-value`](reference.md#httparse-lenient-flags-value-procedure)
raise an error for a name they don't know, rather than treating it as "off".

## `type`: request or response

Nothing in the bytes says whether a request or a response is coming, but you
always know: it depends on which end of the connection you are.

```scheme
(httparse-message-type-value 'request)   ; => 1
(httparse-message-type-value 'response)  ; => 2
```

**Always set it.** There is no safe default. If you leave it out, the parser
starts in llhttp's "either" mode (`HTTP_BOTH`, 0), where llhttp would guess
from the first bytes. This parser does not guess: the first feed fails with
the code `unexpected-message-type` at offset 0.

It fails at the first feed rather than inside `make-parser` because a
setting cannot be made mandatory there, and adding a required callback just
to fail sooner would give you two ways to choose the mode.

## `lenient-flags`: bending the rules

By default every flag is off and the parser is **strict**: it rejects what
llhttp rejects with no lenient flag set. Each flag relaxes one rule, so you
can talk to clients and servers that get HTTP slightly wrong.

```scheme
(httparse-lenient-flags-value '(version optional-lf-after-cr))
;; => 80
(httparse-lenient-flags-value '())
;; => 0, strict
```

Leave the setting out and you get 0, strict. The value combines the flags
you name, so their order doesn't matter and naming one twice changes
nothing.

> ⚠️ **Every flag except `header-value-relaxed` weakens a defence.** llhttp's
> own documentation marks them "USE WITH CAUTION": most open the door to
> request smuggling or cache poisoning. Turn on only what a peer you must
> talk to actually needs.

| Flag                        |  Bit | Allows                                                                             |
|:----------------------------|-----:|:-----------------------------------------------------------------------------------|
| `headers`                   |    1 | invalid header-value characters; whitespace before a colon or after the start line |
| `chunked-length`            |    2 | `Transfer-Encoding` and `Content-Length` in the same message                       |
| `keep-alive`                |    4 | another message after one marked `Connection: close`                               |
| `transfer-encoding`         |    8 | a `Transfer-Encoding` with a value after `chunked`                                 |
| `version`                   |   16 | an HTTP version other than 0.9, 1.0, 1.1 or 2.0                                    |
| `data-after-close`          |   32 | extra bytes after a `Connection: close` message, which are discarded               |
| `optional-lf-after-cr`      |   64 | a line ended by CR alone                                                           |
| `optional-crlf-after-chunk` |  128 | a chunk that starts right after the previous one, with no CRLF between             |
| `optional-cr-before-lf`     |  256 | a line ended by LF alone                                                           |
| `spaces-after-chunk-size`   |  512 | spaces after a chunk size                                                          |
| `header-value-relaxed`      | 1024 | control characters in header values other than NUL, CR and LF; nothing else        |

The bits are llhttp's `enum llhttp_lenient_flags`, in its order. Each flag
does exactly what llhttp's matching setter does — `headers` is
`llhttp_set_lenient_headers`, `chunked-length` is
`llhttp_set_lenient_chunked_length`, and so on — and that setter's
documentation in llhttp's `api.h` is the full description. The table is
`httparse-lenient-flag-bits` in
[`src/httparse/modes.sls`](../src/httparse/modes.sls).

### The flags stay set

The flags are set once, when the parser is made. Moving on to the next
message on a connection does not clear them, and neither does
[`parser-reset!`](reference.md#parser-reset-procedure): a reset restores the
values **you** passed to `make-parser`. The same goes for `type`.

### Two flags that only work together

`optional-cr-before-lf` alone does not let a request line end in a bare LF.
After the line, the parser still expects an LF it has already read, so you
need `optional-lf-after-cr` as well. The same is true at a chunk size.

```text
PUT / HTTP/1.1\nHost: x\n\n
  strict                          ->  code 9 (invalid-version), offset 15
  with optional-cr-before-lf      ->  code 2 (strict), offset 15
  with both flags                 ->  parses
```

Both errors carry the same reason, "Expected CRLF after version", at the
same offset, so only the **code** tells you whether the flag was on. That is llhttp's behaviour, matched
exactly.

### One place where it works alone

A response status line with **no reason phrase**, ended by a bare LF —
`HTTP/1.1 200\n` — is accepted with `optional-cr-before-lf` by itself.
There, llhttp goes straight on to the next line instead of expecting the LF
again. The two places look alike and behave differently, and this parser
follows llhttp in both.
