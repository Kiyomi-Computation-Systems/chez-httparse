# The URL parser

The message parser hands you the request target as one span, `on-url-data`:
`/search?q=cats` arrives as a single piece. If you want it in parts — schema,
host, path, query, fragment — feed it to the URL parser.

The URL parser is llhttp's own URL machine. The message parser already runs
the same rules over every target to reject bad ones
([callbacks.md](callbacks.md#the-request-target-is-checked)); this one also
reports the parts.

```scheme
(import (generated httparse-url)        ; httparse-url-machine
        (byte-machine runtime))
```

## Five callbacks

It has five span callbacks, all required, and no events:

| Callback               | Receives                        |
|:-----------------------|:--------------------------------|
| `on-url-schema-data`   | the scheme, such as `http`      |
| `on-url-host-data`     | the whole authority (see below) |
| `on-url-path-data`     | the path                        |
| `on-url-query-data`    | the query, after the `?`        |
| `on-url-fragment-data` | the fragment, after the `#`     |

Each works like the message parser's span callbacks: `(lambda (parser ctx
bv from to) outcome)`, pointing into the bytevector you fed
([callbacks.md](callbacks.md)).

There are no modes. [`make-parser`](reference.md#make-parser-procedure)
takes just three arguments here, because the URL parser has no settings.

## Example

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

**Reset between URLs.** A feed carries on where the last one stopped, so a
second URL fed to the same parser is read as more of the first: after the
example above, feeding `http://host.com?q=1` gives one path span,
`http://host.com`, then the query. Call
[`parser-reset!`](reference.md#parser-reset-procedure) before each new URL.

## The host is the whole authority

`on-url-host-data` gives you user, password, host and port together, as one
span — brackets and all. Above, `http://a:b@host.com:8080/p` gives the host
span `"a:b@host.com:8080"`. llhttp does not split them, so neither does this
parser; split them yourself if you need to.

## Two surprises

**A space, CR or LF ends one URL and starts another.** The parser is built
to read URL after URL, the way llhttp's URL tests feed it. So `/path /next`
gives two path spans, and whatever follows a space is read as a fresh URL:
`http://host.com xyz` reports `xyz` as a *schema*. Feed it one URL at a time
and you won't meet this.

**A host that ends at a `?` keeps the `?`.** `http://host.com?q=1` gives the
host span `"host.com?"`, then the query span `"q=1"`. That is what llhttp
does, and this parser matches it rather than fixing it.

[`test/common/url-tests.sps`](../test/common/url-tests.sps) checks both
against llhttp's own output.
