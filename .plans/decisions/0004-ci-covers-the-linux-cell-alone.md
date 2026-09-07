# 0004: CI covers the Linux cell alone; macOS portability is verified on the maintainer's laptop and recorded in the slice report

Date: 2026-09-07
Status: accepted
Amends: [0003](0003-slice-1-scope-and-exit-criteria.md), criterion 4

## Context

Decision 0003 fixed Slice 1's exit criterion 4 as "CI green on both cells" —
macOS arm64 on brew Chez, Linux amd64 on source-built 10.4.1. That criterion
was met: the two-cell workflow ran green on the Slice 1 pull request, which is
what the ledger records at the merge gate. The criterion has been satisfied and
cannot be un-satisfied by this record.

What has changed is the workflow the criterion describes. The macOS cell was
removed because its cost and its evidence were mismatched in both directions:
a hosted macOS runner bills at ten times the Linux rate, and what it bought was
a *brew-installed* Chez whose version is whatever Homebrew shipped that week —
so the expensive cell was the one **not** exercising the 10.4.1 floor that
`HTTPARSE_CHEZ_MINIMUM_VERSION` pins, while the cheap cell was. Meanwhile the
same source build was repeated from scratch on every run and is now cached.

The budget is not hypothetical. This account's Actions minutes for September
2026 were exhausted before that change could be validated on a runner, which is
also why the pull request carrying it merged on a red check.

Leaving criterion 4 as written would leave the decision record describing a
workflow that no longer exists — a standing exit criterion that no future slice
can meet, and which a reader would reasonably try to restore.

## Decision

For every slice after Slice 1, criterion 4 of decision 0003 reads:

**CI green on the Linux amd64 cell** — source-built Chez at exactly the pinned
floor, the `pr` and `release` presets, closing with the `no-scheme` lane —
**observed on the slice's pull request; and macOS arm64 verified by a local
run, recorded in the slice report.**

Slice 1's own exit is untouched. This is prospective; it does not re-open,
re-grant, or retroactively re-word what PR #1 already evidenced.

Standing sub-decisions:

- **macOS evidence is a recorded run, not an assertion.** The slice report
  carries the version banner and `(machine-type)` (expected `tarm64osx`) from
  the laptop that ran it, alongside `make test-all` green. "It passes locally"
  without those two lines is not evidence; it is a memory of one.
- **The Linux cell stays the only automatic gate.** No slice closes on a local
  run alone. 0003's consequence — local macOS green is not a substitute for the
  Linux cell — survives this amendment in the direction that still matters.
- **A billing refusal is not a test result.** A run that failed with no steps
  and no logs never started, and says nothing about the diff; a genuine failure
  has both. Whoever merges on a red check names which of the two it was, in the
  merge commit. Anything else teaches the next reader that red is negotiable.

## What this rules out

- Restoring a hosted macOS cell without a decision that prices it against what
  it actually verifies. If it returns it should build the pinned floor, not
  record whatever brew has.
- Closing a slice with no macOS evidence at all, on the theory that the
  maintainer develops there anyway. Untested is untested wherever it runs.
- Reading "CI green" in any earlier record as covering darwin from this date
  forward.

## Consequences

- A darwin-only portability regression now surfaces on the laptop rather than
  on a runner, and at slice close rather than per push. That is the accepted
  cost: bounded by the maintainer working on that platform daily, and cheap to
  revisit if a regression ever does slip a slice.
- CI's remaining spend is dominated by the cached Chez prefix. Its key pins the
  version, so bumping `HTTPARSE_CHEZ_MINIMUM_VERSION` also buys one cold build
  — a bump is now a small, visible cost rather than a free edit.
- The rationale beside the floor in `cmake/HttparseChez.cmake` and the CI entry
  in `CHANGELOG.md` both name this arrangement; they track this record and
  should change with it, not before it.
- The Slice 1 design document
  (`.plans/2026-08-28-gate0-slice1-harness-port-design.md`) still describes the
  two-cell workflow. It is a record of a completed slice and stays as written;
  this file is where the current arrangement lives.
