# 0012: the generated ABI target is 6, and keyword tables replace the hand-built method trie

Date: 2026-09-13
Status: accepted
Amends: [0005](0005-byte-machine-pinned-by-gitlink-generated-abi-5.md), decision item 2
Milestone: M2 (.plans/2026-09-13-gate0-http-parser-milestone-plan.md)

## Context

[0005](0005-byte-machine-pinned-by-gitlink-generated-abi-5.md) item 2 fixed this
repository's generated ABI target at 5, and its item 5 fixed the discipline that
matters more: "The ABI number is re-read, never remembered." That discipline
worked exactly as written. Moving the pin to byte-machine `v0.3.0` turned
`httparse.unit.generator-abi.chez.source` red with `abi version -- expected 5,
got 6` before any other lane noticed, which is the failure 0005 was written to
produce.

The ABI moved because byte-machine gained a `keyword-table` node kind (its
Milestone 11, decisions 0043-0045), opened from **this project's own brief**
under [0006](0006-upstream-first-for-general-gaps.md) — the second of the two
briefs, after the empty-span change this repository picked up at `v0.2.0`. The
node lowers to one compact table walked by a new runtime op, so a generated
library that uses one depends on a runtime binding that did not exist at ABI 5;
upstream's decision 0044 bumps the version rather than let an old runtime meet a
new library as an unbound identifier.

M2 Slice ② had built the 47-name method table as a hand-generated trie of
byte-dispatch nodes, because `make-sequence-dispatch-node` rejects a case list
where one entry is a proper prefix of another and `GET` is a proper prefix of
`GET-PARAMETER`. That trie was correct and large. It is the workaround the brief
existed to remove.

**Measured here across the move, not taken from the upstream release note:**

| | emitted bytes | states |
|---|---|---|
| 242-node hand trie | 120,218 | 281 |
| one `keyword-table` | **26,323** | **40** |

- A **4.57x** reduction in the whole request-line parser from replacing one
  node; upstream measured the table alone at 96,169 -> 2,795 bytes.
- The behaviour did not move. The request-line lane's 30 cases and 40 checks
  pass **unchanged** across the swap — `MKCOLA` closing the span at `MKCOL`,
  all 47 names round-tripping, `GET` versus `GET-PARAMETER` both ways, the empty
  protocol span, and byte-at-a-time feeding.
- Before the swap, at the same pin, our machine emitted **byte-identically to
  `v0.2.0` but for the ABI literal** — one line, one character, `5` -> `6`, same
  120,218 bytes and same IR fingerprint. Upstream claims this for any machine
  that declares no keyword table; it was checked here rather than believed.

## Decision

1. **The generated ABI target is 6**, replacing 0005 item 2's 5. It is still
   reached through the unversioned `byte-machine-make-compiled-machine`, and
   0005 items 1, 3, 4 and 5 stand unchanged — including item 5, which is the
   reason this record exists rather than a silent edit.
2. **Keyword tables replace hand-built tries wherever this grammar matches a
   fixed set of names.** The method table is the first; the protocol constants
   and the header-name tables follow in their own slices. A hand-built trie of
   byte-dispatch nodes is no longer an acceptable shape for a keyword set in
   this repository.
3. **The size win is a consequence, not the justification.** The justification
   is that the grammar now says what it means: a set of keywords is declared as
   a set of keywords, and the prefix semantics live in the generator where they
   are tested, rather than in 63 lines of node-construction here where they were
   not.
4. **Both upstream briefs are discharged.** `.plans/2026-09-13-upstream-empty-span-brief.md`
   landed as byte-machine `v0.2.0` and `.plans/2026-09-13-upstream-keyword-trie-brief.md`
   as `v0.3.0`. They stay in the tree as the record 0006 item 4 requires.

## What this rules out

- Carrying "ABI 5" forward from 0005 or from any earlier prose. The number lives
  in `test/common/generator-abi-tests.sps`, read out of emitted text on every
  run; this record explains a move that the lane already enforces.
- Reintroducing a hand-built prefix trie for a keyword set, including "just this
  once because it is only three names" — the protocol constants are three names
  and they get a keyword table.
- Treating the emitted-size figures above as durable. They are a property of
  this grammar at this revision, re-measured when the grammar changes; the
  record is of the *ratio the change produced*, not of a number to assert later.

## Consequences

- Every generated artifact this project checks in carries ABI 6, and a pin that
  moves the ABI again re-baselines them. That is the cost 0005's Consequences
  already accepted, now paid once and measured.
- The 47-name list `httparse-method-names` survives the swap and stays exported:
  it is the table's content and the subject of the round-trip lane. Only the
  trie machinery around it is gone.
- Milestone 3's header-name matching has its primitive before the slice that
  needs it — byte-machine `v0.3.0` tables are case-insensitive per table, which
  was the other half of the brief's evidence.
