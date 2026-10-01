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

## A floor that guards a lane is satisfied by its easiest member

Both of the property lane's properties are guarded by a floor, because both
would pass vacuously over a run that selected nothing: "every error-free parse
is fragmentation-invariant" is true of zero error-free parses. The floor was
one number over the whole run, and it was right while the lane had one
subject.

Adding the url kind made it wrong without making it fail. At the default seed
the message kinds produce 65 error-free inputs between them, so
`> clean 20` stays green whatever the url machine does — including
contributing nothing at all, which is exactly the failure the floor exists to
catch. Setting `HTTPARSE_PROPERTY_URL_CASES=0` proves it: the global floor
passes, the per-kind floors fail.

**So when a lane gains a subject, re-split every vacuity guard in it.** The
old subjects will go on satisfying a shared guard, and the new one's absence
looks exactly like its presence. Pick the new floors from measured counts
across several seeds rather than from the first number you see — ours is 15
against a worst observed 26 — and print the per-kind tally beside the check,
so a reader can see which member is carrying it.

## Re-measure a number after the last change, not before it

A milestone's headline figure -- `agreed=9603` -- was measured, correctly,
and then the generator changed once more. The change was to the INPUTS, so
it moved their lengths, so it moved how many chunk sizes the ladder gives
them. Merged main measures 9557. The conclusion was unaffected;
the number in the decision record, the plan, the changelog and the PR body
was wrong in four places.

The same slip, a few minutes earlier, put a table of per-mode counts into a
comment that had been SCALED from a smaller run rather than measured. It
survived a full green suite, because nothing executes a comment.

So: when a number goes into a record, **take it from a run of the tree you
are about to commit**, not from the run that motivated the change. And when
a number is a table rather than a single figure, the temptation to fill the
remaining rows by proportion is exactly the failure -- one measured row and
five invented ones looks identical to six measured rows.

`Prefer a check to a comment` is the general form, and the specific form
here is that a printed tally beside the check would have caught both: the
lane prints its per-kind and per-mode counts every run, so the table in the
comment was contradicted on screen by the lane it describes.

## A build cache that hashes arguments has not hashed your file

The differential's lenient oracle is upstream's parser built with an init
hook of ours, passed to `llparse-test-fixture` in its `extra` list. A
deliberately wrong hook — `LENIENT_HEADERS` swapped for
`LENIENT_CHUNKED_LENGTH` — produced a byte-identical binary and a green run.

The cache keys on the generated header, the generated C and
`commonArgs.join(' ')`, then skips the compile when a file with that digest
exists. Our file reaches it as a **path** in that argument list. The path did
not change, so the digest did not, so nothing was rebuilt.

Two habits. **When you hand a source file to someone else's build, check what
their cache key covers** — an argument list is the common case and it almost
never includes file contents. Putting the file's content hash into the
arguments as a define nothing reads is enough. And **a mutation that catches
nothing is a result to chase, not to replace**: the instinct is to pick a
different mutation, and the different mutation would have passed too.

This is `a derived file can silently stop describing its source` pointed at
someone else's build system. Our own emitted parsers have a lane for exactly
this; a binary built outside the tree had none and needed none once the key
was right.

## Explain the behaviour in the code and the version in the changelog

The rename audit has caught the same thing in four consecutive milestones, most
recently in five places at once — and then **twice in one day**, in two
unrelated pieces of work: a calibration comment in the benchmark lane, and the
comment beside the ABI expectation explaining which pin moved it. It is never
the code — it is a *comment*, explaining why something is the way it is, and
the explanation names the dependency and the release it arrived in.

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
* A script run with `cmake -P` inherits **none** of the project's policies:
  the top-level `cmake_minimum_required` never reaches it. CMake 3 leaves an
  unasked-for policy unset, so `if(x IN_LIST y)` is a syntax error there;
  CMake 4 has no old behaviour left for it to fall back on, so the same
  script passes. Every `-P` script opens with the floor, and
  `harness.script-policy-floor` checks that as text.
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
* `make parser-refresh` **configures but does not build**, so the first
  `ctest` after a pin bump runs the new generated sources against stale
  compiled artifacts and objects. That reads as a catastrophic regression —
  sixty of eighty-eight lanes red, including `harness.bootstrap`, which has
  nothing to do with the parser — and it happened twice in one afternoon,
  once in a throwaway worktree and once in the main checkout. `make build`
  clears all of it. The general form: **a red lane whose failures include
  something the change could not possibly touch is a build-state failure
  until proven otherwise.** Rebuild, then read.

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

**A name is a claim too.** `llhttp__test_init_request_lenient_all` sets
**nine** of the eleven lenient flags: `SPACES_AFTER_CHUNK_SIZE` and
`HEADER_VALUE_RELAXED` are not in it. Three fixtures use it and they are the
whole of upstream's combination coverage, so those two flags are combined
with nothing anywhere in the corpus. Nobody would have checked a constant
called `lenient_all` against its own definition; reading it took one minute
and changed what the generator had to cover.

**Upstream's metadata is a claim too, and it can be conservative.** A comment
was about to say that `url.md`'s four `noScan` marks are exactly the fixtures
whose trace depends on chunking — true-sounding, and it is exactly their four
error fixtures. Measured, three of the four diverge and "Failing on broken
schema" does not: its schema span is closed before the error, so no boundary
has an open span to flush early. llhttp does not diverge on it either, checked
against the url fixture binary at both chunk sizes.

Nothing was broken by the belief, which is the point — an annotation that is a
superset of what it needs to be costs nothing until you quote it as a reason.
The check that replaced the comment asserts the direction that is load-bearing
(nothing diverges unmarked, because unmarked fixtures ARE scanned) and records
the one mark that is only caution.

**And OUR OWN names are claims — including the ones in a lane id.** This tree
registers `.chez.source` and `.chez.aot` lanes, and a gap analysis went out
saying the cost lanes measured only source, so "the compiled figure — the one
an embedder would actually get — is unmeasured." Every word of that is
grammatical, plausible, and wrong. Chez compiles on load: measured against
10.4.1 on 2026-09-17, one hot loop ran in 27 ms from source, 28 ms from a
`compile-program` object, and 455 ms from that same source with
`(current-eval interpret)`. `source` names where the TEXT came from, not what
the runtime does with it. The published figures had been compiled-code figures
all along.

Two things make this worse than the usual version of the mistake. The first is
that the inference was *reported as a finding* — not written into a comment
where it would sit quietly, but handed over as a gap, and work was commissioned
on the strength of it. An unchecked claim costs more the moment someone else
acts on it, so the checking threshold for anything you are about to report is
higher than for anything you are about to write down. The second is that the
probe took under a minute, and it was available before the claim was: timing a
loop three ways needs no part of this repository.

The lanes were worth adding anyway, but not for the stated reason, and the
difference matters. They do not publish a faster number; they publish that the
cost claims hold in the configuration this project ships. When a measurement
comes back identical to the one it was supposed to beat, that is the result —
chase it, and rewrite the reason you gave. Do not keep the reason and shrug at
the number.

## An experiment that swaps a library must prove which copy ran

Decision 0027's central measurement was a permutation of the emitted parser's
`case` arms — semantics-preserving, so any change in speed is dispatch cost and
nothing else. The first run reported **no change at all**: 240.6 ns/byte against
the original's 239.8, flat across every input.

That is exactly what a refuted hypothesis looks like, and it was not one. The
permuted library was **second** on `library-directories` and the original had
loaded; the experiment had measured the committed parser twice. Putting the
copy first and giving it a line to print on load produced 42.4 ns/byte on the
same input — a 5.7x swing that had been there the whole time.

**So: a scratch experiment that substitutes a library gets a marker in the copy,
and the marker's output is part of the result.** Not a comment saying which path
was used — a line the run prints, checked before the numbers are read. The
launchers under `test/support/launchers/` exist because library resolution in
Chez is full of this (their headers record `library-directories` pairing both
halves of a bare string, and the object and source guards that follow from it);
a scratch script written beside that machinery inherits none of its care and
hits the hazard immediately.

The general shape is the one under *A build cache that hashes arguments has not
hashed your file*: **when a change that must do something appears to do nothing,
suspect the apparatus before the hypothesis.** Both times the apparatus was
wrong, and both times the tempting move was to accept the null result and go
looking for a different explanation.

## A constant that makes a measurement valid goes stale when the code improves

The throughput lane grew a check that each timed region outlasts the
millisecond clock, with a 10 ms floor, because a rate computed over an interval
the clock cannot resolve is a fabricated number — and the smaller the interval,
the larger and more flattering the fabrication. The floor was written against
the risk of **a faster machine**.

What it caught, one day later, was **a faster parser**. The pin bump that made
the generated dispatch four times cheaper left the three repetition literals
measuring 31 ms, 19 ms and 10 ms where they had measured 135, 70 and 23 — the
byte-at-a-time case landing exactly on the floor, passing, one improvement from
failing. Nothing was wrong with the floor; the literals it guarded had simply
stopped being the right literals, and there is no version of them that stays
right.

**So a constant that exists to keep a measurement valid should be derived at
run time, not chosen.** Each case now doubles its repetitions until the region
clears a target, and prints the count it arrived at; two runs of the lane need
not agree on repetitions, and the floor's job changed from "these literals are
still big enough" to "calibration did not give up". The general shape: *a
tuned constant is a claim about the code as it was when someone tuned it*, and
the failure mode is not a red lane but a plausible number — which is why the
check had to exist before the improvement did.

Worth noting what the guard cost to be right: it was added a day earlier for a
reason that never materialised. That is the usual return on this kind of check,
and it is not a reason to skip the next one.

## A harness you decline to ship is only as good as the list that replaces it

The FFI comparison in `docs/performance.org` needs a C toolchain, so decision
0010 keeps it out of the tree. What went in instead was a section called
*Taking these yourself*: four numbered steps, the clang flags, the struct size,
the shape of the shim.

**That list was cashed in a day later and it worked.** Four generator fixes
made the Scheme row four times faster, which inverted the section's
conclusion — a naive wrapper went from buying 3.7× to losing — so every row
had to be re-taken. The harness was gone; the list rebuilt it, and the rebuilt
rows came back within a few per cent of the originals (96.7 MB/s against 91.8,
2,837 against 2,574). One row did not: the batched decode, because the list
said *what* to build and not *how much work the decode does*, and the rebuild
delivered a call per event where the original summed fields.

So the list was sufficient to reproduce the measurement and not sufficient to
reproduce the number. That is the right place for the line to fall, and it is
only visible because someone tried.

**So: when you decline to ship a harness, the replacement is not prose about
it — it is the list someone rebuilds from, and it has to name the work, not
only the parts.** Two things make it checkable. Take the sizes from the
toolchain rather than quoting them (`sizeof(llhttp_t)` is 96 *because clang
says so*, and the list now says to ask), and name a fact the rebuild must
reproduce — the shim counting 47 triples for the 703-byte request is what
proved the rebuilt harness was measuring the old harness's subject before any
rate was compared.

The rebuild also retired a number the original could only assert. The crossing
cost was stated beside the table at 140 ns; it now falls *out* of the table,
as 7.27 µs minus 0.24 µs over 47 callbacks. A figure a reader can derive from
the rows beats one they have to trust.

## A number that measures how little something matters expires quietly

That same section said this parser "barely notices" `optimize-level` — nine
per cent — and cited byte-machine's decision 0049, which records the emitted
dispatch as costing the same at levels 0, 2 and 3. Both halves were true.

It notices fifty-two per cent now, and nothing about `optimize-level` changed.
The linear scans dominated the parse, a scan **is** level-insensitive, and the
parser inherited that insensitivity from its slowest part. Once the scans went,
what was left was bounds-checked memory access — exactly what level 3 stops
checking.

The nine per cent was never a property of this parser. It was a property of
the defect, and it left with the cause.

**So: a measurement of a thing's irrelevance is a measurement of the ratio
between it and whatever dominates, and fixing the dominant thing invalidates
it without touching it.** These are the claims that rot silently, because
nothing about them looks like a number that needs re-taking — they read as
structural facts. When a sentence says "X barely matters here", write down
what it was competing with, so the next person can see the claim expire.

## A version surface is anywhere the text asserts a relationship to the release

Cutting v0.2.0 meant moving the version string in `CHANGELOG.md` and the
`README.org` status paragraph — the two places a checklist would name. The
third was `docs/conformance.org`, which carried no version number at all:

> v0.1 shipped 190 of them, strict-mode only. Pausing and `skipBody` (26) came
> in after it, then the eleven lenient flags (37), then the url sub-parser
> (21). **All of that is on `main`, unreleased.**

Nothing in that paragraph is a version string, and the release makes its last
sentence false. A grep for `0.1.0` would not have found it; a grep for `v0.1`
would have found the harmless historical half of the same paragraph and not
the claim.

**So: before a release, search for the RELATIONSHIP, not the number.**
"unreleased", "on `main`", "not yet shipped", "deferred to", "since the last
release" — each of those is a version surface that stops being true the moment
a tag exists, and none of them looks like one. The byte-machine side of this
project makes the same point from the other direction: its release ledger
names its surfaces as a list *because* they cannot be found by searching.

## A byte-identical parser is not an unchanged one when the runtime moved

The byte-machine `v0.6.1` bump (#53) regenerated both parsers byte for byte
and left both IR fingerprints where they had been for four pins. Every signal
this repository reads at a bump said *nothing changed*. What had changed was
the runtime the generated code calls: the keyword walk stopped copying its
matched prefix on every byte, and a whole-buffer parse got 35–80% faster.

Fingerprints and goldens describe the **emitted half** of a generated parser
(see *A generated parser has two halves*). The other half is
`vendor/byte-machine/src/byte-machine/runtime.sls`, and nothing here
fingerprints it. So at a bump, read the upstream range's `src/` diff for
`runtime.sls` as well as regenerating. If it moved, the parser's behaviour can
have moved with byte-identical sources. Then write the test that would see it
**before** moving the pin, and watch it fail at the old one: the near-miss
allocation case in `allocation-tests.sps` read +2,944 bytes at k = 16 on
`v0.6.0` and 0 on `v0.6.1`. That red run is the only evidence the case
measures the fix and not something else.

A corollary from the same bump: **a figure computed as a difference can move
the wrong way on a pure improvement.** The per-feed allocation of the 50-byte
message rose from 404 to 444 bytes, while both parses it is derived from got
cheaper. The whole-buffer parse lost more than the byte-at-a-time one, whose
split keywords are still rebuilt per feed. Before calling a derived number a
regression, read the two numbers it is made of.

## A gate that has not run has not passed

The Actions minutes had run out by 2026-09-07 and came back on 2026-10-01.
In between, all 107 CI runs since the byte-machine submodule arrived were
refused before a single step. Each was correctly read as billing, and the
PRs were correctly merged over it. The first run that got a step in found two
defects, and neither was new.

The workflow had never been able to fetch the submodule. Decisions 0002 and
0005 both say CI needs an org-scoped read token for it. The workflow never
had one, because from the day the submodule landed nothing could fail
without it. And a test script that every laptop passed was a syntax error on
the runner. `CorpusProvenanceSpec` used `IN_LIST` without declaring a policy
floor; a `cmake -P` script inherits none of the project's; and the runner's
CMake 3.31 leaves CMP0057 unset, where CMake 4 has no old behaviour left at
all.

Three habits follow.

**When a gate comes back, its first run is a discovery, not a formality.**
Weeks of refusals train the reflex to call red "billing". Read every failure
the returning gate reports as a real one, and expect a backlog: whatever
only that gate could see has been accumulating the whole time it was dark.

**A requirement a decision records is unimplemented until something fails
without it.** Writing "CI needs a read token" into two records did not put
one in the workflow. While the check that would enforce a decision cannot
run, the decision is a note, and the record should say so.

**A toolchain newer than the floor cannot see the floor.** CMake 4 removed
the old side of every policy older than 3.5, so no local run of that script
could fail the way the runner's did. The fix checks the declaration rather
than the behaviour: `harness.script-policy-floor` requires every `-P` script
to open with the floor, as text. And CI now prints its own `cmake --version`
beside Chez's, so the difference between the two machines is on screen
rather than inferred.

## A setup that makes two answers equal cannot tell them apart

`parser-stream-offset` inside a span callback is the fragment's END in the
stream. `to` is the fragment's end in the BUFFER the embedder fed. Every lane
that read the offset there fed one buffer from index 0: the conformance
driver, the generated-input lanes, the request-line cases. In that setup the
two numbers are the same number, and a runtime that handed the callback `to`
passed all 96 other lanes in the pr selection, measured.

It would not have passed chez-http-server, which reads each request into a
fresh buffer from a socket and is the embedder the contract was documented
for. Its evidence for the issue checked every one of 3,101,130 span
callbacks against the fragment's real position. That check discriminated
where ours could not, because its buffers do not start where the stream
does.

`unit.stream-offset` now feeds each chunk from a buffer of its own, at a
nonzero index, with filler either side. So `from` and `to` are never stream
positions, and a fragment that strayed outside its chunk would carry bytes
the input does not have. The mutation that hands the callback `to` fails it,
and that is the mutation worth writing for any contract stated in two
coordinate systems.

So when a test computes an expected value, ask what other quantity the
setup makes equal to it, and break the coincidence. A buffer index and a
stream position, an offset and a length when the start is 0, a call count
and a byte count at chunk size 1: each pair is two answers that one fixture
cannot tell apart.

## Two generators can agree on every trace and still differ when input runs out

llparse's span start waits for a byte. In llhttp's generated
`span_start_llhttp__on_body_2`, `if (p == endp) return` comes before
`_span_pos0 = p`. byte-machine's span start is zero-width and opens at once.
While the input keeps coming, nobody can tell. A span byte-machine opens at
the end of one feed delivers nothing there, because an empty flush is
suppressed, and llparse opens the same span on the next feed's first byte.
Either way the first fragment starts at that byte, so 274 fixtures at every
chunk size agree.

They part only when the input ENDS. A close-delimited body that got no bytes
never opens its span in llhttp, so `llhttp_finish` runs
`on_message_complete` alone. Here the end-of-input route found the span
open, and the verifier requires it closed. A span that closes having
delivered nothing delivers once, empty: an `on-body-data` of no bytes that
llhttp never produces. The corpus could not see it, because its harness
never calls `llhttp_finish`. A probe of llhttp's public API could, in one
compile against the corpus's own checkout: `build/c/llhttp.c` with
`src/native/api.c` and `src/native/http.c`.

The comments beside the old route said llhttp "flushes the identity-eof
body at EOF". It does not. It delivers body bytes at the end of each
execute, and its finish runs nothing but the completion. That sentence was
inferred and never run, and it shipped beside the code it misdescribed in
four releases.

So when a grammar crosses generators, ask what each primitive does when
the input runs out (wait, act or refuse), because no trace that keeps
feeding will tell you. And where the oracle's harness never calls an entry
point, its behaviour there is unrecorded, not agreed: build the probe before
believing the comment.

## A rebase is a change, and the numbers ride along unmeasured

Three PRs went in over one afternoon, #58, then #56, then #57, each rebased
onto what had merged before it. Every rebase moved something a commit
message or PR description stated as measured.
- The pull-request selection grew from 95 lanes to 96 to 98, so "make test
  97/97, release 100/100" described a tree that no longer existed.
- "A runtime that handed the callback `to` passed all 95 other lanes" became
  a claim about 96 lanes it had never been run against.
- "The old behaviour fails unit.finish alone" had been measured against two
  lanes, not all of them.

Each was re-run on the rebased tree before the force-push, and the messages
were amended to say what the re-run found. The mutant still passed all 96,
and only unit.finish still caught the old behaviour; both were now measured.

None of them turned out wrong, and that is the trap. A rebase that changes no
line of yours looks as if it cannot change your evidence, but it changes the
tree the evidence is about. The same afternoon found the older form of this
already in the record: the v0.4.3 changelog quoted a fingerprint from two
grammar changes earlier, carried forward from the entries before it.

So treat a rebase like an edit. Re-take every count, and re-run every "only
X catches it" claim the message carries, on the rebased tree before the
push. A squash merge then records what was measured, not what was true
yesterday.
