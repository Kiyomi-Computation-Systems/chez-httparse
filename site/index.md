# chez-httparse

An HTTP/1.x parser for Chez Scheme: a byte-level state machine, checked
against [llhttp](https://github.com/nodejs/llhttp) by replaying llhttp's
recorded conformance traces byte for byte, at every chunk size.

You could combine this with [chez-libuv](https://github.com/Kiyomi-Computation-Systems/chez-libuv)
to build an HTTP/1.x server like [chez-http-server](https://github.com/Kiyomi-Computation-Systems/chez-http-server).

You feed it bytes and it calls you back. It keeps no buffer, copies no spans,
and allocates nothing in proportion to the input. A request split across any
number of reads parses exactly as one whole buffer does.

💡 These pages were generated from [Markdown](../docs) with
[chez-cmark-gfm](https://github.com/Kiyomi-Computation-Systems/chez-cmark-gfm).

## A taste

```scheme
(import (rnrs)
        (generated httparse-message)
        (httparse modes)
        (byte-machine runtime))

(define parser
  (make-parser
   httparse-message-machine
   (list
    ;; A span callback gets bounds into YOUR bytevector: nothing is copied.
    (list 'on-url-data
          (lambda (p ctx bv from to) (remember-target bv from to) callback-continue))
    ;; ... the other 24 callbacks. All are required; a missing one is
    ;; refused when the parser is made.
    )
   #f
   ;; Request or response: nothing in the bytes says which.
   (list (cons 'type (httparse-message-type-value 'request)))))

(parser-result-status (parser-feed! parser chunk 0 (bytevector-length chunk)))
;; => need-input: feed more, or another message may follow
```

The complete, runnable version is
[`test/common/example-tests.sps`](../test/common/example-tests.sps), which the
test suite runs.

## Read next

- [Installing](installing.md) — put the two library directories on Chez's path.
- [Usage](usage.md) — make a parser, feed it, read results, finish a parse.
- [API reference](reference.md) — every documented binding, by module.
- [Callbacks](callbacks.md) — the 25 callbacks, spans and stream offsets.
- [Modes](modes.md) — request or response, and llhttp's eleven lenient flags.
- [Errors](errors.md) — read an error and map it to a response status.
- [Pausing and upgrades](pausing.md) — pause, resume, and the upgrade hand-offs.
- [Parser state](connection.md) — parser fields, and keep-alive or close.
- [The URL parser](url.md) — split a request target into its parts.
- [Conformance](conformance.md) — what is checked against llhttp, and how.
- [Performance](performance.md) — allocation and throughput, measured.
- [Building](building.md) — presets, test lanes and the opt-in checks.
