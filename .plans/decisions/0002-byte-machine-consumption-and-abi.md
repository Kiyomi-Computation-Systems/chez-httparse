# 0002: byte-machine arrives two ways — the harness by one-time copy, the generator by pinned git submodule targeting generated ABI v2

Date: 2026-08-28
Status: accepted, superseded in part
Superseded in part by: [0005](0005-byte-machine-pinned-by-gitlink-generated-abi-5.md), decision item 3
Milestone: Gate 0 (.plans/2026-08-28-gate0-slice1-harness-port-design.md)

> **Decision item 3 is superseded by
> [0005](0005-byte-machine-pinned-by-gitlink-generated-abi-5.md) (2026-09-13).**
> byte-machine has since released v0.1.0: the generated ABI is now **5**,
> construction goes through one unversioned
> `byte-machine-make-compiled-machine`, and
> `byte-machine-make-compiled-machine/v2` survives only as a tombstone that
> refuses every version. Targeting v2 as written below would call a procedure
> whose contract is to refuse. Items 1, 2 and 4 stand unchanged, and are left
> as written.

## Context

chez-httparse needs two distinct things from byte-machine
(github.com/Kiyomi-Computation-Systems/byte-machine, private, same org as this
repo):

- its **test harness and build layer**, wanted immediately (Slice 1), which
  byte-machine treats as internal infrastructure with no stability promise;
- its **state-machine generator**, wanted from the first grammar slice onward,
  which byte-machine versions deliberately: decision 0010 there defines the
  generated-code ABI as a direct executor with a version tag, and decision
  0012 (2026-08-28) lands ABI v2 — the emitter emits
  `byte-machine-make-compiled-machine/v2` constructing one unified `exec`
  closure with a `finish?` flag; `current-abi-version` is 2; the runtime keeps
  its `/v1` export solely so a stale v1 generated file fails the version
  check cleanly rather than at import.

Both repos being private, any CI checkout of byte-machine (submodule or
sibling clone) needs an org-scoped read token secret; the token cost is the
same either way, so it does not discriminate between mechanisms.

## Decision

1. **The harness is consumed by one-time copy, renamed per decision 0001,
   with attribution in CHANGELOG.md.** No file in this repository ever
   includes or references a path inside a byte-machine checkout. The copy is
   expected to diverge; byte-machine's internals stay free to change without
   breaking this repo.
2. **The generator is consumed as a git submodule** (HTTPS URL
   https://github.com/Kiyomi-Computation-Systems/byte-machine.git), pinned by
   gitlink so the exact dependency commit is recorded in-tree — an explicit,
   reproducible dependency declaration. The submodule is **added in the first
   slice that actually invokes the emitter**, not in Slice 1; adding an unused
   pin now would only rot.
3. **The generated ABI target is v2**: generated parser sources import
   `(byte-machine runtime)` and are constructed via
   `byte-machine-make-compiled-machine/v2` (unified `exec` with `finish?`;
   feed-outcome status symbols including `finished` and `paused`). Reference
   point at decision time: byte-machine commit 9561fa2, decisions 0010/0012.

## What this rules out

- A bare path dependency on a developer checkout (`~/github/byte-machine`):
  unpinned, irreproducible in CI, and invisible in-tree.
- Copying the generator's emitted output by hand without recording the
  emitting commit: the rendered text embeds the ABI tag and IR fingerprint,
  so an unrecorded emitter is an unfalsifiable golden.
- Targeting ABI v1: the upstream emitter no longer emits it.

## Consequences

- When the submodule lands, CI checkout gains `submodules: recursive` plus an
  org-scoped read token secret (the default `GITHUB_TOKEN` cannot read a
  second private repo). Until then, Slice 1's CI needs no cross-repo access.
- Golden generated sources, when they land, record the byte-machine commit
  that emitted them; bumping the submodule re-baselines goldens (the embedded
  IR fingerprint moves) and any upstream pre-1.0 ABI change gets a
  CHANGELOG.md entry here as well as there.
- A local override for developing against a live byte-machine checkout (e.g.
  a cache variable pointing at an alternate root) is deferred to the slice
  that wires the submodule; it must never become the default path.
