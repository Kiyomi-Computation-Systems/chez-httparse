# AGENTS.md

## Project rules

### Architecture and portability

- Functional core, imperative shell. Follow the 12-Factor App principles.
- A Chez Scheme library, portable across macOS, Linux and Windows, on amd64
  and arm64.
- Based on [llhttp](https://github.com/nodejs/llhttp); its test corpus is the
  conformance oracle.
- Every exported procedure has a Typed Racket–style signature comment.

### Layout and process

- Libraries are R6RS `.sls`; each library and program holds its own code — no
  shared include bodies. R6RS forbids assigning an exported variable, so reach
  mutable state through procedures.
- Design decisions are numbered records in `.plans/decisions/`. Plans and
  work-in-progress notes are not kept in the repository.
- `CHANGELOG.md` gets an entry for each release. The `Makefile` has a `help`
  target listing every command.
- Comments describe the code as it is now. Versions belong in `CHANGELOG.md`
  and reasoning in a decision record — not dates, phase names or PR numbers in
  a comment.

### Testing

- Test-driven: write the test first.
- A test that passes whether the code is right or wrong is worse than no
  test. A test is finished when you have watched it fail, not when it passes.
- Prefer a check to a comment. Never write a test that reads code comments.

## Closing ritual

Run this when the PR is ready to merge. **Always ask before running it.**

1. Squash-merge the PR.
2. Catch up local `main`.
3. Delete the merged branch, locally and on the remote.
4. Reflect.

## Lessons

Each rule below was learned from something that went wrong here. The rule
and why it matters are here; the incident, with its numbers, is in
[`.plans/lessons.md`](.plans/lessons.md) under the same heading. Read it when
you need to know whether a rule applies.

### Tests and mutation

- **Reading a red lane.** Read the failure, not the exit status: a mutant the
  verifier refuses (exit 255, no summary line) shows the type system working,
  not a test. Then ask whether the check that went red would go red for *any*
  edit — one that catches everything catches nothing in particular.
- **Mutate by inverting a branch, not by collapsing one.** Deleting a path
  leaves a node unreachable and the verifier refuses the machine before any
  test runs. Swap the targets instead. An inversion tests the wire, not
  whether the branch decides anything; to ask that, remove the condition. A
  survivor is a missing test, a scope statement, or the finding — and a
  survivor in *every* lane points at the oracle, not the tests.
- **Disable the feature and count the red lanes.** Point each new branch at a
  flag nothing sets: a site that breaks nothing is a site the corpus never
  reaches. It answers "is this reached", not "is this right".
- **A test that names a mechanism dies with it — rewrite it, do not delete
  it.** Ask what behaviour the mechanism existed to produce and assert that;
  deleting loses coverage the ratchet cannot see.
- **A setup that makes two answers equal cannot tell them apart.** A buffer
  fed from index 0 makes buffer offsets equal stream offsets. Break the
  coincidence (a nonzero start, filler around it) so the wrong answer fails.
- **A floor that guards a lane is satisfied by its easiest member.** When a
  lane gains a kind of input, give each kind its own vacuity floor, picked
  from measured counts over several seeds, and print the per-kind tally.
- **A check that something is absent passes on nothing.** An empty or
  mis-pointed input has none of the forbidden things either. Pair every
  absence check with a check that something which must be there is.
- **One seed is not a lane.** Vary the seed before trusting a generated-input
  lane. Run the given seed and its successors, derived, not hand-picked.
- **Closing a divergence should turn something red.** Anchor a tolerated
  divergence to exact bytes. When its count reaches zero, delete the class and
  keep the witness, inverted, asserting agreement.

### The oracle and the evidence

- **Numbers in a test come from the oracle, never from the code under test.**
  A number read off your own parser is a snapshot that keeps passing after it
  is wrong. If the oracle has no row for an input, say so or pick another
  input.
- **What you cannot reproduce, refuse — and make the refusal a value.** Never
  fill a gap with a plausible value (a zero, an invented line). Refuse, and
  make the refusal an outcome the driver and the executor differential can
  compare, so a run tells *wrong* from *not yet*.
- **A property that looks universal may be a property of your corpus.** Ask
  the oracle whether the invariant holds for the oracle. Generated input is
  where a property gets tested; the oracle is where it gets qualified.
- **Check what the oracle covers, not only what your code does.** Where the
  oracle cannot judge an arm, don't assert what the parser happens to do.
  Name the idiom the arm follows, and pin the oracle's coverage as a check so
  a corpus refresh turns it red.
- **A blocked fixture stops gating everything else it covered.** When a
  fixture stops running, ask what else its trace pinned and put that in a unit
  case built from the fixture's own numbers.
- **An estimate read off a grouping is not a prediction.** Grouping by one
  attribute and predicting another gives an ordering, not a count. And
  "needs X" is not "needs all of X": read the fixture to size the debt.
- **A dependency that shipped does not un-block anything by itself.** A
  deferral keeps its reason after the reason stops being true. When a
  dependency lands, promote what it blocked and run the lane.

### Reading other people's code

- **Claims about other people's code.** Run a claim about a dependency before
  it enters a record, a comment, a lane's design or a report. Names are claims
  too (`lenient_all` sets nine of eleven flags; a `.chez.source` lane is still
  compiled), and so is upstream metadata. A correct check does not vouch for
  the theory that produced it.
- **Extracting a set from someone else's source.** Script it, then give the
  result an independent invariant to violate, kept as a check. A count guards
  the set, not its elements: also test an input that *uses* each element.
- **A generated parser has two halves, and only one of them greps.** llhttp is
  a generated machine plus hand-written C, and both read the same fields: when
  enumerating where something is read, search `src/native/*.c` too. A shared
  error reason is not evidence of a shared cause.
- **A loop variable is not the node the edges name.** In upstream loops over
  nodes, check whether each edge targets the loop variable or a fixed node,
  and say which. "X is Y without edge Z" is a claim to check against a
  running oracle.
- **Two generators can agree on every trace and still differ when input runs
  out.** Ask what each primitive does at end of input; a trace that keeps
  feeding cannot show it. Where the oracle's harness never calls an entry
  point, probe it before trusting a comment about it.

### The generator and its pin

- **A fingerprint beats reading the diff.** Move the pin on its own commit,
  regenerate, and check the output is byte-identical but for the ABI literal
  and that the IR fingerprint is unchanged.
- **A description built once is a description tested in one configuration.**
  When you factor something to be built twice, build the second instance
  before believing the abstraction.
- **A byte-identical parser is not an unchanged one when the runtime moved.**
  Fingerprints cover the emitted half only. At a bump, read the upstream
  `runtime.sls` diff, and write the test that would see a runtime change
  before moving the pin. A figure computed as a difference can move the wrong
  way on a pure improvement.
- **When no API can see a runtime change, build the old pin beside the new
  one.** Build the old pin in a scratch copy and run the lanes alternately
  over many rounds. One run is not a comparison, and a cause found by removing
  pieces is a finding even when the mechanism is unknown.
- **A build cache that hashes arguments has not hashed your file.** When you
  hand a file to someone else's build, check what its cache key covers; put
  the file's content hash into the arguments. A mutation that catches nothing
  is a result to chase, not to replace.

### Measurement

- **Re-measure a number after the last change, not before it.** Take every
  number in a record from a run of the tree you commit. Never fill a table by
  proportion from one measured row.
- **An experiment that swaps a library must prove which copy ran.** Give the
  substitute a marker it prints, and check the marker before reading the
  numbers. When a change that must do something does nothing, suspect the
  apparatus first.
- **A constant that makes a measurement valid goes stale when the code
  improves.** Derive it at run time (calibrate repetitions to a target
  duration) and print what it arrived at.
- **A harness you decline to ship is only as good as the list that replaces
  it.** The list must name the work, not only the parts, and a fact the
  rebuild must reproduce (such as an event count) before any rate is compared.
- **A number that measures how little something matters expires quietly.**
  "X barely matters" is a ratio against whatever dominates, so write down what
  it was competing with.
- **A comparison is only as fair as its loop, and the loop is the part nobody
  writes down.** Ask what state each side
  carries between iterations (a reused parser, a reset). Rebuild the old
  figure at the old pin before trusting a new one, and check the bytes the
  harness actually received.
- **A headline figure should measure the loop an embedder runs.** A
  benchmark's setup choice (a parser built per message) becomes the number
  readers quote. Ask what a user's loop does, measure that, and keep any
  other loop as a labelled second figure, not a footnote.
- **Something you did not change is your noise floor.** Time a component
  that is byte-identical on both sides in the same sitting; if it moves, the
  sitting cannot support a claim about the change. Read the load average
  first, and run nothing else while it times.

### Writing it down

- **Explain the behaviour in the code and the version in the changelog.**
  A comment says what the code does and why that is right. Versions, dates,
  phases and PR numbers say *when*, and belong in `CHANGELOG.md` or a record.
- **A comment dated by its history reads as true; delete the date and it has
  to be.** History beside a comment
  is how a stale comment survives review; written in the present tense, it is
  visibly wrong when the code changes.
- **A claim fixed in one place is still wrong in its copies.** When you
  correct a claim, search for the claim across `src/`, `docs/`, `README.org`
  and test comments, not just the file in front of you. When rewriting docs,
  re-check every sentence you carry over.
- **A file copied from a sibling carries the sibling's claims.** Rewording it
  to fit this repository gets it past the rename audit without making it
  true. When you copy a file, check each sentence and each rule against this
  tree: a rule that matches no file is a claim too.
- **A version surface is anywhere the text asserts a relationship to the
  release.** Before a release, search for "unreleased", "on `main`", "not yet
  shipped", "deferred to" — not just the version number.

### CI and merging

- **A gate that has not run has not passed.** When a dark gate comes back,
  read its first failures as real and expect a backlog. A requirement a
  decision records is unimplemented until something fails without it. A
  toolchain newer than the floor cannot see the floor.
- **A rebase is a change, and the numbers ride along unmeasured.** Re-take
  every count and re-run every "only X catches it" claim on the rebased tree
  before pushing.

### Traps this repo has already hit

- `0` is truthy in Scheme, and `guard` returns the body's value when nothing
  raises.
- SRFI-64 turns any exception in a test's actual expression into `#f`.
- Chez evaluates argument expressions right to left in compiled library code.
- A CMake variable read before it is `set` expands to nothing, silently — a
  lane's `SOURCES` list hides this well.
- A `cmake -P` script inherits none of the project's policies; every one opens
  with `cmake_minimum_required` (`harness.script-policy-floor` checks it).
- Chez's `bytes-allocated` is a live figure that drops after a collection; the
  cumulative count is `(sstats-bytes (statistics))`.
- `string-set!` is in `(rnrs mutable-strings)`, not `(rnrs)`.
- R6RS forbids `|...|` symbols, and Chez says so only when it reads the file,
  so the aot compile can fail where the source lane passed.
- `(verify-machine m)` returns a verdict; it does not raise. Read
  `verification-ok?`.
- `make parser-refresh` configures but does not build. A red lane the change
  could not have touched is a stale build until proven otherwise: run
  `make build`, then read.
- `akku publish` signs with gpg's default key, and here that is the personal
  key, not the Kiyomi release key. Nothing in its output names the key: pass
  the release key explicitly, then read the `.sig` with `gpg --verify`.
- `akku publish` refuses a git worktree ("Publishing from non-git
  repositories"): run it from a fresh clone checked out at the tag.
