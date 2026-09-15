# Changelog

All notable changes to chez-httparse are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
uses [semantic versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Gate 0 and Slice 1: project bootstrap, then the milestone ladder in
[.plans/2026-09-13-gate0-http-parser-milestone-plan.md](.plans/2026-09-13-gate0-http-parser-milestone-plan.md).
The governing architecture is
[.plans/chez-http-server-architecture.md](.plans/chez-http-server-architecture.md);
the bootstrap slice design is
[.plans/2026-08-28-gate0-slice1-harness-port-design.md](.plans/2026-08-28-gate0-slice1-harness-port-design.md).

### Added

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

### Removed

### Fixed
