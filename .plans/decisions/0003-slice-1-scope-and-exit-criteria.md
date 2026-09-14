# 0003: Slice 1 is the harness port alone, and it exits only when both suites, the no-scheme lane, CI, and the rename audit are green

Date: 2026-08-28
Status: accepted
Amended by: [0004](0004-ci-covers-the-linux-cell-alone.md), criterion 4
Amended by: [0011](0011-the-rename-audit-allows-declared-dependency-forms.md), criterion 5
Milestone: Gate 0 (.plans/2026-08-28-gate0-slice1-harness-port-design.md)

> **Criterion 4 is amended by [0004](0004-ci-covers-the-linux-cell-alone.md)
> (2026-09-07).** The macOS arm64 cell is retired: CI covers the Linux cell
> alone, and macOS is verified by a local run recorded in the slice report.
> Slice 1's own exit is unchanged — it was met on this slice's pull request
> against the two-cell workflow described below, which is left as written.

> **Criterion 5 is amended by
> [0011](0011-the-rename-audit-allows-declared-dependency-forms.md)
> (2026-09-13).** "Zero upstream-name references in the build/test tree" becomes
> "every occurrence matches one of three declared legitimate forms" — the
> submodule path and its library collection, an R6RS library reference, and the
> generated-runtime constructor. The audit was rewritten to match and its
> mutation with it.

## Context

Slice 1 ports byte-machine's harness (build layer, CMake spec suite, mutation
engine, Scheme harness + launchers, CI) into this repository under the
decision-0001 rename map. No HTTP code, no `src/`, no llhttp work. The design
document records the file-level port map, the recorded surgery, and the
rewrite rules for `test/CMakeLists.txt` and the Scheme mutation manifest. The
exit criteria below were proposed at project kickoff and are confirmed here
with the concrete target and preset names fixed by the ported build layer.

## Decision

Slice 1 is complete exactly when all five hold:

1. **`make dev` green** — the `harness` test preset: every `cmake.direct`
   spec (including the CMake mutation suite at its recounted total) and the
   Scheme harness self lanes, run against the discovered Chez.
2. **`make test` and `make test-all` green** — the `pr` and `release` presets
   — with the empty-selection-is-failure rule intact at all three layers:
   every test preset keeps `noTestsAction: error` (and the Makefile keeps
   `--no-tests=error`), the mutation engine keeps its empty-suite and
   empty-stage FATALs and its declared-totals check, and the Scheme harness
   keeps exit 2 on an empty selection (witnessed by its exact-exit lane).
3. **`no-scheme` preset green** — configure with `HTTPARSE_REQUIRE_CHEZ=OFF`,
   `ctest --preset no-scheme` runs the full CMake-layer spec surface with no
   Scheme runtime present.
4. **CI green on both cells** of the ported workflow — macOS arm64 (brew
   Chez) and Linux amd64 (source-built Chez 10.4.1, including the trailing
   no-scheme step) — observed on this slice's pull request.
5. **Zero byte-machine references in the build/test tree** (docs and
   attribution surfaces exempt: `.plans/`, `README.org`, `CHANGELOG.md`,
   `AGENTS.md`, `LICENSE`, `.superpowers/`), enforced by a registered
   rename-audit spec — a check, not a comment — whose own coverage is a
   declared mutation that plants a forbidden token and must be caught, plus a
   closing `rg` sweep recorded in the slice report.

Standing sub-decisions:

- Mutation totals (`EXPECTED_PASSES`/`EXPECTED_MUTATIONS` in both manifests)
  are **recounted from the rewritten manifests, never carried over or
  predicted**; the manifests' own totals checks make a miscount loud.
- Any lane or mutation dropped during the port (e.g. fixture-dependent
  staleness lanes) is dropped **with a written reason in the manifest**,
  never silently.
- The fingerprint sample fixture is this repo's own
  (`test/fixtures/fingerprint-sample.bin`, bytes `chez-httparse\n`); the
  self-test constants derived from it are re-measured under Chez 10.4.1.

## What this rules out

- Declaring the slice done on `make dev` alone: the pr/release presets, the
  no-scheme lane, and both CI cells are part of the bar, not follow-ups.
- Shipping the port with byte-machine names surviving anywhere the audit
  scans, or with the audit itself unwitnessed by a mutation.
- Any llhttp differential/corpus work in this slice (explicitly a later
  slice's harness extension).

## Consequences

- The slice's PR carries the CI evidence for criterion 4; local green on
  macOS arm64 is not a substitute for the Linux cell.
- The rename-audit spec joins the registered surface permanently, so any
  future copy-from-byte-machine that leaks a token fails the build, not a
  review.
- Because criterion 2 depends on preset/label agreement, the ported layer
  vocabulary keeps byte-machine's label set until a later decision trims it.
