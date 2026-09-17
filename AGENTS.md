# AGENTS.md

## Project guidelines

### Architecture & portability

* Use the functional core / imperative shell pattern
* Follow the 12 Factor Apps philosophy
* Project is specific to Chez Scheme and will be a Chez library.
* Project should be portable across macos (darwin), linux, and windows
* Project should be portable across amd64 and arm64
* Exported functions should have a comment with a Typed Racket style type signature
* This project is based on https://github.com/nodejs/llhttp and should leverage its existing testing corpus.

### Layout, process & libraries

* Plans live in `/.plans`, decision records in `/.plans/decisions`
* The subagent-driven development ledger lives in `/.superpowers/sdd/` —
  `progress.md` is the spine and `global-constraints.md` binds every task
  brief. Read both before starting slice work; close-outs are recorded there.
* Add entries to `CHANGELOG.md` for each release
* `Makefile` should have a `help` command which lists all of its commands
* Libraries are R6RS `.sls`; libraries and programs contain their own code —
  no shared include bodies. R6RS forbids assigning an exported variable —
  reach mutable state through procedures.

### Testing & mutation discipline

* Use TDD / test-driven development
* A test that passes whether the code is right or wrong is worse than no test.
* A test is not finished when it passes. It is finished when you have watched
  it fail.
* Prefer a check to a comment.
* **Do not** write tests that rely on reading code comments

## Closing ritual

We run this when we're done and ready to merge the PR.

**Important**: ALWAYS ask before running this.

1. Squash merge the PR.
2. Catch up local `main`.
3. Clean up branches. Delete the merged branch locally and on the remote.
4. Reflect.

## Reading a red lane

A lane going red is not yet evidence. **Read the failure, not the exit status.**

M2 ran mutations whose "caught" was a different thing than it looked. A
mutation routing a span-close somewhere illegal made an error node unreachable,
so the machine was **refused at verification** — exit 255, no assertion, no
summary line. A check that asked only whether `ctest` went red called that
CAUGHT, and it nearly went into the record as a test witness. It is not one: it
says the verifier would stop you, not that a test would notice. Three of Slice
③'s ten mutations were structural refusals of exactly this kind, and they are
recorded as structural.

The distinction matters because the two failure modes recommend opposite
actions. A caught mutation means the test set is doing its job. A refused
mutation means the *type system* is doing its job and the test set has not been
exercised at all — so if you were trying to witness a specific assertion, you
still have not.

This is `assert the edit landed before believing the result` taken one step
further: assert **why** it went red.

**And then ask whether that check could have gone red for an unrelated
reason.** M4 ran three mutations against the conformance lane without
re-deriving the shipped artifact, and all three were caught by the *executor
differential* — the check that the committed parser and the interpreter agree.
It fires for **any** grammar edit at all, so it says nothing whatever about
whether a fixture's trace would change. Reported as CAUGHT it looks like
evidence; it is only evidence that the two executors noticed each other. A
check that catches everything catches nothing in particular. Re-run against
the check that would actually have to notice — for those three, the ratchet's
own regression check, once the artifact was re-emitted.

## Numbers in a test come from the oracle, never from the code under test

An expectation you read off your own parser is not an expectation. It is a
snapshot, and it will keep passing after the behaviour it describes turns out to
be wrong.

M2 Slice ① asserted that a bare LF after the version errors at offset 14. That
number came from running the parser, not from a fixture, and it was wrong:
`request/invalid.md#21` records the error one past the LF, because llhttp
matches the LF into a lenient test strict mode refuses and a match consumes,
while its `.otherwise` does not. The test passed for two slices and was found by
the conformance driver on its first run.

When the oracle has no row for the input you want to check, say so in the test —
write the input the oracle *does* record beside it, or pick a different input.
"This is what we do" is a comment, not a check.

## Extracting a set from someone else's source

Script it, then check the result's shape against something you already have.

M2's method-versus-protocol matrix needed llhttp's three method classes out of
`constants.ts`. The extractor's key pattern matched bare identifiers and missed
`'M-SEARCH': 24`, whose key is quoted because of the hyphen — producing a
46-name union against our own 47-name table. The mismatch is the only reason it
was caught; every individual class looked plausible.

So: the recogniser is the part that fails silently, and it fails by matching
*less* than it should. Give the result an independent invariant to violate — a
count you already trust, a union that must equal a set you already have, a
partition that must cover it — and make that invariant a check in the tree, not
a thing you eyeballed once.

**And a count is an invariant over the SET, not over its ELEMENTS.** The same
table was wrong again for six milestones in a way no count could see. Two of
the 47 names were spelled `GET-PARAMETER` and `SET-PARAMETER`; llhttp's map
keys them `GET_PARAMETER` and `SET_PARAMETER`, with underscores, because they
are TypeScript identifiers — only `'M-SEARCH'` is quoted, which is the very
thing the first extraction bug was about. The cardinality was right, the
numbers were right, the union matched, and the hyphen looked more plausible
than the underscore because RTSP methods are usually written that way.

Nothing in the tree could have caught it: no fixture in a 253-fixture corpus
uses either method, and the two checks that guard the table both range over
the set. A live oracle found it in one run, by being asked about an input
nobody had written down.

So when an invariant is about a collection, ask what it would still accept.
A count accepts any permutation of spellings; a union against a set you
extracted the same way accepts the same mistake twice. The element-level
check is an input that USES the element, and if your corpus has none, that is
the finding.

## An estimate read off a grouping is not a prediction

Name the attribute you grouped on and the attribute you are predicting. When
they differ, what you have is an **ordering**, not a count.

Three milestones, three optimistic ceilings — M2's row read 17 against a real
10, M3's read 44 cumulative against a real 29 — and the first two were treated
as arithmetic to correct. The cause is structural. The ceilings table buckets
each fixture by the **deepest event in its trace**, because that is the
attribute a fixture wears on its face; the question the plan asks is which
**capability** the error needs. Those are different attributes of the same
fixture, and grouping on one says nothing reliable about the other.

`Content-Length: 1000000000000000000000` is the case that shows it. The error
falls inside the header section, so it buckets as header syntax — but llhttp's
value span is 21 of the 22 digits, bounded by where the accumulator overflows.
Only the accumulator can produce that span, so the fixture belongs to the
framing milestone however shallow its trace looks.

So an estimate of this kind is a starting order for the work, and it stops
being an estimate the moment a measurement exists. The ratchet is the
measurement: publish the number it reports, not the number the table implied.

**And a measurement that names a capability still does not scope it.** M4's
close measured two request fixtures as needing the url sub-parser, which is
deferred past v0.1 — correctly: they do need it. What they needed *of* it was
eight nodes, against a 221-line sub-parser, because both are about the
target's boundary and neither touches its structure. M6 met its exit criterion
instead of amending it, and only because someone opened the fixtures to see
which part they wanted.

"Needs X" is not "needs all of X". A measurement tells you which milestone a
fixture belongs behind; the size of the debt is a separate question, and it is
answered by reading the fixture, not the attribution.

## What you cannot reproduce, refuse — and make the refusal a value

An instrument that fills a gap with a plausible value produces a comparison
that is not one.

Two rows of the trace adapter say so out loud. `unexpected-eof` has **no error
number**, because llhttp prints nothing when input runs out mid-token and
giving it one would invent a line the oracle never wrote. `headers complete` is
**unrenderable**, because its line carries `flags=` and `content_length=` and
M3 has neither. The tempting alternatives — omit the line, or emit it with
zeros — both yield a fixture result shaped like a verdict.

The second half is the one that is easy to miss: a refusal has to be an
**outcome**, not a crash. The recorder still *binds* every callback, since
declarations are `required?`, and refuses at render time; the driver catches
the refusal per fixture and reports that fixture as failing; the executor
differential captures it as a comparable value, so both executors must agree
about refusing. Only then can a run tell **wrong** from **not yet** — which is
what made M3's ceiling measurable at all.

This is the runtime half of *numbers in a test come from the oracle*. That
standard governs which inputs you may assert on; this one governs what the
instrument does when the oracle records something you cannot yet produce.

## Mutate by inverting a branch, not by collapsing one

In a graph where each error node is reached by exactly one path, **deleting
that path cannot be a test witness**, because the node then becomes unreachable
and the verifier refuses the machine before a single assertion runs. It is a
guaranteed structural refusal, every time.

Six of M4's first-attempt mutations were exactly this — a `field-branch` whose
two targets were collapsed onto one, so the error behind the other went
unreachable. Two more in M3, three in M2, one in M6, where routing an
illegal-byte arm to a span end left its error node with no path, and one in
M7, where making a three-digit chain loop back to its first digit orphaned the
state that followed it. Six milestones running. The habit is natural (removing
a check is the obvious way to break it) and it is wasted every time.

**Point the branch the wrong way instead.** Swap the true and false targets, or
send the arm to the node its neighbour uses. The machine stays well-formed, the
behaviour becomes wrong, and a test gets the chance to say so. All six of M4's
were caught the moment they were rewritten this way.

The same applies to a mutation that is itself ill-formed for some other reason:
one of M4's put a terminal somewhere the verifier refuses, so it never reached
the comparison it was written to exercise. Before believing a mutation's
result, check that the mutant is a machine that could have run.

**And a caught inversion does not prove the branch DECIDES anything.** This is
the rule above turning round on itself, so it is worth stating plainly. M7
wired `should_keep_alive`'s call to `message_needs_eof` and then mutated it
two ways. Inverting the answer — needs-eof now says yes where it said no —
was caught at once by two lanes, because every keep-alive message suddenly
closed. Skipping the call entirely, wiring straight past the subgraph to the
answer it always gave, was caught by NOTHING. Both mutants are well-formed and
both run the same fixtures; the first flips a value the trace shows and the
second removes a question whose answer was constant on every path that reaches
it.

So an inversion tests the WIRE. It says the target on the other side is wrong,
which is usually what you want to know. It does not say the test is load-bearing,
and when you are asking whether a condition earns its place, the mutation to
write is the one that removes it. If that survives, "reached" was not
"deciding", and the honest thing is to say where the answer stops being
constant — for M7 that is the milestone which teaches the driver to finish a
parse, because a message needing eof never completes without one.

**A survivor is a missing test, a statement about scope, or the finding
itself — and which one is a measurement.** M4 had two mutations survive both
lanes. Neither was argued from the graph: each was re-run against the unit
lane *and* the conformance lane, and only then recorded as unobservable under
this milestone's scope, with a comment at the code naming the slice that owes
it a test. Four other survivors turned out to be real gaps and became checks.

The third kind is rarer and worth recognising. Replacing the upgrade pause
with an *error node* was CAUGHT by the unit lane and SURVIVED the conformance
lane — all 96 fixtures still passed, because llhttp prints a pause as an error
line and no fixture in the corpus resumes. That survival is not a gap to
close; it **is** the evidence for the decision that the substitution would be
undetectable in a trace, which is why the property is checked against the
parser directly. When a mutation's outcome differs between two lanes, the
DIFFERENCE is the finding — run it against both before concluding anything
from either.

The fourth kind is its complement, and it points somewhere else entirely.
**When a mutation survives in EVERY lane, suspect the oracle before the test
set.** Three of M5's nineteen did, all in the chunk-extension machine, and the
cause was not a missing test: of the eight reasons llhttp's extension states
can emit, the vendored corpus records **two**. There was nothing to write a
test against. A same-in-every-lane survivor is the shape that tells you so —
a difference between lanes is about your checks, an agreement across them is
about your evidence.

**What the oracle is missing may be a reason, or it may be an input shape that
separates two conditions.** M7's three same-in-every-lane survivors were one
finding with that second shape. llhttp asks two overlapping questions about a
response — the body decision names 100, 102, 103, 204 and 304 exactly, and
`message_needs_eof` names 1xx, 204 and 304 again — and on a message with no
framing header the two agree, so either alone renders the right trace and a
mutation to one of them changes nothing. They part only when such a status
arrives WITH a `Content-Length` or a `Transfer-Encoding`, and the corpus
records that for 304 alone. So the 304 mutation was caught and the 204 one
survived, from identical code.

The tell is a survivor whose condition is duplicated somewhere downstream. Do
not go looking for a test; go looking for the input that would tell the two
apart, and when the oracle has not got one, pin that.

## A property that looks universal may be a property of your corpus

Before asserting an invariant over generated input, ask the oracle whether it
holds for the oracle.

M8 wrote "the trace is the same however the bytes arrive" as a property test,
because that is what a resumable parser means and because the 190-fixture
corpus passes at every chunk size. A third of the generated inputs failed
it — and llhttp fails it identically. A span still open when the parse fails
is printed only for the bytes a chunk boundary already flushed, so
`Trailer : X-T` announces `span[header_field]="Trailer"` at one byte at a
time and announces nothing at all whole-buffer. Upstream knows: `noScan` is
in the fixture format for the cases where this bites.

The property is true **for a parse that reaches no error** — 71 of 71
generated inputs, measured — and the qualifier is the finding. Asserting the
unqualified version would have produced a red lane that looked like a parser
bug and was a test bug; deleting the property on seeing it fail would have
thrown away the true one underneath.

The corpus could not have told you. A corpus is a set of cases someone chose,
and "the property holds for every case in it" is exactly what you would
expect of cases chosen to be comparable. **Generated input is where a
property gets tested; the oracle is where it gets qualified.**

## Check what the oracle covers, not only what your code does

Having found an arm the oracle cannot judge, the tempting fix is a test that
asserts what the parser currently does there. **Do not.** That is
`numbers in a test come from the oracle` with the source of the number hidden
one step further back, and this repo's `.match`/`.peek` trap has been wrong
three times *precisely* where no fixture looked.

Two things are worth doing instead, and M5 did both.

**Name the idiom, not the arm.** An unmeasured arm is usually an instance of a
pattern that *is* measured somewhere else. Each of M5's six unrecorded
extension errors is one of four llparse idioms — `end().skipTo(error)` one
past the byte, `.otherwise(error)` at it, a bare-LF `.peek` at it, `.match`
past it — and every one of those four is pinned by a fixture in some other
production. The grammar now says which, arm by arm. That is weaker evidence
than a trace and it is honest about being weaker.

**Then pin the oracle's coverage as a check.** The corpus-load lane asserts
which two of the eight reasons the corpus records. It is a fact about the
fixtures, so it needs no parser and can be neither a snapshot nor a
change-detector — and a corpus refresh that brings a fixture for any of the
six turns it red. The right response to that red is to check the arm against
the new trace, not to update the number; the case says so.

A gap you have measured and pinned is a different thing from a gap you have
described. This is `make the refusal a value` applied to the oracle instead of
to the parser.

## A blocked fixture stops gating everything else it covered

A fixture deferred or blocked for one reason was probably holding down several.
When it stops running, it stops holding **all** of them.

M4's parser read ten bytes of body for `CONNECT foo.bar.com:443` with a
`Content-Length: 10`. llhttp reads none. The fixture that records this is one
of nine the upstream pause gap blocks, so the conformance lane was never going
to notice — and the bug was found only because the milestone went on to build
the decision that produces it. Nothing in the tree would have caught it
otherwise, and it would have shipped.

So when a fixture is blocked, do not just record *why* it is blocked. Ask what
else its trace was pinning, and put that in a unit case built from the
fixture's own numbers. M4 did this for the two upgrade arms — an upgrade with a
body reads it, one without does not — and the mutation that collapses them
survives without that case. It was written because the survivor pointed at it.

## A generated parser has two halves, and only one of them greps

M10 wired eleven lenient flags by finding every `testLenientFlags` in
`src/llhttp/*.ts`. Four fixtures across two different flags then failed at the
same line, on a site that grep cannot reach:

```c
/* llhttp__after_headers_complete, src/native/http.c */
} else if (parser->flags & F_TRANSFER_ENCODING) {
  if (parser->type == HTTP_REQUEST &&
      (parser->lenient_flags & LENIENT_CHUNKED_LENGTH) == 0 &&
      (parser->lenient_flags & LENIENT_TRANSFER_ENCODING) == 0) {
```

llhttp is a generated state machine PLUS a hand-written C runtime, and both
read the same fields. A mode, a flag, a counter — anything the grammar exposes
— can be consulted in either half. So when enumerating where something is
read, enumerate `src/native/*.c` too, and expect the C to state conditions the
grammar cannot (this one is a conjunction over two flags; a branch key could
not carry it).

The same milestone found the other half of this: two different flags can meet
on ONE node under ONE reason. A request line ending in a bare LF and one
ending in a lone CR are both `Expected CRLF after version`, from the same node
— so a failure at that node looks like the fork already sitting there, and is
the other flag's arm. A shared reason is not evidence of a shared cause.

## Disable the feature and count the red lanes

A fixture passing is not evidence that the code written for it ran. M9 and M10
both used the same cheap check: point each new branch at a flag nothing sets,
rebuild, and count the failing lanes. A site that breaks nothing is a site the
corpus does not reach.

M9 had one such site of six; M10 had two of thirty-two. In every case the gap
was real and invisible any other way — the fixture that would have covered
M9's was deferred behind a different flag, and M10's needed a byte no recorded
trace contains. Both now carry cases measured against purpose-built oracle
binaries, and re-disabling either fails its lane.

Two cautions. The mutation has to leave a machine that could have RUN: moving
a node off the entry produced twenty-two `unreachable-node` diagnostics, which
is a structural refusal and not a witness. And the sweep answers "is this
reached", not "is this right" — a site the corpus reaches can still be reached
for the wrong reason.

## A dependency that shipped does not un-block anything by itself

M4 measured nine request fixtures as blocked upstream: a generator pause
carried no code and no reason, so `error code=22 reason="Pause on
CONNECT/Upgrade"` could not be rendered. The brief was written, upstream
shipped it at `v0.4.0`, and this tree has been pinned there since before M5.

M9 then found there was nothing left to build. Every event node already
declared its pause continuation as the place an unpaused run would have gone,
so all 24 `pausing` fixtures passed on the lane's FIRST run, at every chunk
size, once the harness could say `off=N pause`. Four milestones ran with a
capability the tree already had, recorded as absent.

The ledger does not re-ask. A fixture deferred with a reason keeps the reason
after the reason stops being true, and the two-way ratchet cannot help: a
`deferred` entry is not run, so it cannot start passing loudly. So when a
dependency lands, go back to what its absence was blocking and ASK WHAT IS
LEFT, rather than reading the old note. The cheapest form of the question is
to promote the rows and run the lane — the answer takes one build.

## A fingerprint beats reading the diff

Moving the pin regenerates a 4000-line artifact. Nobody reviews that diff, and
a reviewer who says they did is the weakest link in the chain.

The pin move to the generator's `v0.5.0` did it differently: move the
submodule, change nothing else, regenerate, and check that the emitted text is
byte-identical to its predecessor **but for the ABI literal** — and that the
IR fingerprint the artifact carries is unchanged. The fingerprint is computed
from the IR rather than the text, so it answers the question the diff only
gestures at: not "does this look the same" but "is this the same machine".

    sed 's/compiled-machine 7 /compiled-machine 8 /' old.sls | cmp - new.sls

Two consequences worth keeping. **Put the pin on its own commit**, because the
check only works when nothing else moved. And when the pin move is a refactor
rather than a feature, "the diff is smaller" becomes an honest acceptance
criterion — but only alongside something that can say *and nothing else
changed*: here, 253 fixtures at every chunk size plus the live differential's
five counts.

## A test that names a mechanism dies with it — rewrite it, do not delete it

Deleting the lenient ask chain orphaned five cases: three in `unit.lenient`,
two in `unit.adapter`. Each asserted the MECHANISM — that eleven callbacks
were bound, that exactly one more binding appeared per flag, that a counting
binding was called once. None of them would compile against the new shape, and
all five would have been easy to delete along with the code they covered.

That is coverage silently lost, and the ratchet cannot see it: 253 fixtures
pass either way. So for each one, ask what BEHAVIOUR the mechanism existed to
produce, and assert that instead. The counting binding existed to prove the
mode is chosen once and survives a restart — which is still true and is now
read straight off the field after two restarts. The binding-count case existed
to prove no callback is invented and none is missed — still true, and now an
exact equality with the trace-row count.

**Two of the five came out stronger than they went in**, which is the tell
that the rewrite was worth doing rather than a formality. The reset case could
previously only say "cleared, then re-asked, so it works out"; it now says the
field holds the embedder's value before any byte and still holds it after
`parser-reset!`.

## A description built once is a description tested in one configuration

The url subgraph was factored so it could be built twice — separate spans for
llhttp's `url` binary, one whole-target span for the HTTP parser. The first
build passed 21 fixtures. The second did not verify, and the diagnostic was
right: `#f` as a span state meant "inside the url, between parts", where the
whole-target span IS open, and the entry nodes run BEFORE it opens.

With separate spans those two states coincide. **The first configuration was
correct by accident and no amount of testing it would have said so.** Only
building the second one did, and the verifier named the exact path rather than
leaving it to a fixture.

So when you factor something to be instantiated more than once, the second
instance is not a bonus — it is the test. Build it before believing the
abstraction, and prefer a generator that type-checks the shape (this one's
flat span lattice) over one that waits for a behavioural difference to show up
in a trace.

## Closing a divergence should turn something red

`url-machine` was one of three named divergence classes, anchored by a witness
holding llhttp's exact bytes for one reduced input. Splicing the URL machine
into the request target closed all 45 comparisons — and the lane went red
**before anyone looked at the counts**, because the witness no longer
witnessed anything.

That is worth more than it sounds. The alternative shape — a classifier with
no anchor — would have reported `url-machine=0` and passed, and the class
would have sat there forever ready to readmit a real bug under a name that
made it look expected.

Two habits follow. **Anchor a tolerated divergence to exact bytes**, not just
a predicate. And when the count reaches zero, **delete the class** rather than
leaving it at zero; keep its witness, inverted, asserting the agreement it now
produces. A count going to zero is a number; two identical traces are the
behaviour.

## One seed is not a lane

The live differential runs generated input from a seed, and the seed had been
a single number since the lane was built. The first url run at that seed found
nothing. Seeds 1, 777 and 20260916 each found the same real bug; seed 2 found
nothing.

So the default's green was luck, and it would have been read as evidence —
`agreed=2573 unclassified=0` looks exactly like a lane with nothing to say.

**Before trusting a generated-input lane, vary the seed and count.** If a
different seed finds something, the lane's default is too narrow, and widening
it is a measurement you now have. The sweep here is the seed it was given plus
its two successors: one number still names the run, any member replays alone,
and re-introducing the bug turns the DEFAULT red. Deriving the extra seeds
arithmetically matters — picking the three that happened to catch this bug
would have been fitting the lane to its own history.

## A loop variable is not the node the edges name

llhttp builds two nodes from one loop:

```js
for (const node of [ server, serverWithAt ]) {
  node.match(USERINFO_CHARS, server)   // server, NOT node
      .match([ '[', ']' ], server);    // server, NOT node
  if (node !== serverWithAt) { node.match('@', serverWithAt); }
}
```

Read at a glance, that is "the same node twice, one with an extra edge". It is
not. The edges name `server` explicitly, so `serverWithAt` is **one byte
wide** — any ordinary host byte returns to `server` and re-arms `@`. Only
`@@` is an error; `a@b@c` is a host.

This parser transliterated the glance, and the comment it left said so in as
many words. **Twenty-one fixtures, six oracle-measured cases and 274 corpus
replays all passed**, because upstream's own `Double @` fixture has its two
`@` adjacent and cannot tell the two rules apart.

Two habits. When upstream writes a loop over nodes, **read every target inside
it for whether it is the loop variable or a fixture**, and say which in the
comment. And when you find yourself writing "X is Y without edge Z", that
sentence is a claim about a graph — go and check it against a running oracle,
because a fixture that exercises the shared part will pass either way.

## Explain the behaviour in the code and the version in the changelog

The rename audit has caught the same thing in four consecutive milestones, most
recently in five places at once. It is never the code — it is a *comment*,
explaining why something is the way it is, and the explanation names the
dependency and the release it arrived in.

That is the shape criterion 5 forbids in the build and test tree, and it is
easy to write without noticing, because naming the version genuinely is the
clearest way to explain a change. `CHANGELOG.md` is an exempt surface and is
where the version narrative belongs; a decision record is where the reasoning
belongs. A comment beside the code should say what the code does and why that
is right — "the generator gives a pause its own reason", not "as of X v0.4.0".

The audit catches it every time, so nothing ships wrong. What it costs is a
red lane and a rewrite, every milestone, and the habit is worth breaking at
the point of writing instead.

## Traps this repo has already hit

Each of these shipped a passing test or a working-looking build that was wrong.
None is obvious from reading the code.

* `0` is truthy in Scheme, and `guard` returns the body's value when nothing
  raises.
* SRFI-64 turns any exception in a test's *actual* expression into `#f`
  (`vendor/chez-srfi/%3a64/testing-impl.scm:568-571`: the R6RS
  `%test-evaluate-with-catch` is `(guard (ex (else #F)) …)`).
* Chez evaluates argument expressions right-to-left in compiled library code
* A CMake variable read before it is `set` expands to **nothing**, with no
  warning. `test/CMakeLists.txt` defined `HTTPARSE_ADAPTER` below two lanes
  that named it in `SOURCES`, so both silently dropped that dependency. A
  lane's `SOURCES` list is the one place this hides well, because the lane
  still runs and still passes.
* Chez's `bytes-allocated` reports what is allocated **right now**, not what
  has been allocated in total, so a collection inside a measured region makes
  the difference NEGATIVE. M8's allocation lane reported a region as
  allocating -33122 bytes before anyone noticed. The cumulative figure is
  `(sstats-bytes (statistics))`. The general form: when a counter can go
  down, a before-and-after difference is not a measurement.
* R6RS keeps `string-set!` out of `(rnrs)`; it lives in
  `(rnrs mutable-strings)`. A hex encoder built with `make-string` and
  `string-set!` fails at library load, not at the call.
* R6RS forbids the `|...|` symbol-escape syntax, and Chez says so only when
  it READS the file — so a lane whose source lane passes can still fail at
  the aot compile, which is the first thing to read the program twice. The
  error is `symbol escape syntax is not allowed in #!r6rs mode`.
* `(verify-machine m)` **returns a verdict; it does not raise one.** A script
  that calls it and then prints "verified" has checked nothing — M7 wrote that
  script, believed it, and was corrected by the emitter, which reads
  `verification-ok?`. The general form: when an instrument ANSWERS rather than
  throws, not reading the answer is indistinguishable from a pass.

## Claims about other people's code

A claim about a dependency's behaviour is **run before it enters a decision
record**. Not read, not remembered — run. Gate 0 drafted three such claims and
all three were wrong: a decision targeting an upstream constructor that had
since become a tombstone refusing every version; "the case-folding workaround
is semantically lossy", which is false because a trie disambiguates
`close`/`closed` where `make-sequence-dispatch-node` rejects the pair; and a
corpus fixture count taken from the wrong block type. Each was plausible, each
was written down, and each was caught only by executing the specific claim.

This is `prefer a check to a comment` pointed outward. The traps above are all
about our own code being surprising; these are about someone else's code
differing from its documentation, or from what it did last month.

**The rule is not only for decision records. A claim that shapes how a LANE
WORKS is the same claim, and it is worth more.** The conformance driver
carried this comment from M1:

> llhttp's own harness calls `llhttp_finish` only for the `*-finish` fixture
> types

It does not. `llhttp__test_finish` is one line, it prints `s->finish`, and it
never calls `llhttp_finish` at all. The claim was inferred from the fixture
type's NAME, written into a comment, and built into the driver's model for
four milestones — and reading it took two minutes once anyone looked.

**A correct check does not vouch for the theory that produced it.** What made
this last so long is that the wrong model was *protected by a right refusal*:
driving the parser to its end-of-input states produced an `unexpected-eof` the
oracle never records, the adapter refused it exactly as it should, and three
fixtures stayed honestly red. Nothing shipped wrong. But the red had an
explanation, and the explanation was true — so nobody went looking for a
second one.

So: when a fixture has been red for more than one milestone and you have an
explanation for it, the explanation being true is not evidence that it is
complete. Go and read the thing that produces the line.
