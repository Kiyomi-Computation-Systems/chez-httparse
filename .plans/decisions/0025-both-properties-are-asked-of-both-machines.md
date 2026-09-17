# 0025: both properties are asked of both machines, and every floor is per kind

Date: 2026-09-17
Status: accepted
Amends: [0024](0024-the-url-input-generator-and-the-second-at.md) (the asymmetry it named)
Builds on: [0024](0024-the-url-input-generator-and-the-second-at.md)
Milestone: Gate 0 (.plans/2026-09-13-gate0-http-parser-milestone-plan.md), after M11

## Context

[0024](0024-the-url-input-generator-and-the-second-at.md) gave the url machine
generated input, and named what it had not done:

> The property lane is still message-only. It runs on every pull request and
> needs no llhttp, and its two properties — fragmentation invariance, and the
> two executors agreeing — hold of the url machine as much as the message one.
> Nothing compares `httparse-url-machine` against its interpreted twin on
> input the corpus does not contain.

That gap mattered more than the differential's did, because of where each lane
runs. The differential is local and opt-in by
[0010](0010-the-live-llhttp-oracle-is-local-and-opt-in.md); the property lane
is a merge gate. And the executor comparison is the **only** check that can
see an emitter bug in `src/generated/httparse-url.sls` over input nobody wrote
down — the conformance lane runs both executors too, but only over 21 recorded
url fixtures.

## Decision

1. **Both properties are asked of both machines.** The kind travels with each
   case and picks an artifact and an interpreted twin, exactly as the
   conformance driver picks one per fixture and the differential picks one per
   case. `generate-urls` and `url.md`'s 21 mutation bases supply the input.

2. **The url cases are a separate run**, as in the differential.
   `HTTPARSE_PROPERTY_URL_CASES=0` reproduces the lane as it was, so a finding
   has one possible source.

3. **EVERY FLOOR IN THE LANE IS PER KIND.** See below; this is the part that
   would have been easy to get wrong and green.

4. **The exception has a url twin, measured.** A span still open when the
   parse fails prints only what a chunk boundary already flushed, so the same
   input traces differently at different chunk sizes. Both traces are
   llhttp's own output from the url fixture binary.

5. **Upstream's `noScan` is checked rather than quoted.** See "what the
   annotation actually says".

## The floor was right, and adding a subject made it wrong without failing

Both properties would pass vacuously over a run that selected nothing —
"every error-free parse is fragmentation-invariant" is true of zero of them —
so both were guarded by a floor. One number over the whole run, which was
right while the lane had one subject.

At the default seed the message kinds produce **65** error-free inputs between
them, so `> clean 20` stays green whatever the url machine does, *including
contributing nothing at all*. That is precisely the failure the floor exists
to catch.

Measured, error-free inputs per kind, over six seeds:

| seed | request | response | url |
|---|---|---|---|
| 20260915 (default) | 39 | 26 | 115 |
| 1 | 32 | 29 | 98 |
| 2 | 28 | 28 | 102 |
| 777 | 37 | 29 | 103 |
| 20260916 | 37 | 34 | 93 |
| 31337 | 31 | 29 | 104 |

The floor is **15** — clear of the worst observed 26 by eleven, and far above
a kind that stopped being generated. The per-kind tally is printed beside the
check, so a reader can see which member is carrying it.

**Witnessed.** `HTTPARSE_PROPERTY_URL_CASES=0`: the old global floor passes at
65, and both per-kind floors fail.

## What the annotation actually says

`url.md` marks four of its 21 fixtures `noScan`, and that annotation is the
corpus's own statement about where this exception bites — it is what tells the
conformance driver not to replay a fixture at every chunk size. A comment was
about to cite it as "exactly the fixtures whose trace depends on chunking",
which is true-sounding and is exactly their four error fixtures.

**Measured, three of the four diverge.** "Failing on broken schema" does not:
its schema span is CLOSED before the error, so no boundary has an open span to
flush early. llhttp does not diverge on it either, checked against the url
fixture binary at both chunk sizes.

So the comment became a check, asserting the two directions separately:

- **The load-bearing one** — nothing diverges unmarked. An unmarked fixture IS
  replayed at every chunk size and compared bit-exactly, so one whose trace
  depended on chunking would make that comparison meaningless.
- **The other one** — the marked set is `(3 15 20 21)` and the diverging set
  is `(15 20 21)`, both written down, so a refresh that moved either fires.

An annotation that is a superset of what it needs to be costs nothing until
you quote it as a reason.

## The evidence

| | before | after |
|---|---|---|
| machines under both properties | 1 | **2** |
| error-free inputs | one global count | **request 39 · response 26 · url 115** |
| executor comparisons | one global count | **request 145 · response 95 · url 240** |
| floors | one, global | **three, per kind** |
| lane cases / checks | 6 / 8 | **12 / 20** |

**Fragmentation invariance holds for the url machine on the same terms.** All
115 error-free url inputs at the default seed are invariant across the whole
chunk ladder; drop the error-free qualifier and 249 url probes disagree. The
qualifier is not a message-parser quirk.

**An emitter bug in the url artifact is caught, and by three groups.**
Hand-editing one byte case in `src/generated/httparse-url.sls` — routing `p`
in a path to the query node, with the grammar untouched — turns red: the
invariance group, the executor group (28 mutants and 29 generated urls), and
the `noScan` group, whose diverging set becomes `(1 2 13 14 15 20 21)`.

That third one is worth noting on its own. The emitter mutation was chosen to
be an *emitter* bug precisely because of the trap in AGENTS.md: the executor
comparison fires for any grammar edit that is not re-emitted, which says
nothing about whether it would catch a compiler bug. This one leaves the
grammar alone.

**A first mutation attempt caught nothing, and that was informative.** Routing
`[` from `url-server` to `url-server-with-at` changed no trace: no pool in
`generate-urls` puts an `@` after a bracket, so the edge is unreachable from
this lane's input. The generator's reach is not the machine's.

## Consequences

**The url machine's emitted artifact now has a merge gate over unwritten
input.** Before this it had the 21 `url.md` fixtures and, locally and
opt-in, the differential.

**Every future kind pays the floor tax.** A fourth subject in this lane must
add itself to `kinds` or its floor will not exist; the tally printing is what
makes that visible rather than silent.

**The lane costs more.** 240 extra cases, each replayed over its full chunk
ladder in the invariance group. Urls are short, so the ladder is every size
rather than the sparse one a long message gets.
