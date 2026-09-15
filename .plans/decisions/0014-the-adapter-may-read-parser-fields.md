# 0014: the adapter may read parser fields, because llhttp's own trace callback reads exactly those

Date: 2026-09-14
Status: accepted
Refines: [0008](0008-bit-exact-trace-conformance-and-the-ratchet.md), decision item 2
Milestone: M4 Slice ⓪ (.plans/2026-09-13-gate0-http-parser-milestone-plan.md)

## Context

[0008](0008-bit-exact-trace-conformance-and-the-ratchet.md) item 2 makes the
conformance adapter a **rename and never a computation**: the offsets, the span
bytes and the reason string arrive from the parser and leave untouched, and
nothing in that layer reconstructs any of them. Until M4 every trace line was
renderable from a callback's own arguments alone, so the rule needed no
qualification — the adapter saw a callback name, an offset and sometimes a
fragment, and that was the whole of its input.

`headers complete` is the first line that is not. llhttp prints it as

```c
llparse__print(p, endp,
    "headers complete method=%d v=%d/%d flags=%x content_length=%llu",
    s->method, s->http_major, s->http_minor, s->flags, s->content_length);
```

— five reads of **parser state**, at a callback that carries no arguments of
its own. M3 answered by refusing: the row said `unrenderable`, the recorder
bound the callback and rendering raised, and every fixture reaching the line
failed honestly. That was right for a milestone with no `flags` and no
`content_length` to read. It is not an answer for the milestone that has them.

Three ways to render the line were available.

1. **Recompute it in the adapter** from the headers the fixture fed in — parse
   `Content-Length` a second time, set the flag bits a second time. This is the
   one item 2 exists to forbid, and the reason is exact: a second
   implementation that agrees with the first proves nothing, and one that
   disagrees fails the fixture for the wrong reason. The oracle would then be
   measuring the adapter.
2. **Carry the numbers as callback arguments**, widening the generated
   callback protocol so `on-headers-complete` is handed five values. This keeps
   the adapter's input shape uniform, at the cost of a protocol change upstream
   for one consumer's rendering convenience — and the numbers would still be
   the parser's, so it buys nothing but uniformity.
3. **Read the five fields off the parser**, which is what llhttp's own callback
   does.

## Decision

1. A callback row may have the kind **`state-line`**: an event whose rendered
   text carries parser field values. Its renderer reads fields **by name** from
   the parser and formats them with llhttp's own format string, quoted in the
   source beside it.

2. `adapter-state-fields` names the fields a state line reads, in llhttp's
   print order, and is **exported** so the set is assertable without a parser.
   Today: `method http-major http-minor flags content-length` — the five
   `llhttp__on_headers_complete` reads.

3. **The adapter may READ parser state; it still may not DERIVE it.** The test
   is the one item 2 already implies, stated for this case: every number on a
   rendered line must be a value the parser itself computed and stored. Reading
   `flags` is a rename of the parser's own bitfield. Recomputing `flags` from
   the header lines is a second parser, and is forbidden.

4. **No default, as everywhere else in this layer.** A field the parser did not
   supply, or supplied as anything but a non-negative exact integer, is a
   refusal — not a zero. This matters more here than in the callback table: the
   plausible default is `0`, and `flags=0 content_length=0` is a line llhttp
   writes for real messages, so a defaulting renderer would produce a
   *correct-looking* trace for every fixture whose flags happen to be zero.
   That is exactly the failure the corpus cannot catch by itself.

5. The pure half keeps taking its input as an argument. `adapter-event-for`
   gains `fields` as a **required** parameter, so the table half is still
   judged alone on hand-built values, with no parser running (0008 item 4). The
   recorder is the only thing that touches a parser.

## Consequences

`on-headers-complete` renders from M4 Slice ⓪ on, and the 27 request fixtures
whose traces end at `headers complete` / `message complete` with no framing go
from `not-yet` to `passing` in that slice alone.

The adapter now knows five grammar field names. That is a coupling, and it is
the same one it already had to fourteen callback names and nine error codes: a
rename table is coupled to both vocabularies by construction. A field renamed
in the grammar and not here fails at the first fixture that reaches the line,
which is the no-default rule doing its job.

`unexpected-eof` having no error number is untouched and is the other half of
the same discipline: where llhttp prints nothing, we print nothing; where
llhttp prints state, we print the same state, read the same way.

## Alternatives rejected

**Recompute in the adapter** — rejected above; it is what 0008 item 2 forbids.

**Widen the callback protocol so the values arrive as arguments** — a change to
the generated ABI, upstream, for one downstream layer's convenience. Decision
[0006](0006-upstream-first-for-general-gaps.md)'s generality test fails: the
need is specific to a trace renderer, the workaround does not repeat per span
or per grammar, and `parser-field-ref` already exists as public API for exactly
this. It would also not improve the honesty of the numbers by one bit, since
they would be the same fields read at the same moment.

**Keep refusing and gate the fixtures another way** — this would leave 27
fixtures failing for a reason that is no longer true, and would make the
ratchet under-report what the parser does. A refusal is the right answer only
while the state genuinely is not there.
