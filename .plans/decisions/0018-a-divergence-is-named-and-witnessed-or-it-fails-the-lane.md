# 0018: a divergence from the live oracle is named and witnessed, or it fails the lane — and two are named for v0.1

Date: 2026-09-15
Status: accepted
Milestone: Gate 0 (.plans/2026-09-13-gate0-http-parser-milestone-plan.md), M8

## Context

[0010](0010-the-live-llhttp-oracle-is-local-and-opt-in.md) placed a live
llhttp behind a local, opt-in lane whose subject is generated input, and item
5 says a divergence it finds "is promoted to a fixture". That is the right
instinct and it is incomplete in one respect: it says what to do with a
divergence you intend to FIX, and says nothing about one you intend to KEEP.

The lane found both kinds on its first run. Three defects, now fixed and
pinned by offline checks that need no llhttp:

- `message begin` was withheld when the first byte was one no method may
  start with, because the start node validated before the event fired;
- repeated spaces between the method and the target produced an **empty**
  target span, because the grammar had one space-matching node where llhttp
  has two;
- the two RTSP methods were spelled `GET-PARAMETER` and `SET-PARAMETER`,
  where llhttp's map keys them `GET_PARAMETER` and `SET_PARAMETER`.

None of the three is visible to the 253-fixture corpus. And two divergences
remain that are not defects of the same kind:

- **the deferred URL sub-parser.** llhttp validates the request target's
  structure; this parser carries it as one opaque span, which is what 0009
  defers to M11 and what every `uri.md` fixture is written against.
- **a completion event at the exact end of the input**, in both directions.
  Where a keyword's completion fires on its last byte, this parser is one
  event short; where a completion fires one byte past a delimiter, it is one
  event early. One more byte and the two agree exactly, which is why no
  recorded fixture shows either.

A lane that reported these on every run would be permanently red and
therefore read by nobody. A lane that ignored anything it could not explain
would be worse.

## Decision

1. **Every divergence is classified, and an unclassified one fails the
   lane.** The classifier names exactly the classes this project has decided
   about. It is deliberately narrow — each class requires a specific
   relationship between the two traces, including the OFFSET the extra lines
   sit at — so that a new defect cannot be absorbed into an existing name.
2. **Each class is anchored by a witness with llhttp's own bytes**, for one
   reduced input, checked exactly. A class defined only by a predicate is a
   class that can quietly widen; a witness turns red the day the class is
   fixed, which is the notification that it should be retired.
3. **A divergence that is fixed is promoted to an offline check**, in a lane
   that runs without llhttp. The live lane is opt-in and must never be the
   only thing standing between a defect and a release.
4. **The two remaining classes are v0.1 known limitations, published**, in
   `docs/conformance.org`, with the reduced input and both traces. A
   compatibility claim that names what it does not do is the only kind worth
   publishing.
5. **The upstream half is filed upstream**, not worked around. The keyword
   table's terminal behaviour is general, has no workaround at this layer,
   and is the fifth brief.

## What this rules out

- A suppression list keyed by input or by seed. The inputs are generated;
  a list of them would be a list of one run's accidents, and it would grow.
- Reproducing llhttp's end-of-input behaviour bug-for-bug by inserting peek
  nodes in front of every completion event. That is a systematic change to
  ten productions to fix a divergence visible only when a feed ends exactly
  on a delimiter, priced during M8 and declined.
- Treating the URL class as a defect. It is a deferral with a milestone and a
  fixture count, and naming it here is what keeps the lane usable while it
  stands.
- Reading a green differential lane as "no divergences". It means no
  divergence outside the named classes, and the printed counts say how large
  each class was.

## Consequences

- The lane is usable as a routine check rather than a one-off investigation,
  and its output is three numbers and a list that should be empty.
- When the URL sub-parser lands in M11, its class should go to zero and its
  witness should fail; the same for the keyword table when upstream takes the
  fifth brief. Both are how this record gets amended.
- The classifier is now a thing that can be wrong. It is tested against the
  witnesses, and its narrowness was arrived at by measurement: an earlier
  version matched "exactly one extra line" and missed the case where a
  completion leads to an error at the same offset.
