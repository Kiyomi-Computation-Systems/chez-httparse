# Pausing and upgrades

A feed can stop before the end of your buffer for two reasons:

- **You asked it to.** A callback returned `callback-pause`.
- **The connection is changing protocol.** The message was an upgrade — a
  `CONNECT` tunnel, a WebSocket handshake, HTTP/2 — and the bytes after it
  belong to someone else.

Either way, the result tells you where it stopped, so you can carry on or
hand the rest of the buffer over.

## Pausing on purpose

Return [`callback-pause`](reference.md#callback-pause-value) from any
callback, and the feed stops right there with status `'paused`. For example,
pause in `on-headers-complete` to look at the headers before deciding what
to do with the body.

To carry on:

1. Call [`parser-resume!`](reference.md#parser-resume-procedure). It only
   lets the parser continue; it reads nothing and calls nothing.
2. Feed again, starting at
   [`parser-result-next`](reference.md#parser-result-next-accessor).

Feeding a paused parser without resuming it first raises an error.

```scheme
;; Feed one buffer, handling any pauses inside it.
(let loop ((at 0))
  (let ((r (parser-feed! parser buf at (bytevector-length buf))))
    (case (parser-result-status r)
      ((paused)
       (act-on-the-pause r)             ; whatever you paused for
       (parser-resume! parser)
       (loop (parser-result-next r)))   ; carry on from here, not from `at`
      (else r))))
```

## Where to carry on from

`parser-result-next` is a position in the buffer you just fed: the first
byte the parser has not read. It counts in the same positions as your
`start` and `end`, so you can pass it straight back. (For logging, use
`parser-result-stream-offset`, which counts from the start of the stream.)

The bytes that led to the pause have already been read. If a span callback
paused, its piece was delivered and counted in `parser-result-consumed`, and
`parser-result-next` points just past it. Resuming carries on from there —
it does not deliver that piece again.

If the status is `'need-input` instead, the whole buffer was read:
`parser-result-next` equals your `end`, and the next thing to feed is your
next buffer.

## Upgrades

When a message hands the connection to another protocol, the parser stops
and tells you — but in **two different ways**, so checking only the status
will miss one of them.

| Hand-off                                     | Status    | Read the reason with  | Code                |
|:---------------------------------------------|:----------|:----------------------|:--------------------|
| `CONNECT`, `Connection: upgrade`, or a `101` | `'paused` | `parser-result-pause` | `paused-upgrade`    |
| an HTTP/2 preface (`PRI * HTTP/2.0`)         | `'error`  | `parser-result-error` | `paused-h2-upgrade` |

The first is a pause, because parsing could go on afterwards. The second
arrives as an `'error`, because that is how llhttp reports it; its reason
still reads "Pause". In both cases, `parser-result-next` is where the new
protocol's bytes start in the buffer you fed: hand everything from there on
to whatever takes over the connection.

To recognise a hand-off, check both:

```scheme
;; #t when the result is an upgrade hand-off of either kind.
(define (hands-off? r)
  (or (and (eq? (parser-result-status r) 'paused)
           (let ((p (parser-result-pause r)))
             (and p (eq? (parser-error-code p) 'paused-upgrade))))
      (and (eq? (parser-result-status r) 'error)
           (let ((e (parser-result-error r)))
             (and e (eq? (parser-error-code e) 'paused-h2-upgrade))))))
```

A pause you asked for is also `'paused`, but it has no reason:
[`parser-result-pause`](reference.md#parser-result-pause-accessor) returns
`#f`. That is how the code above tells the two apart.

## Knowing in advance: the `upgrade` field

The hand-off tells you the connection is changing *now*. To know earlier,
while you can still decide how to answer, read the `upgrade` field with
[`parser-field-ref`](reference.md#parser-field-ref-procedure) in
`on-headers-complete`.

```scheme
(list 'on-headers-complete
      (lambda (p ctx)
        (when (= 1 (parser-field-ref p 'upgrade))
          (prepare-for-hand-off ctx))      ; e.g. answer, then hand off
        callback-continue))
```

It is 1 when the message is an upgrade, by llhttp's own rule (what
`llhttp_get_upgrade` returns), so you don't have to work it out yourself:

- a request, or a `101` response, that carries both an `Upgrade` header and
  `Connection: upgrade`; or
- a `CONNECT` request.

Otherwise it is 0. A response with both headers under any other status is
only announcing that it supports upgrading, and reads 0.

**When to read it.** The field is set just before `on-headers-complete`
runs, and keeps its value through the body, `on-message-complete` and the
hand-off result. It is **not** cleared between messages: until the next
message's `on-headers-complete`, it still holds the previous message's
answer. [`parser-reset!`](reference.md#parser-reset-procedure) sets it back
to 0.

### The field and the hand-off can disagree

They answer different questions. A `101` response always hands off
(`'paused`, `paused-upgrade`), but if it lacks the two headers, its
`upgrade` field is 0.

llhttp also lets its `on_headers_complete` return 2 to force an upgrade.
This parser's `on-headers-complete` has no such answer, so `upgrade` is
always llhttp's computed rule.
[`test/common/upgrade-field-tests.sps`](../test/common/upgrade-field-tests.sps)
checks it against every plain request and response fixture in llhttp's
corpus.
