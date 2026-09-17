# 0027: the cost is dispatch position, and the fix is not in this repository

Date: 2026-09-17
Status: accepted
Builds on: [0025](0025-both-properties-are-asked-of-both-machines.md)
Milestone: Gate 0 (.plans/2026-09-13-gate0-http-parser-milestone-plan.md), after M11

## Context

The cost lanes published absolute rates and nothing to read them against.
`llparse-test-fixture` turns out to carry a `bench` mode, and upstream's own
`npm run bench` drives the very binaries `tools/oracle/` already builds, so a
comparison needed no benchmark program and no methodology of ours. On
upstream's three bench inputs, their binary and ours on the same bytes:
**485x** on a 703-byte request, **365x** on a 520-byte chunked `POST`, **89x**
on a 52-byte URL.

**The ratio is not constant, and the variance is on our side.** llhttp's url
and message parsers are within 1.5x of each other per byte. Ours differ by
4.5x. A uniform cost of being Scheme would have shown up as one number in all
three rows; this did not, so something was concentrated in the message
machine, and a number that varies is a number with a cause.

## What was measured

Four inputs of ~900 payload bytes each, differing only in where those bytes
sit, plus the standalone url machine as a control:

| input                              | ns/byte |
|------------------------------------|---------|
| message machine, ~900 B request target |   239.8 |
| message machine, 30 headers            |   236.4 |
| message machine, 3 long header values  |   153.9 |
| message machine, 900 B body            |    17.1 |
| **url machine**, ~900 B url            |    29.4 |

The first and the last are the same grammar over the same kind of bytes,
**8x apart**. So it is not the header section, and it is not callbacks: the
message machine reaches 17 ns/byte on body bytes, which a `Content-Length`
body consumes in bulk rather than one dispatch at a time.

**Chez compiles `(case st ...)` over integer keys as a linear scan.** Measured
against 10.4.1 on 2026-09-17: with 300 arms, the arm at index 5 dispatches in
1.90 ns and the arm at index 295 in 93.15 ns -- about **0.31 ns per arm
skipped**, and the total number of arms does not matter, only the position of
the one that matches. Identical at optimize-level 0, 2 and 3, so no compiler
setting avoids it.

The generated message machine has **530 states**, and its hot scanning states
are numbered late: `url-path` 468, `url-server` 465, `value-loop` 235,
`header-field-loop` 170. The standalone url machine runs *the same url
grammar* at `url-path` 15 and `url-server` 9, because it only has 75 states.
That difference in numbering is the whole of the 4.5x.

**Proved in the emitted parser, not only in a probe.** `case` arms may be
permuted without changing semantics, so they were:

| input                  | as emitted | url states first | full hot set first |
|------------------------|-----------:|-----------------:|-------------------:|
| ~900 B request target  |      239.8 |    **42.4** 5.7x |               86.9 |
| 30 headers             |      236.4 |            234.1 |     **128.8** 1.8x |
| 3 long header values   |      153.9 |                - |      **70.0** 2.2x |
| 900 B body             |       17.1 |             16.6 |               15.4 |
| url machine (control)  |       29.4 |             28.8 |               28.6 |

The request-target row is *worse* under the larger hot set than the smaller
one, because 129 arms in front puts the url states further back than 34 did.
The model predicts that, which is the reason to trust it.

What the dispatch could cost instead, same machine, same runtime:

| strategy                                   | ns/transition |
|--------------------------------------------|--------------:|
| `case`, hot arm at 468 of 530 (what we get) |         184.4 |
| vector of closures indexed by state         |           2.6 |
| mutual tail calls between state procedures  |           0.8 |

## Decision

1. **The cause is recorded here; the fix is not made here.** Nothing in this
   repository's grammar, generated artifact or runtime is wrong. The dispatch
   is emitted by `byte-machine`'s `render-machine`
   (`vendor/byte-machine/src/byte-machine/compile.sls`), which writes one
   `case` arm per state in state-id order. A change belongs there.

2. **Do not reorder state ids to chase this.** byte-machine's decision 0016
   already names the hazard: state ids feed decision 0009's IR fingerprint
   *and* the order of the emitted arms, and cross-node sharing was excluded
   partly because a pure size optimization "falls under 23.3's admission rule,
   which cannot be satisfied yet". A hotness ordering is the same kind of
   change: it buys 1.8-2.8x, it leaves cost permanently dependent on where the
   generator happens to number things, and it moves every fingerprint. The
   dispatch structure is what should change, and it needs no new numbering.

3. **The upstream work goes through 23.3, including its unmet prerequisite.**
   byte-machine's admission rule requires repeatable material improvement in
   **both** source and AOT lanes, no regression on another platform cell,
   unchanged observable semantics, complete interpreter equivalence, and a
   documented complexity cost -- and, before the first optimization is
   admitted at all, a decision record deriving "material improvement" and
   "significant regression" from observed baseline variance. That record does
   not exist yet, so it is the first piece of work, not a formality to add
   afterwards.

4. **No number from this investigation becomes a gate.** The figures above are
   recorded in `docs/performance.org` and asserted nowhere. A ratio against
   llhttp is stable enough to gate on where an absolute rate is not, but
   gating one now would pin a number that the work in point 3 is expected to
   move by an order of magnitude.

## Consequences

- The published comparison is unflattering and stays that way until the
  dispatch changes. It is recorded rather than softened, because the useful
  part was never the ratio but its *variance*: one number in all three rows
  would have said "this is what Scheme costs" and closed the question.
- The 4.5x is not evidence about this parser's grammar, and a future reader
  comparing the two machines should not conclude that the message grammar is
  extravagant. It has 530 states because HTTP messages need them.
- The body path is already cheap and is not part of this. A `Content-Length`
  body consumes in bulk; only per-byte scanning pays the dispatch.
- Everything here was measured on one cell, `tarm64osx` with Chez 10.4.1.
  That `case` is a linear scan is a property of that compiler, and criterion 3
  of 23.3 exists precisely because a second cell may not agree.
- **A library-path experiment needs the copy to say so.** The first permutation
  run reported no change at all, which read exactly like a refuted hypothesis.
  The reordered library was second on `library-directories` and the original
  had loaded. It was caught by making the copy announce itself on load, and
  only then did the 5.7x appear. This is the same shape as the fixture-cache
  trap in [0026](0026-the-lenient-flags-are-combined-and-the-init-hook-is-ours.md):
  when a change that must do something appears to do nothing, suspect the
  apparatus before the hypothesis.
