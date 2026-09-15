# 0008: conformance is bit-exact trace equality through an adapter that may rename but never compute, gated by a two-way ratchet

Date: 2026-09-13
Status: accepted
Refined by: [0013](0013-error-identity-is-llhttps-code-and-reason-pair.md), items 2 and 3 · [0014](0014-the-adapter-may-read-parser-fields.md), item 2
Amended by: [0016](0016-a-finish-fixture-prints-a-field-not-an-ending.md) (item 5: the `*-finish` types print a field, they do not end a parse)
Milestone: Gate 0 (.plans/2026-09-13-gate0-http-parser-milestone-plan.md)

## Context

The vendored corpus ([0007](0007-llhttp-corpus-vendored-as-data.md)) expects an
exact textual event trace per fixture. Comparing against it means rendering this
parser's behaviour into that text, and that rendering is the whole risk: an
adapter that computes anything can produce a plausible trace from wrong parser
state, which is precisely the test that passes whether the code is right or
wrong.

Three properties of the upstream oracle fix what the comparison must do.

**Fragmentation is built in.** `llparse__run_scan(n, input, len)` feeds the
input in **fixed-size chunks of `n` bytes**, and the driver runs every `n` from
1 to the input length; `noScan` collapses that to the single whole-buffer feed.
So each fixture is a family of runs, and "the result must not depend on read
fragmentation" is not an extra test we write — it is the corpus.

**Span text is split, then re-joined.** `llparse__print_span` breaks span text at
CR and LF, emitting `len=1 span[x]=cr` / `=lf` lines for those bytes; the
JavaScript side then coalesces *contiguous* same-span fragments back together
and **moves the merged line to the end of the output**. The `=cr`/`=lf` lines do
not match the coalescing pattern and are never merged. Reproducing this is
mechanical, and getting it subtly wrong would silently change which traces match.

**The numbers are llhttp's.** `headers complete` prints llhttp's method enum
index, its `FLAGS` bitfield, and its `content_length`; errors print its `ERROR`
code. Matching the corpus means speaking those numbers.

Measured cost of the full scan, from the vendored corpus at `v9.4.3`: 253
fixtures, 22,930 input bytes total, median fixture 63 bytes, longest 2,044
(`test/request/sample.md`); **21,630 parser runs** across every chunk size,
about 7.28M bytes fed. Whole-buffer-only is 253 runs.

> **These figures were corrected on 2026-09-13.** The record first carried
> smaller figures — 22,598 input bytes, 21,326 runs, longest 2,042 — taken from
> a throwaway script whose trailing-newline strip removed two newlines where the
> reference removes one, shortening nearly every fixture by a byte. The numbers
> above come from the in-tree loader and decoder that the corpus lanes
> exercise. That is the
> point of AGENTS.md's run-it-first standard, and this is the measurement it
> was written about.

## Decision

1. **Conformance is bit-exact textual equality** between the trace this parser
   produces and the vendored expected block, line for line, offsets included.
   No normalisation beyond what upstream itself specifies, and no set-wise or
   order-insensitive comparison.
2. **The adapter may rename, never compute.** Rendering our symbolic events,
   errors and flags into llhttp's text is a *test-only* layer that is pure table
   lookup. A symbol with no table entry is a hard error, never a fallback or a
   default. If the parser reports the wrong error, the adapter renders the wrong
   number faithfully and the test fails — which is the only behaviour that makes
   the corpus load-bearing.
3. **The public Scheme API stays symbolic.** llhttp's integers live in the
   adapter's tables, not in this library's exported surface. The tables are
   derived from vendored constants and carry their own provenance check.
4. **The trace formatter replicates upstream's rendering exactly** — the CR/LF
   span split and the coalesce-and-move-to-end normalisation — and is tested as
   a pure function on hand-built event sequences, independently of any HTTP
   parsing. Its own tests come first; it is the instrument, and an uncalibrated
   instrument cannot measure the parser.
5. **Chunk-size coverage splits across the existing presets.** The `pr`
   selection runs chunk size 1 and the whole buffer — the two extremes, 506 runs
   — and the `release` selection runs every chunk size, all 21,630. `noScan`
   fixtures run whole-buffer only in both, as upstream specifies. Any narrowing
   beyond this is recorded in the manifest with a reason, never taken silently
   for speed.
6. **A two-way ratchet gates the lane.** A manifest lists every vendored fixture
   with a status. The lane fails when a fixture marked passing fails, **and when
   a fixture marked not-yet-passing passes**. Status changes are diffs in a
   reviewed file, so every milestone's progress is a countable, reviewable
   number rather than a claim.

## What this rules out

- Any adapter branch that could synthesise trace content the parser did not
  actually produce — inferring `content_length` from the input, defaulting an
  unmapped error to a generic code, or emitting `headers complete` from
  anywhere but the parser reaching that point.
- "Close enough" comparison: normalising whitespace, dropping offsets, comparing
  event multisets, or matching on a prefix of the trace.
- A one-way ratchet. A manifest that only fails when a passing fixture breaks is
  a TODO list; it lets a fixture start passing by accident and never notice,
  which is how a milestone's exit criterion becomes unfalsifiable.
- Editing the expected blocks, which [0007](0007-llhttp-corpus-vendored-as-data.md)
  item 6 already forbids at the source.

## Consequences

- The full-scan lane is a `release`-preset cost, not a per-push one. The
  measured 21,630 runs are dominated by per-run setup and trace formatting
  rather than by the 7.28M bytes; the plan re-measures wall time once the lane
  exists rather than predicting it here.
- Every milestone gets a concrete exit criterion of the form "these N fixtures
  move from not-yet-passing to passing", with the ratchet diff as its evidence.
- A fixture we come to believe is wrong becomes a permanent ratchet entry with a
  written reason and a decision record — visible, countable, and never a silent
  edit.
- Adopting llhttp's numeric tables in the adapter means an upstream corpus
  refresh that renumbers anything shows up as a table provenance failure, not as
  a wave of mysterious trace mismatches.
