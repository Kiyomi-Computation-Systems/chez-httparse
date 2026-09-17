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

CLOSING RITUAL COMPLETE (2026-09-15). PR #10 squash-merged as 45f08a0
"feat(grammar): M5 — chunked bodies, and the ratchet reaches 113 (#10)".
Local main fast-forwarded, branch deleted locally (after an empty diff against
main) and on the remote. Merged main re-verified from a CLEAN build:
make test-all 58/58, ratchet 113 / 77 / 84, and the conformance lane green
under the full scan as well as the pr preset. CI on the PR head was the
billing refusal, not a test result -- linux-amd64 failure steps=0, no logs,
3s (decision 0004).
https://github.com/Kiyomi-Computation-Systems/chez-httparse/pull/10

REFLECTION. One standard extended, one added, one trap recorded.

  1. "Mutate by inverting a branch" gained a FOURTH kind of survivor, the
     complement of M4's third. When a mutation survives in EVERY lane, suspect
     the ORACLE before the test set. A difference between lanes is about your
     checks; an agreement across them is about your evidence. Three of M5's
     nineteen survived everywhere and there was nothing to write a test
     against -- the corpus records two of eight extension reasons.
  2. NEW: "Check what the oracle covers, not only what your code does." Having
     found an arm no fixture can judge, do not assert what the parser
     currently does there -- that is `numbers in a test come from the oracle`
     with the source hidden one step further back, and the `.match`/`.peek`
     trap has been wrong three times precisely where no fixture looked.
     Instead name the IDIOM behind the arm and where that idiom IS measured,
     then pin the oracle's coverage as a check. The corpus-load case needs no
     parser, so it can be neither a snapshot nor a change-detector, and a
     refresh that brings evidence turns it red.
  3. TRAP: a CMake variable read before it is `set` expands to nothing with no
     warning, and a lane's SOURCES list is where that hides best -- the lane
     still runs and still passes.

Nothing routed to memory: every finding is in the tree (AGENTS.md, the
grammar, the corpus-load lane, this ledger).

NEXT: M6, the message loop. Nine fixtures -- five in connection.md, three in
finish.md, one in pipelining.md -- and its exit criterion is all 124 strict
request fixtures, which is the point where the server layer can begin against
this parser rather than waiting for the release.


M6 — THE MESSAGE LOOP (2026-09-15). Branch feat/m6-message-loop.

Ratchet 113 -> 124 passing (66 not-yet, 84 deferred). THE EXIT CRITERION IS
MET: all 124 strict request fixtures pass, which is every request fixture in
llhttp's corpus that decision 0009 puts in v0.1. Everything left is a response
(66) or deferred (84). This is the point the plan named as "a usable request
parser".

Three slices, measured between them:

  0  the loop: keep-alive, reset, pipelining, `closed`     +6
  1  `off=NULL finish=N` is a field, not an ending         +3
  2  the request target's two ends                         +2

THE ANSWER IS READ BEFORE THE STATE IS CLEARED.
`llhttp__after_message_complete` computes should_keep_alive, sets finish,
clears the flags and RETURNS the answer -- in that order, and the order is
load-bearing because the answer is read off the very flags it then clears. So
the test comes first in the graph and each arm does its own resetting.

The flags reset is measured by EXACTLY ONE fixture. pipelining.md#1 carries a
Content-Length on each of three messages and the duplicate test is
`flags & CONTENT_LENGTH`, so a loop that kept the flags would report
`Duplicate Content-Length` on the second message.

DECISION 0016: A `*-finish` FIXTURE PRINTS A FIELD, NOT AN ENDING. Amends 0008
item 5. `llhttp__test_finish` is one line -- `llparse__print(NULL, NULL,
"finish=%d", s->finish)` -- and `test/fixtures/index.ts` defines
LLPARSE__TEST_FINISH for exactly the two `*-finish` types. It never calls
`llhttp_finish`: no callback fires, no end-of-input state is entered.

The driver had modelled it as an ending SINCE M1 and called `parser-finish!`,
which drove this parser to its eof-targets and produced an `unexpected-eof`
the oracle never records. The adapter refused it, correctly, for four
milestones -- and that refusal is the reason three fixtures stayed honestly
red instead of passing for a wrong reason. THE REFUSAL WAS RIGHT AND THE MODEL
BEHIND IT WAS NOT, which is worth separating: a correct check does not vouch
for the theory that produced it.

Two of the three were then already byte-exact without their last line, because
an open span is flushed when a feed ends.

THE LAST TWO REQUEST FIXTURES WERE MEASURED AT M4's CLOSE AS M11's. uri.md#7
and sample.md#10 both need llhttp's url sub-parser -- and both need its
BOUNDARY rather than its structure, which is eight nodes: an illegal byte
errors with the url span STILL OPEN (so no fragment is delivered), and a
target followed by CRLF is HTTP/0.9 with no protocol span, no version span and
v=0/9. So M6's exit was met rather than amended, and M11 keeps url.md's 21
fixtures and the schema/server/query/fragment machinery.

The measurement pointed at the right MILESTONE and the wrong SIZE. That is the
ceilings table's lesson again from the other side: a grouping orders work, it
does not scope it -- and "needs X" is not "needs all of X".

`bad-url`'s placeholder reason, "invalid request target", was replaced by
llhttp's own two for that position. Checked first: no fixture in the corpus
ever recorded the placeholder.

Artifact 214,201 -> 217,945 bytes. ABI unchanged at 7.

FOURTEEN MUTATIONS, all inversions or wrong values, each run against its unit
lane AND the conformance lane with the artifact re-emitted. Thirteen caught in
both on the first attempt. The fourteenth was a COLLAPSE in disguise --
routing the illegal-byte arm to the span end made the error node unreachable,
REFUSED-AT-VERIFICATION -- and was rewritten as an inversion (the space arm
and the illegal-byte arm swapped), which two cases then caught. AGENTS.md's
"mutate by inverting" rule, earning its place a fourth time.

CLOSING RITUAL COMPLETE (2026-09-15). PR #11 squash-merged as b18751a
"feat(grammar): M6 — the message loop, and every strict request fixture
passes (#11)". Local main fast-forwarded, branch deleted locally (after an
empty diff against main) and on the remote. Merged main re-verified from a
CLEAN build: make test-all 62/62, ratchet 124 / 66 / 84, all 124 in-scope
request fixtures passing, and the conformance lane green under the full scan
as well as the pr preset. CI on the PR head was the billing refusal, not a
test result -- linux-amd64 failure steps=0, no logs, 5s (decision 0004).
https://github.com/Kiyomi-Computation-Systems/chez-httparse/pull/11

REFLECTION. Two standards extended, one tally corrected.

  1. "Claims about other people's code" now covers claims that shape how a
     LANE WORKS, not only ones entering a decision record -- and those are
     worth more, because a lane's model is load-bearing for every milestone
     after it. The driver carried "llhttp's own harness calls `llhttp_finish`
     only for the `*-finish` fixture types" from M1. It does not; the hook is
     one line and prints a field. The claim was inferred from the fixture
     type's NAME and reading it took two minutes once anyone looked.

     With it, the observation that made it last: A CORRECT CHECK DOES NOT
     VOUCH FOR THE THEORY THAT PRODUCED IT. The wrong model was protected by
     a right refusal -- the eof path produced an `unexpected-eof` the oracle
     never records, the adapter refused it exactly as it should, and three
     fixtures stayed honestly red. Nothing shipped wrong. But the red had an
     explanation and the explanation was TRUE, so nobody looked for a second
     one. When a fixture has been red for more than one milestone and you
     have an explanation, its being true is not evidence that it is complete.

  2. "An estimate read off a grouping is not a prediction" gained the other
     half: A MEASUREMENT THAT NAMES A CAPABILITY STILL DOES NOT SCOPE IT.
     M4's close put two fixtures behind M11 and was right that they need the
     url sub-parser; what they needed OF it was eight nodes against 221
     lines. "Needs X" is not "needs all of X", and the size is answered by
     reading the fixture, not the attribution.

  3. The collapse-mutation tally is now five milestones running (three in M2,
     two in M3, six in M4, one in M6).

Nothing routed to memory: every finding is in the tree (AGENTS.md, decision
0016, the grammar, this ledger).

NEXT: M7, responses. 66 fixtures -- the status line, the `status` span,
`status complete`, and the response branch of the framing table (1xx / 204 /
304, HEAD skip-body, and the `message_needs_eof` arms M6 left to it, which is
the whole of what `should_keep_alive` does not yet read). Its exit is
decision 0009's v0.1 bar: 190 cumulative.



M7 — RESPONSES (2026-09-15). Branch feat/m7-responses.

Ratchet 124 -> 190 passing, 0 not-yet, 84 deferred. THE EXIT CRITERION IS MET
EXACTLY: 190 is decision 0009's v0.1 bar, every strict fixture in llhttp's
corpus passes, and everything left is deferred with a reason -- 37 lenient,
24 pausing, 21 url sub-parser, 2 skip-body.

Two slices, measured between them:

  0  the type switch and the status line      +43
  1  the response framing table               +23

THE MEASUREMENT BEFORE SLICE 0 WAS DEGENERATE, and saying so is the point.
Every one of the 66 failed at LINE 1 on the FIRST BYTE, because there was no
response parser at all; `first-mismatch` had nothing to partition. So M7 is
the one milestone whose count came off the ceilings table and was right, and
that is because the milestone's boundary IS the request/response split rather
than because bucketing on the deepest event predicted anything. The table's
row now says so.

DECISION 0017: A PARSER CANNOT BE STARTED IN A MODE. llhttp parses both kinds
with one machine and one entry, and which start line it reads comes from
`s->type`, a field the embedder writes before the first byte --
`llhttp__test_init_response` is one line. byte-machine exports
`parser-field-ref` and no writer, and a field's initial value belongs to the
MACHINE, so two parsers from one machine cannot start in two modes. Three ways
out, priced:

  emit the graph twice        doubles a 234 KB artifact for one integer
  a second entry node         refused: unreachable-node for the other mode
  a decision callback         three nodes -- what shipped

`on-message-type` is `required?`, is asked exactly where llhttp's `switchType`
sits, and its branches STORE llhttp's own number -- so the callback configures
and the field is still the state, read by the protocol fork, the version fork,
`before_headers_complete`, `message_needs_eof`, the body decision and the
adapter's `headers complete` line. Its fall-through is a refusal with no
llhttp number, the `unexpected-eof` treatment, and PAUSING IS NOT ANSWERING:
the pause continuation is that same refusal, because re-entering the node
would ask again and the verifier refuses the zero-progress cycle outright.

Filed upstream as this consumer's FOURTH brief
(.plans/2026-09-15-upstream-parser-mode-brief.md), with the part worth
designing named: what `parser-reset!` does with a mode. A reset that restores
the declared initials and forgets the mode is the same bug as a default,
arriving later. Nothing waited on it.

TWO SUBGRAPHS ARE NOW SHARED WHERE llhttp WRITES THEM TWICE -- the three
protocol constants and the four version pairs -- each with a zero-width branch
on `type` where llhttp forks. One definition of what `HTTP` is and which
versions are legal, so a response cannot drift from a request over either.

`message_needs_eof` IS THE HINGE OF SLICE 1 and is generated at each of its
two call sites, for the same reason `setHeaderFlags` has three copies. M6
could omit `should_keep_alive`'s last line because the function is
unconditionally 0 for a request; for a response it is the difference between
a connection that restarts and one that does not. With it comes
`body_identity_eof`: finish rises to SAFE_WITH_CB, the body span opens and
never closes, and there is no `message complete` -- what ends such a message
is the connection.

LLHTTP'S THREE `message complete` SITES ARE NOW THREE HERE. Collapsing them
into one with an upgrade test is safe for every fixture in the corpus, because
"return 1" implies upgrade everywhere except a 101 with no upgrade header and
"return 0" excludes it everywhere. It is not safe for real input, and the
bytes nobody recorded are the point.

THE PLAN'S M7 SECTION SAID "HEAD skip-body" AND SHOULD NOT HAVE. skipBody is
one of decision 0009's own deferrals -- two fixtures -- and the ratchet has
carried them as `deferred skip-body` since M1. The plan was wrong and the
ratchet was right, which is what 0009 item 4 means by "not a judgement call".
The grammar says which condition the skip-body milestone owes a branch.

THIRTY-THREE MUTATIONS, each an inversion or a wrong value, run against its
unit lane and -- for every survivor -- the conformance lane as well, with the
artifact re-emitted so a fixture's trace has to notice rather than the
executor differential. One was a COLLAPSE in disguise (a three-digit chain looped back to
its first digit, orphaning the state after it, REFUSED-AT-VERIFICATION) and
was rewritten as two wrong values, both caught. Sixth milestone for that trap.

THREE SURVIVED EVERY LANE AND ARE ONE FINDING. llhttp asks two overlapping
questions about a response: the body decision names 100, 102, 103, 204 and 304
exactly, and `message_needs_eof` names 1xx, 204 and 304 again. On a message
with no framing header the two AGREE, so either alone renders the right trace.
They part only when such a status arrives WITH a Content-Length or a
Transfer-Encoding, and the corpus records that for 304 alone -- which is why
the 304 mutation was caught and the 204 one was not, from identical code.
Response: the grammar names the overlap at each arm, and corpus-load-tests.sps
pins which of the five the oracle separates, as M5's pins which
chunk-extension reasons it records. A fourth survivor is the same shape one
field along: `bhc-switching` sets `upgrade` on a 101, and a 101 pauses by a
second independent route, so the field it sets is never read -- but an
embedder reads `parser->upgrade` after a paused-upgrade result, a surface no
trace can show, so llhttp's value stays.

AND TWO MORE THAT ARE ABOUT INVERSION ITSELF. Inverting `should_keep_alive`'s
needs-eof ANSWER was caught at once by two lanes; SKIPPING the call entirely,
on either version arm, survived its unit lane AND the whole corpus. Both mutants are well-formed and run the same fixtures.
The answer is constant on every path that reaches it -- a message needing eof
was sent to `body-eof` and never completes -- so the inversion tested the wire
and not the question. AGENTS.md now says so: a caught inversion does not prove
the branch decides anything, and the mutation that asks whether a condition
earns its place is the one that removes it.

Artifact 217,945 -> 234,216 bytes. ABI unchanged at 7. Lanes 62 -> 66: two new
unit lanes, unit.status-line and unit.response-framing, in source and aot.

CLOSING RITUAL COMPLETE (2026-09-15). PR #12 squash-merged as af570b4
"feat(grammar): M7 — responses, and the v0.1 bar at 190 of 190 (#12)". Local
main fast-forwarded, branch deleted locally (after an empty diff against
main) and on the remote. Merged main re-verified from a CLEAN build: make
test-all 66/66, ratchet 190 / 0 / 84, and the conformance lane green under
the full scan as well as the pr preset. CI on the PR head was the billing
refusal, not a test result -- linux-amd64 failure steps=0, no logs, 4s
(decision 0004).
https://github.com/Kiyomi-Computation-Systems/chez-httparse/pull/12

REFLECTION. Nothing new to route: M7's three standards and its trap went in
with the milestone's own close-out (156fba7) -- a caught inversion tests the
wire and not the question; what the oracle is missing may be an input shape
that separates two conditions rather than a reason; the collapse tally is six
milestones; and `verify-machine` RETURNS a verdict rather than raising one,
so a script that does not read the answer has checked nothing.

The one thing the ritual itself turned up is operational and is in memory
rather than here: SSH to GitHub stopped authenticating partway through, with
keys still loaded in the agent, and both remaining steps went through gh's
HTTPS path instead -- `git fetch https://...` for the catch-up and
`gh api -X DELETE .../git/refs/heads/<branch>` for the remote branch.

NEXT: M8, the release. The live llhttp differential as a local opt-in lane
(decision 0010), property and fuzz work over generated and fragmented input,
an allocation audit, a benchmark baseline, the reference documentation set,
and v0.1.


RENAME: THE PARSER IS NAMED FOR WHAT IT PARSES (2026-09-15). Branch
refactor/name-the-parser-for-what-it-parses.

`request-line` was accurate in M2 and has been wrong since M3. The shipped
artifact is now src/generated/httparse-message.sls, library
`(generated httparse-message)` exporting `httparse-message-machine`, emitted
by tools/emit-message.ss from `(httparse grammar)`'s `make-message-machine`;
the machine's own name symbol is `'httparse-message`, which is where the
library's collection name comes from. Conformance lanes follow:
httparse.conformance.message.chez.source and
httparse.conformance.message-full-scan.chez.source.

`message` was chosen because it is RFC 9110's own noun for a request OR a
response, and because the one machine still to come -- the url sub-parser --
is a different machine rather than a bigger one. So it should not go stale
the way `request-line` did.

WHAT KEPT ITS NAME. test/common/request-line-tests.sps, the lanes
httparse.unit.request-line.chez.{source,aot}, and trace-format-tests's "a
request-line trace renders in order": each is genuinely about the request
line. CHANGELOG.md and this ledger's earlier entries were NOT rewritten --
they say what was true when they were written.

THE ARTIFACT IS BYTE-IDENTICAL TO ITS PREDECESSOR ONCE THE NAME IS
SUBSTITUTED, checked by diffing the re-emitted file against a sed of the old
one rather than by eyeballing a 3,840-line diff. 234,216 -> 234,201 bytes,
which is the fifteen characters the shorter name saves. ABI unchanged at 7.
make test-all 66/66, and the rename-audit lane green.

AND THE RENAME TURNED UP A VACUOUS CHECK, which is the M7 trap found in the
tree hours after it was written down. request-line-tests.sps had

    (check "verify-machine returns" (verify-machine (make-request-line-machine)))

green since M2 and checking nothing: `verify-machine` RETURNS a
`verification-result` whether the machine is clean or not, so the check could
only have failed if the call raised, which it does not. It now reads the
verdict -- `verification-diagnostics` mapped to codes, and `verification-ok?`
-- and, because a broken grammar can never reach that case (the lane's
`make-interpreted-machine` raises at load time), a second case CALIBRATES it
against a hand-built machine with exactly one fault, asserting the verifier
answers `(unreachable-node)` and `verification-ok?` is false. Watched it fail
twice on the way: wrong arity to `make-machine`, then a second diagnostic
from a first attempt whose entry was itself a finish node.

---

## 2026-09-15 — M8, the release: the live oracle, and what it found

THE MILESTONE'S POINT WAS NEVER THE LANE. Decision 0010 argued that a live
llhttp adds exactly one thing the vendored corpus cannot: inputs nobody wrote
down. That argument is now cashed. The lane found three defects in a parser
that passes 190 of 190 in-scope fixtures at every chunk size, and none of the
three is visible to any fixture in the corpus.

**What was wrong.** (1) `message begin` was withheld when the first byte was
one no method may start with: the start node checked tchar BEFORE the event,
llhttp checks after, and no corpus fixture begins with a non-tchar. (2)
Repeated spaces between the method and the target produced an EMPTY target
span; llhttp has `req_first_space_before_url` and `req_spaces_before_url`,
one required and the rest skipped, and the same again at `req_http_start`
before the protocol. (3) The RTSP method pair was spelled `GET-PARAMETER` and
`SET-PARAMETER`; llhttp's map keys them `GET_PARAMETER` and `SET_PARAMETER`,
underscores, as RFC 2326 spells them — only `'M-SEARCH'` is quoted and
hyphenated, which is the very quoting the FIRST extraction bug was about.
That one had survived six milestones behind two checks that both range over
the set: a cardinality of 47 and a union against llhttp's map. A count
accepts any permutation of spellings, and no fixture uses either method.
Written up in AGENTS.md as the element-versus-set half of the extraction
lesson.

**How the oracle was built.** Not by writing a driver that prints llhttp's
trace format — that would be a second implementation of the very thing the
comparison depends on. `tools/oracle/build-oracle.mjs` imports llhttp's own
`test/fixtures/index.ts` by absolute path (so its bare imports resolve
against the checkout's `node_modules`, not ours) and builds the same
`http-request-c` / `http-response-c` binaries upstream's own suite uses. A
second script batches inputs to them; inputs and traces cross as hex,
because the fixture binary takes its input as an ARGV STRING and no
generated byte should ever have to survive a shell. That argv constraint is
also why the generator is held to [1,127]: a NUL cannot reach the binary and
a high byte reaches it UTF-8 encoded, which would compare two different
inputs. `generate-safe-bytes?` asserts it rather than a comment claiming it.

**The recogniser is the part that can fail silently**, so its calibration is
the corpus: all 253 recorded expected blocks, parsed back into events and
re-rendered, must come out unchanged — a check that needs no llhttp and runs
on every pull request. Seven mutations against it, six caught first time;
the seventh, a catch-all that turns an unreadable line into a mark, SURVIVED
as first written because the mutant still refused further down. Rewritten as
a real catch-all it was caught. The AGENTS.md rule about checking the mutant
is a machine that could have run, in a new shape.

**A PROPERTY THAT LOOKED UNIVERSAL WAS FALSE.** "The trace is the same
however the bytes arrive" failed for a third of generated inputs — and
llhttp fails it identically. A span still open when the parse fails is
printed only for the bytes a chunk boundary already flushed. Measured: 71 of
71 error-free parses are invariant, 13 of 169 errored ones are not. The
qualifier is the finding, the exception is pinned with llhttp's own bytes,
and AGENTS.md has a new section: a corpus is a set of cases someone chose, so
"the property holds for every case in it" is exactly what you would expect.

**What remains, named.** Two divergence classes, decision 0018: the deferred
URL sub-parser (M11), and a completion event at the exact end of the input,
in both directions — one event short where a keyword's completion fires on
its last byte, one event early where a completion fires one byte past a
delimiter. One more byte and the two agree exactly, which is why no recorded
fixture shows either. The upstream half is the FIFTH brief. The classifier
is narrow by measurement: its first version matched "exactly one extra line"
and missed the case where a completion leads to an error at the same offset,
so it now requires every extra line to sit at the end-of-input offset.
Across four seeds at 3000 cases each — roughly 110,000 probe comparisons —
zero unclassified.

**Allocation and throughput.** The audit asserts a SHAPE: a body a thousand
times longer costs 6548B against 6496B, and a feed costs 384B against 398B
whatever came before it. Its first version read `bytes-allocated`, which in
Chez is the LIVE HEAP, and reported a region as allocating -33122 bytes; the
cumulative figure is `(sstats-bytes (statistics))`, and the lane now carries
a case asserting the counter never goes backwards. Throughput is printed,
not gated, under a new `benchmark` layer: ~20k req/s whole-buffer, ~11k req/s
fed one byte at a time.

**Documentation.** `docs/api.org`, `docs/conformance.org`,
`docs/performance.org`, and a README that no longer says the parser has not
started. The README's example is an `example` lane that runs in CI. Writing
`api.org` caught two wrong claims about the runtime before they shipped:
`parser-resume!` returns a symbol, not a result, and `content-length` is
what REMAINS rather than what was declared — which the example lane now
demonstrates, because reading the field after the parse and calling it the
declared length is the obvious mistake.

`make test-all` green, ratchet 190 / 0 / 84 — decision 0009's v0.1 bar,
unchanged by three parser fixes because none of the three is something the
corpus records.

## 2026-09-15 — M9: pausing, and skip body

**The 26 fixtures v0.1 deferred, and 24 of them needed no parser at all.**
Ratchet 216 / 0 / 58, from 190 / 0 / 84. `make test-all` green at 79 lanes.

**The finding worth keeping.** The pause gap was read as a parser gap from M4
onward — nine request fixtures were "blocked upstream" because a byte-machine
pause carried no reason, and the third brief fixed that at `v0.4.0`, the pin
this project has used since before M5. What nobody re-asked was whether the
PARSER still lacked anything. It did not. Every event node already declared
its pause continuation as the place an unpaused run would have gone, so all 24
`pausing` fixtures passed on the lane's first run at every chunk size, once
the harness could say `off=N pause`. A fixture blocked on a dependency stays
blocked in the ledger after the dependency ships; the ledger does not re-ask.

**The harness mode.** Upstream decides pausing and skip-body BEFORE the first
byte: `test/md-test.ts` turns the meta into a `-D` define and caches one
compiled binary per mode. So a parser is bound in a mode here too, as a third
REQUIRED argument — `#f`, `(pause <name>)` or `(skip-body)`. One argument
rather than two flags, because `extra.c` guards `on_headers_complete` with
`#ifdef PAUSE / #elif SKIP_BODY` and a both-at-once build cannot exist; two
booleans would have made it representable.

**Two pauses, one word.** llhttp prints a callback's pause as bare `off=N
pause` and the upgrade pause as `off=N error code=22 reason="..."`. The
discriminator is the DECLARED REASON: a pause reason belongs to a node, so the
machine's pause node carries one and a callback answering `callback-pause`
cannot. Measured with a probe — `(status paused pause #f consumed 0 next 0)` —
before it entered a decision record, per the rule. A reasonless pause NOBODY
ASKED FOR is still refused; dropping that check is a mutation caught by
exactly one case and by nothing else, which is how it was confirmed to carry
weight.

**Two of fifteen pause points are not a fold of their key.**
`on_chunk_extension_name` names a macro that sits inside
`llhttp__on_chunk_extension_name_complete`, not in the span callback of the
same name. Derived by listing the function each `#ifdef LLHTTP__TEST_PAUSE_*`
encloses rather than by transforming the string — the same discipline the
method table needed, hit again.

**Skip body is a flag because the decision reads it twice.**
`llhttp__after_headers_complete` tests `F_SKIPBODY` inside the upgrade
disjunct and again as the no-body test, so a branch that jumped could serve
only one. `on-headers-complete` becomes the grammar's second decision callback
and its branch stores the flag, which is what `http.ts` does with the C return
value 1. No field writer was needed, and none exists: `parser-field-ref` is
read-only by upstream's design, and a branch key is the same expressive power
for an embedder's answer (as 0017 already found for the message kind).

**One arm had no fixture, so the oracle answered for it.** `upgrade &&
(CONNECT || SKIPBODY || !hasBody)` is in llhttp's C, and nothing in the corpus
arms skip-body on an upgrade — which is the gap decision 0010 exists to close.
A skip-body-mode binary was built from upstream's own `test/fixtures/index.ts`
with the define its `md-test.ts` adds, at the corpus's commit; its 25 lines
are the unit case's expectation, copied, and this parser matches them exactly.

TWO THINGS COST TIME THERE AND ARE WORTH KEEPING. The fixture driver's scan
range is HALF-OPEN — `82:82` runs nothing and prints nothing, which looks
exactly like a binary that failed to parse; `82:83` is the whole-buffer run.
And the committed oracle builder makes only the two plain-mode binaries,
because that is what the differential lane drives, so the skip-body pair was
a hand build from a recipe now in decision 0019. A lane that swept the modes
would be its own piece of work.

**The live differential ran clean over the M9 changes**: 1097 agreed, 45
url-machine, 4 late-complete, 0 unclassified — the two named classes and
nothing new. `drive-feed!` sits in the path of every parse, so this is the
check that it changed nothing for the un-paused ones.

Four mutations on the grammar and two on the harness, all caught: inverting
either skip-body disjunct, letting the skip-body mode print without answering,
inverting the pause discriminator, folding the two chunk-extension rows, and
dropping the armed check.

### M9 close-out

Squash-merged as `af37e7b` (PR #16), five commits. Local `main` caught up and
clean; both branches deleted locally and on the remote, which is back to
`main` alone — including `docs/retire-stale-milestone-plan-header`, left
behind by PR #15.

Verified on MERGED main, not on the branch: `make clean` then `make test-all`
green at **79 of 79** in 40s, and the opt-in differential re-run against the
live oracle at **agreed=1097 url-machine=45 late-complete=4 unclassified=0**
— the two classes 0018 names, unchanged. Reconfigured back to the default
preset afterwards, where the lane is absent rather than skipped.

CI on merged main is run `35035674698`: `linux-amd64 failure steps=0`,
23:26:36 -> 23:26:39, no logs. The billing refusal 0004 names, not a test
result — the fourth merge running.

## 2026-09-16 — M10: lenient modes, and 253 of 253

All eleven `LENIENT_FLAGS`, in seven slices. Ratchet 253 / 0 / 21, and the 21
are `url.md` alone — every HTTP fixture llhttp ships now passes at every chunk
size. `make test-all` green at 81 lanes, 82 with the opt-in oracle; the live
differential unchanged at agreed=1097 url-machine=45 late-complete=4
unclassified=0.

**The ratchet carried the milestone.** Scoping a lenient fixture by whether its
FLAGS are implemented — one list in `ratchet.sls` — turned an eleven-flag
milestone into seven slices, each one name added and its fixtures re-classed in
the same diff. The tree was never red and the manifest never ran ahead of the
parser. That is the same two-way gate from 0008 doing a job nobody designed it
for.

**The version subgraph had to come apart first**, and that is worth separating
from the feature. It fused "store this digit" with "is this an accepted pair":
only digits in 0.9/1.0/1.1/2.0 had a store node. Same three errors, same three
offsets, and no way to print `v=5/6`. Store-then-check is llhttp's own shape,
and it landed green against 216 fixtures and the live oracle before any lenient
code existed — which is why a reviewer can read the refactor separately from
the thing that needed it.

**A FLAG'S SITES ARE NOT ALL IN ONE FILE.** Four fixtures across two different
flags failed at the same line, on a test in `src/native/http.c` rather than in
the generated grammar: `llhttp__after_headers_complete` drops a request's
invalid-transfer-encoding refusal if EITHER `LENIENT_CHUNKED_LENGTH` or
`LENIENT_TRANSFER_ENCODING` is set. Grepping the TypeScript for flag names
finds nothing. The general form: a generated parser with a hand-written runtime
half has two places a mode can be read, and only one of them greps.

**Two flags can meet on one node under one reason.** A request line ending in a
bare LF is `Expected CRLF after version`, the same reason the lone-CR case
gives from the same node — so the failure looked like an OPTIONAL_LF_AFTER_CR
fork that was already there, and was the other flag's arm of the same node.
Found by a fixture, not by reading.

**A quieter wrong answer is worse than a loud one.** TRANSFER_ENCODING has two
routes into one refusal; forking one left `span[header_value]="chunked"` where
the oracle records `"chunked, deflate"` — a truncated span instead of an error,
which no exit status would have caught.

**The disable sweep is now the standard coverage question.** Each of the
thirty-two forks turned off in turn and the red lanes counted: thirty are
reached by the corpus, two are not. Both of those carry cases measured against
purpose-built lenient oracle binaries — the same technique M9 used for the
skip-body upgrade arm — and re-disabling either fails its lane.

**Upstream shipped the answer to our fourth brief mid-milestone.** byte-machine
`v0.5.0` (Milestone 13) adds settable fields and a `make-parser` inits
argument, and its changelog names the collapse in our terms: eleven optional
callbacks and twenty-two entry nodes become one settable field and one
argument. `parser-reset!` restores the embedder's initials, which is stronger
than the re-ask this tree relies on. THE PIN MOVE IS DELIBERATELY NOT IN THIS
MILESTONE: a dependency bump folded into a behaviour milestone is a red lane
nobody can attribute, and the 253-fixture ratchet can prove a behaviour-
preserving refactor changed nothing only if it is the only thing in the diff.

### M10 close-out

Squash-merged as `cccae8e` (PR #18), ten commits. Local `main` caught up and
clean; the branch deleted locally and on the remote, which is back to `main`
alone.

**A lane landed on main mid-milestone and the two composed.** PR #17 added
`httparse.harness.plan-header-audit.cmake.direct` — a check that a milestone
plan's header does not contradict its own ladder — while M10 was in flight,
and M10's records edit that same header. The squash merge took main's
generalised wording and M10's section below it, and the audit PASSES on merged
main. Worth recording because the branch-vs-main diff was NOT empty at
clean-up time: main was strictly ahead, and the three lines going the other way
were #17's improvements the branch had never seen. A non-empty diff is not by
itself a reason to keep a branch; the question is which side is behind.

Verified on MERGED main rather than on the branch: `make clean` then
`make test-all` green at **82 of 82**, and the opt-in differential re-run
against the live oracle at **agreed=1097 url-machine=45 late-complete=4
unclassified=0** — the two classes 0018 names, unchanged across an eleven-flag
milestone. Reconfigured back to the default preset afterwards.

CI on merged main: `linux-amd64 failure steps=0`, 09:42:56 -> 09:42:58, no
logs. The billing refusal 0004 names, the fifth merge running.

**What is left of Gate 0.** 253 of 274 fixtures pass. M11 — the URL
sub-parser, 21 fixtures — is the only milestone still deferred, and it is a
second machine rather than more of this one. The other outstanding piece is
not a milestone at all: byte-machine `v0.5.0` answers the fourth brief, and
moving the pin should DELETE eleven optional callbacks and twenty-two entry
nodes in exchange for two settable fields. Its acceptance criterion is unusual
and strong — 253 still pass, and the diff is smaller.

## 2026-09-16 — the pin move: the modes become settable fields

Not a milestone. No fixture moved, nothing was deferred on it, and the
acceptance criterion was unusual: **everything still passes AND the artifact is
smaller**. Both held. Squash-merged as `3521c3c` (PR #19), five commits.

byte-machine `v0.5.0` answers this project's fourth upstream brief with
settable uint fields and a fourth `make-parser` argument, so the two modes an
embedder chooses stopped being callbacks. Decision
[0021](../../.plans/decisions/0021-the-modes-are-settable-fields-and-the-fourth-brief-is-discharged.md),
amending 0005, 0015, 0017 and 0020. Generated ABI 7 -> 8.

| | before | after |
|---|---|---|
| states | 457 | **434** |
| callback declarations | 37 | **25** |
| bytes | 264 529 | **256 021** |

**The pin moved on its own commit, and that bought the strongest check
available.** With no settable field declared yet, the regenerated artifact is
byte-identical to its ABI-7 self but for the version literal, and the IR
fingerprint — computed from the IR rather than the text — is unchanged at
`2737053619879110440`. Nobody reviews 4000 regenerated lines; this answers
"is it the same machine" instead of "does it look the same". Recorded in
AGENTS.md, because every future pin move can use it.

**Two properties improved rather than merely moved.** `switch-type` sits
inside the message loop, so `on-message-type` was asked ONCE PER MESSAGE — an
embedder could have answered `request` for one pipelined message and
`response` for the next, which `s->type` cannot do upstream. The surface was
WIDER than llhttp's and is now the same width, and no fixture would ever have
said so. And `parser-reset!` now restores the embedder's initials, so a mode
no longer blinks to zero on a reset and return only because the next feed
re-asked.

**One thing got later rather than better, and is recorded as such.** A missing
`on-message-type` binding was refused by `make-parser`; a field initial cannot
be made mandatory, so a parser built with no `type` starts at the declared
`TYPE-BOTH` and refuses at offset 0 with the same code and reason — one feed
later. A case in `unit.lenient` pins it so the trade stays visible rather than
becoming folklore.

**Five tests that named the mechanism were rewritten, not deleted.** Three in
`unit.lenient`, two in `unit.adapter`, each asserting that eleven callbacks
were bound or that a counting binding fired once. All five would have been
easy to delete alongside the code, and the ratchet cannot see that loss
because 253 pass either way. Two came out stronger for the rewrite. Also in
AGENTS.md.

New pure library `(httparse modes)`, importing nothing — the first piece of
the plan's pure layer actually built, and the only one that is both build-time
and run-time. It has its own lane because a duplicated bit would make two
flags one flag and every fixture typed for either would still pass; the lane
was mutation-checked (`keep-alive` set to 2 turns it red in three checks).

**The rename audit fired three times in one session**, always on the same
shape: the generator named in prose in a test comment. AGENTS.md already
covers it. The lane catches it every time, so nothing ships wrong; what it
costs is a red lane and a rewrite.

Verified on MERGED main rather than on the branch: `make clean` then
`make test-all` green at **84 of 84**, ratchet **253 passing / 0 not-yet /
21 deferred**, and the opt-in differential re-run against the live oracle at
**agreed=1097 url-machine=45 late-complete=4 early-complete=0
unclassified=0** — unchanged through a refactor that deleted 23 states.
Reconfigured back to the default preset afterwards.

**CI: the billing refusal again, but the SIGNATURE WAS READ WRONG FIRST.**
Decision 0004's note and the four previous close-outs describe it as
`steps=0` in about 3 seconds. This PR's run took 42 seconds, which does not
match — and the duration was never the evidence. The authoritative check is
the job's ANNOTATION:

> The job was not started because recent account payments have failed or your
> spending limit needs to be increased.

    gh api repos/<owner>/<repo>/check-runs/<job-id>/annotations --jq '.[].message'

`steps=0` plus that annotation is the refusal; the elapsed time is scheduling
latency and says nothing. Merged main's run (`35091512257`, `3521c3c`) carries
the same annotation. Worth fixing here because a 42-second run that does not
match the remembered shape is exactly when someone would merge past a real
failure, or stall on a fake one.

**What is left of Gate 0.** Unchanged by this work: 253 of 274 fixtures pass,
and M11 — the URL sub-parser, 21 fixtures — is the only milestone still
deferred. It is a second machine rather than more of this one, and it is now
the only outstanding piece; the fourth brief is discharged and no upstream gap
is open.

## 2026-09-16 — M11: the url sub-parser, and the end of the ladder

Squash-merged as `a103143` (PR #20), three commits. Ratchet **274 passing /
0 not-yet / 0 DEFERRED** — the manifest's deferral list is empty for the first
time since decision 0009 wrote it with 84 entries, and Gate 0's milestone
ladder is complete. Decision
[0022](../../.plans/decisions/0022-the-url-sub-parser-is-a-second-machine.md).

**A second machine, not more of the first.** `url.md`'s fixtures carry no HTTP
framing: upstream's `test/md-test.ts` calls `buildURL()` — `llhttp.URL(p,
true)` with both exits looped back to its own entry — and passes no `-D` at
all. So `(httparse url-grammar)` is a new builder emitting a new artifact, and
the conformance driver resolves a machine PER FIXTURE from the kind the input
fence already gives it. The HTTP parser is untouched and keeps its single
`span[url]`.

**THE MACHINE WAS RIGHT ON ITS FIRST BUILD** — all 21 fixtures matched
byte-for-byte through a scratch driver before any harness existed. That is not
a claim about care; it is a property of the generator. `schema:/path` must
report at 8 rather than 7 because a failed `//` match keeps the `/` it already
consumed, and the sequence-dispatch reference says exactly that in as many
words. The fixture and the runtime agreed by construction rather than by
transcription being lucky. **When the dependency documents a cursor rule, read
it before writing the node, not after the fixture disagrees.**

**What the milestone did NOT do, re-measured rather than assumed.** The
`url-machine` divergence class is UNCHANGED at 45: `agreed=1097
url-machine=45 late-complete=4 early-complete=0 unclassified=0`. The HTTP
parser still carries its request target as one opaque span. The machine is
built the way llhttp's `url` BINARY runs it — standalone, over a bare URL —
and wiring it into the HTTP parse means joining at `entry.normal` and giving
up the single `span[url]` every `uri.md` fixture is written against.

**"The url sub-parser is done" and "the url divergence is closed" are
different sentences**, and the milestone's name invites reading the first as
the second. It got a heading in the decision record, in the plan and in
`conformance.org` for that reason. A capability that EXISTS is not a
capability that is IN THE PATH, and only the differential can say which
happened. This is the sibling of M9's lesson — there, a capability the tree
already had was recorded as absent; here, one the tree just gained could
easily be recorded as wired in.

**Three transcription traps, each pinned by something that is not an
argument.** The offset-8 sequence mismatch above; a tab refused one byte PAST
itself (upstream's `private node(name)` matches rather than peeks); and a host
ending at `?` KEEPING the `?` — `.match('?', spanEnd('host', …))` advances
before the span end runs. Reading llhttp's source lets you argue the third
either way, and no fixture has one, so it was measured against a
purpose-built url oracle and transcribed rather than repaired.

**The exits are graph the corpus cannot reach.** Not one of the 21 inputs
contains a space, CR or LF, and every node inside a URL has an edge for each.
Omitting them would make a space an ERROR where llhttp ends the URL — a
behaviour difference, not an omission. Built, and covered by six
oracle-measured cases: a space starts ANOTHER URL, and what follows is judged
from scratch (`http://host.com xyz` reports `xyz` as a *schema* span).

**Watched it fail three ways before believing it.** Removing the `?`
self-loop in a query reddens `url.md#9` and `#12`; consuming the `/` before a
path instead of peeking reddens eleven; peeking tab instead of consuming turns
both control-character cases red at offset 4 rather than 5.

Verified on MERGED main: `make clean` then `make test-all` green at **86 of
86**, full chunk-size scan included, ratchet 274/274, and the opt-in
differential re-run at the numbers above. Reconfigured back to the default
preset afterwards.

CI: the billing refusal, `steps=0` with the annotation naming it. The
correction recorded at the pin move held up — this PR's run took 2 seconds and
merged main's took 3, where the previous one took 42. **The duration is
scheduling latency and is not the signal; the annotation is.**

**What is left of Gate 0.** The ladder is done and no upstream gap is open.
Two pieces are named in the records rather than deferred, because neither is a
fixture anyone is waiting on:

- **Wiring the url machine into the HTTP request target**, which is what would
  close those 45 comparisons. It costs the single `span[url]` that every
  `uri.md` fixture is written against, so it is a corpus-visible change and
  needs its own decision.
- **A URL input generator for the live differential**, which today covers
  `request` and `response` only. M8's experience says generated input finds
  what fixtures do not — the keyword-table divergence was found nowhere else.

## 2026-09-16 — the request target is parsed, and the divergence list shortens

Squash-merged as `4697cca` (PR #21), four commits. Not a milestone: no fixture
moved. What moved is the LIVE DIFFERENTIAL, from

    agreed=1097 url-machine=45 late-complete=4 early-complete=0 unclassified=0

to

    agreed=1142 late-complete=4 early-complete=0 unclassified=0

Every one of the 45 became an agreement, nothing shifted into another class,
and the `url-machine` class was DELETED rather than left at zero. Decision
[0023](../../.plans/decisions/0023-the-request-target-is-parsed-not-carried.md),
amending [0022](../../.plans/decisions/0022-the-url-sub-parser-is-a-second-machine.md)
(whose "what this milestone did not do" section is now done) and
[0018](../../.plans/decisions/0018-a-divergence-is-named-and-witnessed-or-it-fails-the-lane.md)
(one class retired).

**The consequence worth leading with is not the count.** A message that used
to parse may now be refused — the first change in this project's history that
does that. `OPTIONS a.com:443 HTTP/1.1` was parsed to completion and is now an
error at offset 9. `api.org` and `CHANGELOG.md` lead with it rather than
burying it under the divergence numbers, because an embedder reading only the
counts would see an improvement and miss the break.

**A DESCRIPTION BUILT ONCE IS A DESCRIPTION TESTED IN ONE CONFIGURATION.** The
url subgraph was factored to build twice — separate spans for llhttp's `url`
binary, one whole-target span for the HTTP parser. The first build passed 21
fixtures. The second would not verify: `#f` as a span state meant "inside the
url, between parts", where the whole-target span IS open, and the entry nodes
run BEFORE it opens. With separate spans those two coincide, so the first
build was **correct by accident** and no amount of testing it would have said
so. `inconsistent-span-state` named the exact path. In AGENTS.md.

**CLOSING A DIVERGENCE SHOULD TURN SOMETHING RED.** The `url-machine` class
was anchored to llhttp's exact bytes for one reduced input, per 0018, so
closing it turned the witness red BEFORE anyone looked at the counts. A
classifier with only a predicate would have reported `url-machine=0` and
passed, leaving a class ready to readmit a real bug under a name that made it
look expected. The witness is kept and INVERTED — same input, same oracle,
now asserting the two traces are one list — and a CONNECT case sits beside it,
because the two entries are one field test apart and a wrong test would fail
only for CONNECT. Also in AGENTS.md.

`httparse-url-bytes`, the stand-in for `URL_CHAR`, is deleted. Its own comment
said the finer rules "belong to the slice that reproduces that error"; this
was that slice. The parser grows 434 -> 450 states and 41 912 bytes, which is
what the refusal costs.

Verified on MERGED main: `make clean` then `make test-all` green at **86 of
86**, full chunk-size scan included, ratchet **274/274**, and the opt-in
differential re-run at the numbers above. Reconfigured back to the default
preset afterwards.

**SSH BROKE MID-RITUAL AND THE MEMORY NOTE HELD.** `ssh -T git@github.com`
gave `sign_and_send_pubkey: signing failed ... communication with agent
failed` — the agent, not the key. The push, the merge's local half and the
`origin/main` ref update all failed; `gh` over HTTPS did all three. Worth
knowing the exact shape: `gh pr merge` MERGED SERVER-SIDE AND THEN FAILED on
its local fast-forward, so the PR was already merged and the branch already
deleted when the command reported an error. Check `gh pr view --json state`
before retrying anything that would merge twice.

CI: the billing refusal, `steps=0` plus the annotation, on both the PR and
merged main.

**What is left.** The ladder is done and no upstream gap is open. One piece
remains named and not deferred: **a URL input generator for the live
differential**, which still covers `request` and `response` only. The ground
just shifted in its favour — the request target now runs a twenty-node
structural machine that generated input would exercise hard, and M8's
experience is that the generated-input lane finds what fixtures do not.

## 2026-09-17 — the url is generated input too, and the second `@` was wrong (#22)

Merged as `ff60c4c`. The one piece the last close-out left named: the live
differential covered `request` and `response` only, so a twenty-node machine
with six error arms was being judged by 21 fixtures and a target pool of ten
strings that all parse. Decision
[0024](../../.plans/decisions/0024-the-url-input-generator-and-the-second-at.md),
amending [0010](../../.plans/decisions/0010-the-live-llhttp-oracle-is-local-and-opt-in.md)
(a third kind, a third binary, a seed sweep) and
[0022](../../.plans/decisions/0022-the-url-sub-parser-is-a-second-machine.md)
(the asymmetry it left).

`generate-urls` as a third producer, `url.md` entire as a mutation base, and a
third oracle binary built the way `test/md-test.ts`'s `buildURL()` builds it —
the program `url.md` was recorded from.

    agreed=1142  ->  agreed=7730 late-complete=4 early-complete=0 unclassified=0

**THE URL CASES ARE A SEPARATE RUN, NOT MORE BASES IN THE EXISTING ONE.**
Added to `bases` they would have changed every message mutant this lane has
ever produced, and a new divergence would have had two possible causes. Kept
apart, `HTTPARSE_DIFFERENTIAL_URL_CASES=0` reproduces `agreed=1142` exactly —
which is how the bisection was done rather than argued.

**IT FOUND A REAL BUG ON ITS FIRST SWEEP, WHICH IS THE POINT.** llhttp
rejects only ADJACENT `@`: `http://a@b@c/p` is a host of `a@b@c`, and only
`a@@b` is `Double @ in url`. This parser refused the second `@` wherever it
fell. Upstream builds `server` and `server_with_at` from one loop whose edges
name `server` EXPLICITLY rather than the loop variable —

    .match(USERINFO_CHARS, server)   // server, NOT node
    .match([ '[', ']' ], server)     // server, NOT node

— so the second node is ONE BYTE WIDE and any ordinary host byte re-arms `@`.
The code had read that as "the same node twice, minus one edge" and said so in
a comment. `url.md`'s "Double `@`" fixture has its two `@` ADJACENT, so
neither the corpus, nor the six oracle-measured cases, nor 274 replays at
every chunk size could tell the two rules apart. Seed 777 found it by mutating
that very fixture — inserting one byte between the two `@`. In AGENTS.md as
**a loop variable is not the node the edges name**.

**ONE SEED IS NOT A LANE**, and that is the finding about the instrument
rather than the parser. The default seed did not see the bug; three of the
five tried did:

| seed | unclassified, before the fix |
|---|---|
| 20260915 (default) | **0** |
| 1 | 20 |
| 2 | 0 |
| 777 | 8 |
| 20260916 | 17 |

`agreed=2573 unclassified=0` looks exactly like a lane with nothing to say, so
the default's green would have been read as evidence. The run is now the seed
it is given AND ITS TWO SUCCESSORS — one number still names it, any member
replays alone, and re-introducing the bug turns the DEFAULT run red at 8. The
extra seeds are derived arithmetically on purpose: picking the three that
caught this would have been fitting the lane to its own history. In AGENTS.md.

**THE FIX IS PINNED TWICE, BECAUSE THE DESCRIPTION IS BUILT TWICE.** Last
close-out's lesson applied rather than re-learned: `unit.url` for the
standalone build, where the host is `span[url.host]`, and
`unit.request-target` for the HTTP build, where the whole target is one
`span[url]`. Both expectations are the live binaries' own bytes, and both were
watched failing before the fix went in.

**The url half's sensitivity was measured three ways, not assumed.** Dropping
`#` from `fragment.match(['?','#'], fragment)` leaves ALL 86 OTHER LANES GREEN
— `url.md`'s 21 at every chunk size included — and turns this lane's
`unclassified` from 0 to 48. Resolving the `url` kind to the request binary
turns all 1431 new comparisons unclassified and `agreed` back to exactly 1142.
Handing a url case to the message machine is a runtime contract violation, not
a divergence — red, but not the red that means anything, which is the
"reading a red lane" rule biting in a new place.

**Three witnesses anchor the kind even though there is no class to name**, in
0018's shape: the same bytes read as a url and as a request are two different
traces; the exits, which no fixture in the corpus reaches; and the fragment
arm the mutation proved only this lane can see.

**A target you used to see refused now parses** — the mirror of #21's
consequence, and the same reason. `CHANGELOG.md` files it under Fixed and
`api.org` says it beside the stricter change, so an embedder reading either
one sees both directions.

Verified on MERGED main: `make clean`, then **86 of 86** at the default preset
and **87 of 87** with the oracle enabled, full chunk-size scan included,
ratchet **274 passing / 0 not-yet / 0 deferred**, differential at the numbers
above. Reconfigured back to the default preset afterwards. SSH was still down;
`gh` over HTTPS did the push, the merge and the ref update, and this time
`gh pr merge --squash --delete-branch` succeeded outright.

CI: the billing refusal, `steps=0` plus the annotation, on both the PR
(`104916213931`) and merged main (`105030545896`).

**What is left.** The PROPERTY lane is message-only. It runs on every pull
request and needs no llhttp, and both its properties — fragmentation
invariance, and the two executors agreeing — hold of the url machine as much
as the message one. Nothing yet compares `httparse-url-machine` against its
interpreted twin on input the corpus does not contain, which is the one place
a compiler bug could hide from the conformance lane. Named in 0024 and in the
plan's *Deferred*, not built.

## 2026-09-17 — both properties, both machines (#23)

Merged as `d2df9d9`. The gap the last close-out named, and the one that
mattered more than the differential's: the property lane is a MERGE GATE
where the differential is local and opt-in, so nothing compared the emitted
url parser against its interpreted twin over input the corpus does not
contain. That is the only place a compiler bug can hide from the conformance
lane, which runs both executors but only over 21 recorded url fixtures.
Decision
[0025](../../.plans/decisions/0025-both-properties-are-asked-of-both-machines.md).

No grammar change and no artifact change. All lane.

    httparse-property: error-free inputs     request=39  response=26  url=115
    httparse-property: executor comparisons  request=145 response=95  url=240

**THE FLOOR WAS RIGHT, AND ADDING A SUBJECT MADE IT WRONG WITHOUT MAKING IT
FAIL.** Both properties pass vacuously over a run that selected nothing --
"every error-free parse is fragmentation-invariant" is true of zero of them --
so both were guarded by a floor. One number over the whole run, correct while
the lane had one subject. The message kinds produce 65 error-free inputs
between them, so `> clean 20` stays green whatever the url machine does,
INCLUDING CONTRIBUTING NOTHING, which is exactly the failure the floor exists
to catch. Three floors now, one per kind, at 15 against a worst observed 26
over six seeds, with the per-kind tally printed beside them. Witnessed:
`HTTPARSE_PROPERTY_URL_CASES=0` passes the old global floor at 65 and fails
both new ones. In AGENTS.md as **a floor that guards a lane is satisfied by
its easiest member**.

**A COMMENT I WAS ABOUT TO WRITE WAS WRONG, AND CHECKING IT WAS THE WHOLE
FINDING.** The draft said `url.md`'s four `noScan` marks are exactly the
fixtures whose trace depends on chunking. True-sounding, and they ARE exactly
its four error fixtures. Measured, three of the four diverge: "Failing on
broken schema" closes its schema span before the error, so no chunk boundary
has an open span to flush early -- and llhttp does not diverge on it either,
checked against the url fixture binary at both sizes. The comment became a
check stating the two directions separately: nothing diverges UNMARKED (the
load-bearing one, since unmarked fixtures ARE scanned bit-exactly), and the
marked set `(3 15 20 21)` against the diverging set `(15 20 21)`, both written
down so a refresh that moves either fires. Folded into AGENTS.md's *claims
about other people's code*: an annotation that is a superset of what it needs
to be costs nothing until you quote it as a reason.

**Fragmentation invariance holds for the url machine on the same terms.** All
115 error-free url inputs invariant across the full ladder; drop the qualifier
and 249 url probes disagree. So the qualifier is not a message-parser quirk,
and the exception has a url twin -- `url.md`'s "Double `@`", both traces
llhttp's own output, the host span printed only at chunk sizes where a
boundary flushed it.

**The emitter mutation was chosen to leave the grammar alone.** AGENTS.md
already records that an executor comparison fires for ANY un-re-emitted
grammar edit, which says nothing about catching a compiler bug. Hand-editing
one byte case in `src/generated/httparse-url.sls` -- routing `p` in a path to
the query node -- reddens three of the four groups, including the `noScan`
one, whose diverging set becomes `(1 2 13 14 15 20 21)`.

**THE FIRST MUTATION ATTEMPT CAUGHT NOTHING, AND THAT WAS THE BETTER RESULT.**
Routing `[` from `url-server` to `url-server-with-at` changed no trace: no
pool in `generate-urls` puts an `@` after a bracket, so the edge is
unreachable from this lane's input. Recorded rather than quietly replaced with
a mutation that worked -- the generator's reach is not the machine's, and
that is a limit of the instrument worth writing down beside its successes.

Verified on MERGED main: `make clean`, then **86 of 86** at the default preset
and **87 of 87** with the oracle enabled, ratchet **274 passing / 0 not-yet /
0 deferred**, differential unchanged at `agreed=7730 late-complete=4
early-complete=0 unclassified=0`. Reconfigured back to the default preset
afterwards. SSH still down; `gh` over HTTPS did everything, and
`gh pr merge --squash --delete-branch` succeeded outright again.

CI: the billing refusal, `steps=0` plus the annotation, on both the PR
(`105035016516`) and merged main (`105037080603`).

**What is left.** Nothing named. The plan's *Deferred* section reads "Nothing"
for the first time with no asymmetry beneath it: the ladder is complete, no
upstream gap is open, and both generated-input lanes -- the merge-gated
property lane and the opt-in differential -- now cover both machines.

## 2026-09-17 — the lenient flags are combined (#24)

Merged as `b496f49`. Upstream's fixture harness picks its init hook with a
`-D` at compile time and ships one per (kind, single flag), so a PAIR of
flags cannot be asked of it at all -- 55 pairs would be 55 binaries and no
hook exists for any. Its only combination fixtures are three
`*-lenient-all` ones, and `lenient_all` sets NINE of the eleven, leaving
`spaces-after-chunk-size` and `header-value-relaxed` combined with nothing
anywhere in the corpus. Decision
[0026](../../.plans/decisions/0026-the-lenient-flags-are-combined-and-the-init-hook-is-ours.md).

`generate-lenient` as a fourth producer, `http-modes-c` as a fourth oracle
binary, and a fifth built by upstream's own harness to hold the fourth to.

    agreed 7730  ->  9557 late-complete=4 early-complete=0 unclassified=0

**THE SUBSETS WALK A SCHEDULE; THE SEED MOVES THE INPUT.** Eleven
singletons, all 55 pairs, the whole set -- 67 entries, case i takes entry
i mod 67. A random draw over 55 pairs needs hundreds of cases and "probably
covered" is not a coverage claim. Two seeds now put the same 67 subsets
against different messages, which is the shape that makes a second seed
worth running.

**THE ONE PIECE OF UPSTREAM'S HARNESS WE DO NOT CALL, AND WHY THAT IS
INSIDE 0010 RATHER THAN AN EXCEPTION TO IT.** `lenient-init.c` assigns two
integer fields and prints nothing; every trace line still comes from
upstream's `extra.c`, which is what 0010 protects -- a second implementation
of the FORMAT would make the comparison circular. But that is an argument,
so the lane measures it: `http-modes-c` must equal `http-request-c` and
`http-response-c` at no flags, and upstream's own
`http-request-lenient-headers-c` at one flag. Both watched failing.

**Two findings, neither reachable by any fixture upstream ships.** A bare LF
after a request's version needs BOTH lf flags: with `optional-cr-before-lf`
alone llhttp still refuses, at the same offset and with the same reason, and
a different code (invalid-version 9 -> strict 2), because `.match('\n')`
consumes and the lenient arm lands on a node wanting the LF again. This
parser jumped straight to the headers. Third interaction of a shape 0020
records twice.

And a THIRTY-THIRD fork: `res_status_code_otherwise` gates its LF arm on
`optional-cr-before-lf` where this parser had a flat error. 0020's sweep
measured all 32 forks -- a fork that is not there is not a site. One flag is
enough at this one, unlike the request side, because upstream's arm goes
straight to the completion. The two sites read alike and behave differently.

**THE NEW PER-MODE FLOOR CAUGHT A DEFECT IN THE GENERATOR ON ITS FIRST
RUN.** Drawn freely, 4 of 134 lenient inputs parsed without an error -- an
input dies at the first malformation its subset cannot excuse, and
fragmentation invariance is about parses that reach NO error. Half the cases
now MATCH their malformations to their subset: 4 -> 32. The free half is
where both findings above came from. This is 0025's lesson arriving one
milestone later, and this time the check found it rather than a person.

**A MUTATION THAT CAUGHT NOTHING WAS THE MORE IMPORTANT RESULT.**
`llparse-test-fixture` keys its build on the generated header, the generated
C and the ARGUMENT LIST, then skips the compile when that digest exists. Our
hook reaches it as a path, so a deliberately wrong hook produced a
byte-identical binary and a green run. The instinct was to pick a different
mutation; the different mutation would have passed too. Its content hash now
goes into the arguments as a define nothing reads. In AGENTS.md.

**AND ONE CORRECTION THIS RITUAL ITSELF TURNED UP.** The milestone was
written with `agreed=9603`, measured before the matched/free split -- which
changes the generated bytes, so their lengths, so how many chunk sizes the
ladder gives them. Merged main measures **9557**. The conclusion is
untouched; the number was wrong in the decision record, the plan, the
changelog and the PR body, and is now corrected in the three that can be.
The same slip had put a SCALED table of per-mode counts into
`property-tests.sps` instead of a measured one, and it survived a full green
suite because nothing executes a comment. Both tables have been re-measured
on merged main. In AGENTS.md as **re-measure a number after the last change,
not before it**.

Verified on MERGED main: `make clean`, then **86 of 86** at the default
preset and **87 of 87** with the oracle enabled, ratchet **274 passing / 0
not-yet / 0 deferred**, 33 lenient forks, differential at the number above.
Reconfigured back to the default preset afterwards. SSH still down; `gh`
over HTTPS did everything.

CI: the billing refusal, `steps=0` plus the annotation, on both the PR
(`105047541394`) and merged main (`105049491514`).

**What is left.** Nothing named. Both generated-input lanes cover both
machines and both modes, and the combination space upstream's harness cannot
express is walked in full every run.

## 2026-09-17 — the cost lanes in both modes, and what the ratio was hiding

PR #25 (squash `f372c00` on main; base `6ccf51e`). Decision
[0027](../../.plans/decisions/0027-the-cost-is-dispatch-position-not-grammar.md).

**Started from a wrong claim of mine, reported as a finding.** Asked whether any benchmarking existed,
I answered that it did, and added that the cost lanes ran only from source so "the compiled figure —
the one an embedder would actually get — is unmeasured." Work was commissioned on that. It is false:
Chez compiles on load. Measured against 10.4.1, a hot loop of 20,000,000 iterations runs in 27ms under
`--script` from source, 28ms from a `compile-program` object, and 455ms from that same source with
`(current-eval interpret)`. `source` names where the text came from, not what the runtime does with
it, and the published costs had been compiled-code costs all along. The probe took under a minute and
was available before the claim was.

The lanes were still worth adding, for a different reason, and the registration says the real one:
the two modes **agree**, so the cost claims now hold in the shipped configuration as an observation
rather than an inference. Both print their mode beside every figure. What ahead-of-time compilation
buys is startup — 0.72s against 0.17s for the allocation lane — with the measured region inside
identical to the byte.

**Two defects fell out of it.** A rate could be reported over an interval the clock never measured:
elapsed time was floored with `(max 1 ...)` *before* the division, so a region finishing inside the
millisecond clock divides by that floor, and the smaller the interval the LARGER the fabricated rate,
sailing over every throughput floor asserted below it. `parse-n` now returns the raw reading and each
case asserts its region outlasted the clock; watched fail with the floor raised to 10000ms. And the
allocation figures in `docs/performance.org` were stale — 6,496/6,548 and 398 where the lane measures
6,592/6,640 and 397.

**Then the comparison against llhttp, on llhttp's own benchmark.** `llparse-test-fixture` carries a
`bench` mode and upstream's `npm run bench` drives the very binaries `tools/oracle/` already builds,
so no benchmark program had to be written and the methodology is upstream's rather than ours; in that
mode the callbacks still fire and only the printing returns early, which is the same shape as this
project's no-op bindings. 485x on a 703-byte request, 365x on a chunked `POST`, 89x on a url.

**The ratio was not constant, and that was the whole value of taking it.** A uniform cost of being
Scheme would have been one number in all three rows. The variance was on our side — our url machine is
4.5x faster per byte than our message machine where llhttp's two are within 1.5x — so it had a cause,
and 0027 records it: Chez compiles `(case st ...)` over integer keys as a **linear scan**, about
0.31ns per arm skipped, identical at every optimize level. The emitted message machine has 530 states
and numbers its hot scanning states late (`url-path` 468, `value-loop` 235); the standalone url
machine runs the same url grammar at `url-path` 15. Nothing in this repository's grammar, artifact or
runtime is at fault. The fix belonged in `byte-machine` and landed there as its PR #133 (`e8b042e`),
after which a request target scans at **27.9 ns/byte** where it scanned at 241.9 and the llhttp ratio
falls from 485x to **105x**.

Verification on merged main, clean rebuild: **88/88** at the default preset, **89/89** with
`HTTPARSE_LLHTTP_ROOT`. Conformance ratchet **274 passing / 0 not-yet / 0 deferred**. Differential
`agreed=9557 late-complete=4 early-complete=0 unclassified=0`. Property tallies unchanged —
`request=49 response=48 url=115`, `strict=180 lenient=32`, `request=242 response=199 url=240`,
`strict=480 lenient=201`. CI a billing refusal on the PR (`105161352742`): `steps=0` plus the
account-payments annotation, decision 0004.

**Still pinned to v0.5.0.** The submodule is untouched at `bce3a6b`, so none of the speedup is in this
repository yet; the bump plus a parser regeneration is its own branch. When it happens, the benchmark
lane's byte-at-a-time case measures **exactly 10ms** against the 10ms floor added above — it passes,
one improvement from failing, and the fix is to raise the repetition count rather than the floor. That
is the check working, and it is the reason to do the bump deliberately rather than as a drive-by.

Two things kept in AGENTS.md. Our own names are claims too, including the ones in a lane id — and an
unchecked inference costs more the moment it is reported and someone acts on it. And an experiment
that swaps a library must prove which copy ran: the first permutation reported no change at all,
which read exactly like a refuted hypothesis, and the reordered library had simply been second on
`library-directories`.

## 2026-09-17 — the pin moves, and decision 0027 is delivered

PR #26 (squash `c199a2d` on main; base `41f9549`). Decision
[0005](../../.plans/decisions/0005-byte-machine-pinned-by-gitlink-generated-abi-5.md) item 3, delivering
[0027](../../.plans/decisions/0027-the-cost-is-dispatch-position-not-grammar.md).

Upstream range `bce3a6b..69276b5` — that project's PR #133 and its close-out. Its decisions 0048 and
0049 replace the emitted `(case st ...)`, which Chez compiles as a linear scan of about 0.31ns per arm
skipped, with one procedure per state and direct tail calls between them, so a machine's per-byte cost
stops depending on where its hot states happened to be numbered.

**0005 item 5 discharged: the ABI is re-read at the pin and is still 8**, so item 2 is unamended.
**Both IR fingerprints are unchanged** — url `3216037711265608570`, message `318434098601601619` —
which is what item 3 asks them for and the reason to quote them: the emitter moved and the IR did
not, so the regenerated sources are a pure re-rendering of the same two machines, and a moving
fingerprint would have meant the bump reached something it should not have. They grow 12.2% and 7.1%.

Throughput, both execution modes, three runs each: **14,925-15,037 → 60,377-64,000 msg/s** on a
request, **28,169-28,571 → 103,225-106,666** on a response, **8,000-8,695 → 18,823-19,753** fed one
byte at a time. Against llhttp's own `bench` mode on its own inputs the ratio falls **485x → 104x**,
**365x → 89x**, **89x → 67x**, and the spread between the three has largely collapsed — which is the
confirmation that the position term is gone, not a separate claim.

**Unchanged, which is the evidence that matters**: differential `agreed=9557 late-complete=4
early-complete=0 unclassified=0`, identical to the pre-bump figure; ratchet **274 passing / 0 not-yet
/ 0 deferred**; both property tallies to the case. A re-rendering of the same IR should move nothing
semantic, and nothing semantic moved. One figure did move and the docs followed it rather than keeping
the prettier number: per-feed allocation for the 50-byte message, 397 → 398 B, stable across runs.

**The benchmark now calibrates its repetition count, and the reason is the previous PR's check firing
one day later.** That check asserts each timed region outlasts the millisecond clock, floor 10ms, and
it was written against the risk of a faster *machine*. What it caught was a faster *parser*: at this
pin the three literals measured 31ms, 19ms and 10ms where they had measured 135, 70 and 23, the
byte-at-a-time case landing exactly on the floor — passing, one improvement from failing. Bumping one
literal would have deferred the problem to whoever next makes the parser faster, and the symptom of
noticing late is a flattering rate rather than a red lane. Each case now doubles until its region
clears 50ms and prints the count it reached; the floor's job changed from "these literals are still
big enough" to "calibration did not give up". AGENTS.md carries the general shape.

**The rename audit caught a leak on the way**, which is the machinery working rather than a defect:
decision 0003 lets the test tree import `(byte-machine runtime)` but not name the project in prose,
and the calibration comment did. Reworded; no rule changed.

Verification on merged main, clean rebuild: **88/88** at the default preset, **89/89** with
`HTTPARSE_LLHTTP_ROOT`. CI a billing refusal on the PR (`105198089053`): `steps=0` plus the
account-payments annotation, decision 0004.

Gate 0's cost work is closed. The parser is four times faster than it was this morning, the reason it
was slow is recorded in three places rather than one, and none of it came from tuning this repository
— it came from measuring a ratio, noticing the ratio was not constant, and chasing the variance into
the dependency.
