# 0005: byte-machine is pinned by gitlink starting at v0.1.0, the generated ABI target is 5, and the pin is expected to move

Date: 2026-09-13
Status: accepted
Supersedes: [0002](0002-byte-machine-consumption-and-abi.md), decision item 3
Milestone: Gate 0 (.plans/2026-09-13-gate0-http-parser-milestone-plan.md)

## Context

Decision 0002 was written on 2026-08-28 against byte-machine commit 9561fa2,
when that project's decisions 0010/0012 had just landed generated ABI v2. It
fixed this repository's target as "generated parser sources ... constructed via
`byte-machine-make-compiled-machine/v2`".

byte-machine has since reached its first release and moved past that ABI. In
the tree at tag `v0.1.0`:

- `current-abi-version` is **5** (`src/byte-machine/runtime.sls:85`);
- construction goes through one **unversioned**
  `byte-machine-make-compiled-machine` (`runtime.sls:114`), which checks
  `(= abi-version current-abi-version)` by strict equality as its first action;
- `byte-machine-make-compiled-machine/v1` and `/v2` survive only as tombstones
  that raise `"retired generated-runtime ABI"` for **every** version argument
  (`runtime.sls:137-145`).

A slice written against 0002 as it stands would therefore not merely be out of
date — it would call a procedure whose entire contract is to refuse.

0002 also framed byte-machine as a dependency this repository consumes at arm's
length. That framing is wrong in one direction that matters: both projects are
ours, and chez-httparse is byte-machine's first real consumer. The generator's
API is frozen for *its* v0.1 release, but that freeze binds byte-machine's
existing users, not this project's ability to ask for a v0.2. See
[0006](0006-upstream-first-for-general-gaps.md) for what happens when a slice
finds a gap.

## Decision

1. **The submodule is pinned by gitlink to a named commit, starting at
   byte-machine `v0.1.0`** (commit `c38e76f55c0d17b80541b917167e227aaed00601`).
   The gitlink, not the tag, is the pin — the tag names where we started. The
   four commits on that project's `main` past the tag are documentation-only and
   are deliberately not picked up at the start.
2. **The generated ABI target is 5**, reached through the unversioned
   `byte-machine-make-compiled-machine`. Generated parser sources import
   `(byte-machine runtime)` alone. No code in this repository names
   `byte-machine-make-compiled-machine/v1` or `/v2`.
3. **The pin is expected to move, and moving it is a first-class event, not an
   accident.** A bump lands in its own pull request carrying: the upstream
   commit range, the re-measured IR fingerprints for every affected golden, a
   CHANGELOG.md entry here as well as there, and — when the bump exists to
   deliver an upstream change this project asked for — a pointer to the record
   that asked.
4. **Decision 0002 items 1, 2 and 4 stand unchanged**: the harness arrived by
   one-time copy; the submodule is added in the first slice that actually
   invokes the emitter; upstream byte-machine identifiers are never renamed.
5. **The ABI number is re-read, never remembered.** The slice that wires the
   submodule asserts the version it finds against the version it emits, as a
   check in the tree. A number carried forward in prose is what this record is
   repairing.

## What this rules out

- Writing any slice against `byte-machine-make-compiled-machine/v2`. It is a
  tombstone; the failure is an assertion violation at construction, not a
  deprecation warning.
- Tracking byte-machine's `main` by floating reference. Reproducibility is the
  whole point of a gitlink, and it survives however often the pin moves.
- Treating byte-machine's v0.1 API freeze as a reason this project must work
  around a generator gap rather than ask for a v0.2 — that reading is closed by
  [0006](0006-upstream-first-for-general-gaps.md).
- Treating "ABI 5" as a fact this repository may restate later from memory. It
  is a property of the pinned tree, re-read at the pin.

## Consequences

- Bumping carries a real cost: emitted goldens re-baseline because the embedded
  IR fingerprint moves. That cost is accepted and budgeted per bump; it is also
  the reason bumps are batched rather than continuous.
- The submodule needs an org-scoped read token in CI, as 0002 records; the
  version pin does not change that requirement.
- Because the pin starts at a release tag and moves under our own hand, the
  first bump is a useful early test of the bump ritual itself. It should not be
  deferred until it is urgent.
