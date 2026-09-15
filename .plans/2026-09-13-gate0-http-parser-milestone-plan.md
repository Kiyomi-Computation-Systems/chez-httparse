# Gate 0: the HTTP parser milestone plan

Status: Gate 0 design. Decisions [0005](decisions/0005-byte-machine-pinned-by-gitlink-generated-abi-5.md)–[0010](decisions/0010-the-live-llhttp-oracle-is-local-and-opt-in.md) fix what this document plans.

## Goal

An HTTP/1.x parser for Chez Scheme, defined as a byte-machine grammar and
generated from it, behaviourally compatible with llhttp and measured against
llhttp's own recorded test corpus. v0.1 is strict-mode request and response
parsing: 190 of the 253 upstream HTTP fixtures ([0009](decisions/0009-v01-is-strict-request-and-response-parsing.md)).

Slice 1 ported the harness and build layer. `src/` is still empty. This plan
covers everything from there to the release.

## The shape of the work

Four layers, in the dependency direction the architecture document fixes (§ Core
Design Principles 2–6):

```
  build time                          run time
  ----------                          --------
  (httparse grammar)                  (generated httparse-request)
    builds the source IR    --emit-->   depends on (byte-machine runtime) ALONE
    via (byte-machine graph)                    |
                                                v
                                        (httparse core)     pure decisions:
                                          framing, keep-alive, needs-eof
                                                |
                                                v
                                        (httparse parser)   the imperative shell:
                                          make-http-parser, feed!, reset!, callbacks
```

`(httparse grammar)` is build-time only and never ships. The generated parser is
a **checked-in derived artifact** — committed, with a determinism lane that
re-emits and compares, following the standard byte-machine established in its
own Milestone 9.

`(httparse core)` is the functional core, and it is where llhttp's C decision
functions land: `llhttp__after_headers_complete`, `llhttp__before_headers_complete`,
`llhttp__after_message_complete`, `llhttp_should_keep_alive`,
`llhttp_message_needs_eof` (`src/native/http.c`, ~170 lines of pure decision
logic over parser state). In byte-machine terms these are `decision` callbacks
with branch keys — pure functions from a state record to a branch. They are
tested as pure functions, independently of any parsing.

## The test instrument comes first

The corpus is not a list of inputs; it is llhttp's recorded behaviour
([0007](decisions/0007-llhttp-corpus-vendored-as-data.md)). Measured at
llhttp `v9.4.3`:

- 253 HTTP fixtures in 23 files, 288K; 22,930 input bytes total; median fixture
  63 bytes, longest 2,044.
- Each fixture is `input → exact byte-offset event trace`, ~20 distinct line
  shapes over 4,754 expected lines.
- Upstream replays each fixture at **every chunk size from 1 to its length**, so
  resumability across arbitrary input boundaries is the corpus, not an extra
  suite. Full scan is 21,630 parser runs; whole-buffer-only is 253.

Reading it needs four pure functions, each with its own input→output tests:

1. **the loader** — file bytes → fixture records. It must associate `meta`,
   ` ```http ` and ` ```log ` **by markdown section, not by adjacency**: five
   fixtures carry prose between the input and the log block (four in
   `test/request/connection.md`, one in `test/response/sample.md`).
2. **the input decoder** — strip the trailing newline, remove backslash-escaped
   newlines, normalise newlines to CRLF, expand `\r \n \t \f \xHH` and octal.
   It **refuses** `${...}` rather than implementing it
   ([0007](decisions/0007-llhttp-corpus-vendored-as-data.md) item 5).
3. **the trace formatter** — events → llhttp's exact text, including the CR/LF
   span split and the coalesce-and-move-to-end normalisation
   ([0008](decisions/0008-bit-exact-trace-conformance-and-the-ratchet.md) item 4).
4. **the scan driver and comparator** — feed at each chunk size, compare
   bit-exactly, report the first differing line.

All four are testable, and must be tested, before any HTTP byte is parsed. They
are the instrument; an uncalibrated instrument cannot measure the parser.

## Milestones

Each milestone exits on a ratchet diff: named fixtures move from
not-yet-passing to passing, and nothing else moves
([0008](decisions/0008-bit-exact-trace-conformance-and-the-ratchet.md) item 6).

### M1 — the corpus harness, with no parser

Vendor the corpus under `test/vendor/llhttp/` with `LICENSE`, `PROVENANCE` and a
checksum manifest. Build the four pure functions above, the ratchet, and the
`pr`/`release` chunk-size split.

**The byte-machine submodule does NOT land here.** This bullet originally said
it did, which contradicts [0002](decisions/0002-byte-machine-consumption-and-abi.md)
item 2 — the submodule is added in the first slice that actually invokes the
emitter, because "adding an unused pin now would only rot". M1 builds no
grammar and emits nothing, so the pin and its ABI-5 assertion move to **M2**,
which is the first slice that does. The plan was wrong and the decision was
right.

**Exit**: all 274 fixtures (253 HTTP + 21 URL) load and decode; the ratchet
lists them all with a status, 190 in scope and 84 deferred, each entry's class
checked against the one derived from its fixture's own meta; the comparator is
mutation-witnessed — a deliberately corrupted trace must fail it. No HTTP
parsing in this milestone.

### M2 — the request line

`message begin`; `method`, `url`, `protocol`, `version` spans and their
`complete` events; the strict CRLF rule; `invalid-method`, `invalid-version`,
`invalid-url`, `invalid-constant`.

This is the first slice that invokes the emitter, so it is where the
byte-machine submodule lands at the
[0005](decisions/0005-byte-machine-pinned-by-gitlink-generated-abi-5.md) pin,
with ABI 5 asserted as a check in the tree rather than restated in prose.

**Reachable ceiling**: fewer than the ceilings table suggests, and the table's
row is an over-count. It buckets a fixture by the deepest event in its trace,
so a request whose start line parses perfectly and which then errors on the
*first header byte* has no `span[header_*]` and no `headers complete`, and
lands in the start-line row. Measured over those 17: **11 terminate inside the
request line and 6 need the header section**, and one of the 11
(`request/invalid.md#13`, which errors on a bare `:` where a field name should
start) needs it too.

**The ratchet is the measurement, not this number.** The grammar is built, the
conformance lane is run, and whatever passes is promoted — which is what a
two-way ratchet is for. The ceilings table stays as a planning aid with this
caveat attached.

What M2 must actually produce, read off those fixtures rather than assumed:
`message begin`; the `method`, `url`, `protocol` and `version` spans with their
`complete` events at llhttp's exact offsets (note the asymmetry — `method`,
`protocol` and `version` complete fire *at* their delimiter, while `url`
complete fires one byte *past* its space); a method table, since `MKCOLA`
reports `Expected space after method` after matching `MKCOL`; the `HTTP`/`RTSP`/
`ICE` protocol constants; version validity; and llhttp's method-versus-protocol
compatibility rules, which carry four distinct reasons under error code 8.

### M3 — the header section, as syntax

`header_field` / `header_value` spans, OWS handling, strict line endings, the
empty line, `headers complete` with no framing interpretation yet. Field names
stay **opaque spans** here, which is what keeps M3 clear of the
case-insensitivity gap.

**obs-fold is REJECTED, and that is llhttp's strict behaviour, not a
simplification.** A continuation line beginning with SP or HTAB reaches
`header_value_discard_lws`, whose SP/HTAB arm is behind `LENIENT_FLAGS.HEADERS`;
with the flag off it is `error code=10 reason="Invalid header value char"`. The
corpus agrees: the folding fixture that exercises folding is
`request-lenient-headers` and therefore deferred by
[0009](decisions/0009-v01-is-strict-request-and-response-parsing.md), and its
in-scope twin ("Line folding in header value with LF") never reaches a fold at
all -- it uses bare LF line endings and errors at the first one with
`code=25 "Missing expected CR after header value"`.

**`headers complete` is an EVENT here, not a trace line.** That line carries
`method=`, `v=`, `flags=` and `content_length=`; the last two are M4's. Every
fixture that reaches it is in M4's bucket or later, so M3 builds the event and
M4 makes the line renderable. No fixture M3 claims prints one.

**Reachable ceiling**: **+29** request fixtures, and **44 cumulative** -- not
the 46 first written here, which assumed M2 would take all 17 of the fixtures
whose trace ends inside the start line. It took 9. Re-measured over the 124
in-scope request fixtures:

| | |
|---|---|
| 46 | end before `headers complete` -- M3's territory |
| 10 | reach `headers complete` and stop there -- M4 |
| 68 | need body, chunk or `message complete` -- M4 and later |

Of the 46: 17 end inside the start line (9 passing, 6 blocked on the header
section, 1 on the url sub-parser, 1 on pausing) and 29 error inside the header
section.

> **This was first written as 44 cumulative, and the achieved ceiling is 29.**
> Measured after M3 Slice ⓪ by running every remaining fixture and reading its
> first mismatch, not by re-counting. Of the 17 that remain in the bucket,
> **every one needs a capability M3 excludes**:
>
> | | |
> |---|---|
> | 13 | M4 — eleven need `Content-Length` / `Transfer-Encoding` semantics, and two (`connection.md#16`, `content-length.md#6`) need the special-header NAME table, whose `header_field_colon` path consumes a space before the colon and reports `Invalid header field char` where the general path reports `Invalid header token` one byte earlier |
> | 2 | deferred by [0009](decisions/0009-v01-is-strict-request-and-response-parsing.md) — `method.md#15` (pausing) and `uri.md#7` (the url sub-parser) |
> | 2 | `finish.md#2` and `#3` — they need the parser's own finish-safety state, which llhttp prints as `off=NULL finish=N` (0 safe, 1 safe-with-callback, 2 unsafe; it is the state field, not a return code). Message lifecycle, so M6 |
>
> **The methodology, not the arithmetic, was the error.** The ceilings table
> buckets a fixture by the deepest EVENT in its trace, and an event does not
> say which parser capability the error needs. `Content-Length: 1000...0`
> errors inside the header section and looks like M3's, but its value span is
> bounded by the overflow check — 21 of its 22 digits — so only the
> accumulator can produce it. Every future ceiling is a bucket count until the
> slice runs, and the ratchet is the measurement.

### M4 — framing, and the decision core

`Content-Length` accumulation (uint64, checked overflow →
`invalid-content-length`), `Transfer-Encoding`, `Connection` → the FLAGS
bitfield; `after_headers_complete` as a pure decision callback; the fixed-length
body via counted consumption.

**The case-insensitivity gap did not block, and the trie never shipped.** Gate 0
planned a hand-built downstream trie for the four header names, the `Connection`
values and `chunked` — 91 nodes across the three — because
`make-sequence-case` takes exact bytes. The upstream `keyword-table` primitive
landed at `v0.3.0` instead, from this project's second brief, and all three are
one case-folded table each. Gate 0's constraint on the design was right and is
still visible: a case-insensitive `make-sequence-case` would inherit
`ambiguous-sequence-prefix`, and `close` / `closed` is exactly the pair the
`Connection` table disambiguates.

**Done, in four slices.** Ratchet **29 → 87 passing**, 103 not-yet, 84 deferred.

| | |
|---|---|
| ⓪ | the four numbers on the `headers complete` line, and `message complete` (+27) |
| ① | the special-header name table, `Content-Length`, and the fixed-length body (+17) |
| ② | `Transfer-Encoding`, `Connection`, `Upgrade`, and the FLAGS bitfield (+11) |
| ③ | the upgrade decision, the HTTP/2 preface, and a leading CRLF (+3) |

**Measured after the fact, by running every remaining fixture and reading its
first mismatch** — not by bucketing. All 37 request fixtures still `not-yet`
need something M4 excludes: 17 chunked bodies (M5), 6 the message loop and 3
the finish state (M6), 2 the url sub-parser (M11), and **9 are blocked
upstream** — a byte-machine pause carries no code and no reason, so
`error code=22 reason="Pause on CONNECT/Upgrade"` cannot be rendered without
inventing both halves. Briefed as
[the pause-reason brief](2026-09-14-upstream-pause-reason-brief.md) under
[0006](decisions/0006-upstream-first-for-general-gaps.md); it is the third such
brief and the first two both shipped.

The remaining 66 are responses, which is M7. **M4 has no request fixture left
that framing alone can reach.**

The decision core found a bug no fixture could: `CONNECT` with a
`Content-Length` read a body llhttp never reads, because `upgrade` is set
before the headers-complete callback and the body decision exits early. The
fixture that records it is one of the nine the pause gap blocks.

### M5 — chunked bodies

`chunk header len=`, `chunk complete`, `chunk_extension_name` /
`chunk_extension_value` spans, trailers, the zero chunk, `invalid-chunk-size`.

**Done, in two slices.** Ratchet **96 → 113 passing**, 77 not-yet, 84
deferred — all seventeen chunked fixtures, which is every one the measurement
at M4's close named.

| | |
|---|---|
| ⓪ | the chunk reader, the zero chunk and trailers (+13) |
| ① | chunk extensions: names, values, quoted values (+4) |

**The chunk reader added no field and no span.** llhttp accumulates the size
into `content_length` and prints that field from `on_chunk_header`, so the
size shares the field a fixed-length body counts down, the data shares
`span[body]`, and the zero chunk shares `header_field_start` — trailers are
the header section again, told apart by a flag. The whole of the trailer
support is one field-branch and one callback node.

**Six of llhttp's eight chunk-extension reasons are unrecorded in the
corpus.** The mutation pass found it by surviving in every lane, and a search
of all 274 fixtures confirms it: only `Invalid character in chunk extensions`
and `... quoted value` appear. What stands behind the other six is the
llparse IDIOM rather than the arm — `skipTo` past the byte, `.otherwise` at
it, a bare-LF peek at it, a `.match` past it — and each idiom is measured
somewhere the corpus can see. The corpus-load lane pins the count at two, so a
refresh that brings a fixture for any of the six goes red.

The `span-active-at-pause` rule cost one reorder: llhttp opens the extension
value's span and THEN fires the name's complete event, and a callback
reachable with a span open is refused. Both steps are zero-width and land on
the same byte, so the trace cannot tell — and the order here is the one that
stays right if the callback ever pauses.

**M5 has no request fixture left that chunked bodies alone can reach.** The
eleven remaining are M6 (nine) and M11 (two), exactly as measured at M4's
close.

### M6 — the message loop

`should_keep_alive`, `message_needs_eof`, the finish states and
`off=NULL finish=N`, `reset`, pipelining, EOF semantics.

**Exit**: all 124 strict request fixtures pass. **This is a usable request
parser**; the server layer can begin against it here rather than at the release.

**Done, in three slices.** Ratchet **113 → 124 passing**, 66 not-yet, 84
deferred. **The exit criterion is met**: every strict request fixture in
llhttp's corpus passes, and everything left is a response or deferred.

| | |
|---|---|
| ⓪ | the loop: keep-alive, reset, pipelining, `closed` (+6) |
| ① | `off=NULL finish=N` is a field, not an ending (+3) |
| ② | the request target's two ends (+2) |

**`after_message_complete` reads its answer before it clears the state.**
llhttp's C callback computes `should_keep_alive`, sets `finish`, clears the
flags and returns the answer — in that order, and the order is load-bearing.
The flags reset is measured by exactly one fixture, `request/pipelining.md#1`,
because the duplicate-`Content-Length` test is `flags & CONTENT_LENGTH`.

**A `*-finish` fixture prints a field, it does not end a parse**
([0016](decisions/0016-a-finish-fixture-prints-a-field-not-an-ending.md)). The
driver had modelled it as an ending since M1; llhttp's hook is one line and
prints `s->finish`. Two of the three finish fixtures were already byte-exact
without their last line.

**The last two request fixtures were measured at M4's close as M11's**, and
they turned out to need the target's BOUNDARY rather than its structure —
eight nodes. So the exit criterion was met rather than amended, and M11 keeps
`url.md`'s 21 fixtures and the schema/server/query/fragment machinery. That
the measurement pointed at the right milestone and the wrong SIZE is the same
lesson the ceilings table below teaches: a grouping orders work, it does not
scope it.

### M7 — responses

The status line, `status` span, `status complete`, and the response branch of
the framing table (1xx / 204 / 304, `message_needs_eof` for responses).

**Exit**: all 66 strict response fixtures pass — 190 cumulative, which is
[0009](decisions/0009-v01-is-strict-request-and-response-parsing.md)'s v0.1 bar.

**Done, in two slices.** Ratchet **124 → 190 passing, 0 not-yet**, 84
deferred. **The exit criterion is met exactly**: every strict fixture in
llhttp's corpus passes and everything left is deferred with a reason.

| | |
|---|---|
| ⓪ | the type switch and the status line (+43) |
| ① | the response framing table (+23) |

**This section said "HEAD skip-body" and should not have.** `skipBody` is one
of [0009](decisions/0009-v01-is-strict-request-and-response-parsing.md)'s own
deferrals — two fixtures, one request and one response — and the ratchet has
carried them as `deferred skip-body` since M1. The plan's parenthetical was
wrong and the ratchet was right, which is what item 4 of that decision means
by "the ratchet is the exit criterion, not a judgement call".

**A parser cannot be started in a mode**
([0017](decisions/0017-the-message-kind-is-a-decision-callback-not-a-field-the-embedder-writes.md)).
llhttp reads the kind from a field its embedder wrote; byte-machine's runtime
has no field writer and a field's initial belongs to the MACHINE, so the same
configuration arrives as a `decision` callback whose branches store llhttp's
own number. Three nodes, against a doubled artifact for the alternative. The
gap is general and is filed upstream as this consumer's fourth brief; nothing
waited on it.

**Two subgraphs are now shared where llhttp writes them twice** — the protocol
constants and the version pair — each with a zero-width branch on `type` where
llhttp forks. What a response does NOT share is its first line and its body
decision.

**THREE MUTATIONS SURVIVED EVERY LANE, AND ALL THREE ARE ONE FINDING.** llhttp
asks two overlapping questions about a response: the body decision names 100,
102, 103, 204 and 304 exactly, and `message_needs_eof` names 1xx, 204 and 304
again. On a message with no framing header the two agree, so either alone
produces the right trace. They part only when such a status arrives WITH a
`Content-Length` or a `Transfer-Encoding`, and the corpus records that for 304
alone — which is why the 304 mutation was caught and the 204 one was not. The
corpus-load lane now pins which of the five the oracle separates, as M5's pins
which chunk-extension reasons it records.

### M8 — release — DONE

The live llhttp differential as a local opt-in lane
([0010](decisions/0010-the-live-llhttp-oracle-is-local-and-opt-in.md)), property
and fuzz work over generated and fragmented input, allocation audit, benchmark
baseline, the reference documentation set, and v0.1.

**The lane found three defects in a parser that passes 190 of 190.** The
first byte's validation happened before `message begin`; repeated spaces
before the target produced an empty span; and the two RTSP methods were
spelled with hyphens where llhttp's map uses underscores. None is visible to
any fixture in the corpus, which is decision 0010's whole argument, cashed.
Two divergences remain and are named, witnessed and published
([0018](decisions/0018-a-divergence-is-named-and-witnessed-or-it-fails-the-lane.md)):
the deferred URL sub-parser, and a completion event at the exact end of the
input, in both directions. The upstream half of the second is the fifth
brief.

**Fragmentation invariance is true only for a parse that reaches no error**,
measured at 71 of 71 against 13 of 169, and llhttp shares the exception
exactly. The unqualified property would have been a false one and the corpus
could not have said so.

### Deferred past v0.1, in order

**M9** pausing and upgrade (24 + 2 fixtures) · **M10** lenient modes (37) ·
**M11** the URL sub-parser (21). All are vendored and ratcheted from M1, so each
deferral is a visible count rather than an absence.

## Reachable ceilings, measured

How far each strict fixture's expected trace reaches. **This is an ordering,
not a count, and three milestones have now proved it.**

It buckets a fixture by the deepest EVENT in its trace, because that is the
attribute a fixture wears on its face. What a milestone needs to know is which
CAPABILITY the fixture's failure requires, and grouping on one attribute says
nothing reliable about the other — so the table over-counts some rows and
under-counts others, and no care with the arithmetic fixes that.

| | predicted | measured |
|---|---|---|
| M2 | 17 | 9 |
| M3 | 44 cumulative | 29 |
| M4 | +15 and a share of 63 | 87 cumulative, +58 |
| M5 | — | 113 cumulative, +17 |
| M6 | — | 124 cumulative, +11 |
| M7 | 66 | 190 cumulative, +66 |

M2 and M3 both fell short; M4 overshot, because the header-section row's
fixtures mostly needed framing and the `message complete` row's mostly did not
need chunks. **M5 hit its number exactly, and that is the table's own point
rather than a counter-example**: its seventeen were not read off this table at
all, but measured at M4's close by running every remaining fixture and reading
its first mismatch. A count taken that way is a prediction; a count read off a
grouping is an ordering. `Content-Length: 1000000000000000000000` is the case that shows
the mechanism: it errors inside the header section and buckets there, but
llhttp's value span is 21 of its 22 digits — bounded by where the accumulator
overflows — so only the framing milestone could ever produce it.

**M7 is the one row the table got exactly right, and it proves nothing.** Its
66 are simply every response fixture in scope: the grouping and the capability
coincide because the milestone's boundary IS the request/response split, not
because bucketing on the deepest event predicted anything. Read at M6's close
the measurement was degenerate — all 66 failed at line 1, on the first byte,
because there was no response parser — so the only honest prediction available
was the partition itself.

Read the table as a rough order of work. **The ratchet is the measurement**,
and the honest way to state a ceiling is to run every remaining fixture and
read its first mismatch, which is what each milestone's section now records.

| trace reaches | request | response |
|---|---|---|
| start line only | 17 | 16 |
| header section | 29 | 3 |
| `headers complete` | 15 | 24 |
| `message complete` | 63 | 23 |
| **total** | **124** | **66** |

## Out of scope for this plan

- The server/connection layer, `libuv`, response serialisation, limits and
  timeouts — architecture document §5, §7, §8, §11, above the parser.
- Request-target decomposition. `span[url.schema|host|path|query|fragment]`
  appears **only** in `url.md`; `test/request/uri.md` is request-target syntax
  against one opaque `span[url]` and belongs to the request milestones.
- Any edit to vendored fixtures
  ([0007](decisions/0007-llhttp-corpus-vendored-as-data.md) item 6).

## Standing risks

- **The upstream round trip — retired as a risk for M4 by measurement.** The
  trie workaround verifies, compiles and behaves, so no milestone in this plan
  waits on a byte-machine release. What remains is the ordinary risk that the
  trie generator has a bug the verifier cannot catch, which is why it is tested
  here as a pure function from keyword list to node list.
- **Full-scan wall time.** 21,630 runs are dominated by per-run setup and trace
  formatting, not by the 7.28M bytes. Re-measure once the lane exists; the
  `pr`/`release` split exists to absorb it.
- **Unseen-input divergence is uncovered until M8.** Accepted and bounded — see
  [0010](decisions/0010-the-live-llhttp-oracle-is-local-and-opt-in.md).
