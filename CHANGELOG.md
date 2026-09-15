# Changelog

All notable changes to chez-httparse are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
uses [semantic versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Nothing yet.

## [0.1.0] - 2026-09-15

**Strict-mode HTTP/1.x request and response parsing**, byte-exact against
llhttp's own recorded traces for 190 of the 253 HTTP fixtures in its
conformance corpus, replayed at every chunk size from 1 to the input length.
The remaining 63 and the 21 URL fixtures are enumerated, vendored and
ratcheted rather than omitted — see
[docs/conformance.org](docs/conformance.org) and decision
[0009](.plans/decisions/0009-v01-is-strict-request-and-response-parsing.md).

Gate 0 and Slice 1: project bootstrap, then the milestone ladder in
[.plans/2026-09-13-gate0-http-parser-milestone-plan.md](.plans/2026-09-13-gate0-http-parser-milestone-plan.md).
The governing architecture is
[.plans/chez-http-server-architecture.md](.plans/chez-http-server-architecture.md);
the bootstrap slice design is
[.plans/2026-08-28-gate0-slice1-harness-port-design.md](.plans/2026-08-28-gate0-slice1-harness-port-design.md).

### Added

- **The live llhttp differential**, local and opt-in
  ([0010](.plans/decisions/0010-the-live-llhttp-oracle-is-local-and-opt-in.md)):
  `HTTPARSE_LLHTTP_ROOT` points at a built llhttp checkout and the lane
  builds its oracle with llhttp's OWN test harness — the program that
  produced the vendored corpus — rather than a driver of ours printing the
  same shape. Absent, not failing, when the variable is unset. Generated
  input comes from a seeded in-tree generator (assembled messages and
  mutants of corpus fixtures); the oracle's printed lines are read back into
  events by `(httparse test oracle)`, whose calibration is all 253 recorded
  blocks round-tripping unchanged and which needs no llhttp.
- **A divergence is named and witnessed or it fails the lane**
  ([0018](.plans/decisions/0018-a-divergence-is-named-and-witnessed-or-it-fails-the-lane.md)).
  Two classes remain for v0.1 and both are published with the reduced input
  and both traces: the deferred URL sub-parser, and a completion event at
  the exact end of the input, in both directions.
- **Property lanes over generated input**, needing no llhttp: no generated
  input reaches an outcome the adapter cannot name; the committed artifact
  and the reference interpreter agree where nothing recorded the answer; and
  fragmentation invariance **for a parse that reaches no error** — the
  qualifier measured, not assumed.
- **An allocation audit** asserting a shape rather than a number: a body a
  thousand times longer costs 6,548 B against 6,496 B, and a feed costs
  384 B against 398 B whatever came before it.
- **A throughput baseline**, printed rather than gated, under a new
  `benchmark` test layer the pull-request preset does not select.
- **The reference documentation set**: [docs/api.org](docs/api.org),
  [docs/conformance.org](docs/conformance.org),
  [docs/performance.org](docs/performance.org), and a rewritten README. The
  README's example is an `example` lane that runs in CI, so it cannot drift.
- The fifth upstream brief, for a keyword table that waits one byte past a
  decided match
  ([.plans/2026-09-15-upstream-keyword-terminal-brief.md](.plans/2026-09-15-upstream-keyword-terminal-brief.md)).


- Gate 0 decision records: project naming and the mechanical rename map
  ([0001](.plans/decisions/0001-project-name-and-rename-map.md)), how
  byte-machine is consumed and the generated-ABI v2 target
  ([0002](.plans/decisions/0002-byte-machine-consumption-and-abi.md)), and
  Slice 1 scope with its five exit criteria
  ([0003](.plans/decisions/0003-slice-1-scope-and-exit-criteria.md)).
- The test harness and build layer, ported from
  [byte-machine](https://github.com/Kiyomi-Computation-Systems/byte-machine)
  under decision 0001's rename map: the CMake build (presets `dev`/`prod`/
  `no-scheme`, Makefile entry points, JUnit-emitting test presets with
  empty-selection-is-failure), Chez discovery with a 10.4.1 floor, the
  test registrar and its name grammar `httparse.<layer>.<feature>.<backend>.<mode>`,
  exact-exit-status assertions, source and AOT Scheme lanes with content-
  fingerprint provenance, the R6RS test harness `(httparse test harness)` /
  `(httparse test fingerprint)` / `(httparse test prng)` with six self-test
  programs, four launchers, and the mutation engine. Attribution: the harness
  is a one-time copy; it does not track the upstream tree.
- The two mutation suites, re-measured on this tree: the CMake-layer manifest
  at 1 pass / 73 mutations and the Scheme manifest at 28 passes /
  59 mutations (upstream passes that mutated product sources did not port —
  this repository has none yet).
- A rename-audit specification (`httparse.harness.rename-audit.cmake.direct`)
  enforcing decision 0003's exit criterion 5 — zero upstream-name references
  in the build/test tree — witnessed by its own mutation. Its first clean-tree
  run caught a real rename miss.
- This repository's own fingerprint sample fixture (`chez-httparse\n`,
  fingerprint `1f2902297117b4a3` measured under Chez 10.4.1 threaded
  tarm64osx, 2026-08-28, and cross-checked against an independent
  reimplementation) and a regenerated stale-root provenance fixture.
- CI: the Linux amd64 cell (Chez 10.4.1 built from source, cached across
  runs under `~/.local/chez` and keyed on the pinned version), closing with
  the no-scheme lane. macOS arm64 is verified locally on the maintainer's
  laptop rather than on a hosted runner.
- Decision record
  ([0004](.plans/decisions/0004-ci-covers-the-linux-cell-alone.md)) amending
  [0003](.plans/decisions/0003-slice-1-scope-and-exit-criteria.md)'s criterion
  4: from this date, a slice closes on the Linux cell green in CI plus a
  recorded local macOS run, not on two CI cells.

### Changed

- **The generated parser is named for what it parses.** It was
  `request-line` from M2, when that is all it read, and it has since grown
  the header section, framing, chunked bodies, the message loop and both
  response productions — so the shipped artifact is now
  `src/generated/httparse-message.sls`, the library `(generated
  httparse-message)` exporting `httparse-message-machine`, emitted by
  `tools/emit-message.ss` from `(httparse grammar)`'s `make-message-machine`.
  The conformance lanes follow: `httparse.conformance.message.chez.source`
  and `httparse.conformance.message-full-scan.chez.source`. Nothing else
  moved — the re-emitted artifact is byte-identical to its predecessor once
  the name is substituted, and ABI stays at 7. **`request-line` survives
  where it is still true**: `test/common/request-line-tests.sps` and
  `httparse.unit.request-line.chez.*` really are about the request line.
- **The byte-machine pin moved from `v0.1.0` to `v0.2.0`**
  (`c38e76f` to `19e2c05`), so that an empty span is observable. A span that
  opens and closes having delivered no bytes now invokes its data callback
  exactly once with an empty range, which is what
  [request/uri.md#11](test/vendor/llhttp/request/uri.md) records for
  `GET /foo bar/ HTTP/1.1`: `off=9 len=0 span[protocol]=""` between
  `url complete` and the error. Before the bump that line was simply absent
  from our trace, and a consumer could not tell "present and empty" from
  "never opened". The gap was found by Milestone 2 Slice 1, recorded under
  [0006](.plans/decisions/0006-upstream-first-for-general-gaps.md), and
  briefed upstream in
  [.plans/2026-09-13-upstream-empty-span-brief.md](.plans/2026-09-13-upstream-empty-span-brief.md);
  this bump is the ritual
  [0005](.plans/decisions/0005-byte-machine-pinned-by-gitlink-generated-abi-5.md)
  item 3 describes, and its first exercise.

  Measured across the bump here rather than taken from the upstream release
  note:

  - The generated ABI is still **5**, read out of emitted text by
    `httparse.unit.generator-abi.chez.source`.
  - The emitted request-line parser is **byte-identical at both pins**
    (120,218 bytes, same SHA-256), so no generated golden moves and the
    checked-in derived artifact a later slice adds is unaffected.
  - Nine upstream sources differ textually between the two tags, but eight of
    them have **byte-identical reader-level datum streams** -- they differ only
    in comments, from an unrelated documentation sweep. The only code change in
    the range is `runtime.sls`.
  - The harness content fingerprints for every byte-machine source moved, as
    they do for any pin change, and were regenerated by the build.

- **The byte-machine pin moved from `v0.2.0` to `v0.3.0`** (`19e2c05` to
  `9c027fd`), **the generated ABI target moved 5 to 6**, and the 47-name method
  table became **one `keyword-table` node** instead of a 242-node hand-built
  trie. byte-machine's Milestone 11 added the node kind, opened from this
  project's second upstream brief
  ([.plans/2026-09-13-upstream-keyword-trie-brief.md](.plans/2026-09-13-upstream-keyword-trie-brief.md))
  under [0006](.plans/decisions/0006-upstream-first-for-general-gaps.md); with
  the empty-span change at `v0.2.0`, **both briefs are now discharged**. The ABI
  move is recorded in
  [0012](.plans/decisions/0012-generated-abi-6-and-keyword-tables.md), amending
  [0005](.plans/decisions/0005-byte-machine-pinned-by-gitlink-generated-abi-5.md)
  item 2.

  The swap replaces one node and is measured, not estimated:

  | | emitted bytes | states |
  |---|---|---|
  | 242-node hand trie | 120,218 | 281 |
  | one `keyword-table` | 26,323 | 40 |

  **Behaviour did not move.** The request-line lane's 30 cases and 40 checks pass
  unchanged across the swap — `MKCOLA` closing its span at `MKCOL`, all 47 names
  round-tripping, `GET` against `GET-PARAMETER` both ways, the empty protocol
  span, and byte-at-a-time feeding. The no-match cases gained offset and
  no-fragment assertions, since the walk's failure point is now a property of the
  table rather than of hand-wired fallbacks: `FOO` fails at 1, `MKCO` at 4, and
  neither delivers a method fragment.

  Before the swap, at the same new pin, this project's machine emitted
  **byte-identically to `v0.2.0` but for the ABI literal** — one line, one
  character, same 120,218 bytes and same IR fingerprint. Upstream claims that for
  any machine declaring no keyword table; it was checked here.

- **The request line now checks the protocol constants, the method against the
  protocol, and the version as a pair** (M2 Slice 3). `HTTP` / `RTSP` / `ICE` are
  a keyword table, so a partial match closes the protocol span over exactly the
  bytes the walk took (`HTP` gives `span[protocol]="HT"`) and `protocol complete`
  fires only on a full match. The method is remembered across the url in a
  one-byte bitmask field and tested at the protocol constant with `mask-any`,
  which is where llhttp reports its four distinct reasons under error code 8.
  The version is `<digit> "." <digit>` restricted to 0.9, 1.0, 1.1 and 2.0.

  The A-Z loop this replaced accepted `HTTX/1.1` outright, and the
  digits-and-dot loop accepted `1.1.1`.

- **Error identity is llhttp's `(code, reason)` pair**
  ([0013](.plans/decisions/0013-error-identity-is-llhttps-code-and-reason-pair.md)),
  refining [0008](.plans/decisions/0008-bit-exact-trace-conformance-and-the-ratchet.md)
  items 2 and 3. One code symbol per llhttp error number, llhttp's reason text
  verbatim, and both halves checked. Over the corpus there are 42 distinct
  `(code, reason)` pairs across 17 codes and 41 reasons, eight codes carry more
  than one reason, and one reason — `"Expected CRLF after version"` — appears
  under **two** codes, both of them in the request line. The single
  `invalid-line-ending` code that stood here could render neither, and is
  retired.

- **The conformance driver runs, and the ratchet moves for the first time**
  (M2 Slice 4). Nine vendored fixtures go from `not-yet` to `passing`, compared
  bit-exactly against their own recorded traces at every chunk size the
  selection replays: the four method-versus-protocol rejections, `MKCOLA`,
  `HTTP/5.6`, both line-ending failures, and the empty protocol span of
  `request/uri.md#11`. Ratchet: **9 passing / 181 not-yet / 84 deferred**.

  Two lanes register it — `extremes` (chunk size 1 and the whole buffer) on
  every pull request and `full` (every size) on release, per
  [0008](.plans/decisions/0008-bit-exact-trace-conformance-and-the-ratchet.md)
  item 5. The driver calls `parser-finish!` only for the `*-finish` fixture
  types, which is what llhttp's own harness does.

- **Fixed: a bare LF after the version reported its error one byte early.** The
  driver found it on its first run. `request/invalid.md#21` records the error at
  one past the LF, because llhttp matches the LF into a lenient test that strict
  mode refuses and a match consumes, while an unrelated byte is not consumed —
  so the two line-ending failures land one byte apart. The test that had
  asserted the old offset took that number from this parser rather than from a
  fixture.

- **Fixed: a compiled lane could not find the generator's objects.** The
  ahead-of-time run command named an `--object-dir` for the harness and source
  roots but not for the generator, and the compile step never created that
  directory. No AOT lane had imported a generator library before the
  request-line and adapter twins added here, so nothing had exercised it; it
  failed as an unbound library rather than a missing directory.

- **The parser ships as a checked-in derived artifact.**
  `src/generated/httparse-request-line.sls` is emitted from the grammar by
  `tools/emit-request-line.ss` and committed, so what this project ships is
  reviewable as a diff and loadable without a generator — it imports
  `(byte-machine runtime)` and nothing above it. `make parser-refresh` and the
  determinism lane run the same script, so a grammar edit without a refresh
  reddens rather than shipping a stale artifact.

  **The conformance gate runs the committed artifact itself**, with the
  reference interpreter built beside it from the same grammar and compared over
  every gated fixture. Hand-editing the artifact is caught three ways: the
  byte-for-byte re-emit, the ratchet's regression check, and the executor
  differential.

- **The header section parses, strictly** (M3 Slice 0), and the ratchet goes
  **9 to 29 passing** (161 not-yet, 84 deferred). Field and value spans, OWS
  discarded, the empty line, and `headers complete` as an event. Field names
  stay opaque: llhttp's special-header table, and the framing it feeds, is M4's.

  **obs-fold is rejected in both of its places**, with different offsets and
  different reasons — llhttp matches the whitespace after an empty value and
  peeks it after a non-empty one, so one errors past it and one at it.

  `headers complete` is deliberately **unrenderable**: its trace line carries
  two numbers M4 owns, so the adapter refuses rather than writing a line llhttp
  never emits, and a fixture reaching it fails honestly.

- **Message framing, and the body** (M4, four slices), taking the ratchet from
  **29 to 87 passing** (103 not-yet, 84 deferred).

  `headers complete` now renders. Its four numbers are read off the parser's
  own fields, the way llhttp's callback reads its own struct
  ([0014](.plans/decisions/0014-the-adapter-may-read-parser-fields.md)) — the
  adapter may READ parser state and still may not DERIVE it, and a field it was
  not given is a refusal rather than a zero.

  `Content-Length` accumulates into a checked uint64 and measures a body that
  arrives as `span[body]`; `Transfer-Encoding`, `Connection` and `Upgrade` set
  llhttp's FLAGS bits; and `after_headers_complete` is reproduced as a decision
  over those flags, the method and the length. A field NAME now selects which
  value machine runs, through a **case-folded keyword table** — the second of
  the two reasons this project asked for that primitive upstream.

  Several behaviours are exact in ways that are easy to get wrong, and each is
  a check: the overflowing digit of a `Content-Length` is **consumed** before
  the overflow is reported, so 22 digits give a span of 21; a space before the
  colon is a different error on a special name than on a general one, one byte
  apart and with a different reason; `close` is not `closed` and
  `chunkedchunked` is not `chunked`; a `Content-Length` of zero has **no body
  at all**, unlike an empty header value, which is an empty span; and `CONNECT`
  does not read the body its own `Content-Length` declares.

  **A pause cannot be rendered yet.** llhttp pauses with a code and a message
  and prints it as `error code=22 reason="Pause on CONNECT/Upgrade"`; a
  byte-machine pause carries neither, so the adapter refuses and nine fixtures
  wait. Recorded as
  [the third upstream brief](.plans/2026-09-14-upstream-pause-reason-brief.md)
  under [0006](.plans/decisions/0006-upstream-first-for-general-gaps.md). An
  error node would give a bit-identical trace and would be wrong — a paused
  parser is resumable — and no test in the corpus could tell.

- **byte-machine pinned at `v0.4.0`** (`9c027fd..18fcc8b`, two commits), and
  **the generated ABI moves 6 → 7**
  ([0015](.plans/decisions/0015-generated-abi-7-and-a-pause-carries-its-reason.md),
  amending [0012](.plans/decisions/0012-generated-abi-6-and-keyword-tables.md)
  item 1). The bump delivers this project's **third** upstream ask,
  [the pause-reason brief](.plans/2026-09-14-upstream-pause-reason-brief.md):
  a pause now carries its own `(code, reason)`, read through the new
  `parser-result-pause`.

  `parser-result-error` stays `#f` for a pause — upstream rejected folding the
  reason into the error slot, because a consumer that reads "has an error" as
  "failed" would mis-read a resumable pause. So `off=N error code=22
  reason="Pause on CONNECT/Upgrade"` is now a **rename** like every other row
  rather than a refusal, and **nine fixtures** move to passing: ratchet
  **87 → 96** (94 not-yet, 84 deferred).

  **That the pause is a pause is a check in the tree**, because no trace can
  show it: a parser that errored where llhttp pauses would match every fixture
  in the corpus byte for byte and would be unresumable. Three unit cases ask
  the parser directly instead.

  Measured across the pin with the grammar unchanged, the emitted parser is
  byte-identical but for the ABI literal — 144,172 bytes both sides, same IR
  fingerprint `12284084569705248381`. All three upstream briefs are now
  discharged.

- **Chunked bodies** (M5, two slices), taking the ratchet from **96 to 113
  passing** (77 not-yet, 84 deferred). All seventeen of the corpus's chunked
  request fixtures pass, and **no request fixture is left that chunks alone
  can reach**.

  A hex size, `chunk header len=`, the data as `span[body]`, `chunk complete`,
  and the whole extension grammar — names, values, quoted values with escapes,
  and their four spans and events. The size accumulates into
  `content-length`, the field a fixed-length body counts down, because llhttp
  reuses it and prints it; so the chunk reader shares the body span and the
  counted consume rather than adding either.

  **The zero chunk re-enters the header section.** Trailers are parsed by the
  same states a header block uses, and a flag the zero chunk sets is the only
  thing that tells the empty line at the end which block it just closed —
  `chunk complete` when it is a trailer, `headers complete` when it is not.

  Exact in ways easy to get wrong, each a check: a space after the size is
  matched into a lenient test strict mode refuses, so its error is one **past**
  the space, while the catch-all reports **at** the byte; a CR already
  consumed stays consumed when no LF follows; an extension span closes at its
  delimiter and its event fires past it, 88 and 99 rather than 88 and 98; and
  a quoted value's span **includes both quotes**, so it is two bytes longer
  than its text.

  **Six of llhttp's eight chunk-extension reasons are unrecorded in the
  corpus**, which the mutation pass found by surviving in every lane. They are
  translated from `src/llhttp/http.ts` and what stands behind each is an idiom
  the corpus measures elsewhere; the grammar names the idiom arm by arm, and
  the corpus-load lane pins the count at two so a refresh that brings evidence
  goes red rather than quiet. The chunk-size overflow shim is the same shape:
  no fixture in the corpus carries a chunk larger than 51.

- **The message loop** (M6, three slices), taking the ratchet from **113 to
  124 passing** (66 not-yet, 84 deferred). **Every strict request fixture in
  llhttp's corpus now passes** — the milestone's exit criterion, and the point
  at which a server layer can begin against this parser.

  `should_keep_alive` as a decision over the version and the flags, then
  `restart` or `closed`; `reset` between two messages on one connection;
  pipelining; and `off=NULL finish=N`.

  **The answer is read before the state is cleared.** llhttp's C callback
  computes `should_keep_alive`, sets `finish`, clears the flags and returns
  the answer, in that order — and the order is load-bearing, because the
  answer is read off the very flags it then clears. The flags reset is
  measured by exactly one fixture: `request/pipelining.md#1` carries a
  `Content-Length` on each of three messages, and the duplicate test is
  `flags & CONTENT_LENGTH`.

  **A `*-finish` fixture prints a field, it does not end a parse**
  ([0016](.plans/decisions/0016-a-finish-fixture-prints-a-field-not-an-ending.md),
  amending [0008](.plans/decisions/0008-bit-exact-trace-conformance-and-the-ratchet.md)
  item 5). llhttp's hook is one line and prints `s->finish`; it never calls
  `llhttp_finish`. The driver had modelled it as an ending since M1 and drove
  this parser to its end-of-input states, producing an `unexpected-eof` the
  oracle never records — which the adapter refused, correctly, for four
  milestones. The refusal was right and the model behind it was not.

  **The request target gained its two ends**, which the last two request
  fixtures needed: a byte no target may carry is an error with the span
  **still open**, so no `span[url]` fragment is delivered; and a target
  followed by CRLF is **HTTP/0.9** — no protocol span, no version span, and
  `v=0/9` on the headers line. This is not the url sub-parser: the schema, the
  server, the query and the fragment are still M11's, with `url.md`'s 21
  fixtures still deferred. `bad-url`'s placeholder reason, which no fixture
  ever recorded, is replaced by llhttp's own two for that position.

### Removed

### Fixed

- **`message begin` was withheld when the first byte was one no method may
  start with.** The start node validated before the event fired; llhttp
  validates after. `@ET / HTTP/1.1` printed the error alone.
- **Repeated spaces between the method and the target produced an empty
  target span.** llhttp requires one space and skips the rest, in two nodes;
  so does the grammar now, before the target and again before the protocol.
  `PUT   /url HTTP/1.1` records the target at 6.
- **The two RTSP methods were misspelled.** llhttp's map keys them
  `GET_PARAMETER` and `SET_PARAMETER`, with underscores, as RFC 2326 spells
  them; only `'M-SEARCH'` is quoted and hyphenated. The table carried hyphens
  for six milestones, and no fixture in the corpus uses either method.

All three were found by the live differential and none is visible to the
253-fixture corpus. Each is now pinned by an offline check.
