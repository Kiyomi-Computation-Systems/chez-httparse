# 0017: the message kind is a decision callback, because a parser cannot be started in a mode

Date: 2026-09-15
Status: accepted
Superseded in part by: [0021](0021-the-modes-are-settable-fields-and-the-fourth-brief-is-discharged.md) — the mechanism only. `type` is a
settable field an embedder writes at `make-parser`, which is what this record
wanted and could not have. Everything it argues about the third arm, the kind
not being derivable, and the fall-through being an error still holds.
Milestone: M7

## Context

llhttp parses a request and a response with one machine and one entry state.
Which start line it reads is decided by a field the embedder writes before the
first byte:

```c
void llhttp__test_init_response(llparse_t* s) {
  s->type = HTTP_RESPONSE;
}
```

and the grammar reads it once per message, immediately after `message begin`:

```js
const switchType = this.load('type', {
  [TYPE.REQUEST]: n('start_req'),
  [TYPE.RESPONSE]: n('start_res'),
}, n('start_req_or_res'));
```

**The third arm is not v0.1's.** `start_req_or_res` opens a METHOD span on `H`
and matches `HTTP/` inside it, so a response parsed that way records
`span[method]="HTTP/"` where all 66 response fixtures record
`span[protocol]="HTTP"`. Every fixture in the corpus names its kind, and
llhttp's harness turns that name into one of the two init hooks above, so
`HTTP_BOTH` appears nowhere in what this project has to reproduce.

byte-machine has no way to write a field from outside the machine. `(byte-machine
runtime)` exports `parser-field-ref` and no setter — deliberately, and its own
comment says so — and `make-parser` takes a compiled machine, a binding list and
a user context, filling every field from the DECLARED initials. A field's
initial value therefore belongs to the machine, not to the parser, and two
parsers built from one machine cannot start in two modes.

Three ways out were available.

**Emit the graph twice**, once per initial `type`. It works and nothing else
changes; it also doubles a 234 KB checked-in artifact, the determinism lane that
re-emits it, and the load of every lane that reads it — to encode one integer
that differs.

**Ask byte-machine for a field writer**, per [0006](0006-upstream-first-for-general-gaps.md).
The gap is general by 0006's own test: any protocol with a client half and a
server half over one grammar hits it. But 0006 item 2 keeps a gap downstream
when the local workaround is small, and this one is three nodes.

**A decision callback.** byte-machine has them — a callback node declares branch
keys and the callback returns one — and the Gate 0 plan already names them as
where llhttp's C decision functions land. The embedder answers once per message
instead of writing once per parser.

## Decision

1. **The message kind arrives as a required `decision` callback,
   `on-message-type`, with branch keys `request` and `response`**, invoked
   exactly where llhttp invokes `switchType`: after `message begin`, before the
   first byte of either start line.
2. **Its branches store llhttp's own `type` number into a `type` field.** The
   field exists, holds 1 or 2, and is what everything downstream reads — the
   protocol fork, the version fork, `before_headers_complete`,
   `message_needs_eof`, the body decision, and the adapter's `headers complete`
   line, which llhttp's own callback renders from `s->type`. The callback
   configures; the field is still the state.
3. **`required?`, and the fall-through is a refusal.** A parser that was never
   told what it is parsing does not start. `continue` from a decision callback
   means "no branch", and it reaches an error whose code symbol has no llhttp
   number — the same treatment `unexpected-eof` gets, for the same reason:
   llhttp cannot reach the state, so no trace can carry the line.
   **Pausing is not answering**: the pause continuation is that refusal too,
   because re-entering the node would ask again and a run that paused twice
   would not advance — which the verifier's `zero-progress-cycle` refuses
   outright.
4. **The gap is recorded and stays downstream** ([0006](0006-upstream-first-for-general-gaps.md)
   item 4). A brief for byte-machine is filed at
   `.plans/2026-09-15-upstream-parser-mode-brief.md`; nothing in this plan waits
   on it.

## What this rules out

- Emitting the machine twice, or shipping a second artifact that differs from
  the first in one integer.
- A default kind. `trace-recorder-bindings` takes the kind as a REQUIRED
  argument for the same reason the callback is `required?`: a default would
  silently make every response a request, and all 66 of them would print
  `method=0` on a line that looks exactly like a real one.
- Reading the kind back out of the input. That is `start_req_or_res`, it has a
  different trace, and no fixture asks for it.
- Treating the callback as the state. The field is the state; a reader that
  wanted to know what a parser is parsing asks `parser-field-ref`, not the
  binding list.

## Consequences

- The parser's eventual public constructor takes the kind, which is the right
  shape anyway: `(make-http-parser 'response ...)` reads better than a mode set
  after construction, and it cannot be forgotten.
- One callback invocation per message, where llhttp has one field load. Both are
  once per message and neither is on a per-byte path.
- The adapter gains a binding with no trace row — the first one. That is
  faithful rather than awkward: llhttp's harness sets the type in an init hook
  that prints nothing, and a trace name for it would be a line the oracle never
  writes.
- If byte-machine later grows a field writer, this becomes a two-line change at
  the seam and the grammar does not move: the branches that store `type` would
  simply have nothing left to do.
