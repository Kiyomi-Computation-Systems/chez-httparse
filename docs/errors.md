# Errors

When the parser meets something it won't accept, the feed returns a result
with status `'error`, and
[`parser-result-error`](reference.md#parser-result-error-accessor) holds the
error.

The parser stops there. Feeding it again just returns the same status and
reads nothing; to use it for a new connection,
[reset](reference.md#parser-reset-procedure) it.

## What an error tells you

| Accessor                                                                 | Gives you                                                 |
|:-------------------------------------------------------------------------|:----------------------------------------------------------|
| [`parser-error-code`](reference.md#parser-error-code-accessor)           | a symbol, such as `'invalid-header-token` — match on this |
| [`parser-error-reason`](reference.md#parser-error-reason-accessor)       | llhttp's message, as a string — log this                  |
| [`parser-error-offset`](reference.md#parser-error-offset-accessor)       | where in the stream the parser stopped                    |
| [`parser-error-node-name`](reference.md#parser-error-node-name-accessor) | which rule in the grammar refused, as a symbol            |

```scheme
(let ((r (parser-feed! parser buf 0 (bytevector-length buf))))
  (when (eq? (parser-result-status r) 'error)
    (let ((e (parser-result-error r)))
      (log-refusal (parser-error-code e)      ; match on this
                   (parser-error-reason e)    ; log this
                   (parser-error-offset e)))))
```

The offset counts bytes from the start of the stream — since the parser was
made or reset, across every feed — not from the start of the buffer you
just fed.

## Match on the code, log the reason

The codes and reasons are llhttp's own, so this parser reports exactly what
llhttp would.

- **The code** is a symbol, one for each of llhttp's error numbers. It is
  what your program should branch on.
- **The reason** is llhttp's human-readable text. Log it, but don't match on
  it: it can be reworded.

Neither one alone pins down a failure. llhttp uses one code for several
different failures, and uses one reason — "Expected CRLF after version" —
under two different codes. Together, the code and the reason identify the
failure exactly.

## Errors that are not bad input

A few `'error` results come from somewhere other than malformed bytes:

| Code                          | Comes from                                                                      |
|:------------------------------|:--------------------------------------------------------------------------------|
| the code you chose            | a callback returned `make-callback-failure`; the reason is `"callback failure"` |
| `callback-contract-violation` | a callback returned something other than its allowed outcomes                   |
| `paused-h2-upgrade`           | an HTTP/2 preface, handing the connection off — see [pausing.md](pausing.md)    |

The last one is not a failure at all: it is how llhttp reports a hand-off to
HTTP/2, and this parser reports it the same way.

## Turning an error into a response status

One family of errors comes with exact rules from RFC 9112:
`invalid-transfer-encoding`. On a request, **every one is a `400`**, and the
code alone tells you so. A strict parser refuses a request with that code in
four ways:

| Request                                    | Node                        | Why a `400`       |
|:-------------------------------------------|:----------------------------|:------------------|
| `Transfer-Encoding:` with an empty value   | `e-empty-transfer-encoding` | §6.3, item 4      |
| `Transfer-Encoding: chunked, deflate`      | `e-bad-te-value`            | §6.3, item 4      |
| `Transfer-Encoding: gzip`                  | `e-request-invalid-te`      | §6.3, item 4      |
| `Content-Length`, then `Transfer-Encoding` | `e-te-with-content-length`  | §6.1, §6.3 item 3 |

The sections are RFC 9112's.

- **The first three rows.** `chunked` is not the last coding, and §6.3 item
  4 says the server "MUST respond with the 400 (Bad Request) status code" to
  such a request and then close the connection. llhttp quotes that rule
  where it produces the third row.
- **`chunked, chunked`** also lands at `e-bad-te-value`. It does end in
  `chunked`, but §6.1 lets a sender apply `chunked` only once, so the message
  is malformed and still a `400`.
- **The fourth row** carries both framing headers. §6.1 lets a server reject
  that, this parser does, and either way the server "MUST close the
  connection" after answering. The other order — `Transfer-Encoding`, then
  `Content-Length` — is refused too, but under `invalid-content-length`.

### When to answer `501`

The parser never reports a case that calls for a `501`, but your server
may still need to send one. RFC 9112 §6.1 says a server SHOULD answer `501` to a transfer coding it does not
understand, and where §6.3's MUST also applies, the MUST wins. That leaves
§6.1 with requests the parser **accepts**: codings that end in `chunked` but
list another first, such as `gzip, chunked`.

Only you know which codings you support. If `gzip` is not one of them,
answer that request with a `501` yourself, using the `Transfer-Encoding`
value your header callbacks collected.

## Telling failures with one code apart

Several failures can share a code. Usually that is fine. When you want to
know *which* one it was — for a more useful log line, say — read
[`parser-error-node-name`](reference.md#parser-error-node-name-accessor). It
returns the Node column of the table above.

```scheme
(case (parser-error-code e)
  ((invalid-transfer-encoding)
   (respond 400)
   (log-te-failure (parser-error-node-name e)))  ; e.g. 'e-bad-te-value
  (else (handle-other-error e)))
```

Use it only to split a code you have already matched. The node name is this
parser's own label for a rule in its grammar, not llhttp's, so it is finer
than the code but less stable: a grammar change can move it, where llhttp's
code and reason will not.

A node name names a **place** in the grammar, so one failure can show up
under more than one name when it is reachable from different places. For the
four in the table, it is one name each.
[`test/common/te-error-nodes-tests.sps`](../test/common/te-error-nodes-tests.sps)
checks those four against every strict request fixture in llhttp's corpus
that fails with this code.
