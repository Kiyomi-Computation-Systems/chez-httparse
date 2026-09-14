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

## Traps this repo has already hit

Each of these shipped a passing test or a working-looking build that was wrong.
None is obvious from reading the code.

* `0` is truthy in Scheme, and `guard` returns the body's value when nothing
  raises.
* SRFI-64 turns any exception in a test's *actual* expression into `#f`
  (`vendor/chez-srfi/%3a64/testing-impl.scm:568-571`: the R6RS
  `%test-evaluate-with-catch` is `(guard (ex (else #F)) …)`).
* Chez evaluates argument expressions right-to-left in compiled library code

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
