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
illegal-byte arm to a span end left its error node with no path. Five
milestones running. The habit is natural (removing a check is the obvious way
to break it) and it is wasted every time.

**Point the branch the wrong way instead.** Swap the true and false targets, or
send the arm to the node its neighbour uses. The machine stays well-formed, the
behaviour becomes wrong, and a test gets the chance to say so. All six of M4's
were caught the moment they were rewritten this way.

The same applies to a mutation that is itself ill-formed for some other reason:
one of M4's put a terminal somewhere the verifier refuses, so it never reached
the comparison it was written to exercise. Before believing a mutation's
result, check that the mutant is a machine that could have run.

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
