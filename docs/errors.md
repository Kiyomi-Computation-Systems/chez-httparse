# Errors

When the input is malformed, [`parser-feed!`](reference.md#parser-feed-procedure)
returns a result whose status is `'error`, and
[`parser-result-error`](reference.md#parser-result-error-accessor) carries a
`ParserError` describing it. After a malformation the parser makes no further
progress.

This page covers reading that error, which part of it to match on, and how to
turn one family of errors into an HTTP response status.

## Reading an error

| Accessor                                                               | Gives you                                    |
|------------------------------------------------------------------------|----------------------------------------------|
| [`parser-error-code`](reference.md#parser-error-code-accessor)         | a symbol, e.g. `'invalid-header-token`       |
| [`parser-error-reason`](reference.md#parser-error-reason-accessor)     | llhttp's own text, as a string               |
| [`parser-error-offset`](reference.md#parser-error-offset-accessor)     | the stream offset where the parser refused   |
| [`parser-error-node-name`](reference.md#parser-error-node-name-accessor) | the grammar node that refused, as a symbol |

```scheme
(let ((r (parser-feed! parser buf 0 (bytevector-length buf))))
  (when (eq? (parser-result-status r) 'error)
    (let ((e (parser-result-error r)))
      (log-refusal (parser-error-code e)      ; switch on this
                   (parser-error-reason e)    ; log this
                   (parser-error-offset e)))))
```

The offset counts bytes since the parser was made or last reset, across every
feed, not an index into the buffer you just fed.

## The code and reason together are the identity

The code and the reason are llhttp's, deliberately, and an error's identity is
the *pair* rather than either half. llhttp gives several distinct failures one
code, and gives one reason, "Expected CRLF after version", two codes. Switch on
the symbol and log the text, and you get the same answer llhttp would give.

[`parser-error-code`](reference.md#parser-error-code-accessor) is one-to-one
with llhttp's error number.

## Mapping a Transfer-Encoding error to a response status

Every `invalid-transfer-encoding` on a request is a `400`, and the code alone
is enough to say so. A strict parser refuses a request with that code in four
ways:

| Request                                  | Node                        | Why a `400`       |
|------------------------------------------|-----------------------------|-------------------|
| `Transfer-Encoding:` with an empty value | `e-empty-transfer-encoding` | §6.3, item 4      |
| `Transfer-Encoding: chunked, deflate`    | `e-bad-te-value`            | §6.3, item 4      |
| `Transfer-Encoding: gzip`                | `e-request-invalid-te`      | §6.3, item 4      |
| `Content-Length`, then `Transfer-Encoding` | `e-te-with-content-length` | §6.1, §6.3 item 3 |

The sections are RFC 9112's.

- **The first three rows.** `chunked` is not the final coding, and §6.3 item 4
  says the server "MUST respond with the 400 (Bad Request) status code" to such
  a request and then close the connection. llhttp quotes that rule at the
  branch that produces the third row.
- **`chunked, chunked`** also lands at `e-bad-te-value`. Its final coding is
  `chunked`, but §6.1 lets a sender apply `chunked` only once, so the message
  is malformed and still a `400`.
- **The fourth row.** The request carries both framing headers. §6.1 lets a
  server reject that, the parser does, and either way the server "MUST close
  the connection" after answering it. The opposite order, `Transfer-Encoding`
  then `Content-Length`, is refused too, but under `invalid-content-length`.

### When to answer `501`

A `501` is still possible, but the parser does not produce one. RFC 9112 §6.1
gives a SHOULD `501` for a transfer coding the server does not understand, and
the MUST in §6.3 wins wherever both apply. So §6.1 is left with the requests
the parser *accepts*: codings that end in `chunked` but list another first,
such as `gzip, chunked`.

Only you know which codings you implement. If `gzip` is not one of them, you
answer that request with a `501` yourself, from the `Transfer-Encoding` value
your header callbacks collected.

## Telling failures within one code apart

Because llhttp gives several distinct failures one number, so does this
parser, and those failures share a code. Usually that is what you want. When
it is not (a log line that says *which* Transfer-Encoding failure it was, say),
match on [`parser-error-node-name`](reference.md#parser-error-node-name-accessor),
which returns the Node column of the table above.

```scheme
(case (parser-error-code e)
  ((invalid-transfer-encoding)
   (respond 400)
   (log-te-failure (parser-error-node-name e)))  ; e.g. 'e-bad-te-value
  (else (handle-other-error e)))
```

Do not match on the reason string. That match breaks as soon as llhttp
re-words the reason.

The node name is the *grammar's* own label for the node that refused. It is
finer than the code, which is why it can split one. But it is this parser's
label, not llhttp's, and a node name can move where a `(code, reason)` pair
will not. So reach for it only to split within a code you have already
matched; the pair stays the stable, llhttp-faithful identity.

A node name marks a *site*, and is not always a one-per-failure key: one
declaration can surface under several node names when it is reachable with
different spans open (end of input is the extreme). For each of the four in
the table above it is one key, because every refusal under that reason stops
at that node.
[`../test/common/te-error-nodes-tests.sps`](../test/common/te-error-nodes-tests.sps)
holds those four names to every strict request fixture in the corpus that
ends in this code.
