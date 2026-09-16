# 0022: the url sub-parser is a second machine, and Gate 0's corpus is complete — 274 of 274

Date: 2026-09-16
Status: accepted
Amended by: [0023](0023-the-request-target-is-parsed-not-carried.md) — its "What this milestone did NOT do"
section is now done. The url machine IS in the HTTP request target's path, and
the `url-machine` divergence class is deleted.
Amends: [0009](0009-v01-is-strict-request-and-response-parsing.md) (its last deferral)
Builds on: [0020](0020-lenient-modes-a-flag-at-a-time.md)
Milestone: Gate 0 (.plans/2026-09-13-gate0-http-parser-milestone-plan.md), M11

## Context

[0009](0009-v01-is-strict-request-and-response-parsing.md) deferred 84 fixtures.
M9 took 26, M10 took 37, and the 21 in `url.md` were what remained. They are
not more of the HTTP parser:

```js
function buildURL() {
  const p = new LLParse();
  const instance = new llhttp.URL(p, true);   // separateSpans
  const node = instance.build();
  node.exit.toHTTP.otherwise(node.entry.normal);
  node.exit.toHTTP09.otherwise(node.entry.normal);
  return { llparse: p, entry: node.entry.normal };
}
```

`test/md-test.ts` builds that binary for the `url` type and passes **no `-D` at
all** — no `LLHTTP__TEST_HTTP`, no pause, no skip-body. Its traces carry no
`message begin` and no `headers complete`: five span names and errors, over a
bare URL with no HTTP framing around it.

## Decision

1. **A second machine, `(httparse url-grammar)`, emitting a second artifact
   `(generated httparse-url)`.** Not a mode of the first and not a subgraph of
   it. The two share no field, no callback and no error node.

2. **The HTTP parser is untouched.** Its request-target is one span,
   `span[url]`, which is upstream's `separateSpans = false` build and is
   already what M2 shipped. The five separate spans exist only in the url
   binary, so this milestone adds a capability rather than refining one.

3. **The conformance driver resolves a machine PER FIXTURE**, from the kind the
   input fence already gives it (` ```url ` rather than ` ```http `). Both
   executor lanes — the committed artifact and the reference interpreter —
   cover both machines, so the executor differential judges the url parser
   exactly as it judges the message parser.

4. **The ratchet's url class is gone.** `ratchet-fixture-class` no longer
   consults the kind; the kind decides which machine runs a fixture, not
   whether it is gated. **The deferral list is now empty**, and
   `unit.ratchet` asserts that as `0` and `274` rather than by no longer
   having a case.

5. **One emitter, one refresh, one determinism lane.** `make parser-refresh`
   writes both artifacts and one lane re-emits and compares both, so a refresh
   that reached only one of them cannot pass.

## Three transcription traps, and what pinned each

**`schema:/path` reports at 8, not 7.** Matching `//` against `/p` consumes the
first `/` before discovering the mismatch, and the consumed prefix stays
consumed. This generator's sequence dispatch says so in as many words — *"already
consumed prefix bytes remain consumed, and the declared mismatch edge decides
whether the mismatching byte advances or is reexecuted"* — so the fixture and
the runtime agree by construction. A machine that checked two bytes without
consuming would report 7 and pass every other case in the file.

**A tab is refused one byte past itself.** Upstream's `private node(name)`
wraps EVERY construction in `.match(['\t','\f'], this.errorInvalid)` — a match,
which consumes. It is a helper here for the same reason it is one there: a node
that forgot it would be a hole only `url.md#20` and `#21` could find.

**A host that ends at a `?` keeps the `?`.** `.match('?', spanEnd('host', ...))`
advances before the span end runs, so the span closes one byte late. Reading the
source lets you argue it either way. **The oracle does not**, and no fixture in
`url.md` has one — so it is measured, in `unit.url`, and transcribed rather than
repaired.

## What upstream has that this does not, and why

**The `url` span is a stub in this build.** With `separateSpans`, the span table
holds five names and not `url`, so `spanStart('url')` and `spanEnd('url')`
resolve to `span_start_stub_url` / `span_end_stub_url` — nodes that only
forward. Omitted: a node that only forwards is not a behaviour.

**`url_query_start` is built and never routed to.** Nothing in `build()` targets
it; it survives only in the adaptor loop that gives every node its space/CR/LF
edges. llparse drops it, and this verifier would refuse it as
`unreachable-node` — the same judgement said out loud.

**Six copies each of two errors, for the opposite reason.** The verifier keeps a
flat span lattice, so an error reachable with two different spans open needs two
nodes. `e-invalid-*` and `e-eof-*` therefore come in one per span state, and
every one is reachable. `(httparse grammar)` pays the same price at its own
`e-eof-*` block.

## The exits are graph the corpus cannot reach

Not one of `url.md`'s 21 inputs contains a space, a CR or an LF, and upstream
gives every node inside a URL an edge for each. Leaving them out would make a
space in a URL an **error** where llhttp ends the URL and goes looking for
`HTTP/` — a behaviour difference, not an omission.

So they are built, and measured against a purpose-built url oracle rather than
argued for. Two of the six measurements are worth naming: a space does not end
the parse but starts **another URL** (the test build loops both exits back to
the entry), and what follows is judged from scratch — `http://host.com xyz`
prints `xyz` as a **schema** span.

**That loop is a property of the TEST BUILD, not of the URL parser.** In a real
llhttp the two exits join the HTTP machine at `HTTP/`. This machine is built for
the binary the corpus was recorded from, so it has the loop; a future embedder
wanting the URL parser inside an HTTP parse would want the exits wired
differently, and that is a different machine again.

## What this milestone did NOT do

> **Done since, by [0023](0023-the-request-target-is-parsed-not-carried.md)
> (2026-09-16).** The subgraph was spliced into the request target, every one
> of the 45 comparisons became an agreement, and the class was deleted. This
> section is kept as written because it is what made the next step obvious —
> naming the gap is what got it closed.

**The `url-machine` divergence class is unchanged, and was re-measured after
the fact to be sure: `agreed=1097 url-machine=45 late-complete=4
early-complete=0 unclassified=0`, identical to before.**

The HTTP parser still carries its request target as one opaque span and reads
on where llhttp's structural check stops. Building the URL machine did not
change that, because the machine is built the way llhttp's `url` BINARY runs
it — standalone, over a bare URL, exits looped back to its own entry. Wiring
it into the HTTP parse means joining at `entry.normal` / `entry.connect`,
leaving at `toHTTP` / `toHTTP09`, and giving up the single `span[url]` that
every `uri.md` fixture is written against.

This is worth a heading because the milestone's NAME invites the opposite
reading: "the url sub-parser is done" and "the url divergence is closed" are
different sentences, and only the differential can tell you which one is
true. A capability that exists is not a capability that is in the path.

## Consequences

**Gate 0's corpus claim is now unconditional: 274 of 274, every HTTP fixture and
every URL fixture llhttp ships, bit-exact at every chunk size.** No fixture is
deferred and no upstream gap is open.

**The live differential does NOT cover the url machine.** It generates
`request` and `response` inputs and drives `http-request-c` / `http-response-c`;
a URL input generator and a url oracle lane would be a separate piece of work.
Named here rather than left as an assumed symmetry: the url parser's evidence is
21 fixtures at every chunk size, the executor differential, and six
oracle-measured cases — not a generated-input differential. M8's experience says
that is a real difference, since the generated-input lane is what found the
keyword-table divergence nothing else did.
