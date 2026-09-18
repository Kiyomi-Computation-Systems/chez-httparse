# Changelog

All notable changes to chez-httparse are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
uses [semantic versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- **The pin moves to `df16902`, the parser gets 2.6x faster again, and the
  generated ABI becomes 9**
  ([0005](.plans/decisions/0005-byte-machine-pinned-by-gitlink-generated-abi-5.md)
  item 3). Upstream range `69276b5..df16902`, four commits: PRs #134 and #135
  and their close-outs. Three more dispatches, all the same defect one level
  further out each time.

  - **A byte class is a range** (upstream 0050). The inner `(case b ...)`
    rendered one arm per byte of a character class; Chez scans those linearly
    at 21.60 ns for a lowercase letter against 1.25 for a range test. The
    grouped datum list the emitter's own comment had proposed as the deferred
    optimization turns out to be *worse* than what it would have replaced.
  - **A goto target comes from a known set** (upstream 0051). The three arms
    that call application code answered a callback's `goto` through the one
    linear dispatch still standing -- four crossings per header, ~34 ns each
    -- although the target is always one of the literals the emitter wrote
    into that very call.
  - **A callback outcome is the object** (upstream 0052). The seam consed
    `(goto TARGET)` where it could answer the target: 128 bytes per header.

  **The generated ABI is 9** (0005 item 5, and the reason that clause exists).
  Upstream's 0052 changed what the callback seam answers, so an ABI-8 parser
  meeting an ABI-9 runtime would read every callback wrong -- and is refused
  at construction instead. Two expectations move from 8 to 9,
  `unit.generator-abi`'s and `determinism.generated-artifact`'s, both of which
  read the number out of the emitted text rather than remembering it. That is
  the whole cost of the bump here.

  **Both IR fingerprints are unchanged** -- `httparse-url-machine`
  `3216037711265608570`, `httparse-message-machine` `318434098601601619`. The
  emitter moved and the IR did not, for the third pin running. The sources
  **shrink**: 334,508 -> 193,819 bytes for the message parser and 65,806 ->
  33,239 for the url parser, paying back the 12% the state-dispatch pin cost.

  Throughput, source and compiled: a request **62,745 -> 168,421 msg/s**
  (18 -> 49 MB/s), a response **103,225 -> 191,044** (114 -> 212 MB/s), the
  request fed one byte at a time 19,753 -> 25,396. Whole-buffer allocation
  6,592 -> 6,112 B. Against llhttp on llhttp's own three bench inputs,
  **104x/89x/67x -> 27x/31x/20x**; they were 485x/365x/89x three days ago.

  Semantics unchanged where it counts: the live llhttp differential reports
  `agreed=9557 late-complete=4 early-complete=0 unclassified=0`, identical to
  the previous pin, and the 274-fixture conformance ratchet is bit-exact.

- **The byte-machine pin moves to `69276b5`, and the parser gets four times
  faster** ([0005](.plans/decisions/0005-byte-machine-pinned-by-gitlink-generated-abi-5.md)
  item 3; the bump exists to deliver
  [0027](.plans/decisions/0027-the-cost-is-dispatch-position-not-grammar.md)).
  Upstream range `bce3a6b..69276b5`, two commits: byte-machine's PR #133 and
  its close-out. That project's decisions 0048 and 0049 replace the emitted
  `(case st ...)` -- which Chez compiles as a linear scan -- with one procedure
  per state and direct tail calls between them.

  **The generated ABI is re-read at the pin and is still 8** (0005 item 5), so
  item 2 is unamended. **Both IR fingerprints are unchanged**, which is the
  point: `httparse-url-machine` is still `3216037711265608570` and
  `httparse-message-machine` still `318434098601601619`. The emitter moved and
  the IR did not, so the regenerated sources are a pure re-rendering of the
  same machines. They grow: 298,126 -> 334,508 bytes for the message parser
  (+12.2%) and 61,431 -> 65,806 for the url parser (+7.1%).

  Throughput, both execution modes, three runs each:

  | what | before | after |
  |---|---|---|
  | 308 B request, 8 headers, whole buffer | 14,925-15,037 msg/s | **60,377-64,000** |
  | 1,166 B response, 1 KB body, whole buffer | 28,169-28,571 | **103,225-106,666** |
  | the same request, one byte at a time | 8,000-8,695 | **18,823-19,753** |

  Against llhttp's own `bench` mode on its own inputs, the ratio falls from
  **485x to 104x** on a 703-byte request, **365x to 89x** on a chunked `POST`,
  and **89x to 67x** on a url. The spread between the three has largely
  collapsed, which is the confirmation that the position term is gone.

- **The benchmark calibrates its repetition count instead of carrying three
  literals.** Those literals were right for one parser on one machine: at the
  new pin the same counts measured 31 ms, 19 ms and 10 ms where they had
  measured 135, 70 and 23 -- the byte-at-a-time case landing exactly on the
  10 ms floor added a day earlier, one improvement from failing. Each case now
  doubles its repetitions until the region clears 50 ms and prints the count it
  arrived at, so two runs need not agree on repetitions. The floor still
  exists; what it catches now is calibration giving up rather than a literal
  gone stale.

### Added

- **Both cost lanes run in both execution modes.** `httparse.property.allocation`
  and `httparse.benchmark.throughput` were registered only as `.chez.source`;
  each now also runs as `.chez.aot`, and every figure prints its mode so one
  release log can be read.

  **They agree, and that is the finding.** These lanes were added expecting
  the compiled numbers to beat the source ones, on the assumption — never
  checked — that a lane named "source" interprets. Measured against Chez
  10.4.1 on 2026-09-17, a hot loop of 20,000,000 iterations: 27 ms under
  `--script` from source, 28 ms from a `compile-program` object, and 455 ms
  from that same source with `(current-eval interpret)`. Chez compiles on
  load. Ahead-of-time compilation buys startup — 0.72 s against 0.17 s for
  the allocation lane — and the measured region inside is identical to the
  byte. So the published costs were never interpreted-code costs, and the
  compiled half now says so as an observation rather than an inference.
  See [docs/performance.org](docs/performance.org).

- **A recorded comparison against llhttp**, on llhttp's own benchmark.
  `llparse-test-fixture` carries a `bench` mode and upstream's `npm run bench`
  drives the very binaries `tools/oracle/` already builds, so there is no
  benchmark program to write and the methodology is upstream's rather than
  ours. On upstream's three bench inputs: 485x on a 703-byte request, 365x on
  a 520-byte chunked `POST`, 89x on a 52-byte URL.

  **The ratio is not constant, and the variance is on our side.** llhttp's URL
  and message parsers are within 1.5x of each other per byte; ours differ by
  4.5x. Recorded rather than gated: a ratio is stable enough to gate on where
  an absolute rate is not, but gating one now would lock in a number while
  that 4.5x is unexplained.

- **The 4.5x is state numbering, and the cause is recorded**
  ([0027](.plans/decisions/0027-the-cost-is-dispatch-position-not-grammar.md)).
  Chez compiles `(case st ...)` over integer keys as a linear scan -- ~0.31 ns
  per arm skipped, the total arm count irrelevant, identical at every optimize
  level. The emitted message machine has 530 states with its hot scanning
  states numbered late (`url-path` 468, `value-loop` 235); the standalone url
  machine runs the same url grammar at `url-path` 15. Permuting the emitted
  `case` arms, which changes no semantics, moves the request-target figure
  from 239.8 to 42.4 ns/byte.

  Nothing in this repository's grammar, generated artifact or runtime is at
  fault. The dispatch is emitted by byte-machine's `render-machine`, and the
  fix belongs there, through that project's own admission rule.

### Fixed

- **A benchmark could report a rate the clock never measured.** Elapsed time
  was floored with `(max 1 ...)` before the rate was computed, so a region
  finishing inside the millisecond clock's resolution would divide by that
  floor and print a large, entirely fabricated figure — one that passes every
  throughput floor in the lane, because the smaller the interval the larger
  the quotient. `parse-n` now returns the raw reading and each case asserts
  its region outlasted the clock.

- **The allocation figures in `docs/performance.org` were stale**: 6,496 /
  6,548 B and 398 B where the lane measures 6,592 / 6,640 B and 397 B. The
  shape the prose draws from them is unchanged; the numbers are now the ones
  the lane prints.

- **A bare LF after a request's version needs BOTH `OPTIONAL_CR_BEFORE_LF`
  and `OPTIONAL_LF_AFTER_CR`**
  ([0026](.plans/decisions/0026-the-lenient-flags-are-combined-and-the-init-hook-is-ours.md)).
  With the first alone llhttp still refuses — at the same offset and with the
  same reason as strict, and a different code: `Expected CRLF after version`
  as `strict` (2) rather than as `invalid-version` (9). This parser accepted
  it. **A message you used to parse may now be refused.**

- **A response status line with no reason phrase, ending in a bare LF, is
  accepted under `OPTIONAL_CR_BEFORE_LF`** (same decision). Upstream's
  `res_status_code_otherwise` has an LF arm gated on that flag which this
  parser had as a flat `Invalid response status`. A thirty-third lenient
  fork, where decision 0020's sweep measured thirty-two — a fork that is not
  there is not a site. **A message you used to see refused now parses.**

  Neither is reachable by any fixture upstream ships: the corpus tests one
  flag at a time where the first needs a pair, and `Invalid response status`
  appears nowhere in the 274.

- **A host may hold two `@` if they are not adjacent**
  ([0024](.plans/decisions/0024-the-url-input-generator-and-the-second-at.md)).
  llhttp accepts `http://a@b@c/p` — the host is `a@b@c` — and refuses only
  `a@@b` with `Double @ in url`. This parser refused the second `@` wherever
  it fell.

  Upstream builds `server` and `server_with_at` from one loop whose edges
  name `server` explicitly rather than the loop variable, so the second node
  is ONE BYTE WIDE: any ordinary host byte returns to the first and re-arms
  `@`. `url.md`'s "Double `@`" fixture has its two adjacent, so neither the
  corpus, nor the six oracle-measured cases, nor 274 replays at every chunk
  size could tell the two rules apart.

  **A target you used to see refused now parses.** Found by the new url kind
  of the live differential, on its first sweep.

### Changed

- **The generated-input lanes combine the lenient flags**
  ([0026](.plans/decisions/0026-the-lenient-flags-are-combined-and-the-init-hook-is-ours.md)).
  Upstream's harness picks its init hook with a `-D` at compile time and
  ships one per (kind, single flag), so no combination can be asked of it at
  all — and `lenient_all` sets nine of the eleven, leaving
  `spaces-after-chunk-size` and `header-value-relaxed` combined with nothing
  anywhere in the corpus.

  A fourth oracle binary takes its mode from the environment, and
  `generate-lenient`'s subsets walk a fixed schedule — 11 singletons, 55
  pairs, the whole set — so the seed moves the input rather than the
  coverage. Differential `agreed` 7730 → **9557**; the property lane gains a
  mode tally and a floor per mode.

  The custom init hook is held to upstream's own binaries at no flags and at
  one flag, rather than argued into place.

- **Both generated-input properties are now asked of both machines**
  ([0025](.plans/decisions/0025-both-properties-are-asked-of-both-machines.md)).
  The property lane is a merge gate and was message-only, so nothing compared
  the emitted url parser against its interpreted twin over input the corpus
  does not contain — the one place a compiler bug could hide from the
  conformance lane. Error-free inputs `request=39 response=26 url=115`;
  executor comparisons `145 / 95 / 240`.

  **Every floor in the lane is now per kind.** Both properties pass vacuously
  over a run that selected nothing, so both are guarded by a floor — and one
  global floor is satisfied by the message kinds alone, whatever the url
  machine contributes. Three floors now, picked from measured counts over six
  seeds, with the per-kind tally printed beside them.

  Upstream's `url.md` `noScan` annotation is checked rather than quoted: it
  marks the four error fixtures, and only three of them actually diverge
  across chunk sizes.

- **The live differential compares a third kind, and sweeps three seeds**
  ([0024](.plans/decisions/0024-the-url-input-generator-and-the-second-at.md)).
  `generate-urls` assembles urls from llhttp's own decision points, `url.md`
  entire is a mutation base, and a third oracle binary is built the way
  `test/md-test.ts`'s `buildURL()` builds it — the program `url.md` was
  recorded from. `agreed` 1142 → **7730**, `unclassified=0`.

  The message inputs are byte for byte what they were:
  `HTTPARSE_DIFFERENTIAL_URL_CASES=0` reproduces `agreed=1142` exactly.

  **The seed sweep is a measurement.** The bug above did not appear at the
  default seed and did appear at three of the five tried, so the run is now
  the seed it is given plus its two successors. A lane pinned to one seed can
  be silently lucky, and its green reads as evidence.

- **The request target is parsed, not just carried — and the parser is
  STRICTER for it**
  ([0023](.plans/decisions/0023-the-request-target-is-parsed-not-carried.md)).
  llhttp's URL machine now runs over the request target, entering at the
  authority form for `CONNECT` and the general form otherwise, so a target
  whose structure llhttp rejects is an error here too:

  ```
  OPTIONS a.com:443 HTTP/1.1
    ->  error code 7, "Unexpected char in url schema", at offset 9
  ```

  **A message you used to parse may now be refused.** This is the first
  change in this project's history that turns a previously-parsed message
  into an error. It is llhttp's behaviour, arrived at deliberately.

  The target is still ONE `span[url]` — llhttp builds the same machine two
  ways, and this builds it from one description twice for the same reason.
  No `on-url-data` fires before such an error: the span is open when the
  refusal happens, and an error abandons an open span.

  **This closes the largest measured divergence.** The live differential goes
  from `agreed=1097 url-machine=45` to `agreed=1142`, every one of the 45
  becoming an agreement, and the `url-machine` class is deleted rather than
  left at zero. 274 fixtures unchanged; the parser grows 434 → 450 states.

### Added

- **The url sub-parser, and with it every fixture llhttp ships.** The ratchet
  stands at **274 of 274** and the deferral list is EMPTY, for the first time
  since decision 0009 wrote it with 84 entries
  ([0022](.plans/decisions/0022-the-url-sub-parser-is-a-second-machine.md)).

  A SECOND MACHINE, not more of the first. `url.md`'s fixtures carry no HTTP
  framing: upstream builds a separate binary from `llhttp.URL(p, true)` with
  both exits looped back to its own entry, and its traces are five span names
  (`url.schema`, `url.host`, `url.path`, `url.query`, `url.fragment`) and
  errors. So `(httparse url-grammar)` is a new builder emitting a new
  artifact, `(generated httparse-url)`, and the conformance driver resolves a
  machine per fixture.

  **The HTTP parser is unchanged** and keeps its single `span[url]`, which is
  upstream's other build of the same class and already what M2 shipped.

  Three shapes are where a transcription would have gone wrong quietly, and
  each is pinned by something that is not an argument: `schema:/path` reports
  at 8 and not 7 (a sequence match keeps the prefix it consumed before the
  mismatch); a tab is refused one byte PAST itself (the node wrapper matches
  rather than peeks); and a host ending at a `?` KEEPS the `?` — measured
  against an oracle, since no fixture has one, and transcribed rather than
  repaired.

  The space/CR/LF exits are graph no fixture reaches — none of the 21 inputs
  contains one — so they were built faithfully and measured against a
  purpose-built url oracle. A space does not end the parse; it starts another
  URL, and what follows is judged from scratch.

### Changed

- **The two modes an embedder chooses are settable FIELDS, written at
  `make-parser`, not callbacks the parser asks**
  ([0021](.plans/decisions/0021-the-modes-are-settable-fields-and-the-fourth-brief-is-discharged.md)).
  The pin moved to the generator's `v0.5.0`, which answers this project's
  fourth upstream brief, and the surface collapses to llhttp's own:

  ```scheme
  (make-parser httparse-message-machine bindings #f
               (list (cons 'type (httparse-message-type-value 'request))
                     (cons 'lenient-flags
                           (httparse-lenient-flags-value '(headers version)))))
  ```

  **`on-message-type` and the eleven `on-lenient-*` callbacks are gone.** So
  is the twenty-two-node ask chain ahead of the machine's entry. The emitted
  parser loses 23 states (457 → 434) and 12 callback declarations (37 → 25),
  and shrinks by 8508 bytes. Ratchet unchanged at 253, and the live
  differential is unmoved.

  Two properties improved rather than merely moved. The message kind was asked
  **once per message**, so an embedder could have answered `request` for one
  pipelined message and `response` for the next, which `s->type` cannot do
  upstream — a surface narrower than llhttp's now, where it was wider. And
  `parser-reset!` restores the initials **you gave**, so a mode no longer
  blinks to zero on a reset, coming back only because the next feed re-asked.

  **One thing is later rather than better, and is recorded rather than
  smoothed over:** a missing `on-message-type` binding used to be refused by
  `make-parser`, and a missing `type` initial is now refused at offset 0 with
  the same code and reason. A field initial cannot be made mandatory.

  New pure library **`(httparse modes)`**, importing nothing — llhttp's bit
  tables and the arithmetic over them, so the grammar, the harness and an
  embedder read one source rather than three.

- **Generated-runtime ABI 7 → 8.** A settable machine emits an optional fourth
  metadata member. Moved on its own commit, with the machine proved unchanged
  by its IR fingerprint rather than by reading the diff.

### Added

- **Lenient modes — all eleven flags, and with them every HTTP fixture llhttp
  ships.** The ratchet stands at **253 of 253**; the 21 that remain are
  `url.md`, which is a separate parser
  ([0020](.plans/decisions/0020-lenient-modes-a-flag-at-a-time.md)).

  Each flag arrives as an OPTIONAL decision callback asked once, ahead of the
  machine's entry, and sets a bit in a `lenient-flags` field of its own —
  separate from `flags`, because the restart between two messages zeroes that
  one and a mode the embedder chose must survive it. An embedder that wants
  none of them binds nothing and parses strictly, which is what the other 216
  fixtures do.

  Every leniency is one mask test, because that is all `testLenientFlags` is
  upstream: thirty-two of them across the eleven flags. Thirty are reached by
  the vendored corpus — measured by disabling each in turn — and the two that
  are not carry cases taken from purpose-built lenient oracle binaries.

  Landed a flag at a time. The ratchet scopes a lenient fixture by whether its
  flags are IMPLEMENTED, so each slice is one name added to a list and its
  fixtures re-classed in the same reviewed diff.

- **The version subgraph stores every digit and judges the pair afterwards**,
  which is llhttp's `checkVersion` shape. It previously fused the two — only a
  digit belonging to 0.9/1.0/1.1/2.0 had a store node — which gave the same
  three errors at the same three offsets and could not print `v=5/6`.

- **Pausing, and `skipBody`** — M9, the 26 fixtures decision
  [0009](.plans/decisions/0009-v01-is-strict-request-and-response-parsing.md)
  deferred past v0.1. The ratchet stands at **216 of 253** HTTP fixtures, from
  190; the 58 that remain are 37 lenient-mode and 21 URL.

  A parser is now BOUND IN A HARNESS MODE, which is upstream's own shape: its
  test driver turns a fixture's meta into a compiler define and caches one
  binary per mode, and the two modes are exclusive in the C preprocessor. Here
  that is one required argument — `#f`, `(pause <name>)` or `(skip-body)` —
  rather than two flags that could represent a build nobody can make.
  ([0019](.plans/decisions/0019-the-harness-mode-and-the-two-kinds-of-pause.md))

- **`off=N pause`, told apart from the machine's own pause.** Upstream prints
  a callback's pause as the bare word and an upgrade pause as an error line,
  and nothing in the word says which. The discriminator is the declared
  reason: a pause reason belongs to a NODE, so the machine's pause node
  carries one and a callback answering `callback-pause` cannot. A reasonless
  pause nobody asked for is still refused.

- **`off=N skip body`**, and the flag behind it. `on-headers-complete` is now
  the grammar's second decision callback; its `skip-body` branch sets
  `F_SKIPBODY` and rejoins the body decision, because that decision reads the
  flag in two places and a jump could only serve one. The second of the two —
  an upgrade whose embedder said "no body" — has no fixture to vouch for it,
  so it is pinned against a LIVE llhttp built in skip-body mode from the
  commit the corpus came from.

- **A milestone plan's header is checked against its own ladder.** It had gone
  stale twice: M8 shipped while the header still introduced the document as a
  design, and M9 landed one pull request later and left the Goal section
  calling M9 deferred while its own heading said DONE. The lane fails a
  decision link that resolves to no record, and a deferral sentence in the
  header that names a milestone marked DONE. Three synthetic documents witness
  it, so deleting either check reddens instead of passing quietly, and a run
  that finds no ladder to judge fails rather than reporting success.

### Changed

- `trace-recorder-bindings` takes the harness mode as a third required
  argument. `drive-feed!` joins `(httparse test drive)`, so the conformance
  lane and the unit lanes resume a pause through one loop rather than two.

- The milestone plan's header no longer names a decision range, and no longer
  enumerates which milestones are deferred. Both restated state the tree
  already carries, and both drifted the moment a record or a milestone landed;
  the milestone sections carry their own status. A check that the range ends at
  the highest-numbered record was deliberately NOT written: the records are
  project-wide, so a later decision need not concern that plan, and such a lane
  would demand a false edit.

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
