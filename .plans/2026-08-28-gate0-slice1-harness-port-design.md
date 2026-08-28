# Gate 0 + Slice 1: bootstrap chez-httparse on the byte-machine harness

Date: 2026-08-28
Status: accepted design for Slice 1 (this document governs the harness port only)

## Goal

chez-httparse is the HTTP/1 parser layer of the Chez HTTP stack described in
[chez-http-server-architecture.md](./chez-http-server-architecture.md) (§3
there names the layer `chez-http1`; decision [0001](./decisions/0001-project-name-and-rename-map.md)
records why this repo keeps the name chez-httparse). The parser will be
defined against byte-machine's state-machine DSL and generated ABI.

Gate 0 settles three decisions (recorded as ADRs 0001–0003 under
[.plans/decisions/](./decisions/)). Slice 1 ports byte-machine's test harness
and build layer — no HTTP code, no `src/`, no parser work.

## Why port the harness first

byte-machine's harness is a proven discipline machine: CMake-layer specs that
run with no Scheme runtime, source+AOT Scheme lanes with provenance
fingerprinting, exact-exit-status assertions, a mutation engine whose suites
fail when a declared mutation goes uncaught, and empty-selection-is-failure
enforced at three layers (CTest presets, mutation engine, Scheme harness).
Porting it before any parser code exists means every later slice lands on a
harness that already distrusts its own tests.

The port is a **copy**, not a dependency: this repo never includes files from
the byte-machine checkout (its internals stay free to change), and the copied
harness is expected to diverge. Attribution lives in CHANGELOG.md.

## Rename map (fixed by ADR 0001)

Mechanical, applied in this order so longer tokens win:

| byte-machine token | chez-httparse token | where |
|---|---|---|
| `ByteMachine*` | `Httparse*` | CMake module + spec filenames, `include()` names |
| `BYTE_MACHINE_*` | `HTTPARSE_*` | CMake cache/regular variables, env vars (incl. CI `EXPECT_OS`/`EXPECT_ARCH`) |
| `byte_machine_*` | `httparse_*` | CMake functions/macros/targets |
| `byte-machine` (bare) | `httparse` | test-name grammar `^httparse\.`, diagnostic prefixes (`httparse:`, `httparse-spec:`, `httparse-mutation:`, `httparse-harness:`, `httparse-launcher:`, `httparse-fingerprint:`), underscore-sanitized lane paths |
| `(byte-machine test …)` | `(httparse test …)` | R6RS library names; directory `test/support/harness/byte-machine/` → `test/support/harness/httparse/` |

Product/prose contexts use the full name **chez-httparse**: `project()`,
`DESCRIPTION`, `HOMEPAGE_URL`, Makefile help banner, README, CHANGELOG, SDD
ledger header. Upstream byte-machine API names (`(byte-machine runtime)`,
`byte-machine-make-compiled-machine/v2`, …) are the dependency's identifiers
and are never renamed when they appear in later slices.

Rename hazards the port must respect (from the survey of the source tree):

- Mutation-suite `FIND`/`REPLACE` literals are verbatim module text; the
  `SITES` occurrence counts fail loudly on any rename skew. Rename manifests
  and modules in lockstep, byte-for-byte, preserving deliberate trailing
  newlines/parens in FIND patterns.
- Spec files assert module diagnostics verbatim (`byte-machine: …` →
  `httparse: …`) and stub registrar functions by name; stubs must be renamed
  with the registrars or they stop shadowing.
- One library-name token is split across two comment lines in `harness.sls`
  (lines 8–9); line-oriented sed misses it.
- `_bm_` internal locals (ExpectExit runner, MutationRunner properties) escape
  all four passes; rename to `_hp_` for consistency.
- The `-bm-`-free internal names, runtime identity strings (`chez`,
  machine-type tables), and suite-name strings carry no project token — do not
  touch.

## Files ported (copy + rename + recorded surgery)

Build layer: `Makefile`, `CMakeLists.txt`, `CMakePresets.json`,
`.gitignore`, `.gitattributes`.
CMake modules: `cmake/Httparse{Chez,Probe,ExpectExit,Testing,SchemeLane}.cmake`,
`cmake/chez-probe.ss`.
Spec suite: `test/support/cmake/` — SpecSupport(+Spec), the five module
specs, MutationRunner(+Spec), MutationSuite, SchemeMutationSuite (rewritten,
see below).
Harness: `test/support/harness/httparse/test/{harness,fingerprint,prng}.sls`,
`test/support/harness/self/*.sps` (all six).
Launchers: `test/support/launchers/{chez-source,chez-aot,chez-compile,fingerprint-manifest}.ss`.
CI: `.github/workflows/ci.yml` (macOS brew cell; Linux source-built Chez
10.4.1 cell with trailing no-scheme step).
Process: AGENTS.md (merge byte-machine's delta into the existing file),
CHANGELOG.md (fresh, Keep-a-Changelog shape), ADR convention README to
`.plans/decisions/README.md`, fresh SDD ledger under `.superpowers/sdd/`.

**Not ported**: `src/`, `test/common/`, `test/fixtures/` contents,
byte-machine's `test/CMakeLists.txt` (rewritten minimal), the four
domain-fixture libraries under the harness that import `(byte-machine graph)`
(`eof-machine`, `machine-gen`, `one-byte-machine`, `sequence-machine`),
`.superpowers/sdd` contents, `docs/plans` history, `bench/`, `examples/`,
`test/chez/`.

## Recorded surgery (beyond mechanical rename)

1. `CMakeLists.txt`: description/homepage/prose become chez-httparse's; drop
   the byte-machine ADR pointer in the header comment (re-point at ADR 0001).
2. `HttparseSchemeLane.cmake` line ~425: the `FINGERPRINT_SAMPLE` default env
   stays, pointed at this repo's own fixture (below) — stripping it would
   cascade into the SchemeLane spec's verbatim env assertions and 24 mutation
   literals for no gain.
3. New fixture `test/fixtures/fingerprint-sample.bin` containing the bytes
   `chez-httparse\n` (14 bytes). The self-tests' hard-coded constants (length
   13 → 14, first byte 98 → 99, fingerprint hex) are updated, the hex
   recomputed by running the ported fingerprint library under Chez 10.4.1 and
   cross-checked against an independent reimplementation of the documented
   hash.
4. Comments citing byte-machine plans/decisions/slice numbers/protium are
   trimmed or re-anchored; the load-bearing rationale sentences stay.
5. Test-lane label vocabulary keeps byte-machine's full layer list (the `pr`
   preset regex matches it); trimming it is deferred until real parser lanes
   exist and would only then earn a decision.
6. Chez floor 10.4.1 is retained but re-justified by this repo's own CI
   (Linux cell builds exactly 10.4.1; macOS brew cell records its version).

## New test/CMakeLists.txt (rewritten, minimal)

Registers only the ported harness/build-layer surface:

- The eight `cmake.direct` spec tests (Testing, Probe, Chez, SpecSupport,
  MutationRunner, MutationSuite, ExpectExit, SchemeLane), plus a ninth, new
  `httparse.harness.rename-audit.cmake.direct` (below).
- Harness path variables + the fingerprint expectation machinery
  (`httparse_expected_fingerprint` / `httparse_wrong_fingerprint` and the
  aggregated expectation targets) — required because SchemeLane's per-lane
  provenance block calls them whenever a Chez is discovered.
- Scheme harness lanes (skip gracefully with no Chez): self-tests and
  bootstrap (source + aot), the four exact-exit lanes (failing→1,
  duplicate-case→2, empty-selection→2, unreached-provenance→3), the verbose
  lane, the launcher-refusal exact-exit lanes, and the provenance lanes.
- The scheme-mutation lane running the rewritten SchemeMutationSuite.

Triage rule for anything fixture-dependent (e.g. the `stale-artifact.chez.aot`
staleness-falsifiability lane, whose upstream fixture lives in the excluded
`test/fixtures/stale-root/`): keep it if a fresh fixture against the ported
tree is small and honest; otherwise drop the lane **and** its paired
mutations, with a written reason in the mutation manifest — never a silently
missing pass.

## SchemeMutationSuite rewrite

Drop passes 32–40 (57 mutations targeting `src/` through `test/common/` —
neither exists here) and the `src`/`test/common` stage dirs. Keep the
harness/launcher passes. `EXPECTED_PASSES`/`EXPECTED_MUTATIONS` are
**recounted from the rewritten manifest, never predicted** (survey estimate
28/59; the totals check at the bottom makes a miscount loud). Any kept pass
whose verify lane was dropped is dropped with it, with a written reason.

## New: rename-audit spec (TDD)

`test/support/cmake/RenameAuditSpec.cmake`, registered as
`httparse.harness.rename-audit.cmake.direct`. Enforces exit criterion 5 as a
check instead of a comment (AGENTS.md rule): scans the build/test tree
(`Makefile`, `CMakeLists.txt`, `CMakePresets.json`, `cmake/`, `test/`,
`.github/`, `.gitignore`, `.gitattributes`) for the four byte-machine token
shapes, assembled via `string(CONCAT)` so the spec never matches itself.
Docs/attribution surfaces (`.plans/`, `README.org`, `CHANGELOG.md`,
`AGENTS.md`, `LICENSE`, `.superpowers/`) are outside the audit by design.
Missing scan roots are skipped (the mutation stage holds only `cmake/` and
`test/support/cmake/`). Coverage: a MutationSuite mutation plants a forbidden
token in a scanned module and the audit spec must catch it (watched to fail
before the mutation is declared caught).

## Exit criteria (fixed by ADR 0003)

1. `make dev` green — harness preset: all `cmake.direct` specs (including the
   72+-mutation CMake suite) plus the Scheme harness self lanes.
2. `make test` (pr preset) and `make test-all` (release preset) green, with
   empty-selection-is-failure intact at all three layers.
3. `no-scheme` preset green: configure with `HTTPARSE_REQUIRE_CHEZ=OFF`, ctest
   preset `no-scheme` runs the CMake-layer specs with no Scheme runtime.
4. CI green on both cells (macOS brew, Linux source-built Chez + no-scheme
   step) — verified on the feature branch's pull request.
5. Zero byte-machine references in the build/test tree (attribution/docs
   exempt), enforced by the registered rename-audit spec and a closing `rg`
   sweep.

## Out of scope for Slice 1

The llhttp differential oracle / corpus runner (later slice), any HTTP
grammar or parser code, `src/`, and the byte-machine submodule wiring
(decided in ADR 0002, added when the first slice consumes the generator).
