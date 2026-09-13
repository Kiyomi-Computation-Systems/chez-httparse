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

M1 SLICES ③-⑤ COMPLETE (2026-09-13). Trace formatter, scan schedule and
comparator, ratchet. Every library is a pure function with hand-built
input/output tests, and every one was mutation-tested: 6 against the decoder,
4 the loader, 4 the formatter, 4 the comparator/schedule, 4 the ratchet — 22
mutations, all caught.

The formatter reproduces two upstream behaviours that are not obvious and both
decide which traces match: spans split at CR and LF with an EMPTY span still
printing one empty quoted line, and contiguous fragments coalescing with the
merged line MOVED TO THE END, so anything between two fragments of one span
precedes the merged line. Merging in place would invert those two lines on
every chunked-body fixture.

Ratchet: 274 entries, 190 in scope and 84 deferred, matching decision 0009's
partition. The in-scope/deferred class is DERIVED from each fixture's own meta
and checked against the manifest, so a refresh cannot smuggle a lenient
fixture in as not-yet and have it counted against v0.1's bar.

TWO MEASUREMENT TRAPS HIT AGAIN IN THIS SLICE, both the same shape as the
earlier ones and both caught only by checking whether the mutation applied
before believing its result: a BSD sed that silently does nothing because it
does not support \b, and a manifest mutation whose replacement string assumed
single spaces where the file is column-padded. Each first reported GREEN. A
mutation that does not apply is not a passing test; the discipline is to
assert the edit landed, not to read the result.

PLAN CORRECTED: M1's bullet said the byte-machine submodule lands here. That
contradicts decision 0002 item 2 — the submodule is added in the first slice
that actually invokes the emitter, since an unused pin only rots. M1 builds no
grammar and emits nothing, so the pin and its ABI-5 assertion move to M2. The
plan was wrong and the decision was right.

M1 EXIT: all 274 fixtures load and decode; the ratchet covers them exactly
with derived classes checked; the comparator and formatter are
mutation-witnessed. make test-all 46/46, no-scheme 10/10 (Darwin 25.6.0 arm64,
Chez 10.4.1 tarm64osx, CMake 4.3.3). CI is refusing on exhausted Actions
minutes for the month, so the Linux cell cannot be observed on this branch;
that is a billing refusal, not a test result (decision 0004).

M1 MERGE GATE (2026-09-13): PR #5 squash-merged as b55750e "feat(corpus): M1 —
the corpus harness, with no parser (#5)". Local main fast-forwarded; branch
deleted locally and on origin. Merged on a red check, named per decision 0004
as a billing refusal: 0 steps, no logs, 4s, same shape as every run since
2026-09-07. Evidence in its place: make test-all 46/46, no-scheme 10/10,
Darwin 25.6.0 arm64, Chez 10.4.1 tarm64osx, CMake 4.3.3.

M2 SLICE ⓪ (2026-09-13, branch feat/m2-request-line). The generator submodule
lands at vendor/byte-machine, gitlink-pinned to c38e76f (tag v0.1.0) per
decision 0005. A new lane asserts ABI 5 by READING IT OUT OF THE EMITTED TEXT
rather than restating it — 0002's ABI clause went stale unnoticed for three
weeks because it lived only in prose. The lane also asserts the emitted library
imports (byte-machine runtime) and none of graph/verify/compile, that neither
retired /v1 nor /v2 constructor is emitted, and that two renderings are
byte-identical.

THE LATENT CONFLICT 0002 PREDICTED CAME DUE. Decision 0001 item 4 says upstream
identifiers are never renamed; decision 0003 criterion 5 says zero such
references may exist in the build/test tree. Both held only while no slice
imported the dependency. Measured, not assumed: adding the library-root
variable turned the rename audit red. Decision 0011 amends criterion 5 — the
audit's question moves from "does the token occur" to "does every occurrence
match a declared legitimate form". Three forms: the submodule path and its
library collection, an R6RS library reference, and the generated-runtime
constructor with an optional /vN suffix.

The third form was NOT anticipated into the record. 0011 item 4 said the next
shape would be added when a slice needed it, with the audit's red lane as the
prompt; that is exactly what happened, one commit later, and the record was
amended rather than the audit widened quietly.

The narrowness is witnessed by a declared mutation that plants a forbidden
token IMMEDIATELY BESIDE a legitimate one, so an allowlist that became a
blanket permission is caught. Six leak shapes were checked by hand first — a
cache variable, a function prefix, a CamelCase filename, a bare token, and two
placed adjacent to legitimate forms — all still caught. CMake mutation totals
recounted from the rewritten manifest, not predicted: the suite reported
1 pass / 74 mutations and EXPECTED_MUTATIONS was then set to 74.

HttparseSchemeLaneSpec's command-line expectation grew by one --library-root
pair, which is the lane machinery's own comment coming true: "a lane names one
library root per library family it imports, and the count grows with each
slice."

Evidence: make test-all 47/47, no-scheme 10/10.

M2 SLICE ① (2026-09-13): the request-line grammar. src/httparse/grammar.sls is
this repository's first product code — a byte-machine source machine for
`method SP request-target SP HTTP-version CRLF`, run here through the
reference interpreter.

THE EVENT OFFSETS ARE ASYMMETRIC AND THE ASYMMETRY IS REAL. Read off
request/sample.md: method, protocol and version complete fire AT their
delimiter, unconsumed, while url complete fires one byte PAST its space, which
is consumed. So `after-method` fires the event and then consumes the SP, while
`after-url` consumes the SP and then fires. All nine events for
`OPTIONS /url HTTP/1.1` land on the corpus's exact offsets, including
url-complete at 13 where the SP is at 12. Making the four uniform would shift
every url offset in the corpus by one, and that mutation is one of the three
the lane catches.

Adapter rule discovered here and needed by the conformance driver: a span
fragment's ABSOLUTE start is (parser-stream-offset - (to - from)). The
span-data callback receives buffer indices and fires having already advanced
past the bytes it is handed, so `from` is only the absolute offset when the
feed started at zero.

Two findings recorded for later slices:

  1. The runtime SUPPRESSES EMPTY SPAN FRAGMENTS (runtime.sls:682, `(if (or
     (>= from to) ...)`). llhttp does not — request/uri.md#11 expects
     `off=9 len=0 span[protocol]=""`. Reproducing that fixture will need
     either a grammar shape that avoids an empty span or an upstream change
     under decision 0006; it is not yet clear which, and the slice that hits
     it decides.
  2. Callback declarations are `required?`, so a parser must bind every one
     even when a case ignores what they report. Two test cases were written
     with an empty binding list and the parser refused them — the declaration
     doing its job.

Three mutations, all caught: making url-complete uniform with the other three,
consuming the delimiter before closing the method span, and accepting a bare
LF as a line ending.

Evidence: make test-all 48/48, no-scheme 10/10.
