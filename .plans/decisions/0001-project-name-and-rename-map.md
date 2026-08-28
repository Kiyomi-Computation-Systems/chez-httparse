# 0001: The project is chez-httparse; machine tokens use the bare stem httparse

Date: 2026-08-28
Status: accepted
Milestone: Gate 0 (.plans/2026-08-28-gate0-slice1-harness-port-design.md)

## Context

The architecture document (.plans/chez-http-server-architecture.md §3) sketches
the HTTP/1 parser layer under the name `chez-http1`. This repository was
created as chez-httparse, with LICENSE and README already committed under that
name. The harness being ported from byte-machine embeds its project name in
four distinct shapes — `byte_machine_*` CMake functions, `BYTE_MACHINE_*`
variables and environment names, `ByteMachine*` filenames, and the bare
hyphenated `byte-machine` (the `project()` name, the test-name grammar regex
`^byte-machine\.`, seven diagnostic prefixes, R6RS library names
`(byte-machine test …)`, and the harness collection directory). The bare-token
mapping is not fixed by the first three rules and must be decided before any
rename runs, because mutation-manifest FIND/REPLACE literals, spec diagnostic
assertions, and the name-grammar regex all have to move in lockstep.

## Decision

1. **The project name is chez-httparse.** The architecture doc's `chez-http1`
   is a layer sketch, not a contract; the repository, remote, LICENSE, and
   README already carry chez-httparse, and the name describes the deliverable
   (an HTTP parser) without implying a scope change if HTTP/1.x coverage
   details shift. The divergence from the architecture doc is deliberate and
   this record is its trail.
2. **Machine tokens use the bare stem `httparse`**, not `chez-httparse`:
   `byte_machine_*` → `httparse_*`, `BYTE_MACHINE_*` → `HTTPARSE_*`,
   `ByteMachine*` → `Httparse*`, bare `byte-machine` → `httparse`,
   `(byte-machine test …)` → `(httparse test …)` with the collection directory
   `test/support/harness/httparse/`.
3. **Product and prose contexts use the full name chez-httparse**: the CMake
   `project()` name, `DESCRIPTION`, `HOMEPAGE_URL`
   (https://github.com/Kiyomi-Computation-Systems/chez-httparse), Makefile
   help banner, README, CHANGELOG, and the SDD ledger header. Nothing
   functional derives from `PROJECT_NAME`, so the full name is safe there.
4. **Upstream byte-machine identifiers are never renamed.** When later slices
   import `(byte-machine runtime)` or construct via
   `byte-machine-make-compiled-machine/v2`, those are the dependency's names;
   renaming them would break the contract they name. The rename map applies
   only to the copied harness and this repo's own code.

## What this rules out

- `chez-httparse` as the test-name grammar stem: lane names are
  `<name>.<layer>.<feature>.<backend>.<mode>` and the backend token is `chez`
  — `chez-httparse.harness.x.chez.source` puts the backend's name inside the
  project segment and misreads.
- `CHEZ_HTTPARSE_*` variables: the discovery layer's key variable would become
  `CHEZ_HTTPARSE_CHEZ_EXECUTABLE`; `HTTPARSE_CHEZ_EXECUTABLE` says the same
  thing without the stutter.
- Adopting `chez-http1`/`http1` as the stem: would rename the repository out
  from under its existing remote and history for no functional gain.

## Consequences

- Every harness rename runs the four-pass map in longest-token-first order;
  the ported spec suite and mutation SITES counts are the net that catches a
  missed or skewed pass.
- Test names are `httparse.<layer>.<feature>.<backend>.<mode>`; diagnostic
  prefixes are `httparse:`, `httparse-spec:`, `httparse-mutation:`,
  `httparse-harness:`, `httparse-launcher:`, `httparse-fingerprint:`.
- `README.org`'s title (currently "chez-httpars", a typo) is corrected to
  chez-httparse.
