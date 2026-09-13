# chez-httparse — subagent-driven development ledger

SLICE 1 — HARNESS PORT (byte-machine harness → chez-httparse). Branch
feat/gate0-harness-port.

Plan: .plans/2026-08-28-gate0-slice1-harness-port-design.md
Decisions: .plans/decisions/0001..0003 (Gate 0, 2026-08-28)
Base at start: 1e0c336 (local main; origin/main is behind by two commits).

Gate 0 complete 2026-08-28: naming + rename map (0001), byte-machine
consumption + generated ABI v2 target (0002), Slice 1 scope + exit criteria
(0003). Port map derived from a six-reader survey of the byte-machine tree at
commit 9561fa2 plus a completeness critic; the one open naming question the
survey surfaced (bare `byte-machine` token mapping) is settled by 0001.

Measured environment for this slice (2026-08-28, Darwin 25.5.0 arm64):
CMake/CTest 4.3.3; Chez 10.4.1 threaded (machine-type tarm64osx, brew,
binary name `chez`).

Slice 1 harness port, local phase complete 2026-08-28 (commits f49bd3a,
96ff723 + docs): 41 files ported under the 0001 rename map (six passes:
ByteMachine/BYTE_MACHINE/BYTE-MACHINE/byte_machine/byte-machine/_bm_,
1,696 replacements), test/CMakeLists.txt rewritten minimal (35 lanes),
SchemeMutationSuite rewritten to the harness passes. Fresh fixtures:
fingerprint sample `chez-httparse\n` (hex 1f2902297117b4a3, measured under
Chez 10.4.1 and cross-checked against an independent Python
reimplementation), regenerated stale-root copy. New rename-audit spec
(watched red on a planted token, then green; its first clean-tree run
caught a real miss: the fused wrong-prefix name in HttparseTestingSpec) —
witnessed by MutationSuite mutation 73. Upstream decision/plan citations
re-anchored with an "upstream" qualifier; Chez floor re-justified by this
repo's CI cells.

Exit criteria 1-3 and 5 measured green locally (make dev/test/test-all
35/35, no-scheme 9/9, closing rg sweep clean). Criterion 4 met 2026-08-28:
CI run 33213389847 on PR #1 (draft) completed success on both cells
(macos-arm64 brew cell; linux-amd64 source-built 10.4.1 cell including the
no-scheme step), 4m40s.

SLICE 1 EXIT CRITERIA: all five met. Awaiting review; closing ritual not
run (PR #1 left as draft for the human pass).

MERGE GATE (2026-08-28): PR #1 squash-merged as 99839ab "feat: Gate 0 +
Slice 1 — bootstrap on the byte-machine harness (#1)". Clean rebuild of
merged main: release preset 35/35, no-scheme preset 9/9 (Darwin 25.5.0
arm64, Chez 10.4.1 tarm64osx, CMake 4.3.3). CI on the PR head: run
33213389847, both cells success.
https://github.com/Kiyomi-Computation-Systems/chez-httparse/pull/1

CLOSING RITUAL COMPLETE (2026-08-28; steps 1-4). Step 1: squash merge of
PR #1 (origin/main was first fast-forwarded b3fc6d8..1e0c336 so the squash
base was current). Step 2: local main fast-forwarded to 99839ab. Step 3:
feat/gate0-harness-port deleted locally (-D after an empty diff against
main) and on origin. Step 4 (retrospective, not a summary): what held up —
the survey-first port map made the rename mechanical and the ported
mutation suites did their job as the safety net (SITES caught nothing
because the literals moved in lockstep; the totals checks forced honest
recounts, 118->59 and 72->73 measured rather than carried). What nearly
slipped — two rename-miss classes the four-pass map cannot see (a fused
token with no separator; a token split across a comment line break), both
now Traps in AGENTS.md, and the first was caught by the new rename-audit
spec on its first clean-tree run, which is the prefer-a-check rule paying
for itself immediately. Standards routed to AGENTS.md this close: a
pointer to this ledger (nothing in the repo previously told a fresh
session it exists) and the push-main-before-squash-merge caveat learned in
step 1. Nothing routed to memory: every finding is recorded in the tree
(AGENTS.md, the ADRs, this ledger), which is where the discipline says it
belongs.

GATE 0 — HTTP PARSER MILESTONES (2026-09-13). Branch
docs/gate0-http-parser-milestones.

Plan: .plans/2026-09-13-gate0-http-parser-milestone-plan.md
Decisions: .plans/decisions/0005..0010

Survey basis: byte-machine at v0.1.0 (tag c38e76f; its main is 4 docs-only
commits ahead at e9f8d9c) and llhttp at v9.4.3 (commit ee51043, one past the
tag), read locally. Primitive-by-primitive check of byte-machine against
HTTP/1 needs: spans, uint64 fields with checked accumulation (base 10 and
16), counted consumption, decision callbacks, pause/resume, and absolute
stream offsets all match. ONE GAP FOUND: no transform or case-folding
primitive, so case-insensitive header-name matching cannot use
make-sequence-dispatch-node. Recorded as the shakeout's first finding
(0006), expected to surface in M4, design deferred to that slice.

0002's ABI clause was found stale and is superseded by 0005: upstream
current-abi-version is 5 (runtime.sls:85), construction is through one
unversioned byte-machine-make-compiled-machine, and /v2 is a tombstone that
refuses every version (runtime.sls:137-145). A slice written against 0002 as
it stood would have called a procedure whose contract is to refuse.

Corpus measured on this tree, not carried forward: 253 HTTP fixtures in 23
files (288K), 1:1:1 meta/http/log; 21 URL fixtures in url.md, which carry no
required meta; 22,598 input bytes, median fixture 63, longest 2,042; 4,754
expected trace lines in ~20 shapes. Full scan (every chunk size 1..len) is
21,326 parser runs, ~7.2M bytes; whole-buffer-only is 253. Strict-mode
partition: 190 in v0.1 scope (124 request + 66 response), 37 lenient, 24
pause, 2 skipBody, plus the 21 URL. Trace-depth ceilings per milestone
measured and tabled in the plan.

Two loader constraints found by replicating the upstream decoder in an
independent script rather than reading its source alone: five fixtures carry
prose BETWEEN the http and log blocks (four in request/connection.md, one in
response/sample.md), so association must be by markdown section and not by
adjacency; and zero fixtures use the ${...} inline-JavaScript escape the
upstream driver supports, so 0007 has the loader refuse it rather than
implement it. Zero fixtures contain a NUL byte (inputs reach the reference
binary as C strings).

GATE 0 OPEN: decisions recorded, plan written, no code. M1 (the corpus
harness, with no parser) is the next slice.

GATE 0 SPIKE (2026-09-13): the case-insensitivity gap was measured, not
argued. A trie of byte-dispatch nodes with a two-element byte set per letter,
generated programmatically, was built against byte-machine at the 0005 pin and
run through the GENERATED lane (emit, load, feed), not only the interpreter.
Header names (content-length, transfer-encoding, connection, upgrade): 52
nodes, 22,118 emitted bytes. Connection values (keep-alive, close, upgrade):
28 nodes, 11,489 bytes. chunked: 11 nodes, 4,368 bytes. All verify and
compile on the public v0.1 API. Behaviour correct across case, and correct at
the boundaries — "Connection-Foo:" and "conten:" both fall through rather than
matching.

Two findings corrected 0006 as first drafted. (1) The workaround is NOT
semantically lossy: a trie with an explicit terminator disambiguates
close/closed in both cases, where make-sequence-dispatch-node would reject
that pair as ambiguous-sequence-prefix — the trie is strictly more expressive
than the construct it replaces. What is given up is a check on the builder,
not a guarantee about the grammar. (2) A naive upstream primitive — a
case-insensitive flag on make-sequence-case — would inherit that same
rejection and fail on close/closed, so it would be worse than what we can
build today. That is a real constraint on the eventual design, found only
because a grammar pressed on it, which is 0006 item 3 paying for itself at
Gate 0 rather than at M4.

CONSEQUENCE: M4 is not blocked and no byte-machine work is scheduled ahead of
it. The primitive is scheduled after M4 lands, when the grammar can specify it
and a before/after node count (91 -> ~3 for eight keywords) can price it.

GATE 0 MERGE GATE (2026-09-13): PR #4 squash-merged as 8cad258 "docs: Gate 0
— the HTTP parser milestone plan and decisions 0005-0010 (#4)". Local main
fast-forwarded; branch deleted locally and on origin.

MERGED ON A RED CHECK, NAMED PER DECISION 0004: billing refusal, not a test
result. The linux-amd64 check on run 34760173445 reported failure with 0 steps
and no retrievable logs after 4 seconds; every run in this repository since
2026-09-07 has that same shape, including pushes to main carrying no code. The
account's Actions minutes for this month are exhausted and will refuse until
billing resets (confirmed by the maintainer). Evidence in its place, per
0004's macOS sub-decision: Darwin 25.6.0 arm64, Chez Scheme Version 10.4.1,
(machine-type) tarm64osx, CMake/CTest 4.3.3, make test-all 35/35 green in
14.50s. The change touched .plans/ and .superpowers/ only.

CLOSING RITUAL COMPLETE (steps 1-4). Step 4 (retrospective, not a summary).

What held up: measuring instead of reasoning. Two questions that looked like
judgement calls — is M4 blocked on upstream, and is the trie workaround
semantically lossy — were both answered by building the thing and running it
through the generated lane. Both answers contradicted the draft record, and
the record was corrected before it merged rather than after. Separately,
reimplementing llhttp's input decoder independently, rather than only reading
its source, surfaced two loader constraints (prose between the http and log
blocks; zero use of the ${...} escape) that a reading pass had missed.

What nearly slipped, three of them, all the same shape — a plausible claim
about someone else's code, written down before being run:

  1. Decision 0002's ABI clause named a constructor upstream has since retired
     to a tombstone. A slice written against it would have failed at
     construction. Found only by reading the pinned tree instead of trusting
     the record.
  2. "The workaround is semantically lossy" was drafted into 0006 on the
     strength of a survey. It is false: the trie disambiguates close/closed,
     which make-sequence-dispatch-node rejects outright. Caught because the
     specific claim was tested before being asserted.
  3. The first corpus census counted meta blocks and would have put 257 into
     the plan as the fixture count. Reconciling meta against http and log
     counts found url.md carries 21 fixtures behind 4 metas; the HTTP corpus
     is 253.

Standard routed to AGENTS.md this close: a claim about a dependency's
behaviour is run before it enters a decision record. This is the
prefer-a-check rule pointed outward — the existing traps are all about our own
code being surprising, and all three near-misses above were about someone
else's code being different from its documentation or from memory.

M1 (the corpus harness, with no parser) starts now on branch
feat/m1-corpus-harness.

M1 SLICES ⓪-② (2026-09-13, branch feat/m1-corpus-harness).

Slice ⓪ vendored the corpus: 24 files from llhttp v9.4.3-1-gee51043,
byte-identical, PROVENANCE with a SHA-256 per file, a registered spec watched
failing on all four defect classes (edited fixture, unrecorded file, deleted
file, dropped PROVENANCE entry), and `make corpus-refresh`. The refresh script
was written first and used to perform the initial vendor, so the first copy
and every later refresh run identical code. .gitattributes gained
test/vendor/** -text. The rename audit caught the new cmake module leaking the
generator's name into a comment — second time that spec has paid for itself on
a clean tree.

Slice ① is the input decoder, slice ② the loader. Both are pure functions with
hand-built input/output tests and both were mutation-tested: six mutations
against the decoder and four against the loader, every one turning its lane
red. The loader mutation that matters most is adjacency-modulo-blank-lines
pairing, which is the plausible wrong implementation and loses the five
fixtures that carry prose between their input and log blocks.

THREE FINDINGS, ALL THE SAME SHAPE AS GATE 0'S NEAR-MISSES — a plausible claim
about someone else's format, believed before being run:

  1. Escapes yield CODE POINTS which are then UTF-8 encoded: \xff reaches the
     parser as C3 BF, not as the byte FF. Established, not assumed —
     request/sample.md records off=49 len=8 for a seven-character value, and
     across all 253 fixtures the UTF-8 reading produces no offset exceeding
     its fixture's length while the raw-byte reading produces four.
  2. Gate 0's corpus figures were wrong. The throwaway script that produced
     them used a regex whose $ also matches before a trailing newline, so it
     stripped two newlines where the reference strips one, shortening nearly
     every fixture by a byte. Corrected from the in-tree tested libraries:
     22,930 input bytes (was 22,598), longest 2,044 (was 2,042), full-scan
     21,630 parser runs (was 21,326), ~7.28M bytes fed. Fixture counts,
     median 63 and 4,754 expected trace lines were unaffected.
  3. Decision 0007's claim that two expectation lines are regular expressions
     is FALSE. Zero are. The two /.../ lines in url.md are URL *inputs*
     (/foo\tbar/ and /foo\fbar/), miscounted by a grep that ignored block
     structure; the loader, which knows which fence it is inside, reports
     zero. The comparator may therefore compare literal text only, and the
     loader still recognises a pattern so a refresh introducing a real one is
     a red lane rather than a silent mismatch.

0007, 0008 and the milestone plan were corrected in place on this branch, each
carrying why. The run-it-first standard routed to AGENTS.md at the Gate 0 close
has now caught three more instances in the slice immediately after it.
