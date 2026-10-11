# Modes

Two things about a parser are fixed before the first byte: whether it reads
requests or responses, and which of llhttp's leniencies it allows. You choose
both when you make the parser, as *field initials*, and they hold for the
parser's whole life.

## Choosing the modes

[`make-parser`](reference.md#make-parser-procedure)'s optional fourth
argument is an alist of field initials. Two fields accept one, `type` and
`lenient-flags`, and together they are everything the parser needs to be told
up front:

```scheme
(import (generated httparse-message)
        (httparse modes)
        (byte-machine runtime))

(make-parser httparse-message-machine bindings #f
             (list (cons 'type (httparse-message-type-value 'request))
                   (cons 'lenient-flags
                         (httparse-lenient-flags-value '(headers version)))))
```

Both values are llhttp's own integers, written the way llhttp's embedder
writes them. `(httparse modes)` is pure and depends on nothing; you need it
only to spell these integers, and a caller that already has llhttp's number
may pass it directly.

The alist is range-checked at construction. `make-parser` refuses it for:

- an unknown field name,
- a field that exists but is not settable,
- a duplicate name,
- a value outside the field's declared width.

So a misspelled mode is an error, never a silent default. The same holds one
level up: [`httparse-message-type-value`](reference.md#httparse-message-type-value-procedure)
and [`httparse-lenient-flags-value`](reference.md#httparse-lenient-flags-value-procedure)
raise for a name they do not know rather than reading it as "off".

## `type`: request or response

HTTP does not say which is coming. A request begins with a method and a
response with `HTTP/`, and you always know which to expect from the side of
the connection you are on.

```scheme
(httparse-message-type-value 'request)   ; => 1
(httparse-message-type-value 'response)  ; => 2
```

**This one has no safe default.** Omit it and the parser starts at llhttp's
`HTTP_BOTH` (0), which this parser does not implement: llhttp's third arm
sniffs the first bytes, and this one does not. Instead the first feed returns
`'error` with code `unexpected-message-type` at offset 0. That is a refusal,
not a fallback.

The refusal comes at the first feed rather than at `make-parser` because a
field initial cannot be made mandatory, and a required callback kept only to
fail earlier would be a second way to choose the mode.

## `lenient-flags`: llhttp's eleven leniencies

A bitset. Zero is strict, and zero is the default when you leave the row out.

```scheme
(httparse-lenient-flags-value '(version optional-lf-after-cr))   ; => 80
(httparse-lenient-flags-value '())                               ; => 0, strict
```

The value is the bitwise OR of the flags you name, so order does not matter
and naming one twice changes nothing.

| Flag                        |  Bit | llhttp setter                                  |
|:----------------------------|-----:|:-----------------------------------------------|
| `headers`                   |    1 | `llhttp_set_lenient_headers`                   |
| `chunked-length`            |    2 | `llhttp_set_lenient_chunked_length`            |
| `keep-alive`                |    4 | `llhttp_set_lenient_keep_alive`                |
| `transfer-encoding`         |    8 | `llhttp_set_lenient_transfer_encoding`         |
| `version`                   |   16 | `llhttp_set_lenient_version`                   |
| `data-after-close`          |   32 | `llhttp_set_lenient_data_after_close`          |
| `optional-lf-after-cr`      |   64 | `llhttp_set_lenient_optional_lf_after_cr`      |
| `optional-crlf-after-chunk` |  128 | `llhttp_set_lenient_optional_crlf_after_chunk` |
| `optional-cr-before-lf`     |  256 | `llhttp_set_lenient_optional_cr_before_lf`     |
| `spaces-after-chunk-size`   |  512 | `llhttp_set_lenient_spaces_after_chunk_size`   |
| `header-value-relaxed`      | 1024 | `llhttp_set_lenient_header_value_relaxed`      |

The bits are llhttp's `enum llhttp_lenient_flags`, in its order. Each flag
corresponds one-for-one to its llhttp setter and does what that function's
documentation says. The table lives in
[`../src/httparse/modes.sls`](../src/httparse/modes.sls) as
`httparse-lenient-flag-bits`; `httparse-lenient-flag-names` lists the names.

### Set once, not once per message

The field is written at construction, and the restart between two pipelined
messages does not touch it. That restart stores zero over `flags`, which is a
different field for exactly this reason.

It also survives [`parser-reset!`](reference.md#parser-reset-procedure),
which restores the initials *you* gave rather than the ones the machine
declares. The same is true of `type`.

### Two flags only useful together

`optional-cr-before-lf` sends a bare LF to a node that then expects the LF it
has just consumed, so you need `optional-lf-after-cr` as well. This happens
at a chunk size, and at a request line:

```text
PUT / HTTP/1.1\nHost: x\n\n
  with optional-cr-before-lf alone
    ->  error code 2, "Expected CRLF after version", at offset 15
  with both
    ->  parses
```

Note the *code*. Strict parsing gives the same reason at the same offset with
code 9 (`invalid-version`); `optional-cr-before-lf` alone gives code 2
(`strict`). The reason text alone cannot tell them apart. That is upstream's
behaviour, reproduced.

### One flag that stands alone

A response status line with *no reason phrase* ending in a bare LF,
`HTTP/1.1 200\n`, is completed by `optional-cr-before-lf` by itself. Upstream's
arm there goes straight to the completion rather than to a node wanting the
LF again. The two sites read alike and behave differently.
