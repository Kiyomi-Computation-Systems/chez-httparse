# The URL parser

The message parser hands you the request target as one `on-url-data` span. If
you want it broken into schema, host, path, query and fragment, use the
separate URL parser.

It is a second, separate parser: llhttp's own URL machine, in the build its
`url` fixtures were recorded from. The message parser does not use it.

```scheme
(import (generated httparse-url)        ; httparse-url-machine
        (byte-machine runtime))
```

## Callbacks

Five span callbacks, all required, and *no events at all*:

| Callback               | Receives               |
|------------------------|------------------------|
| `on-url-schema-data`   | the scheme, e.g. `http` |
| `on-url-host-data`     | the whole authority    |
| `on-url-path-data`     | the path               |
| `on-url-query-data`    | the query, after `?`   |
| `on-url-fragment-data` | the fragment, after `#` |

Each is a span callback like the message parser's: `(lambda (parser ctx bv
from to) outcome)`, with `[from, to)` indexing the bytevector you fed. See
[callbacks.md](callbacks.md).

There is no mode. [`make-parser`](reference.md#make-parser-procedure) takes
its three arguments and no field initials, because the machine declares no
settable field.

```scheme
(define (show name)
  (lambda (p ctx bv from to)
    (let ((b (make-bytevector (- to from))))
      (bytevector-copy! bv from b 0 (- to from))
      (display (list name (utf8->string b)))
      (newline))
    callback-continue))

(define url-parser
  (make-parser httparse-url-machine
               (list (list 'on-url-schema-data   (show 'schema))
                     (list 'on-url-host-data     (show 'host))
                     (list 'on-url-path-data     (show 'path))
                     (list 'on-url-query-data    (show 'query))
                     (list 'on-url-fragment-data (show 'fragment)))
               #f))

(let ((bv (string->utf8 "http://a:b@host.com:8080/p")))
  (parser-feed! url-parser bv 0 (bytevector-length bv)))
;; (schema http)
;; (host a:b@host.com:8080)
;; (path /p)
```

## What it does not split

`on-url-host-data` carries the *whole* authority: userinfo, host and port
together, brackets and all. `http://a:b@host.com:8080/p` gives one host span,
`"a:b@host.com:8080"`. llhttp does not separate them and neither does this.

## Two edges worth knowing

**A space, CR or LF ends the URL and starts another.** That is the build
llhttp's `url` fixtures run against: its two exits are looped back to its own
entry. So `/path /next` produces two path spans, and what follows a space is
judged from scratch: `http://host.com xyz` reports `xyz` as a *schema*. If you
feed it one URL at a time, you will not meet this.

**A host that ends at a `?` keeps the `?`.** `http://host.com?q=1` gives a
host span of `"host.com?"`, then a query span of `"q=1"`. That is upstream's
behaviour, measured rather than inferred, and reproduced rather than repaired.

[`../test/common/url-tests.sps`](../test/common/url-tests.sps) pins both
edges against llhttp's traces.
