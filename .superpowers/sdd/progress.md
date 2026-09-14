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
