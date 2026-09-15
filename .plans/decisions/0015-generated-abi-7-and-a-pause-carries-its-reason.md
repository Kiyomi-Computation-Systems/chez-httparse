# 0015: the generated ABI target is 7, and a pause carries its own (code, reason)

Date: 2026-09-15
Status: accepted
Amends: [0012](0012-generated-abi-6-and-keyword-tables.md), item 1 (which amended [0005](0005-byte-machine-pinned-by-gitlink-generated-abi-5.md) item 2)
Milestone: the pin move to `v0.4.0`, between M4 and M5

## Context

[0005](0005-byte-machine-pinned-by-gitlink-generated-abi-5.md) item 2 fixed the
generated-runtime ABI target at 5; [0012](0012-generated-abi-6-and-keyword-tables.md)
amended it to 6 when the keyword-table lowering needed a new runtime op. This
record amends it again, for a reason this project asked for.

M4 could not render one trace line. llhttp pauses with a code and a message —
`p.pause(ERROR.PAUSED_UPGRADE, 'Pause on CONNECT/Upgrade')` — and its harness
prints that the way it prints an error, so nine in-scope request fixtures end on

```
off=127 error code=22 reason="Pause on CONNECT/Upgrade"
```

A generator pause carried neither. Measured with a probe machine rather than
read: `(status paused error #f stream-offset 1)`. With nothing to rename, the
adapter refused ([0008](0008-bit-exact-trace-conformance-and-the-ratchet.md)
item 2, [0014](0014-the-adapter-may-read-parser-fields.md)) and the nine
fixtures failed honestly.

**The shortcut was available and was declined.** An error node produces a
BIT-IDENTICAL trace, because no fixture in the corpus resumes — and would be
wrong, since a paused parser is resumable and an errored one is not. No test
in the corpus could tell the difference. That is what made it a brief rather
than a workaround, recorded under
[0006](0006-upstream-first-for-general-gaps.md) item 4 as
[the pause-reason brief](../2026-09-14-upstream-pause-reason-brief.md) — the
third from this consumer, after the empty span and the keyword table.

Upstream answered at `v0.4.0` (Milestone 12, its decision 0046). Two of its
choices differ from what the brief proposed, and both are better:

1. **The reason is a distinct result slot, not the error slot.** The brief
   allowed either. Upstream rejected the error slot by name, with the failure
   it would cause: a consumer written before the change that reads "has an
   error" as "failed" would mis-read a resumable pause. `parser-result-error`
   stays `#f` for a pause and a new accessor `parser-result-pause` carries the
   reason.
2. **The boundary is drawn at author-declared pause points.** A `pause` node
   and a `callback` node may declare a reason; the span-callback pauses — an
   internal fragment-resumption step — may not, and the sites say so. The
   brief did not distinguish them.

## Decision

1. **The generated ABI target is 7.** The emitted paused-outcome's error slot
   goes from always-`#f` to `#f | ParserError`, so the emitted contract moves
   and a version-6 library and a version-7 runtime refuse each other.

2. **A pause reason is declared in the `error-declaration` shape and is NOT an
   error.** Upstream reuses that shape for both, so this grammar declares
   `upgrade-paused` beside its error declarations. The distinction is enforced
   at the result — `'paused` status, empty error slot, reason in its own slot —
   never by the record's type. **No error node in this grammar may name a
   pause declaration, and no pause may name an error's.**

3. **The adapter renames a pause's code exactly as it renames an error's**, and
   `paused-upgrade . 22` is an ordinary row. A pause with no declared reason is
   still a refusal, not a guess: the reason is optional upstream, and a parser
   that pauses without saying why has produced something this vocabulary cannot
   spell. [0013](0013-error-identity-is-llhttps-code-and-reason-pair.md)'s
   pair-identity rule applies unchanged.

4. **The ABI number stays re-read, never remembered.** [0005](0005-byte-machine-pinned-by-gitlink-generated-abi-5.md)
   item 5 is untouched and is what named this move at the pin: the generator
   lane asserts the version it finds, and the artifact lane reads the literal
   out of the committed text.

5. **That the pause is a pause is a check in the tree, because no trace can
   show it.** A parser that errored where llhttp pauses would match every
   fixture in the corpus byte for byte. Three unit cases therefore ask the
   parser directly: the status is `paused`, the error slot is `#f`, the reason
   is llhttp's pair — and an ordinary request carries no pause at all, so the
   first two cannot pass vacuously.

## Consequences

Nine fixtures move from `not-yet` to `passing`: `connection.md` #14 #18 #19
#20 #21, `method.md` #2 #3 #4, and `uri.md` #9. Ratchet 87 → 96.

Measured across the pin with the grammar unchanged, the emitted parser is
byte-identical but for the ABI literal — 144,172 bytes both sides, same IR
fingerprint `12284084569705248381`, one line and one character different. The
artifact grows to 144,303 bytes only when the grammar names the reason.

All three of this project's upstream briefs are now discharged.

## What this rules out

- Rendering a pause as an error node to make a fixture pass. It is bit-exactly
  indistinguishable in a trace and behaviourally wrong, and item 5's checks
  exist to catch it.
- Treating "ABI 7" as a fact this repository may restate from memory. It is a
  property of the pinned tree, re-read at the pin — the defect
  [0005](0005-byte-machine-pinned-by-gitlink-generated-abi-5.md) item 5 was
  written to repair, and the lane that catches it has now caught two bumps.
