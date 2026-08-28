# Changelog

All notable changes to chez-httparse are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
uses [semantic versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Gate 0 and Slice 1: project bootstrap. The governing architecture is
[.plans/chez-http-server-architecture.md](.plans/chez-http-server-architecture.md);
the slice design is
[.plans/2026-08-28-gate0-slice1-harness-port-design.md](.plans/2026-08-28-gate0-slice1-harness-port-design.md).
No parser code yet.

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
- CI: macOS arm64 (brew Chez) and Linux amd64 (Chez 10.4.1 built from
  source) cells, the latter closing with the no-scheme lane.

### Changed

### Removed

### Fixed
