# 0010: the vendored corpus is the CI oracle; a live llhttp binary is a local, opt-in lane

Date: 2026-09-13
Status: accepted
Milestone: Gate 0 (.plans/2026-09-13-gate0-http-parser-milestone-plan.md)

## Context

The architecture document (§4) asks for differential testing against llhttp as
an executable oracle: same byte stream into both parsers, compare accepted
versus rejected, bytes consumed, error position and class, and the callback
sequence. That is the right instinct, and this record does not retire it — it
places it.

What the document could not know is that the corpus already *is* that oracle,
recorded. Each of the 253 HTTP fixtures carries llhttp's own byte-offset event
trace, and upstream's driver replays each one at every chunk size from 1 to the
input length ([0008](0008-bit-exact-trace-conformance-and-the-ratchet.md)). The
comparison dimensions §4 lists — consumed bytes, error position, error class,
event sequence, body and message boundaries — are all present in that text. A
freshly built llhttp binary, fed a corpus input, would print what the corpus
already contains.

So a live binary adds exactly one thing: the ability to run **inputs the corpus
does not contain** — generated, fragmented and mutated HTTP, the property and
fuzz work §4 describes. That is genuinely valuable and genuinely different.

It is also not free. A live oracle in CI means Node, a C toolchain, and an
llhttp build on every pull request.
[0004](0004-ci-covers-the-linux-cell-alone.md) exists because this account's
Actions minutes ran out mid-slice; it retired a macOS cell that cost ten times
Linux and bought weaker evidence than the cheap cell did. Adding a per-push
build that duplicates evidence we already have checked in would repeat exactly
the mistake 0004 recorded.

## Decision

1. **The vendored corpus is the CI oracle.** The conformance lane runs offline
   with no network, no Node and no C toolchain, under the Linux-only arrangement
   of 0004.
2. **A live llhttp oracle is a local, opt-in lane**, off by default and never a
   merge gate. It builds from a checkout named by a variable — the same rule
   [0007](0007-llhttp-corpus-vendored-as-data.md) item 3 applies to corpus
   refresh — and is absent, not failing, when that variable is unset.
3. **Its job is generated input, not corpus input.** Replaying vendored
   fixtures through a live binary is redundant by construction; the lane exists
   for property and fuzz differential, where no recorded trace can exist.
4. **It lands in the release milestone**, not before. Until there is a parser
   that passes the corpus, a fuzz differential reports the same defects the
   corpus already found, more slowly and less legibly.
5. **A divergence it finds is promoted to a fixture.** The reduced input and
   both traces are written into this repository's own test data — never into the
   vendored corpus, which 0007 item 6 keeps verbatim — so the finding survives
   as an offline check that CI runs.

## What this rules out

- Building llhttp on every pull request. The evidence is checked in; paying for
  it again per push is the 0004 mistake with a different runner label.
- A local lane that silently becomes required — a developer machine passing a
  gate no runner can reproduce is how a green build stops meaning anything.
- Hardcoding a sibling checkout path, which 0002 ruled out for byte-machine and
  0007 ruled out for the corpus; a third mechanism here would be a third thing
  to get wrong.
- Reading this record as retiring §4's differential testing. It sequences it.

## Consequences

- Between M1 and the release milestone, unseen-input divergence is not covered.
  That is the accepted gap, bounded by 190 fixtures replayed at every chunk size
  and by the fact that §4's own comparison dimensions are all represented in
  them.
- The release milestone carries real setup cost — building llhttp, wiring the
  generator, reducing failures — which is budgeted there rather than discovered
  there.
- If the opt-in lane proves valuable enough to want automatically, that is a
  decision to take with its measured minute cost in hand, amending this record
  the way 0004 amended 0003.
