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

- 253 HTTP fixtures in 23 files, 288K; 22,598 input bytes total; median fixture
  63 bytes, longest 2,042.
- Each fixture is `input → exact byte-offset event trace`, ~20 distinct line
  shapes over 4,754 expected lines.
- Upstream replays each fixture at **every chunk size from 1 to its length**, so
  resumability across arbitrary input boundaries is the corpus, not an extra
  suite. Full scan is 21,326 parser runs; whole-buffer-only is 253.

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
`pr`/`release` chunk-size split. Wire the byte-machine submodule at the
[0005](decisions/0005-byte-machine-pinned-by-gitlink-generated-abi-5.md) pin and
assert ABI 5 as a check in the tree.

**Exit**: all 274 fixtures (253 HTTP + 21 URL) load and decode; the ratchet
lists them all with a status; the comparator is mutation-witnessed — a
deliberately corrupted trace must fail it. No HTTP parsing in this milestone.

### M2 — the request line

`message begin`; `method`, `url`, `protocol`, `version` spans and their
`complete` events; the strict CRLF rule; `invalid-method`, `invalid-version`,
`invalid-url`, `invalid-constant`.

**Reachable ceiling**: the 17 strict request fixtures whose expected trace ends
in the start line.

### M3 — the header section, as syntax

`header_field` / `header_value` spans, OWS handling, obs-fold, strict line
endings, the empty line, `headers complete` with no framing interpretation yet.
Field names stay **opaque spans** here, which is what keeps M3 clear of the
case-insensitivity gap.

**Reachable ceiling**: +29 request fixtures (46 cumulative).

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

How far each strict fixture's expected trace reaches — the upper bound on what
each milestone can claim, not a prediction of exact counts, since a
message-complete fixture may need chunked (M5) rather than only framing (M4):

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
- **Full-scan wall time.** 21,326 runs are dominated by per-run setup and trace
  formatting, not by the 7.2M bytes. Re-measure once the lane exists; the
  `pr`/`release` split exists to absorb it.
- **Unseen-input divergence is uncovered until M8.** Accepted and bounded — see
  [0010](decisions/0010-the-live-llhttp-oracle-is-local-and-opt-in.md).
