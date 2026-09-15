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

M2 SLICE ② (2026-09-13): the method table. llhttp matches the method against a
TABLE, not `1*tchar`, and the difference is observable — `MKCOLA / HTTP/1.1`
records span[method]="MKCOL" and errors at offset 5, where a tchar loop takes
MKCOLA whole and accepts it. Our grammar now reproduces that exactly.

`make-sequence-dispatch-node` CANNOT express the table: it rejects a case list
where one entry is a proper prefix of another, and GET is a proper prefix of
GET-PARAMETER — measured over llhttp's 47-name union, which is the only such
pair. So the table is a generated trie, the same shape the Gate 0 spike
measured on close/closed.

THIS IS THE SECOND INDEPENDENT REASON FOR THE SAME UPSTREAM PRIMITIVE, and it
is stronger than the first. Case-insensitive header matching merely could not
use make-sequence-dispatch-node's case-sensitivity; the method table cannot use
the construct AT ALL. Gate 0 left open whether the eventual primitive should be
a case-insensitive sequence or a trie; two independent consumers now both need
a trie with an explicit terminator, and a case-insensitive sequence would
inherit the prefix rejection and fail here. That hypothesis is no longer a
hypothesis.

The union is all 47 names including RTSP and HTTP/2: the corpus parses ANNOUNCE
(RTSP-only) into a method span and rejects it only later by the
method-versus-protocol rule, so the matcher accepts it and the compatibility
check is a separate concern.

A test feeds every one of the 47 names as a complete request line, so a trie
that dropped or mis-wired a name fails there rather than in whichever fixture
happened to use it.

FOURTH INSTANCE OF THE MUTATION-DID-NOT-APPLY TRAP. The drop-a-method mutation
first reported GREEN because the edit appended a comment at a line end and
removed nothing. Re-run with an assertion that the occurrence count actually
changed, it was caught. The rule stands: assert the edit landed before reading
the result.

Evidence: make test-all 48/48.

M2 PIN BUMP (2026-09-13): byte-machine v0.1.0 -> v0.2.0, closing Slice ①'s
finding 1. That finding left open whether the empty-span gap would be answered
by a grammar shape that avoids empty spans or by an upstream change under
decision 0006. It is answered upstream: v0.2.0 delivers an empty span's data
callback exactly once with an empty range. The grammar shape was never a real
option — request/uri.md#11 records `off=9 len=0 span[protocol]=""` for
`GET /foo bar/ HTTP/1.1`, and a span that is never opened cannot produce that
line no matter how the grammar is arranged.

THE PIN IS INTRODUCED AT v0.2.0 RATHER THAN BUMPED TO IT. Decision 0005 item 3
and the brief's own section 10 both say a bump lands in its own pull request.
Neither applies yet: main carries no `.gitmodules` and no `vendor/`, because
decision 0002 item 2 puts the submodule in the first slice that invokes the
emitter and that slice (M2 Slice 0) has not merged. So this is not a bump of a
published pin, it is the initial pin landing one version later — and it goes on
the M2 branch because that is where the pin lives. The ritual's substance is
carried anyway, below; only the separate pull request is not, and it cannot be.

MEASURED ACROSS THE MOVE, NOT READ OFF THE UPSTREAM RELEASE NOTE:

  1. The two new cases were written and watched FAIL at v0.1.0 first, with the
     gap named exactly: expected `(protocol 9 0 "")` in the event list, got an
     event list with that element missing. They pass at v0.2.0.
  2. Generated ABI still 5, read out of emitted text by the existing lane.
  3. The emitted request-line parser is byte-identical at both pins — 120,218
     bytes, same SHA-256 — so no generated golden moves. This matters for the
     slice that checks in the derived artifact.
  4. Nine upstream sources differ textually between the tags. Eight have
     BYTE-IDENTICAL reader-level datum streams: compared by reading each file
     to data at both tags and diffing the written streams, they differ only in
     comments, from an unrelated documentation sweep. The only code change in
     the range is runtime.sls. Upstream claims this; it was checked here rather
     than believed, per AGENTS.md on claims about other people's code.

THE RENAME AUDIT CAUGHT THE FIRST DRAFT OF THE NEW TEST. Its comment named the
upstream project and version in prose, which is none of decision 0011's three
declared forms, and the lane failed on it. The version narrative belongs in
CHANGELOG.md, which is an exempt surface; the test comment cites the fixture
instead. The audit doing this unprompted is the check earning its place.

STILL OPEN, AND SEPARATE: request/uri.md#11 is not yet `passing` in the ratchet,
because no conformance driver exists to run it — every in-scope fixture is still
`not-yet`. The empty span was the blocker; the driver is M2 Slice 4's work.

A FINDING FOR SLICE 3, from reading the four protocol-constant fixtures. llhttp
emits `protocol complete` only on a FULL match of HTTP/RTSP/ICE, and otherwise
closes the span over exactly the bytes consumed and errors:

    response/sample.md    span[protocol]="HTTP" / protocol complete / error@4
    response/invalid.md   span[protocol]="HT"   /                     error@2
    request/invalid.md    span[protocol]="I"    /                     error@24
    request/uri.md#11     span[protocol]=""     /                     error@9

Our `protocol-loop` is an A-Z loop that closes on any non-letter and always
fires `protocol complete`, so it gets the offsets right on the first and last
rows by luck and is wrong everywhere else. Measured:

    GET / HTTX/1.1      ours: ACCEPTED, span[protocol]="HTTX", version parsed
    GET /... ICY 200 OK ours: span[protocol]="ICY", error@26
                        llhttp: span[protocol]="I",  error@24

The first is the serious one: an A-Z loop has no notion of a constant, so any
run of capitals followed by `/` is a protocol. That is a keyword table with
partial-match spans — the same primitive the trie brief asks for, now wanted a
third time, and Slice 3 cannot be honest without it.

Evidence: make test-all 48/48 at the new pin.

M2 PIN BUMP II (2026-09-13): byte-machine v0.2.0 -> v0.3.0, generated ABI 5 -> 6,
and the method table stops being a hand-built trie. Milestone 11 upstream added a
`keyword-table` node kind, opened from this project's SECOND brief. Both briefs
are now discharged: empty spans at v0.2.0, keyword tables at v0.3.0.

THE ABI LANE DID ITS JOB BEFORE ANYTHING ELSE NOTICED. Moving the pin turned
`httparse.unit.generator-abi.chez.source` red with `abi version -- expected 5,
got 6`, at the pin, not at load time in some later slice. That is decision 0005
item 5 working exactly as written, and it is why 0012 is a decision record rather
than a silent edit to a constant.

THE SWAP, MEASURED:

                          emitted bytes   states
    242-node hand trie          120,218      281
    one keyword-table            26,323       40

4.57x on the whole request-line parser from replacing ONE node; upstream measured
the table alone at 96,169 -> 2,795. 63 lines of trie construction deleted
(`string-prefix-of?`, `method-prefixes`, `method-node-name`, `method-children`,
`method-terminal?`, `method-trie-nodes`). `httparse-method-names` survives — it
is the table's content and the subject of the round-trip lane.

BEHAVIOUR DID NOT MOVE, AND THAT IS THE EVIDENCE. All 30 cases and 40 checks of
the request-line lane pass unchanged across the swap. Nothing in the test file
was weakened to accommodate it; three comments that said "trie" were corrected,
and two cases were STRENGTHENED, because the walk's failure point is now a
property of the table rather than of hand-wired fallbacks:

    FOO  / HTTP/1.1   error at 1   no method fragment   (F begins FLUSH; O ends it)
    MKCO / HTTP/1.1   error at 4   no method fragment   (prefix of MKCOL, not a name)

Both are consistent with the corpus, where `span[method]` never precedes an error
in any of the 253 fixtures — checked, not assumed.

THREE MUTATIONS, AND ONE OF THEM CHANGED WHAT I WOULD HAVE CLAIMED. Each edit was
asserted to have landed before its result was read.

  1. no-match ADVANCES instead of reexecuting — CAUGHT, and caught by the two new
     offset assertions ALONE (FOO expected 1 got 2, MKCO expected 4 got 5).
     Without them the mutation is green. That is the witness the strengthening
     was for.
  2. GET-PARAMETER dropped from the entries — CAUGHT.
  3. no-match routed somewhere that closes the span — NOT a test catch. Routing
     it to `method-close` is refused as `unreachable-node e-bad-method-open`, and
     to `e-bad-method` as `inconsistent-span-state` ("incoming edges disagree
     about the active span"). So "no fragment on the no-match path" is a
     STRUCTURAL guarantee of the verifier's span lattice, not something a test
     could lose. The first run of this mutation reported CAUGHT and I nearly
     recorded it as a test witness; it exits 255 at verification, which the
     crude "did ctest go red" check cannot tell from a failed assertion. Read the
     failure, not the exit status.

ALSO CHECKED RATHER THAN BELIEVED: upstream claims a machine declaring no keyword
table emits byte-identically but for the ABI literal. Rendering this grammar at
both pins BEFORE the swap: one line differs, one character, `5` -> `6`; same
120,218 bytes, same IR fingerprint 14988618514841855427.

A LEDGER GAP FOUND AND CLOSED WHILE FOLLOWING THE CONVENTION. Decision 0011
claims to amend 0003 criterion 5, but 0003 carried no back-link — only 0004's.
A reader of 0003 would have applied criterion 5 as written. 0003 now records
both amendments.

STILL OPEN: Slice ③ (protocol constants, version validity, the method-versus-
protocol matrix) and Slice ④ (the generated lane, the checked-in derived
artifact, the conformance driver). Every in-scope fixture is still `not-yet` in
the ratchet because no conformance driver exists yet to run one.

Evidence: make test-all 48/48, no-scheme 10/10.

M2 SLICE ③ (2026-09-13): the protocol constants, the method-versus-protocol
matrix, and the version as a PAIR. This is the slice the milestone plan named as
"the HTTP/RTSP/ICE protocol constants; version validity; and llhttp's
method-versus-protocol compatibility rules, which carry four distinct reasons
under error code 8".

THE PROTOCOL IS A KEYWORD TABLE FOR A SECOND REASON BEYOND THE METHOD'S. The
method table needed one because GET is a proper prefix of GET-PARAMETER. The
protocol needs one because the span must close over exactly the bytes the walk
took, and `protocol complete` must fire only on a FULL match. Read off the four
code-8 fixtures:

    HTTPER/1.1   span="HTTP"  protocol complete@4   error@4
    HTP/1.1      span="HT"    (no completion)       error@2
    IHTTP/1.0    span="I"     (no completion)       error@24
    bar/         span=""      (no completion)       error@9

The A-Z loop that stood here reproduced the first and last by luck and neither
middle one -- and, worse, ACCEPTED `HTTX/1.1` outright, version and all, because
a loop has no notion of a constant. Measured before replacing it.

THE MATRIX IS A BITMASK FIELD, NOT A GRAMMAR FORK. llhttp's `checkMethod` is
`span.protocol.end(on_protocol_complete(load('method', accepted, failure)))` --
span end, event, THEN the branch, at the protocol's own offset and before the
version is read. Reproducing that needs the method REMEMBERED across the url, so:
one uint8 field `method-protocols`, one bit per protocol, `store`d by the
keyword table's entry target and tested with `mask-any` at each constant. The 47
entries collapse to FOUR store nodes, one per distinct mask (1 HTTP, 2 RTSP,
3 both, 5 SOURCE), generated from the three lists rather than written out.

The three lists are llhttp's METHODS_HTTP (36), METHODS_RTSP (14) and
METHODS_ICECAST (1). Extracted from constants.ts by script, not by hand -- and
the first extraction was WRONG: it missed `'M-SEARCH': 24`, whose key is quoted
because of the hyphen, and reported a 46-name union against our 47-name table.
The mismatch is what caught it. The corrected union is exactly our table, which
is now a check.

THE VERSION IS `<digit> "." <digit>` WITH THE PAIR RESTRICTED to 0.9, 1.0, 1.1,
2.0 (llhttp's `checkVersion`, strict). Major and minor are single digits there
too -- `select(MAJOR, ...)` over a digit map -- so this is four one-byte cases
and needs no field. The digits-and-dot loop that stood here took `1.1.1` whole.
Three distinct failures at three distinct offsets, and the offsets are the point:

    HTTP/01.1   span="0"     error@12   Expected dot
    HTTP/5.6    span="5.6"   error@14   Invalid HTTP version
    HTTP/1.x    span="1."    error@13   Invalid minor version
    HTTP/x.1    span=""      error@11   Invalid major version

A rejected PAIR errors after its digit is consumed; a malformed minor errors
before. One mutation swapping those two `advance`/`reexecute` edges is caught by
exactly that difference.

DECISION 0013, FORCED BY A COLLISION INSIDE THIS SLICE. Over the corpus there are
42 distinct (code, reason) pairs across 17 codes and 41 reasons. Eight codes
carry more than one reason. And exactly ONE reason appears under two codes:
"Expected CRLF after version" is code 9 with no CR and code 2 when a CR is not
followed by LF -- both in the request line. So neither half identifies an error,
and the single `invalid-line-ending` code that stood here could not render both.
The rule is now one code symbol per llhttp number, llhttp's reason verbatim, and
identity is the pair. `bad-url` is the one placeholder left and is named as one.

MEASURED:

                     emitted bytes   states   cases   checks
    after Slice ②           26,323       40      30       40
    after Slice ③           38,585       79      50       82

Still 3.1x smaller than the 120,218 the hand trie emitted, while doing
considerably more.

TEN MUTATIONS. Seven caught by tests: ICE checking the HTTP bit; OPTIONS dropped
from the RTSP list; major 1 accepting any minor digit; the rejected-pair error
moving to `reexecute`; the protocol no-match firing a completion event; the
CR-without-LF failure reporting the no-CR code; the version separator becoming a
comma. Three REFUSED AT VERIFICATION rather than by a test, all for the same
reason -- deleting a path makes its error node unreachable: merging the two CRLF
errors, making the dot optional, dropping RTSP from the table. Recorded as
structural, not as test witnesses. Each edit was asserted to have landed.

FINDINGS FOR LATER SLICES, measured not assumed:

  1. HTTP/0.9. `GET /` with no version at all is request/sample.md "No HTTP
     version": url complete at 7, then straight to `headers complete` with
     `v=0/9`. It is llhttp's `url.exit.toHTTP09` branch and it needs `headers
     complete`, so it belongs to M3/M4, not here.
  2. PRI. `PRI * HTTP/1.1` parses the version fine and then errors at 24 with
     code 23 "Pause on PRI/Upgrade". Pausing is deferred by decision 0009, so
     the `req_pri_upgrade` branch is deliberately not built.
  3. Multiple spaces before the url. llhttp's `req_spaces_before_url` loops on
     SP, so `GET  /` is legal there and not here. ZERO of the 274 fixtures
     exercise it -- checked -- so it is not a corpus parity gap, and it belongs
     to whichever slice builds the url properly.

STILL OPEN: no conformance driver exists, so every in-scope fixture is still
`not-yet` in the ratchet. That is Slice ④.

Evidence: make test-all 48/48, no-scheme 10/10.

M2 SLICE ④ (2026-09-13), first half: the trace adapter, the conformance driver,
and THE RATCHET MOVES. Nine fixtures go from `not-yet` to `passing`.

THE ADAPTER IS TWO HALVES IN ONE FILE, exported separately so each is judged
alone: two pure rename tables (callback -> llhttp's trace words, our error code
symbol -> llhttp's number) and a recorder that drives them from the generated
runtime's callback protocol. Its own lane runs on hand-built events with no
parser, per decision 0008 item 4, and most of what it checks is what the tables
REFUSE -- an unknown callback, a span callback handed no bytes, an error code
with no row. `unexpected-eof` deliberately has no row: llhttp prints nothing at
all when input runs out mid-token, so renaming it to a number would invent a
line the oracle never records.

THE DRIVER HONOURS TWO THINGS THE CORPUS SPECIFIES AND WE HAD NOT BUILT. First,
llhttp's own harness calls `llhttp_finish` only for the `*-finish` fixture types
(test/fixtures/index.ts), so the driver does too -- finishing unconditionally
would invent an end-of-input error. Second, an adapter REFUSAL is reported as a
failing fixture, not a crashed lane: the parser produced something the oracle's
vocabulary has no word for, which is exactly a conformance failure.

PROMOTED, all nine at every chunk size the selection runs:

    request/invalid.md#1    GET ... ICE/1.0        Expected SOURCE method for ICE
    request/invalid.md#2    GET ... IHTTP/1.0      Expected HTTP/, RTSP/ or ICE/
    request/invalid.md#3    PUT ... RTSP/1.0       Invalid method for RTSP
    request/invalid.md#4    ANNOUNCE ... HTTP/1.0  Invalid method for HTTP
    request/invalid.md#14   MKCOLA / HTTP/1.1      Expected space after method
    request/invalid.md#19   GET / HTTP/5.6         Invalid HTTP version
    request/invalid.md#21   POST / HTTP/1.1<LF>    Expected CRLF after version
    request/sample.md#13    GET / HTTP/1.1<CR>L    Expected CRLF after version (strict)
    request/uri.md#11       GET /foo bar/ ...      the empty protocol span

Ratchet: 9 passing / 181 not-yet / 84 deferred.

THE DRIVER FOUND A REAL PARITY BUG ON ITS FIRST RUN, which is what it is for.
`request/invalid.md#21` records `version complete` at 15 and the error at 16 --
ONE PAST the bare LF. llhttp `.match('\n', ...)` into a lenient test that strict
mode refuses, and a match CONSUMES; its `.otherwise` does not. So the two
line-ending failures land one byte apart. Our `expect-cr` reexecuted both, and
the Slice ① test asserting offset 14 had taken that number from our own
behaviour rather than from a fixture. Corrected, and the corrected case is now
pinned by the fixture that records it plus a second input for the not-consumed
side.

THE AOT TWINS FOUND A BUILD-LAYER GAP ON THEIR FIRST RUN. The generator-abi
lane's comment promised the source/aot pair "returns with the first real
grammar"; registering it surfaced that the aot RUN command names an
`--object-dir` for the harness and src roots but not for the generator, and the
compile step never created that directory either. No aot lane had ever imported
a generator library, so nothing had exercised it. It failed as `library
(byte-machine runtime) not found` -- a broken-import shape, not a broken-build
shape. Fixed, pinned in HttparseSchemeLaneSpec's exact command line, and given a
mutation (a plausible copy-paste: the third dir points at src). CMake mutations
74 -> 75, recounted from the file.

TWO VOCABULARY ADDITIONS, both deliberate. `conformance` joins the test layers
as this project's own -- byte-machine's eleven do not name corpus conformance --
and `HTTPARSE_TEST_SELECTORS` is a new label category holding `full-scan`, so
the pr preset can exclude the every-chunk-size lane that decision 0008 item 5
puts on release. The label validator refusing `full-scan` is what forced the
category to be declared rather than smuggled in.

WHAT THE 17 REACHABLE FIXTURES ACTUALLY NEED. Measured over every in-scope
request fixture whose expected trace ends inside the start line:

    9  pass now
    5  need the header section -- code 10 "Invalid header token", the error is
       on a header field byte (content-length#15, invalid#11 #12 #13 #15)
    1  needs it too -- invalid#20, code 30 "Unexpected space after start line"
    1  needs the url sub-parser -- uri#7, code 7 "Invalid char in url path"
    1  needs pausing -- method#15, PRI, code 23 "Pause on PRI/Upgrade"

The plan's M2 estimate was "11 terminate inside the request line, one of which
needs the header section too". The real number is 9, and the six that need the
header section are six, not one.

A NOTE ON THE CLASS DERIVATION, not acted on. `method.md#15` (PRI) and
`uri.md#7` are classed `in-scope` because their meta carries no `pause` key and
they are not url.md, yet both need a feature decision 0009 defers. Changing
`ratchet-fixture-class` would move the 190/84 split that decision records, so
this is noted rather than changed.

THE FULL-SCAN LANE'S COST SCALES WITH WHAT PASSES. A mismatching fixture
short-circuits at the first chunk size, so today the nine passing fixtures
replay 396 times under `full` and 16 under `extremes`; decision 0008's 21,630 is
the figure for a fully-passing corpus, not for today's.

Evidence: make test-all 53/53, pr 52/52, no-scheme 10/10.

M2 SLICE ④, second half: the parser ships as a checked-in derived artifact, and
the conformance gate runs IT.

`src/generated/httparse-request-line.sls` -- 38,672 bytes, library
`(generated httparse-request-line)`, importing `(byte-machine runtime)` and
nothing above it -- is emitted by `tools/emit-request-line.ss` and committed, so
what this project ships is reviewable as a diff and loadable without a
generator. `make parser-refresh` and the determinism lane run the SAME script,
the way the vendored corpus refresh does, so a refresh cannot drift from the
check that guards it.

THE GATE READS WHAT THE EMITTER WROTE. byte-machine's AGENTS.md standard: "a
'the saved artifact reproduces' test must run the artifact's OWN code, not a
re-derivation from the inputs... ask of every such check: which mutation to the
saver's OUTPUT does it miss?" So the conformance driver imports the committed
library and runs it as the gate, with the reference interpreter built beside it
from the same grammar and compared, never substituted.

Two mutations, both caught:

  1. The grammar moves and the artifact does not (an error reason reworded,
     no refresh) -- caught by the byte-for-byte re-emit.
  2. The committed artifact is hand-edited ("Invalid HTTP version" ->
     "Invalid http version") -- caught THREE ways: the re-emit, the ratchet's
     passing-fixture regression check, and the executor differential. The second
     and third are the ones that prove the gate reads the artifact; a check that
     only re-derived from the grammar would have missed both.

The request-line UNIT lane still runs the interpreter alone. That is deliberate:
its 50 cases pin exact offsets on hand-chosen inputs, and the artifact is
exercised across 190 gated fixtures by the driver, which also asserts the two
executors agree. If they ever diverge the driver says so by fixture.

A FOURTH LAYER CHECK, cheap and worth having: the artifact lane re-reads the
generated ABI out of the committed text and asserts 6 -- decision 0005 item 5's
rule applied to the file that actually ships, not only to the generator.

Evidence: make test-all 54/54, no-scheme 10/10, `make parser-refresh`
idempotent.

M2 CLOSED (2026-09-14). Squash-merged as a035812 (#6), main caught up, branch
deleted locally and on the remote, main re-verified green: test-all 54/54,
no-scheme 10/10.

CI was the billing refusal again -- run 34827434748, linux-amd64, 0 steps, no
logs, 4s. Decision 0004: a billing refusal is not a test result, and the local
run stands in its place.

REFLECTION, three standards added to AGENTS.md, each from something that nearly
entered a record wrong:

  1. "Reading a red lane" -- read the failure, not the exit status. A mutation
     REFUSED AT VERIFICATION is not a test witness; it says the verifier would
     stop you, not that a test would notice. Three of Slice ③'s ten were
     structural refusals, and one in the pin-bump slice first reported CAUGHT to
     a check that only asked whether ctest went red. This is "assert the edit
     landed" taken one step further: assert WHY it went red.
  2. "Numbers in a test come from the oracle, never from the code under test."
     Slice ①'s bare-LF offset 14 was read off our own parser, passed for two
     slices, and was wrong -- the corpus records one past the LF.
  3. "Extracting a set from someone else's source." The recogniser is what fails
     silently, and it fails by matching LESS than it should. A quoted key
     (`'M-SEARCH': 24`) cost eleven methods their class until the 47-name table
     contradicted the 46-name union. Give the extraction an invariant it can
     violate, in the tree.

M2 SHIPPED: the request line, the method table as one keyword-table node, the
protocol constants, the method-versus-protocol matrix, the version pair, the
error taxonomy (decision 0013), the trace adapter, the conformance driver with a
two-way ratchet at 9/181/84, and the parser as a checked-in derived artifact the
gate runs. byte-machine v0.1.0 -> v0.3.0, generated ABI 5 -> 6 (decision 0012).
Both upstream briefs discharged.

NEXT: M3, the header section as syntax. Six of the eight remaining
request-line-reachable fixtures are waiting on it.

M3 SLICE ⓪ (2026-09-14): the header section, strict. The ratchet goes
9 -> 29 passing, 161 not-yet, 84 deferred -- twenty fixtures in one slice.

BUILT AS ONE PIECE, deliberately. llhttp's header machine is field, colon,
OWS, value, line ending and the empty line, and none of those halves is
independently observable: a fixture needs all of them to produce a single
trace line the corpus records. The request line was built the same way in M2
Slice ①.

TWO OFFSET BUGS, BOTH THE SAME TRAP, both found by the corpus and not by
reading. llhttp `.match` CONSUMES and `.peek` / `.otherwise` do not, so an
error reached through a match lands one byte later than one reached through a
peek. Two arms I had written as `reexecute` are matches upstream:

  headers-start's space        request/invalid.md#20 records off=17 for a
                               space at 16
  value-discard-lws's SP/HTAB  obs-fold after an EMPTY value, one past the
                               whitespace

And the mirror case is real: `value-lws`'s SP/HTAB -- obs-fold after a
NON-EMPTY value -- is a peek, so it errors AT the whitespace, with a different
reason. The two obs-fold sites differ in both offset and reason, and that pair
is now two cases.

This is the third instance of the consume-or-not trap in three slices (the
bare LF after the version was the first). It is the standard AGENTS.md gained
at the M2 close, earning its place.

TWO VERIFIER RULES LEARNED THE HARD WAY. A stop terminal may not be reachable
on an EOF path (`eof-reachable-stop`) and a finish terminal may not be reached
from a byte edge (`non-eof-into-finish`). `headers complete` is a callback
node and therefore zero-width, so BOTH were refused behind it -- which the
request line's stop never tripped, because that one sat directly behind a
consumed byte. The fix is a dispatch that separates them: end of input after
the empty line is a clean end of message, and a byte is the body, which is
exactly where M4 continues.

`headers complete` IS UNRENDERABLE ON PURPOSE. Its trace line carries
`method=`, `v=`, `flags=` and `content_length=`, and two of those are M4's. The
adapter's row says `unrenderable`: the recorder still BINDS the callback --
every declaration is `required?` -- and rendering refuses, so a fixture that
reaches it fails with "adapter refused" rather than being handed a line llhttp
never writes. Same discipline as `unexpected-eof` having no number.

The executor differential had to learn the same thing: a refusal is an OUTCOME
both executors must agree about, not a crash, so it is captured as a value and
compared.

THE UNIT LANE ASSERTS llhttp's OWN TEXT. `header-section-tests.sps` renders
through the same adapter the driver uses, so an expectation is a block of lines
copied out of a fixture rather than a transliteration of one. Fifteen cases;
the first is request/sample.md#1's entire expected block minus the line M3
cannot render.

SEVEN MUTATIONS. Five caught by tests -- the space's consume, both obs-fold
arms, OWS inside the value span, and the field event firing before the colon is
consumed. Two REFUSED AT VERIFICATION and checked to be so rather than assumed:
routing the no-colon path to the span close makes `e-bad-header-token-open`
unreachable, and skipping the empty-value span makes both of its nodes
unreachable. `unreachable-node` both times, read from the diagnostic.

A BEHAVIOURAL CHANGE THE M2 TESTS FELT. A well-formed request line no longer
terminates the parse -- it runs on into the header section -- so `status-of` is
`need-input` where it was `stopped`. Six cases moved to an `accepted?` helper
that asks what they were actually claiming: no error.

Emitted artifact: 73,605 bytes, 122 states (was 38,672 / 79).

Evidence: make test-all 56/56, pr 55/55, no-scheme 10/10.

M3 CLOSED (2026-09-14). Squash-merged as f0b4d24 (#7), main caught up, branch
deleted locally and on the remote, main re-verified green: test-all 56/56,
no-scheme 10/10.

CI was the billing refusal a third time -- run 34836631842, linux-amd64,
0 steps, no logs, 3s. Decision 0004: not a test result, and the local run
stands in its place.

REFLECTION. Two standards added to AGENTS.md, and one fact moved out of prose
and into the file where the next arm gets written.

  1. "An estimate read off a grouping is not a prediction." Three milestones,
     three optimistic ceilings -- M2's row read 17 against a real 10, M3's read
     44 cumulative against a real 29 -- and the first two were treated as
     arithmetic to correct. The cause is structural: the ceilings table buckets
     each fixture by the DEEPEST EVENT in its trace, because that is the
     attribute a fixture wears on its face, while the plan asks which
     CAPABILITY the error needs. Different attributes; grouping on one says
     nothing reliable about the other. `Content-Length: 1000000000000000000000`
     buckets as header syntax and is M4's, because the span is 21 of 22 digits
     -- bounded by the overflow check, so only the accumulator can produce it.
     An estimate of this kind is a starting ORDER, and it stops being an
     estimate the moment the ratchet reports a number.
  2. "What you cannot reproduce, refuse -- and make the refusal a value." An
     instrument that fills a gap with a plausible value produces a comparison
     that is not one. `unexpected-eof` has no number and `headers complete` is
     unrenderable, and the alternatives -- omit the line, or emit it with zeros
     -- both yield a fixture result shaped like a verdict. The half that is
     easy to miss is that the refusal must be an OUTCOME, not a crash: bound
     but refusing at render, caught per fixture by the driver, captured as a
     comparable value by the executor differential. That is what lets a run
     tell WRONG from NOT YET, and it is what made this ceiling measurable.

  3. Not a standard -- a fact with a better home. The `.match` consumes /
     `.peek` does not trap has cost three offset bugs in three slices, and it
     lived only in these entries. It is now in the header of
     `src/httparse/grammar.sls`, where an arm gets translated, with the three
     instances and the note that the two obs-fold sites differ in BOTH offset
     and reason ("Invalid header value char" vs "Unexpected whitespace after
     header value") -- 0013's pair-identity, in the place it bites. Two stale
     claims in that header went with it: the scope line still said "M2: the
     request line alone", and the error codes were still described as
     structural placeholders three slices after 0013 made them llhttp's.

M3 SHIPPED: the header section as syntax -- field, colon, OWS, value, line
ending, the empty line -- with obs-fold rejected as llhttp's strict behaviour,
`headers complete` as an event the adapter deliberately cannot render, the
unit lane asserting llhttp's own trace text through that adapter, and the
ratchet at 29/161/84. Emitted artifact 38,672 -> 73,605 bytes, 79 -> 122
states. No new decision records; 0009 and 0013 covered every question raised.

NEXT: M4, message framing -- `Content-Length` and `Transfer-Encoding`, the
special-header NAME table behind them, and the body. Thirteen fixtures measured
as waiting on it, eleven for the framing semantics and two for the name table's
`header_field_colon` path, which consumes a space before the colon and reports
"Invalid header field char" where the general path reports "Invalid header
token" one byte earlier. The dispatch M3 put behind `headers complete` -- built
because the verifier refuses both a stop and a finish behind a zero-width event
-- is exactly where the body decision goes.

M4 SLICE ⓪ (2026-09-14, branch feat/m4-framing): `headers complete` renders.
Ratchet 29 -> 56 passing. Eighty-five of the ninety-five in-scope request
fixtures had been stopping at that one line, so making it renderable was worth
twenty-seven on its own.

DECISION 0014: the adapter may READ parser fields, never DERIVE them. llhttp's
own `llhttp__on_headers_complete` is five reads of parser state and a format
string, so a `state-line` row here is five reads of the same fields BY NAME
plus llhttp's format quoted beside them. Recomputing `flags` from the header
lines would be a second parser agreeing with the first, which proves nothing.
No default, and that matters more here than anywhere else in the layer: the
plausible default is 0, and `flags=0 content_length=0` is a line llhttp writes
for real messages, so a defaulting renderer would produce a correct-LOOKING
trace for every fixture whose flags happen to be zero.

THE METHOD NUMBER IS NOT OUR LIST POSITION. `method=%d` is the value in
llhttp's `METHODS`, assembled from eight sub-maps and one alias; our list is
alphabetical, so OPTIONS is 6 there and 21 here. Extracted by script with three
invariants: the key set equals the 47-name table, the values are exactly 0..46
with no gap or repeat, and sixteen (name, number) pairs appear on one trace in
the corpus. All three are checks in the tree.

`%x` IS LOWERCASE AND CHEZ'S IS NOT. `number->string` radix 16 gives `20A`;
the corpus records `flags=20a`. Caught by an adapter case on a hand-made field
list -- no fixture this slice claims has a hex letter in its flags, so the
corpus could not have found it until Slice ②.

Ten mutations, eight caught (one by the executor differential), two refused at
verification. Two first reported wrong: a REPLACE that kept the text it was
meant to delete read SURVIVED, because the runner's post-check asserted the
replacement's COUNT rather than the original's ABSENCE; and a mutation that was
itself structurally invalid never reached the comparison it was written for.
Artifact 73,605 -> 82,196 bytes, 122 -> 176 states.

M4 SLICE ① (2026-09-14): the special-header name table, Content-Length, and the
fixed-length body. Ratchet 56 -> 73.

The case-folded keyword table is the SECOND reason this project asked for that
primitive upstream. A no-match leaves the walk where it broke and reexecutes,
so `Content-Type` breaks at the `T` that cannot continue `content-l` and the
general loop carries on with the span still open -- the whole name lands in it
either way. `Connection-Duration` matches `connection` WHOLE and falls through
at the hyphen, which is llhttp's own comment on that node.

A SPACE BEFORE THE COLON IS A DIFFERENT ERROR ON A SPECIAL NAME: `Invalid
header field char` one PAST the space (peek, span end, `skipTo` -- and a skip
consumes) against `Invalid header token` AT it with the span still open. Two
sixteen-byte names in the test, so only the rule moves the number. This is the
only thing the table changes that this slice can observe, and it is what made
`proxy-connection`'s presence in the table checkable at all.

THE OVERFLOWING DIGIT IS CONSUMED BEFORE THE OVERFLOW IS REPORTED. llhttp
`select`s the digit and only then runs `mulAdd`, so 22 digits give a span of 21
and an error at 56. The accumulate node reexecutes, which would give 20 and 55,
so the overflow route eats one digit -- one dispatch wide. Both overflow on the
SAME digit, the twenty-first.

A CONTENT LENGTH OF ZERO IS NOT AN EMPTY BODY -- no `span[body]=""` -- which is
the opposite of what an empty header VALUE does.

Fourteen mutations, eleven caught, one survivor answered with a test. FOUR
first attempts were refused at verification, every one because collapsing a
branch removed an error node's only path; redesigned to INVERT instead, all
four were caught. THREE were caught only by the executor differential, which
fires for any grammar edit and so is not a witness that the fixtures would
notice -- the runner now re-emits the artifact for conformance runs, and all
three are caught by the ratchet's own regression check.
Artifact 82,196 -> 93,479 bytes, 176 -> 214 states.

M4 SLICE ② (2026-09-14): Transfer-Encoding, Connection, Upgrade and the flags.
Ratchet 73 -> 84.

THREE COPIES OF `setHeaderFlags`, AND NOT BY CHOICE: its three call sites are
the end of a value, the comma inside one, and the empty-value path, and the
value span is open at one and closed at the other two. The flat span lattice
refuses one node reached with two span states, so the chain is generated from a
prefix and a continuation. Third milestone in which that lattice has decided a
shape.

`close` IS NOT `closed` and `chunkedchunked` IS NOT `chunked`, both by the
keyword table's own rule. A bare transfer coding is refused AFTER the line that
reports it, because the body decision runs after the callback. The chunked arm
parks at the dispatch M5 will replace, so a chunked request's trace STOPS after
`headers complete` rather than continuing with a `message complete` llhttp
never wrote.

Eighteen mutations: fourteen caught, two refused at verification, one refused
at EMIT (new -- the emitter says so before any lane runs, and the runner had to
be taught to read that rather than crash), and two survive BY CONSTRUCTION.
The two are collapsing the sub-state back to CONNECTION and clearing CHUNKED on
a new coding; both are llhttp's, both unobservable under strict request
parsing, both re-run against BOTH lanes rather than argued from the graph, and
both now carry a source comment naming the slice that owes them a test.
Three other survivors were real gaps and are now checks: the Connection table's
case folding, the `chunked` table's, and Upgrade's own bit.
Artifact 93,479 -> 137,760 bytes, 214 -> 271 states.

M4 SLICE ③ (2026-09-14): the upgrade decision, PRI, and a leading CRLF.
Ratchet 84 -> 87.

COMPLETING THE DECISION CORE FOUND A BUG NO FIXTURE COULD. `CONNECT` with a
`Content-Length: 10` read ten bytes of body; llhttp reads none, because
`before_headers_complete` sets `upgrade` for CONNECT and the decision exits
early. The fixture that records it is one the pause gap blocks, so the corpus
lane was never going to notice.

The two upgrade arms differ -- `upgrade && (CONNECT || !hasBody)` -- so an
upgrade WITH a body reads it and pauses afterwards. That is a unit case taken
from `request/connection.md`, because the fixture that would gate it is
blocked, and without it the mutation collapsing the two arms survives.

A PAUSE CARRIES NO CODE AND NO REASON. Measured with a probe machine
(`status paused error #f`), and true at all five construction sites. llhttp's
is `p.pause(ERROR.PAUSED_UPGRADE, 'Pause on CONNECT/Upgrade')` and prints as
`error code=22`. THE SHORTCUT WAS AVAILABLE AND WAS DECLINED: an error node
gives a bit-identical trace, because no fixture resumes -- and would be wrong,
since a paused parser is resumable and an errored one is not, and no test could
tell. Third upstream brief, under decision 0006.

The mutation that makes the adapter invent the pair instead is caught by the
ratchet's SECOND direction -- seven `not-yet` fixtures start passing -- which is
the first time that half has caught an invention rather than a forgotten
promotion.

PRI is NOT a pause despite its wording: `p.error(ERROR.PAUSED_H2_UPGRADE, ...)`,
so it has a number to rename and renders today. A `.match` of the whole ten-byte
preface, so the error lands past it at 24.

Twelve mutations: nine caught, two refused at verification, one at emit, one
survivor now a check. Artifact 137,760 -> 144,172 bytes, 271 -> 294 states.

M4 CEILING, MEASURED (2026-09-14). Every one of the 37 request fixtures still
`not-yet` was run and its first mismatch read, per the standard AGENTS.md
gained at the M3 close:

  17  M5 -- chunked bodies
   9  BLOCKED UPSTREAM -- a pause carries no code or reason
   6  M6 -- the message loop (reset, `Data after \`Connection: close\``)
   3  M6 -- the finish state (`off=NULL finish=N`)
   2  M11 -- the url sub-parser

and the remaining 66 are responses, which is M7. M4 has no request fixture left
that framing alone can reach.

The prediction was "+15 that stop at `headers complete`, plus the fixed-body
share of the 63 that reach `message complete`". The result is +58. Third
milestone and third time the ceilings table was wrong -- but this one OVERSHOT
rather than fell short, which is the same defect seen from the other side: the
header-section row's fixtures mostly needed framing, and the `message complete`
row's mostly did not need chunks. The plan's table now carries all three data
points beside the caveat.

NEXT: M5, chunked bodies. 17 fixtures measured as waiting on it. The dispatch
M4 Slice ② parked the CHUNKED arm on is where `chunk_size_start` goes, and
`content_length` is already the accumulator llhttp reuses for a chunk size --
at base 16 rather than 10.

M4 CLOSED (2026-09-15). Squash-merged as 50d3b3f (#8), main caught up, branch
deleted locally and on the remote, main re-verified green: test-all 56/56.

CI was the billing refusal a fourth time -- run 34847574174, linux-amd64,
0 steps, no logs, 3s. Decision 0004: not a test result.

REFLECTION. Two standards added to AGENTS.md, one existing standard extended,
and one stale header refreshed.

  1. "Mutate by inverting a branch, not by collapsing one." In a graph where
     each error node is reached by exactly ONE path, deleting that path cannot
     be a test witness -- the node goes unreachable and the verifier refuses
     the machine before an assertion runs. Six of M4's first attempts were
     exactly that, after three in M2 and two in M3. Pointing the branch the
     WRONG WAY keeps the machine well-formed and the behaviour wrong, and all
     six were caught once rewritten. The entry also carries the survivor
     discipline: a survivor is either a missing test or a statement about
     scope, and which one is a MEASUREMENT -- re-run against both lanes, then
     recorded at the code with the slice that owes it a test.
  2. "A blocked fixture stops gating everything else it covered." The
     CONNECT-with-body bug -- ten bytes read where llhttp reads none -- was
     invisible because the fixture recording it is one of the nine the pause
     gap blocks. A deferred fixture is not just a deferred pass; it is a hole
     in the gate. Ask what else its trace was pinning and put that in a unit
     case from the fixture's own numbers.
  3. "Reading a red lane" extended: after asking WHY a lane went red, ask
     whether that check could have gone red for an unrelated reason. Three M4
     mutations were caught by the executor differential, which fires for ANY
     grammar edit -- it looks like evidence and is only evidence that the two
     executors noticed each other. A check that catches everything catches
     nothing in particular.
  4. `src/httparse/grammar.sls`'s header still said field names were opaque
     and the framing belonged to a later slice, one milestone after that slice
     ran. Rewritten, with what is still missing named explicitly -- including
     that the CHUNKED arm parks rather than pretending.

M4 SHIPPED: `headers complete` with its four numbers read off the parser
(decision 0014), the special-header name table, Content-Length with a checked
uint64 and the fixed-length body, the FLAGS bitfield from Transfer-Encoding /
Connection / Upgrade, llhttp's body decision including the upgrade arm, the
HTTP/2 preface, and a leading CRLF before the request line. Ratchet 29 -> 87.
Artifact 73,605 -> 144,172 bytes, 122 -> 294 states. One new decision record
(0014) and one new upstream brief (the pause reason).

NEXT: the pin bump. byte-machine v0.4.0 landed Milestone 12, "a pause carries a
reason", from this project's third brief -- so the gap is closed upstream and
nine fixtures are waiting on the pin. Decision 0005 item 3 makes a bump its own
pull request, and this one is of a PUBLISHED pin, so unlike M2's two it does
not ride a milestone branch. M5 (chunked bodies, 17 fixtures) follows.

PIN BUMP CLOSED (2026-09-15). byte-machine v0.3.0 -> v0.4.0, generated ABI
6 -> 7, decision 0015. Squash-merged as 77be8d0 (#9), main caught up, branch
deleted locally and on the remote, main re-verified green: test-all 56/56,
ratchet 96 / 94 / 84.

Its OWN pull request, per decision 0005 item 3 -- unlike M2's two bumps, which
rode the milestone branch because the pin had never been published. This one
carried the commit range (9c027fd..18fcc8b), the re-measurement, a CHANGELOG
entry on both sides, and a pointer to the brief that asked.

THE THIRD UPSTREAM BRIEF IS DISCHARGED, and with it all three. Nine fixtures:
connection.md #14 #18 #19 #20 #21, method.md #2 #3 #4, uri.md #9.

Upstream decided two things differently from the brief and both are better:
the reason is a DISTINCT result slot rather than the error slot -- they
rejected the error slot by name, with the failure it would cause, which the
brief had merely allowed -- and the boundary is drawn at author-declared pause
points, leaving the span-callback pauses alone. The brief did not distinguish
them.

Measured across the pin with the grammar unchanged: byte-identical but for the
ABI literal, 144,172 bytes both sides, same IR fingerprint
12284084569705248381. 144,303 once the grammar names the reason.

REFLECTION. One standard added, one extended.

  1. "Explain the behaviour in the code and the version in the changelog." The
     rename audit has caught the same shape in FOUR consecutive milestones,
     five places this time -- always a comment whose explanation names the
     dependency and its release. It never ships wrong, because the audit
     catches it; what it costs is a red lane and a rewrite every milestone.
     CHANGELOG.md is the exempt surface and the decision records hold the
     reasoning.
  2. "Mutate by inverting a branch" gained a THIRD kind of survivor. Replacing
     the pause with an error node was CAUGHT by the unit lane and SURVIVED the
     conformance lane -- all 96 fixtures still passed. That survival is not a
     gap; it IS the evidence for decision 0015 item 5, that the substitution
     is undetectable in a trace. When a mutation's outcome differs between two
     lanes, the DIFFERENCE is the finding.

NEXT: M5, chunked bodies. 17 fixtures measured as waiting on it, and nothing
upstream is outstanding.

M5 — CHUNKED BODIES (2026-09-15). Branch feat/m5-chunked-bodies.

Ratchet 96 -> 113 passing (77 not-yet, 84 deferred). ALL SEVENTEEN chunked
fixtures, which is every one the measurement at M4's close named -- and M5 has
no request fixture left that chunked bodies alone can reach. The eleven
remaining requests are M6 (nine) and M11 (two), unchanged from that
measurement.

Two slices, measured between them by running every not-yet fixture and reading
its first mismatch:

  0  the chunk reader, the zero chunk and trailers   +13
  1  chunk extensions: names, values, quoted values  +4

THE CHUNK READER ADDED NO FIELD AND NO SPAN. llhttp accumulates the size into
`content_length` and its `on_chunk_header` prints that field, so the size
shares the field a fixed-length body counts down, the data shares `span[body]`
and its end-of-input node, and the zero chunk shares `header_field_start`. The
whole of the trailer support is one field-branch on a flag and one callback
node -- trailers ARE the header section, and the flag is the only thing that
tells the empty line at the end which block it just closed.

Artifact 144,303 -> 211,520 bytes, 294 -> 358 states. ABI unchanged at 7.

TWO NEW SHAPES IN THE ADAPTER AND ONE NEW VERIFIER RULE MET.

  - `count-line`: the second kind of callback whose text carries a parser
    field, after `state-line`. One name, read off the parser and refused
    rather than zeroed when missing (decision 0014). llhttp prints it with
    `%d` on an `(int)` cast rather than the state line's `%llu`; no fixture
    carries a chunk above 51, so nothing records what it does past INT_MAX and
    there was nothing to reproduce.
  - `span-active-at-pause`: a callback node may not be reachable with a span
    open. llhttp opens the extension value's span and THEN fires the name's
    complete event; the two are zero-width and land on the same byte, so
    firing the event first is trace-identical -- and it is the order that
    stays right if the callback ever pauses.

THE MUTATION PASS FOUND SOMETHING THE FIXTURES COULD NOT. Nineteen mutations,
all inversions or wrong values, each run against both the unit lane and the
conformance lane with the artifact re-emitted. Sixteen CAUGHT in both. THREE
SURVIVED IN BOTH -- and a survivor that is the same in every lane is not the
lane-difference finding M4 recorded; it is a finding about the ORACLE.

Chased down: of the eight reasons llhttp's chunk-extension states can emit,
the corpus records TWO. `Invalid character in chunk extensions` (#10) and
`... quoted value` (#12). The other six appear in no fixture of the 274, so no
trace can judge their offsets.

What was done about it, in preference order:

  1. NOT a test asserting our own output -- that is a change-detector, and the
     `.match`/`.peek` trap has been wrong three times in this project
     precisely where no fixture looked.
  2. The grammar now names, arm by arm, the llparse IDIOM behind each of the
     six and WHERE THAT IDIOM IS MEASURED: `end().skipTo(error)` one past the
     byte (the quoted catch-all, #12); `.otherwise(error)` at it
     (chunk_size_digit's, #24); `.peek(LF, end(...))` at the LF (the header
     value's `Missing expected CR`); `.match(byte, error)` one past it
     (chunk_extensions', #10). Every one of the six is an instance of an idiom
     the corpus measures elsewhere.
  3. A CHECK, not only a note: the corpus-load lane now pins which two of the
     eight the corpus records. A refresh that brings a fixture for any of the
     six goes red, and the response is to check the arm against the new trace
     rather than to update the number. Witnessed with two mutations.

The chunk-size overflow shim is the same situation and got the same treatment:
no fixture carries `Chunk size overflow`, so the one-dispatch eat rests on the
shared llhttp production (the same `mulAdd` behind the same `select` as
Content-Length's, which #23's 22-digit value DOES measure) rather than on a
recorded offset. Having the two copies of one production differ is the outcome
worth avoiding.

Found in passing and fixed: `set(HTTPARSE_ADAPTER ...)` sat BELOW the lanes
that name it, so the header-section lane's SOURCES entry expanded to nothing
and the dependency was dropped without a word. Moved up beside
HTTPARSE_TRACE_FORMAT.

