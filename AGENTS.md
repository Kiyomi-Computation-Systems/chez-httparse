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
