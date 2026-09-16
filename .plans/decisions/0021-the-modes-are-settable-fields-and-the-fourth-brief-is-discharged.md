# 0021: the modes are settable fields — generated ABI 8, and the fourth brief is discharged

Date: 2026-09-16
Status: accepted
Supersedes: [0017](0017-the-message-kind-is-a-decision-callback-not-a-field-the-embedder-writes.md) (its mechanism, not its reasoning)
Amends: [0020](0020-lenient-modes-a-flag-at-a-time.md) item 1, [0015](0015-generated-abi-7-and-a-pause-carries-its-reason.md) (the ABI number), [0005](0005-byte-machine-pinned-by-gitlink-generated-abi-5.md) item 2
Milestone: Gate 0 (.plans/2026-09-13-gate0-http-parser-milestone-plan.md), between M10 and M11

## Context

Twice now this parser has spent graph on something llhttp spends an assignment
on. [0017](0017-the-message-kind-is-a-decision-callback-not-a-field-the-embedder-writes.md)
made the message kind a required decision callback and three nodes;
[0020](0020-lenient-modes-a-flag-at-a-time.md) item 1 made the lenient bitset
eleven optional decision callbacks and a twenty-two-node ask chain ahead of the
entry. Both records name the same cause and neither pretends it is a design:
a field's initial value belonged to the machine, and `parser-field-ref` had no
mutating sibling, so *a parser could not be started in a mode*.

That was this project's fourth upstream brief
(`.plans/2026-09-15-upstream-parser-mode-brief.md`). The generator answered it
at the pin this record moves to, and its own changelog prices the collapse in
exactly this consumer's terms: a request/response selector and an eleven-bit
bitset become **two settable field declarations and one `make-parser`
argument**.

## Decision

1. **The pin moves, and the pin moves alone first.** One commit carries the
   submodule and the two ABI lanes and nothing else, so that the regenerated
   artifact's *one-character* diff is reviewable on its own. A machine with no
   settable field emits byte-identically to its ABI-7 self but for the version
   literal, and the IR fingerprint — computed from the IR, not the text —
   is unchanged at `2737053619879110440`. That is the evidence the machine did
   not move, and it is stronger than reading the diff.

2. **The generated ABI is 8**, amending [0015](0015-generated-abi-7-and-a-pause-carries-its-reason.md).
   A settable machine emits an optional fourth metadata member, a
   `(name width)` table the generated `make-parser` range-checks an override
   against. Both lanes that pin the number are updated together, which is
   [0005](0005-byte-machine-pinned-by-gitlink-generated-abi-5.md) item 5 working
   as designed: the number lives in two checks and neither could go stale
   quietly.

3. **`lenient-flags` and `type` are settable; the callbacks are deleted.**
   Not deprecated, not kept as an alternative surface. Two ways to choose a
   mode is two things to keep in agreement, and the second one would be the
   one no fixture exercises.

4. **The bit tables move to `(httparse modes)`, which imports nothing.**
   Three consumers must agree on these integers — the grammar that reads a bit,
   the harness that builds a parser per fixture, and an embedder writing the
   initials — and before this the grammar and the harness each kept their own
   list. A pure library is also what an embedder can import without dragging
   the generator's builder and verifier in behind it.

5. **The strict path is exercised harder, not less.** Every fixture passes an
   explicit `(lenient-flags . 0)` rather than omitting the row, so all 216
   strict ones run the override at its identity value. A bug that wrote the
   wrong field, or wrote it at the wrong time, cannot hide behind "strict
   passed nothing".

6. **The acceptance criterion is the ratchet AND the size.** 253 fixtures pass
   at every chunk size and the emitted artifact is smaller. Measured on the
   artifact, over the three commits:

   | | before | after |
   |---|---|---|
   | states | 457 | **434** |
   | callback declarations | 37 | **25** |
   | bytes | 264 529 | **256 021** |

   The live differential is unmoved: `agreed=1097 url-machine=45
   late-complete=4 early-complete=0 unclassified=0`.

## Why this is not only a deletion

**The message kind got NARROWER, not just cheaper.** `switch-type` sits inside
the message loop — the restart re-enters at `start`, which reaches it again —
so `on-message-type` was asked **once per message**, and an embedder could have
answered `request` for one pipelined message and `response` for the next.
`s->type` is written once over there and cannot do that. Nothing in the corpus
exercised the difference, which is why it is written down here rather than left
to the ratchet to notice. The restart never cleared `type`, so the per-message
store it did was already redundant work.

**The reset property got STRONGER.** Under the ask chain, `lenient-flags` read
zero until the first byte arrived, `parser-reset!` really did clear it, and the
mode came back only because the next feed re-entered the chain and asked again.
A settable field reads its value before any byte and still reads it after a
reset, because `parser-reset!` restores *the embedder's* initials. The brief
asked for that; this is it.

## The one thing that got later, not better

`on-message-type` was **required**, so a parser built without it was refused by
`make-parser`. A field initial cannot be made mandatory. A parser built with no
`type` now starts at the declared `TYPE-BOTH` — llhttp's `HTTP_BOTH`, whose
`start_req_or_res` arm v0.1 does not implement — and refuses at offset 0 with
the same code and the same reason string, one feed later than before.

**Accepted, with the trade recorded rather than smoothed over.** It is still a
refusal and not a guess, it is the error llhttp's own `type` gap produces here,
and the alternative — keeping a required callback purely to fail earlier — is
the two-surface problem item 3 refuses. A case in `unit.lenient` pins the
behaviour so the trade stays visible rather than becoming folklore.

## What this record does NOT change

[0017](0017-the-message-kind-is-a-decision-callback-not-a-field-the-embedder-writes.md)'s
*reasoning* stands in full: the third arm is still not v0.1's, the kind is
still not derivable from the bytes, and the fall-through is still an error
rather than a default. Only its mechanism is superseded.
[0020](0020-lenient-modes-a-flag-at-a-time.md) items 2 onward — one
`lenient-fork` per leniency, the two flags that only work together, the
reasoned NUL divergence — are untouched.

## The method that made this safe

**A behaviour-preserving refactor is the one case where "the diff is smaller"
is an acceptance criterion** — but only because the 253-fixture ratchet and the
live differential can both say "and nothing else moved". Keeping the pin move
out of M10 is what bought that: a dependency bump folded into a behaviour
milestone is a red lane nobody can attribute.

**Three commits, each green.** Pin alone; lenient; type. The middle one is the
only one that could plausibly have moved a trace, and it is the one whose test
changes are all rewrites of cases that tested a mechanism rather than a
behaviour.

**Tests that named the mechanism were rewritten, not deleted.** Three cases in
`unit.lenient` and two in `unit.adapter` asserted the ask chain. Each became the
property that now holds — the mode outliving two restarts, the initials
producing llhttp's integers, the reset restoring the embedder's value — because
a case deleted along with the code it covered is coverage silently lost.
