# API reference

Every binding you use, with its exact signature and the library it comes
from. The loop is always the same: make a parser with `make-parser`, feed it
with `parser-feed!`, and read the result. The three `(httparse …)` libraries
are small helpers around that loop: naming the modes, naming a method, and
deciding keep-alive.

For explanation and examples, read the guide pages first:
[Usage](usage.md), [Callbacks](callbacks.md), [Modes](modes.md),
[Errors](errors.md), [Pausing](pausing.md), [Connections](connection.md) and
[The URL parser](url.md). The [index](#alphabetical-index) at the bottom
lists every name.

## Modules

| Module                         | Purpose                                                                               | Coverage                         |
|:-------------------------------|:--------------------------------------------------------------------------------------|:---------------------------------|
| `(generated httparse-message)` | The HTTP/1.x message parser, as a compiled machine.                                   | every export                     |
| `(generated httparse-url)`     | llhttp's URL parser, which splits a request target into parts.                        | every export                     |
| `(httparse modes)`             | llhttp's request/response type and lenient-flag tables, and the arithmetic over them. | every export                     |
| `(httparse methods)`           | llhttp's 47 method names and the number it assigns each.                              | every export                     |
| `(httparse decisions)`         | llhttp's keep-alive and needs-EOF rules, and the flag bits they read.                 | every export                     |
| `(byte-machine runtime)`       | Parser construction, feeding, results, errors and callback outcomes.                  | the procedures an embedder calls |

The two generated libraries depend on `(byte-machine runtime)` and nothing
else. The three `(httparse …)` libraries depend on nothing at all, so you can
import them without loading a parser. The runtime exports more than this
page lists; the rest is for the generated code, not for you.

```scheme
(import (generated httparse-message)   ; httparse-message-machine
        (httparse modes)               ; the mode tables, pure
        (httparse methods)             ; the method table, pure
        (httparse decisions)           ; keep-alive / needs-eof, pure
        (byte-machine runtime))        ; make-parser, parser-feed!, ...
```

## Conventions

**Reading a signature.** `(parser-feed! parser bytevector start end) ->
ParserResult` takes four arguments and returns a `ParserResult`; the `->` is
notation, not Scheme. A line like `callback-continue : CallbackOutcome`
describes a value, not a procedure.

**Types.** `ExactInteger` is any exact integer and `Nat` a non-negative one.
`(Option T)` is a `T` or `#f`. `Void` means nothing useful is returned.
`Parser`, `ParserResult`, `ParserError`, `CallbackOutcome` and
`CallbackFailure` are records you read only through the accessors below. A
`bytevector` is always your own: the parser never keeps or copies it.

**Bad input does not raise.** A malformed message comes back as a result
with status `error` ([Errors](errors.md)). Raising is for mistakes in the
calling code, and comes in two kinds:

- **A contract violation**, from `(byte-machine runtime)`: you called it
  wrongly — a bad range, feeding a paused parser, a missing callback. The
  **Raises** line names the violation's code. The runtime does not export a
  predicate for these conditions: treat one as a bug to fix, not an outcome
  to handle.
- **A refusal**, from the three `(httparse …)` libraries: you passed a name
  or number they don't know. Each library exports a predicate and a
  `detail` accessor for its refusals, so you can catch them if you want to.

Ordinary R6RS assertion and arity errors can still happen too.

## Parser construction

### `make-parser` (procedure)

`(make-parser machine bindings context) -> Parser`\
`(make-parser machine bindings context field-initials) -> Parser`

Makes a parser that runs `machine`, one of the two compiled machines below.
`bindings` is a list of two-element lists, `(list name procedure)`, one per
callback. `context` is handed back to every callback as its second argument;
`#f` is fine. `field-initials` is an alist of `(name . ExactInteger)` pairs
that sets the parser's modes before the first byte; omitted, it is `'()`.

Every callback the machine declares is required, so a binding list with a
hole is refused here rather than quietly ignored. So is a binding that names
no callback, a name bound twice, and an entry that is not a two-element list
of a symbol and a procedure. Field initials are range-checked here too: an
unknown field, a field the machine does not let you set, a duplicate, or a
value outside the field's declared width is refused. The message machine
lets you set `type` (8 bits) and `lenient-flags` (16 bits); the URL machine
declares no fields.

```scheme
(make-parser
 httparse-message-machine bindings #f
 (list (cons 'type (httparse-message-type-value 'request))
       (cons 'lenient-flags
             (httparse-lenient-flags-value '(headers version)))))
```

**Available from:** `(byte-machine runtime)`\
**Raises:** an assertion violation when `machine` is not a compiled machine;
contract code `invalid-argument`, with detail `missing-required-callback`,
`unknown-callback-binding`, `duplicate-callback-binding`,
`callback-bindings`, `unknown-field`, `non-settable-field`,
`duplicate-field-initial`, `field-initial-out-of-range` or
`field-initials`\
**Details:** [Usage](usage.md)

### `parser?` (predicate)

`(parser? object) -> Boolean`

Returns whether `object` is a parser made by `make-parser`.

**Available from:** `(byte-machine runtime)`\
**Details:** [Usage](usage.md)

## Feeding and lifecycle

### `parser-feed!` (procedure)

`(parser-feed! parser bytevector start end) -> ParserResult`

Parses the half-open range `[start, end)` of `bytevector` and returns what
happened. Feed as much or as little as you have: the parser resumes exactly
where it stopped, and a token, a header or a body split across any number of
feeds produces the same result as one whole buffer. Callbacks run during the
call, and a span callback's bounds index this `bytevector`.

On a parser that has already reached `error`, `finished` or `stopped`, a
feed runs nothing and returns that status again, with `consumed` 0 and
`next` equal to `start`. A condition raised by a callback, or a non-local
exit from one, propagates out of the feed and leaves the parser poisoned:
only `parser-reset!` makes it usable again.

**Available from:** `(byte-machine runtime)`\
**Raises:** contract code `invalid-slice` unless `bytevector` is a
bytevector and `0 <= start <= end <= (bytevector-length bytevector)`;
`lifecycle-violation` on a paused parser; `reentrancy` when a callback feeds
the parser it is running inside; `poisoned-parser` after a callback
escaped\
**Details:** [Usage](usage.md)

### `parser-finish!` (procedure)

`(parser-finish! parser) -> ParserResult`

Says the input has ended and asks whether stopping here is legal. The parser
runs with input exhausted, taking each state's end-of-input route, and
returns `finished`, `error` or `paused`. Finishing mid-message is the error
`invalid-eof-state`, reason "Invalid EOF state" (code 14), from every such
state.

A body the connection delimits completes here and nowhere else: a response
with neither `Content-Length` nor `Transfer-Encoding`, a response whose
`Transfer-Encoding` does not end in `chunked`, and such a request under the
`transfer-encoding` or `chunked-length` lenient flag. `on-message-complete`
fires during the finish, and is the only callback a finish runs; the body's
bytes already went out with the feeds that carried them.

A finish result has no buffer behind it: `next` repeats the stream offset
and `consumed` is 0. A parser already at `error`, `finished` or `stopped`
returns that status again without running.

**Available from:** `(byte-machine runtime)`\
**Raises:** contract code `lifecycle-violation` on a paused parser;
`reentrancy` from inside a callback; `poisoned-parser` after a callback
escaped\
**Details:** [Finishing a parse](usage.md#4-finish)

### `parser-resume!` (procedure)

`(parser-resume! parser) -> Symbol`

Lets a paused parser continue. It changes the lifecycle only: no callback
runs and no input is read. It returns `'feed-ready` after a pause from a
feed, and `'finish-ready` after a pause from a finish; feed or finish again
afterwards.

**Available from:** `(byte-machine runtime)`\
**Raises:** contract code `lifecycle-violation` on a parser that is not
paused; `reentrancy` from inside a callback; `poisoned-parser` after a
callback escaped\
**Details:** [Pausing](pausing.md)

### `parser-reset!` (procedure)

`(parser-reset! parser) -> Void`

Returns the parser to its just-constructed state: the machine's entry, a
stream offset of 0, no stored error, no open span, and every field restored
to the initials it was built with. Those are your `field-initials` for the
fields you set and the machine's declared ones for the rest, so a mode you
chose survives a reset. It is the one operation that makes a poisoned parser
usable again.

**Available from:** `(byte-machine runtime)`\
**Raises:** contract code `reentrancy` when a callback resets the parser it
is running inside\
**Details:** [Usage](usage.md)

## Results

### `parser-result?` (predicate)

`(parser-result? object) -> Boolean`

Returns whether `object` is a result returned by `parser-feed!` or
`parser-finish!`.

**Available from:** `(byte-machine runtime)`\
**Details:** [Usage](usage.md)

### `parser-result-status` (accessor)

`(parser-result-status result) -> Symbol`

Returns how the call ended:

| Status                | Meaning                                                                                                                           |
|:----------------------|:----------------------------------------------------------------------------------------------------------------------------------|
| `need-input`          | The range is consumed; feed more. The ordinary outcome, including after a complete message, since a connection may carry another. |
| `error`               | The message is malformed, a callback failed, or the HTTP/2 preface handed off. `parser-result-error` has the detail.              |
| `paused`              | A callback returned `callback-pause`, or the parser reached a CONNECT or Upgrade hand-off. Resume with `parser-resume!`.          |
| `finished`, `stopped` | The machine reached a terminal state.                                                                                             |

**Available from:** `(byte-machine runtime)`\
**Details:** [Usage](usage.md)

### `parser-result-next` (accessor)

`(parser-result-next result) -> ExactInteger`

Returns the index in the bytevector you just fed where the unconsumed tail
begins. It shares the coordinates of the `start` and `end` you passed, so it
feeds straight back in after a pause. On `need-input` it equals your `end`.
For a result from `parser-finish!` it repeats the stream offset.

**Available from:** `(byte-machine runtime)`\
**Details:** [Pausing](pausing.md)

### `parser-result-consumed` (accessor)

`(parser-result-consumed result) -> ExactInteger`

Returns the number of bytes this call took from its range. At a pause it
includes the fragment delivered to the pausing callback. It is 0 for a
result from `parser-finish!`, and for a feed on a parser already at
`error`, `finished` or `stopped`.

**Available from:** `(byte-machine runtime)`\
**Details:** [Pausing](pausing.md)

### `parser-result-stream-offset` (accessor)

`(parser-result-stream-offset result) -> ExactInteger`

Returns the bytes the parser has taken since it was made or last reset,
counted across feeds and across every message parsed on it. This is the
absolute position to log; `parser-result-next` is the one to feed from.

**Available from:** `(byte-machine runtime)`\
**Details:** [Usage](usage.md)

### `parser-result-error` (accessor)

`(parser-result-error result) -> (Option ParserError)`

Returns the error when the status is `error`, and `#f` otherwise. It is
`#f` for a pause, so code that checks only this slot reads a pause as "not
failed". The HTTP/2 preface hand-off arrives here, with code
`paused-h2-upgrade`.

**Available from:** `(byte-machine runtime)`\
**Details:** [Errors](errors.md)

### `parser-result-pause` (accessor)

`(parser-result-pause result) -> (Option ParserError)`

Returns the pause reason when the status is `paused`, read with the same
`parser-error-*` accessors as an error. A CONNECT or Upgrade hand-off
carries code `paused-upgrade`. A plain `callback-pause` carries no reason, so
this is `#f`; that is how you tell an ordinary pause from a hand-off. It is
also `#f` for every result that is not a pause.

**Available from:** `(byte-machine runtime)`\
**Details:** [Pausing](pausing.md)

## Errors

### `parser-error?` (predicate)

`(parser-error? object) -> Boolean`

Returns whether `object` is a parser error: the value of
`parser-result-error`, or a pause reason from `parser-result-pause`.

**Available from:** `(byte-machine runtime)`\
**Details:** [Errors](errors.md)

### `parser-error-code` (accessor)

`(parser-error-code error) -> Symbol`

Returns the error's code, such as `'invalid-header-token`. For a parse
failure it is llhttp's, one-to-one with llhttp's error number, so several
distinct failures share one code. An error's identity is the pair of code
and reason: one reason, "Expected CRLF after version", appears under two
codes. When a callback returned a `make-callback-failure`, the code is the
one it carried; a callback that returned anything outside its allowed
outcomes produces `'callback-contract-violation`.

**Available from:** `(byte-machine runtime)`\
**Details:** [Errors](errors.md)

### `parser-error-reason` (accessor)

`(parser-error-reason error) -> String`

Returns llhttp's own text for a parse failure, such as "Invalid header
token". A callback failure's reason is always "callback failure". Log the
reason; match on the code.

**Available from:** `(byte-machine runtime)`\
**Details:** [Errors](errors.md)

### `parser-error-offset` (accessor)

`(parser-error-offset error) -> ExactInteger`

Returns where the error happened as a stream offset: bytes since the parser
was made or last reset, not an index into the bytevector you fed.

**Available from:** `(byte-machine runtime)`\
**Details:** [Errors](errors.md)

### `parser-error-node-name` (accessor)

`(parser-error-node-name error) -> Symbol`

Returns the grammar's own name for the node that refused, such as
`'e-request-invalid-te`. It is finer than the code, so it can tell apart
failures that share one, such as the four strict `invalid-transfer-encoding`
refusals of a request. It is this project's label, not llhttp's, and can
move where a code and reason will not: use it only to split within a code
you have already matched. One declaration can surface under several node
names, so a node name marks a site rather than always one failure.

**Available from:** `(byte-machine runtime)`\
**Details:** [Errors](errors.md)

## Callbacks and stream position

### `callback-continue` (value)

`callback-continue : CallbackOutcome`

The outcome a callback returns to let the parse go on. It is a shared value,
so returning it allocates nothing.

An event callback is `(lambda (parser context) outcome)` and a span callback
is `(lambda (parser context bytevector from to) outcome)`, where
`[from, to)` indexes the bytevector you passed to `parser-feed!`. Copy what
you need before returning; the bytes are not retained. The one decision
callback, `on-headers-complete`, may also return `'skip-body`. Any other
return value fails the parse with code `callback-contract-violation`.

**Available from:** `(byte-machine runtime)`\
**Details:** [Callbacks](callbacks.md)

### `callback-pause` (value)

`callback-pause : CallbackOutcome`

The outcome a callback returns to stop the current feed. The feed returns
`paused` with no pause reason, `parser-result-next` one past the bytes
already taken, and a resume re-enters where an unpaused run would have gone.
Pausing is allowed in `on-headers-complete` too.

**Available from:** `(byte-machine runtime)`\
**Details:** [Pausing](pausing.md)

### `make-callback-failure` (procedure)

`(make-callback-failure code detail) -> CallbackFailure`

Builds the outcome a callback returns to fail the parse. The feed returns
`error`, and the error carries `code` as its code, "callback failure" as its
reason and `detail` as application data. `code` must be a symbol whose first
character is `a`–`z` and whose rest are `a`–`z`, `0`–`9` or `-`; `detail` may
be anything, including `#f`.

**Available from:** `(byte-machine runtime)`\
**Raises:** contract code `invalid-argument`, detail `code`, when `code` is
not such a symbol\
**Details:** [Callbacks](callbacks.md)

### `parser-stream-offset` (procedure)

`(parser-stream-offset parser) -> ExactInteger`

Returns the bytes the parser has taken since it was made or last reset,
counted across feeds and messages. Between feeds it equals the last
`parser-result-stream-offset`. Inside a callback it says where that callback
is:

- an event callback reads the bytes taken before it, the position llhttp's
  traces print as `off=`, the same however the input was split;
- a span callback reads its fragment's end, so the fragment starts at
  `(- (parser-stream-offset p) (- to from))`, whichever feed delivered it.

**Available from:** `(byte-machine runtime)`\
**Details:** [Callbacks](callbacks.md)

## Parser fields

### `parser-field-ref` (procedure)

`(parser-field-ref parser field) -> ExactInteger`

Reads one of the parser's fields, by name. It is read-only; nothing writes a
field from outside the machine. The message machine's fields an embedder
reads:

| Field                      | Value                                                       |
|:---------------------------|:------------------------------------------------------------|
| `method`                   | llhttp's method number; see `httparse-method-name`          |
| `status-code`              | a response's three digits                                   |
| `http-major`, `http-minor` | the version                                                 |
| `flags`                    | llhttp's flag bits; see the `F-*` constants                 |
| `content-length`           | what remains to be read, not what was declared              |
| `upgrade`                  | 1 if this message upgrades, as `llhttp_get_upgrade`, else 0 |
| `type`, `lenient-flags`    | the modes, as set at construction                           |

`content-length` counts down as the body arrives: read it in
`on-headers-complete` for the declared length. `upgrade` is written just
before `on-headers-complete` and holds until the next message's, so read it
there or later in the same message; `parser-reset!` returns it to 0. The
reset between two messages zeroes `flags`, so read it in
`on-headers-complete` or `on-message-complete`.

**Available from:** `(byte-machine runtime)`\
**Raises:** contract code `accessor-misuse` for a field the machine does not
declare; `invalid-argument` when `parser` is not a parser\
**Details:** [Connections](connection.md)

## Modes `(httparse modes)`

### `httparse-message-type-value` (procedure)

`(httparse-message-type-value name) -> Nat`

Returns llhttp's number for a message type: `'both` is 0, `'request` 1 and
`'response` 2. Pass it as the `type` field initial. Nothing in the bytes says
whether a request or a response is coming, and there is no safe default:
omit `type` and the parser starts at llhttp's `both`, which this parser does
not implement, so the first feed returns the error
`unexpected-message-type` at offset 0.

**Available from:** `(httparse modes)`\
**Raises:** a modes refusal for a name not in `httparse-message-type-names`\
**Details:** [Modes](modes.md)

### `httparse-message-type-names` (constant)

`httparse-message-type-names : (Listof Symbol)`

The message type names llhttp declares, in its own numbering order:
`(both request response)`.

**Available from:** `(httparse modes)`\
**Details:** [Modes](modes.md)

### `httparse-lenient-flags-value` (procedure)

`(httparse-lenient-flags-value names) -> Nat`

Returns the bitset for a list of lenient flag names, to pass as the
`lenient-flags` field initial. The empty list is 0, which is strict, and is
also what you get by omitting the field. The setting is made once: the
restart between two pipelined messages leaves it alone, and `parser-reset!`
restores it.

```scheme
(httparse-lenient-flags-value '(version optional-lf-after-cr))   ; => 80
```

**Available from:** `(httparse modes)`\
**Raises:** a modes refusal when `names` is not a list, or names a flag llhttp
does not declare\
**Details:** [Modes](modes.md)

### `httparse-lenient-bit` (procedure)

`(httparse-lenient-bit name) -> Nat`

Returns the bit for one lenient flag, such as 16 for `'version`.

**Available from:** `(httparse modes)`\
**Raises:** a modes refusal for a name not in `httparse-lenient-flag-names`\
**Details:** [Modes](modes.md)

### `httparse-lenient-flag-bits` (constant)

`httparse-lenient-flag-bits : (Listof (List Symbol Nat))`

llhttp's eleven lenient flags and their bits, in llhttp's bit order. Each
corresponds one-for-one to an `llhttp_set_lenient_*` function.

| Name                        |  Bit |
|:----------------------------|-----:|
| `headers`                   |    1 |
| `chunked-length`            |    2 |
| `keep-alive`                |    4 |
| `transfer-encoding`         |    8 |
| `version`                   |   16 |
| `data-after-close`          |   32 |
| `optional-lf-after-cr`      |   64 |
| `optional-crlf-after-chunk` |  128 |
| `optional-cr-before-lf`     |  256 |
| `spaces-after-chunk-size`   |  512 |
| `header-value-relaxed`      | 1024 |

What each one allows is in [Modes](modes.md#lenient-flags-bending-the-rules).

**Available from:** `(httparse modes)`\
**Details:** [Modes](modes.md)

### `httparse-lenient-flag-names` (constant)

`httparse-lenient-flag-names : (Listof Symbol)`

The eleven lenient flag names, in bit order.

**Available from:** `(httparse modes)`\
**Details:** [Modes](modes.md)

### `httparse-lenient-flags-width` (constant)

`httparse-lenient-flags-width : Nat`

The width in bits the `lenient-flags` field must have for every flag to fit:
16. The message machine declares the field at that width.

**Available from:** `(httparse modes)`\
**Details:** [Modes](modes.md)

### `httparse-modes-error?` (predicate)

`(httparse-modes-error? object) -> Boolean`

Returns whether `object` is a refusal raised by `(httparse modes)`.

**Available from:** `(httparse modes)`\
**Details:** [Modes](modes.md)

### `httparse-modes-error-detail` (accessor)

`(httparse-modes-error-detail condition) -> String`

Returns what the refusal says, such as "llhttp declares no lenient flag named
verison". The same text is the condition's `&message`.

**Available from:** `(httparse modes)`\
**Details:** [Modes](modes.md)

## Methods `(httparse methods)`

### `httparse-method-name` (procedure)

`(httparse-method-name number) -> Symbol`

Returns the method llhttp numbers `number`, as a symbol for routing or
logging. Use it on the `method` field, which holds llhttp's number rather
than an index into any list here.

```scheme
(httparse-method-name 1)                              ; => GET
(httparse-method-name (parser-field-ref p 'method))   ; the parsed method
```

**Available from:** `(httparse methods)`\
**Raises:** a methods refusal when `number` is not an exact non-negative
integer, or is not one of the 0 to 46 llhttp assigns\
**Details:** [Usage](usage.md)

### `httparse-method-number` (procedure)

`(httparse-method-number name) -> Nat`

Returns llhttp's number for a method named by a symbol, in llhttp's own
spelling: `'GET`, `'M-SEARCH`, `'GET_PARAMETER`. Symbols are case-sensitive.
An unknown name is refused rather than read as 0, which is `DELETE`.

**Available from:** `(httparse methods)`\
**Raises:** a methods refusal when `name` is not a symbol, or names no method
llhttp declares\
**Details:** [Usage](usage.md)

### `httparse-method-names` (constant)

`httparse-method-names : (Listof String)`

The 47 method names llhttp matches on a request line, in alphabetical order,
HTTP, RTSP and ICE methods together. The order is not the numbering; see
`httparse-method-numbers`. The parser matches the method against this table,
not against any token, so `MKCOLA` is an error rather than a method.

**Available from:** `(httparse methods)`\
**Details:** [Usage](usage.md)

### `httparse-method-numbers` (constant)

`httparse-method-numbers : (Listof (Pair String Nat))`

Each method name paired with llhttp's number for it, the value its
`METHODS` map assigns. The numbers are exactly 0 to 46:

```text
  0  DELETE           1  GET              2  HEAD             3  POST
  4  PUT              5  CONNECT          6  OPTIONS          7  TRACE
  8  COPY             9  LOCK            10  MKCOL           11  MOVE
 12  PROPFIND        13  PROPPATCH       14  SEARCH          15  UNLOCK
 16  BIND            17  REBIND          18  UNBIND          19  ACL
 20  REPORT          21  MKACTIVITY      22  CHECKOUT        23  MERGE
 24  M-SEARCH        25  NOTIFY          26  SUBSCRIBE       27  UNSUBSCRIBE
 28  PATCH           29  PURGE           30  MKCALENDAR      31  LINK
 32  UNLINK          33  SOURCE          34  PRI             35  DESCRIBE
 36  ANNOUNCE        37  SETUP           38  PLAY            39  PAUSE
 40  TEARDOWN        41  GET_PARAMETER   42  SET_PARAMETER   43  REDIRECT
 44  RECORD          45  FLUSH           46  QUERY
```

**Available from:** `(httparse methods)`\
**Details:** [Usage](usage.md)

### `httparse-methods-error?` (predicate)

`(httparse-methods-error? object) -> Boolean`

Returns whether `object` is a refusal raised by `(httparse methods)`.

**Available from:** `(httparse methods)`\
**Details:** [Usage](usage.md)

### `httparse-methods-error-detail` (accessor)

`(httparse-methods-error-detail condition) -> String`

Returns what the refusal says, such as "llhttp assigns no method the number
47". The same text is the condition's `&message`.

**Available from:** `(httparse methods)`\
**Details:** [Usage](usage.md)

## Connection decisions `(httparse decisions)`

### `should-keep-alive?` (predicate)

`(should-keep-alive? http-major http-minor type status-code flags) -> Boolean`

llhttp's `llhttp_should_keep_alive`: can another message follow this one on
the connection? It is `#t` only when both hold:

- the version and `Connection` header allow it. llhttp's version test is
  literally `major > 0 && minor > 0`: such a message stays open unless it
  sent `Connection: close`, and any other — HTTP/1.0, and HTTP/2.0 too —
  must have sent `Connection: keep-alive`;
- `message-needs-eof?` is `#f`.

Read the fields with `parser-field-ref` in `on-headers-complete` or
`on-message-complete`, and pass the `type` you gave `make-parser` as a
symbol, `'request` or `'response`.

```scheme
(should-keep-alive? (parser-field-ref p 'http-major)
                    (parser-field-ref p 'http-minor)
                    'request
                    (parser-field-ref p 'status-code)
                    (parser-field-ref p 'flags))
```

**Available from:** `(httparse decisions)`\
**Raises:** a decisions refusal when `type` is not `'request` or
`'response`\
**Details:** [Connections](connection.md)

### `message-needs-eof?` (predicate)

`(message-needs-eof? type status-code flags) -> Boolean`

llhttp's `llhttp_message_needs_eof`: whether this message ends only when the
connection closes. A request never does. A response does not when its status
is 1xx, 204 or 304, when `F-SKIP-BODY` is set, or when it is framed by
`Content-Length` or chunked coding. A `Transfer-Encoding` that is not chunked
leaves it framed by end of input.

**Available from:** `(httparse decisions)`\
**Raises:** a decisions refusal when `type` is not `'request` or
`'response`\
**Details:** [Connections](connection.md)

### `F-CONNECTION-KEEP-ALIVE` (constant)

`F-CONNECTION-KEEP-ALIVE : Nat`

Value 1. Set when the message sent `Connection: keep-alive`. The `F-*`
constants are llhttp's `enum flags`, under its names and values, so you can
test a bit of the `flags` field by name; the grammar uses the same
definitions.

**Available from:** `(httparse decisions)`\
**Details:** [Connections](connection.md)

### `F-CONNECTION-CLOSE` (constant)

`F-CONNECTION-CLOSE : Nat`

Value 2. Set when the message sent `Connection: close`.

**Available from:** `(httparse decisions)`\
**Details:** [Connections](connection.md)

### `F-CONNECTION-UPGRADE` (constant)

`F-CONNECTION-UPGRADE : Nat`

Value 4. Set when the message sent `Connection: upgrade`.

**Available from:** `(httparse decisions)`\
**Details:** [Connections](connection.md)

### `F-CHUNKED` (constant)

`F-CHUNKED : Nat`

Value 8. Set when the message is framed by chunked transfer coding.

**Available from:** `(httparse decisions)`\
**Details:** [Connections](connection.md)

### `F-UPGRADE` (constant)

`F-UPGRADE : Nat`

Value 16. Set when the message carried an `Upgrade` header.

**Available from:** `(httparse decisions)`\
**Details:** [Connections](connection.md)

### `F-CONTENT-LENGTH` (constant)

`F-CONTENT-LENGTH : Nat`

Value 32. Set when the message carried a `Content-Length`.

**Available from:** `(httparse decisions)`\
**Details:** [Connections](connection.md)

### `F-SKIP-BODY` (constant)

`F-SKIP-BODY : Nat`

Value 64. Set when `on-headers-complete` returned `'skip-body`, saying this
message has no body after all. `message-needs-eof?` reads it, so a `HEAD`
response is not read to the end of the connection.

**Available from:** `(httparse decisions)`\
**Details:** [Connections](connection.md)

### `F-TRAILING` (constant)

`F-TRAILING : Nat`

Value 128. Set by the zero-size chunk, not by a header. Neither decision
reads it.

**Available from:** `(httparse decisions)`\
**Details:** [Connections](connection.md)

### `F-TRANSFER-ENCODING` (constant)

`F-TRANSFER-ENCODING : Nat`

Value 512. Set when the message carried a `Transfer-Encoding`. llhttp leaves
256 unused, so no constant has that value.

**Available from:** `(httparse decisions)`\
**Details:** [Connections](connection.md)

### `httparse-decisions-error?` (predicate)

`(httparse-decisions-error? object) -> Boolean`

Returns whether `object` is a refusal raised by `(httparse decisions)`.

**Available from:** `(httparse decisions)`\
**Details:** [Connections](connection.md)

### `httparse-decisions-error-detail` (accessor)

`(httparse-decisions-error-detail condition) -> String`

Returns what the refusal says, such as "type must be 'request or 'response,
not 'both". The same text is the condition's `&message`.

**Available from:** `(httparse decisions)`\
**Details:** [Connections](connection.md)

## Machines `(generated …)`

### `httparse-message-machine` (value)

`httparse-message-machine : CompiledMachine`

The HTTP/1.x message parser, to pass to `make-parser`. It declares
twenty-five callbacks, all required: ten span callbacks, each with its
completion event, and six events with no span.

| Span                            | Event                               |
|:--------------------------------|:------------------------------------|
| `on-method-data`                | `on-method-complete`                |
| `on-url-data`                   | `on-url-complete`                   |
| `on-protocol-data`              | `on-protocol-complete`              |
| `on-version-data`               | `on-version-complete`               |
| `on-status-data`                | `on-status-complete`                |
| `on-header-field-data`          | `on-header-field-complete`          |
| `on-header-value-data`          | `on-header-value-complete`          |
| `on-body-data`                  |                                     |
| `on-chunk-extension-name-data`  | `on-chunk-extension-name-complete`  |
| `on-chunk-extension-value-data` | `on-chunk-extension-value-complete` |

The events with no span are `on-message-begin`, `on-headers-complete`,
`on-chunk-header`, `on-chunk-complete`, `on-message-complete` and
`on-reset`. `on-reset` fires between pipelined messages, before the next
`on-message-begin`. The machine's settable fields are `type` and
`lenient-flags`; see `httparse-message-type-value` and
`httparse-lenient-flags-value`.

**Available from:** `(generated httparse-message)`\
**Details:** [Usage](usage.md)

### `httparse-url-machine` (value)

`httparse-url-machine : CompiledMachine`

llhttp's URL parser, which splits a request target into its parts. (The
message parser checks every target against the same rules, but reports it
as one span.) It declares five span callbacks, all required, and no events:
`on-url-schema-data`, `on-url-host-data`, `on-url-path-data`,
`on-url-query-data` and `on-url-fragment-data`. It declares no fields, so
`make-parser` takes three arguments for it. A feed continues the URL the
last feed was reading, so reset the parser before each new URL.

**Available from:** `(generated httparse-url)`\
**Details:** [The URL parser](url.md)

## Alphabetical index

- [`F-CHUNKED`](#f-chunked-constant)
- [`F-CONNECTION-CLOSE`](#f-connection-close-constant)
- [`F-CONNECTION-KEEP-ALIVE`](#f-connection-keep-alive-constant)
- [`F-CONNECTION-UPGRADE`](#f-connection-upgrade-constant)
- [`F-CONTENT-LENGTH`](#f-content-length-constant)
- [`F-SKIP-BODY`](#f-skip-body-constant)
- [`F-TRAILING`](#f-trailing-constant)
- [`F-TRANSFER-ENCODING`](#f-transfer-encoding-constant)
- [`F-UPGRADE`](#f-upgrade-constant)
- [`callback-continue`](#callback-continue-value)
- [`callback-pause`](#callback-pause-value)
- [`httparse-decisions-error-detail`](#httparse-decisions-error-detail-accessor)
- [`httparse-decisions-error?`](#httparse-decisions-error-predicate)
- [`httparse-lenient-bit`](#httparse-lenient-bit-procedure)
- [`httparse-lenient-flag-bits`](#httparse-lenient-flag-bits-constant)
- [`httparse-lenient-flag-names`](#httparse-lenient-flag-names-constant)
- [`httparse-lenient-flags-value`](#httparse-lenient-flags-value-procedure)
- [`httparse-lenient-flags-width`](#httparse-lenient-flags-width-constant)
- [`httparse-message-machine`](#httparse-message-machine-value)
- [`httparse-message-type-names`](#httparse-message-type-names-constant)
- [`httparse-message-type-value`](#httparse-message-type-value-procedure)
- [`httparse-method-name`](#httparse-method-name-procedure)
- [`httparse-method-names`](#httparse-method-names-constant)
- [`httparse-method-number`](#httparse-method-number-procedure)
- [`httparse-method-numbers`](#httparse-method-numbers-constant)
- [`httparse-methods-error-detail`](#httparse-methods-error-detail-accessor)
- [`httparse-methods-error?`](#httparse-methods-error-predicate)
- [`httparse-modes-error-detail`](#httparse-modes-error-detail-accessor)
- [`httparse-modes-error?`](#httparse-modes-error-predicate)
- [`httparse-url-machine`](#httparse-url-machine-value)
- [`make-callback-failure`](#make-callback-failure-procedure)
- [`make-parser`](#make-parser-procedure)
- [`message-needs-eof?`](#message-needs-eof-predicate)
- [`parser-error-code`](#parser-error-code-accessor)
- [`parser-error-node-name`](#parser-error-node-name-accessor)
- [`parser-error-offset`](#parser-error-offset-accessor)
- [`parser-error-reason`](#parser-error-reason-accessor)
- [`parser-error?`](#parser-error-predicate)
- [`parser-feed!`](#parser-feed-procedure)
- [`parser-field-ref`](#parser-field-ref-procedure)
- [`parser-finish!`](#parser-finish-procedure)
- [`parser-reset!`](#parser-reset-procedure)
- [`parser-result-consumed`](#parser-result-consumed-accessor)
- [`parser-result-error`](#parser-result-error-accessor)
- [`parser-result-next`](#parser-result-next-accessor)
- [`parser-result-pause`](#parser-result-pause-accessor)
- [`parser-result-status`](#parser-result-status-accessor)
- [`parser-result-stream-offset`](#parser-result-stream-offset-accessor)
- [`parser-result?`](#parser-result-predicate)
- [`parser-resume!`](#parser-resume-procedure)
- [`parser-stream-offset`](#parser-stream-offset-procedure)
- [`parser?`](#parser-predicate)
- [`should-keep-alive?`](#should-keep-alive-predicate)
