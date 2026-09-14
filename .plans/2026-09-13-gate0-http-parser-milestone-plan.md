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

**This is where the case-insensitivity gap surfaces** — the first point a header
*name* drives a decision rather than a span — **and it does not block.** Gate 0
built and measured the downstream trie workaround through the generated lane:
52 nodes for the four header names, 28 for the `Connection` values, 11 for
`chunked`; all verify and compile on the public v0.1 API, and all behave
correctly across case and at the `Connection-Foo:` / `conten:` boundaries. M4
ships with that trie. The byte-machine primitive is scheduled *after* M4, per
[0006](decisions/0006-upstream-first-for-general-gaps.md), when the grammar can
specify it — and Gate 0 already found one constraint on its design: a
case-insensitive `make-sequence-case` would inherit `ambiguous-sequence-prefix`
and so reject the `close` / `closed` pair the trie handles today.

**Reachable ceiling**: +15 fixtures that stop at `headers complete`, plus the
fixed-body share of the 63 that reach `message complete`.

### M5 — chunked bodies

`chunk header len=`, `chunk complete`, `chunk_extension_name` /
`chunk_extension_value` spans, trailers, the zero chunk, `invalid-chunk-size`.

### M6 — the message loop

`should_keep_alive`, `message_needs_eof`, the finish states and
`off=NULL finish=N`, `reset`, pipelining, EOF semantics.

**Exit**: all 124 strict request fixtures pass. **This is a usable request
parser**; the server layer can begin against it here rather than at the release.

### M7 — responses

The status line, `status` span, `status complete`, and the response branch of
the framing table (1xx / 204 / 304, HEAD skip-body, `message_needs_eof` for
responses).

**Exit**: all 66 strict response fixtures pass — 190 cumulative, which is
[0009](decisions/0009-v01-is-strict-request-and-response-parsing.md)'s v0.1 bar.

### M8 — release

The live llhttp differential as a local opt-in lane
([0010](decisions/0010-the-live-llhttp-oracle-is-local-and-opt-in.md)), property
and fuzz work over generated and fragmented input, allocation audit, benchmark
baseline, the reference documentation set, and v0.1.

### Deferred past v0.1, in order

**M9** pausing and upgrade (24 + 2 fixtures) · **M10** lenient modes (37) ·
**M11** the URL sub-parser (21). All are vendored and ratcheted from M1, so each
deferral is a visible count rather than an absence.

## Reachable ceilings, measured

How far each strict fixture's expected trace reaches — an upper bound on what
each milestone can claim, not a prediction of exact counts. It buckets by the
deepest event in a trace, which **over-counts every row**: a fixture that dies
on the first byte of the next section lands in the previous section's row. M2
measured this and found its own row of 17 contains only ~10 it can reach. Read
the table as an ordering, and let the ratchet supply the numbers.

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
