# 0011: the rename audit checks that every upstream-token occurrence matches a declared legitimate form, rather than that none occurs

Date: 2026-09-13
Status: accepted
Amends: [0003](0003-slice-1-scope-and-exit-criteria.md), criterion 5
Milestone: M2 Slice ⓪ (.plans/2026-09-13-gate0-http-parser-milestone-plan.md)

## Context

Two standing decisions have always pointed in opposite directions, and M2 is
where they meet.

[0001](0001-project-name-and-rename-map.md) item 4: "Upstream byte-machine
identifiers are never renamed. When later slices import `(byte-machine
runtime)` … those are the dependency's names; renaming them would break the
contract they name."

[0003](0003-slice-1-scope-and-exit-criteria.md) criterion 5: "**Zero
byte-machine references in the build/test tree** (docs and attribution surfaces
exempt) … enforced by a registered rename-audit spec."

[0002](0002-byte-machine-consumption-and-abi.md) foresaw the collision in its
own words — "when later slices import `(byte-machine runtime)`" — without
resolving it, because in Slice 1 no such reference existed and the audit's flat
prohibition cost nothing.

M2 adds the generator as a submodule at `vendor/byte-machine` and builds the
first grammar. Two kinds of reference become unavoidable in scanned files:

- the **submodule path**, which the build must name to put the generator's
  `src/` on Chez's library path;
- **R6RS library names** — `(byte-machine graph)`, `(byte-machine verify)`,
  `(byte-machine compile)`, `(byte-machine runtime)` — which test programs must
  import by their real names.

Measured, not assumed: adding the library-root variable to `test/CMakeLists.txt`
turns the audit red with "upstream project token leaked into
'test/CMakeLists.txt'". The prohibition as written cannot coexist with the
dependency it was written alongside.

## Decision

1. **The audit's question changes from "does the token occur?" to "does every
   occurrence match a declared legitimate form?"** It remains a registered check
   over the same scan surface; only the predicate moves.
2. **Three forms are legitimate, and no others**:
   - `vendor/byte-machine`, and the library collection inside it
     `vendor/byte-machine/src/byte-machine` — the submodule path fixed by
     [0005](0005-byte-machine-pinned-by-gitlink-generated-abi-5.md);
   - `(byte-machine <name>)` — an R6RS library reference;
   - `byte-machine-make-compiled-machine`, with an optional `/vN` suffix — the
     generated-runtime constructor, named by the lane that asserts the ABI and
     by the one that asserts the retired `/v1` and `/v2` tombstones are not
     emitted. Item 4 below predicted this one; it was added when the audit went
     red on the slice that needed it, which is the intended sequence.
   Every other shape still fails: a `byte_machine_*` function, a
   `BYTE_MACHINE_*` variable, a `ByteMachine*` filename, a bare hyphenated
   token in a test name, diagnostic prefix or collection directory. Those are
   what 0001's rename map moved and what criterion 5 exists to keep moved.
3. **The narrowness is itself witnessed.** A declared mutation plants a
   forbidden token *immediately adjacent to* a legitimate one, so an allowlist
   that leaked into a blanket permission is caught. An exemption no test can
   fail is an exemption that will widen.
4. **A new form is added by amending this record, never by a quiet edit.** The
   next legitimate shape — most likely `byte-machine-make-compiled-machine` in
   a program that constructs a parser — is added when a slice actually needs
   it, with the audit's red lane as the prompt.

## What this rules out

- Renaming the dependency's own identifiers to satisfy the audit, which 0001
  item 4 forbids and which would break the contracts those names denote.
- Exempting `test/CMakeLists.txt`, or the whole Scheme lane surface, from the
  scan. The leak class criterion 5 catches — a file copied from upstream
  carrying its names — lives in exactly those files.
- Deleting the audit because it now has an exception. It caught a real miss on
  its first clean-tree run in Slice 1 and caught this work leaking a token into
  a new cmake module in M1; a check with two declared holes is worth more than
  no check.
- Reading criterion 5 as satisfied by "no *accidental* references". The audit
  judges form, not intent.

## Consequences

- The audit's implementation strips the declared forms before scanning, so the
  allowlist is one place and is visible in the diff when it changes.
- The CMake mutation suite's declared totals move by one and are **recounted
  from the rewritten manifest, never predicted** — the standing sub-decision in
  0003.
- Criterion 5's spirit is preserved and its letter is narrowed: the tree still
  carries no *ported* upstream names, which is what the rename was for.
