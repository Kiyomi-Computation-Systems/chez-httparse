# Pausing and upgrades

A feed can stop before the end of your buffer. Either a callback asked it to,
or the message handed the connection to another protocol. This page covers
both: how to resume, where to resume from, and how to recognise a hand-off.

## Pausing from a callback

Return [`callback-pause`](reference.md) from any callback and the feed stops
there, with status `'paused`. Pausing is allowed in `on-headers-complete` too:
a resumed run re-enters the body decision exactly where an unpaused one would.

To carry on, call [`parser-resume!`](reference.md#parser-resume-procedure)
and feed again from
[`parser-result-next`](reference.md#parser-result-next-accessor).
`parser-resume!` changes the lifecycle only: no callback runs, no input is
read, and it returns an acknowledgement symbol rather than a result.

## Where to resume

`parser-result-next` is *the offset in the buffer you just fed* where the
unconsumed tail begins, and it is what you feed from next. It shares the
coordinate of the `start` and `end` you passed to `parser-feed!`, so it feeds
straight back in. `parser-result-stream-offset` is the absolute count since
the parser was made, and is what you log.

The byte that stopped the parser is already behind it. At a pause,
`parser-result-consumed` *includes* the fragment delivered to the pausing
callback, and `parser-result-next` points one past it. A resume re-enters
where an unpaused run would have gone, not at that fragment again.

```scheme
;; Feed one buffer, honouring any pauses within it.
(let loop ((at 0))
  (let ((r (parser-feed! parser buf at (bytevector-length buf))))
    (case (parser-result-status r)
      ((paused)
       (act-on-the-pause r)          ; your reason for pausing; then continue
       (parser-resume! parser)
       (loop (parser-result-next r)))  ; the tail starts here, not at `at`
      (else r))))
```

On `'need-input` the whole buffer was taken: `next` equals your `end` and
there is nothing to re-feed, so you supply the next buffer instead.

## Upgrades hand off on two channels

When a message hands the connection to another protocol, the parser stops and
tells you, but on *two different result channels*. A dispatch on
[`parser-result-status`](reference.md#parser-result-status-accessor) alone
will miss one.

| Hand-off                                      | Status    | Reason from           | Code                |
|:----------------------------------------------|:----------|:----------------------|:--------------------|
| CONNECT tunnel, `Connection: upgrade`, or 101 | `'paused` | `parser-result-pause` | `paused-upgrade`    |
| HTTP/2 preface (`PRI * HTTP/2.0`)             | `'error`  | `parser-result-error` | `paused-h2-upgrade` |

The first is a pause because the parse could resume. The second is an
`'error` because llhttp implements the h2 preface that way; its reason still
reads "Pause". In both, `parser-result-next` is where the tunnelled or
next-protocol bytes begin in the buffer you fed: hand that tail to whatever
takes the connection.

Because the two arrive differently, recognising a hand-off means checking
both channels:

```scheme
;; #t when the result is either upgrade hand-off, whichever channel it took.
(define (result-hands-off-stream? r)
  (or (and (eq? (parser-result-status r) 'paused)
           (let ((p (parser-result-pause r)))
             (and p (eq? (parser-error-code p) 'paused-upgrade))))
      (and (eq? (parser-result-status r) 'error)
           (let ((e (parser-result-error r)))
             (and e (eq? (parser-error-code e) 'paused-h2-upgrade))))))
```

A plain `callback-pause` is also `'paused`, but it carries no reason
([`parser-result-pause`](reference.md#parser-result-pause-accessor) is `#f`),
so the code check tells a hand-off from an ordinary pause.

## Does this message upgrade?

The hand-off tells you the connection is changing hands *now*. To know earlier,
while you can still decide how to serve the message, read the `upgrade` field
with [`parser-field-ref`](reference.md#parser-field-ref-procedure).

`upgrade` is llhttp's own answer, as `llhttp_get_upgrade` gives it, so you
need not copy its rule. It is 1 when the message carries both an `Upgrade`
header and `Connection: upgrade` *and* is a request or a `101` response, or
when it is a `CONNECT` request; otherwise 0. A response that sends both
headers under any other status is only announcing support, and reads 0.

```scheme
(list 'on-headers-complete
      (lambda (p ctx)
        (when (= 1 (parser-field-ref p 'upgrade))
          (plan-to-close-after-this-message ctx))  ; e.g. serve, then hand off
        callback-continue))
```

**Read it in `on-headers-complete` or later in the same message.** It is
written once, just before that callback runs, and then holds through the
body, `on-message-complete` and the hand-off result.

It is *not* cleared between messages. Before the next `on-headers-complete` it
still holds the previous message's answer: after a `CONNECT` and a resume, the
next message's `on-message-begin` reads 1.
[`parser-reset!`](reference.md#parser-reset-procedure) returns it to 0.

### The field and the hand-off are separate answers

A `101` always hands off (`'paused`, `paused-upgrade`), but without the two
headers its `upgrade` is 0.

llhttp also lets `on_headers_complete` return 2 to force an upgrade. This
parser's `on-headers-complete` has no such answer, so `upgrade` is only ever
llhttp's computed rule.
[`../test/common/upgrade-field-tests.sps`](../test/common/upgrade-field-tests.sps)
holds it to that rule over every plain request and response fixture in the
corpus.
