# AGENTS.md

## Project guidelines

### Architecture & portability

* Use the functional core / imperative shell pattern
* Follow the 12 Factor Apps philosophy
* Project is specific to Chez Scheme and will be a Chez library.
* Project should be portable across macos (darwin), linux, and windows
* Project should be portable across amd64 and arm64

### Layout, process & libraries

* Plans live in `/.plans`, decision records in `/.plans/decisions`
* The subagent-driven development ledger lives in `/.superpowers/sdd/` —
  `progress.md` is the spine and `global-constraints.md` binds every task
  brief. Read both before starting slice work; close-outs are recorded there.
* Add entries to `CHANGELOG.md` for each release
* `Makefile` should have a `help` command which lists all of its commands
* Libraries are R6RS `.sls`; libraries and programs contain their own code —
  no shared include bodies. R6RS forbids assigning an exported variable —
  reach mutable state through procedures. (The harness inherits this shape
  from the byte-machine tree it was ported from; see decision 0002.)

### Testing & mutation discipline

* Use TDD / test-driven development
* A test that passes whether the code is right or wrong is worse than no test.
  Every decision in a module gets a mutation that breaks it, and the owning
  specification must notice. Seed an output variable before asserting it is empty.

  **A test is not finished when it passes. It is finished when you have watched
  it fail.** Before calling any new assertion done: copy the code under test to a
  scratch location outside the repo, break the specific decision that assertion
  claims to guard, run the suite, and confirm that assertion fails *by name*.
  Then revert and confirm it passes again. State the evidence when you report.
  - The mutation must break the test *through the asserted property*. If it fails
    for some other reason — a side effect of the edit, a syntax or import error —
    it has proved nothing. Narrow the mutation until the failure is the one you
    predicted.
  - If no mutation can break the assertion, the assertion is empty. Rewrite it, or
    write down in the mutation log that the property is uncovered and why. Leaving
    it silently is the exact failure this rule exists to prevent.
  - **Expect a value only success can produce.** Ask what *else* yields it.
    Truthiness is the obvious trap — in Scheme almost everything is true, so
    `test-assert` is where empty tests hide — but `#f` is worse: it is what a
    missing key returns, what a defaulting accessor returns, and what a
    swallowed exception returns. Prefer a sentinel no failure path produces.
* **Treat an uncaught mutation as a test to strengthen, never to loosen.**
  Find something that can witness the decision before concluding nothing can —
  "this cannot be tested" is a claim to demonstrate. `EXPECT_SURVIVES` is for
  the genuinely unwitnessable, with a written reason; never to reach green.
* **After adding an exit path, re-run the whole mutation suite.** A new exit
  can silently disarm an existing mutation: in the upstream harness a
  reachability guard gave a mutated `harness-begin` its own route to status 3,
  so baseline and mutant both landed on 3 — still reported caught, no longer
  discriminating anything. A green suite will not tell you.
* **Gate a lane on every tool it uses, not only on its own backend.** A lane
  whose expectation is computed by a Chez process needs
  `if(HTTPARSE_CHEZ_EXECUTABLE)` even when Chez is not its own backend; its
  no-runtime skip fires on a missing instance of its own backend and says
  nothing about a missing Chez. The upstream tree shipped this bug twice, on a
  host where both tools were installed and no review could see it.
* **Prefer a mutation caught by a failed comparison over one caught by a
  raise.** A raise-based catch depends on where the mutant happens to crash
  rather than on the assertion naming the decision. Before accepting one, try
  the opposite constant — `(if #f` often fails a case's `check-equal` outright
  where `(if #t` merely makes a later case error.
* **Before deleting a mutation, ask what its REPLACE still changes and whether
  any input can reach it.** A mutation is not dead just because its witnesses
  are; its REPLACE may still narrow a surviving guard reachable through a
  route nothing yet uses.
* **Keep a pass's provenance manifest off the file it mutates, unless
  self-reference is the declared mechanism.** A manifest covering the mutated
  file trips a generic mismatch on any edit — "caught" without discriminating
  the decision. Deliberate self-reference is its own named mechanism: it is
  exactly what makes an exit-path constant witnessable (SchemeMutationSuite
  passes 30/31).
* **Prefer a check to a comment.** When you are about to write a comment stating
  an invariant — these two things must stay equal, this must run before that,
  never call X from here — ask first whether it can be a make target, a test, or
  an assertion. A stated rule does not enforce itself, and the person who most
  needs the comment is the one who did not read it.

  This is not abstract. The rule above about empty tests was already written down
  here, and five tests violating it shipped anyway; it only started holding once
  it carried an executable standard. A Makefile comment requiring the `chez-srfi`
  submodule and `Akku.lock` to name the same commit was violated *in the same
  commit that introduced it*, and only became true once it was `make check-pins`.
  When a comment is load-bearing, that is the signal it should not be a comment.
  (The rename audit spec is this repo's first instance: exit criterion 5 of
  decision 0003, enforced by `httparse.harness.rename-audit.cmake.direct`.)

### Documentation & record discipline

* **Re-measure against the shipped artifact before a number enters a doc or
  record.** Numbers from a pre-design scratch fixture describe the fixture.
  Re-measure, then state what was measured against what, dated and
  platform-stamped.
* **Sweep a retired concept's whole vocabulary, not just its name.** A removal
  gate that greps the departed name is an inventory check, not a vocabulary
  check; live comments asserting a retired contract survive it.
* **Correct a stale instruction in place; annotate a stale record — never
  reword evidence.** A record (a measurement, a finding, a decision record's
  Context) gets a dated amendment, because a record edited to agree with a
  later decision stops being evidence of anything. An instruction (a work
  order, an exit criterion, a live code comment saying what the code is for)
  gets corrected in place — leaving a false one is leaving a landmine, and
  what it used to say is in git. A sentence that was never true is a third
  case: annotated rather than fixed when it is load-bearing. A closed exit
  criterion has become the record of what was asked — it gets a dated
  disposition, never a rewording to match what shipped.
* **Before writing "met" or "moot", find the thing in the tree.** A
  disposition is a claim, and "met" is the easiest to get wrong; "moot" has
  been written about live contracts in force. Then check what the document
  already says elsewhere — such defects usually contradict their own file.
* **Re-read every early artifact against HEAD before the final review**, and
  note what changed in a dated amendment. A record written in a slice's first
  task goes stale against that slice's own later tasks; the tree it was
  decided against is its evidence — state it, then disclose what has since
  changed.

## Closing ritual

Run this when a branch's work is complete and reviewed — all four parts,
without asking which. It is a ritual because each step is easy to skip and
each one left undone costs someone else later.

1. **Squash merge the PR.** One commit per branch on `main`. The granular
   history — the review trail, the fixes, the plan corrections they forced —
   stays readable in the PR.
2. **Catch up local `main`.** Fetch and fast-forward, so the next branch starts
   from what was actually merged rather than from where this one began. If
   local `main` was ahead of origin when the branch started, push it *before*
   step 1: a squash merge onto a stale origin base bakes those commits into
   the squash and leaves local `main` divergent instead of fast-forwardable.
3. **Clean up branches.** Delete the merged branch locally and on the remote.
   A squash merge leaves the branch unreachable by ancestry, so `git branch -d`
   refuses it and `-D` is required — diff against `main` first to confirm
   nothing unique is being dropped.
4. **Reflect.** A retrospective, not a summary of what was done. Put what was
   learned where it will be found again, choosing the destination by who needs
   it: durable facts and corrections into memory, project standards into this
   file, and anything the code should say about itself into a comment at the
   site. A finding recorded only in a session transcript has not been recorded.

## Traps this repo has already hit

Each of these shipped a passing test or a working-looking build that was wrong.
None is obvious from reading the code.

* **`0` is truthy in Scheme, and `guard` returns the body's value when nothing
  raises.** So `(test-assert "…" (guard (e ((pred e) #t) (#t #f)) (accessor x)))`
  passes even when `accessor` never raises — freed pointer fields are zeroed, and
  `0` satisfies `test-assert`. Assert on *what was raised*, compared against an
  expected value, with a distinct sentinel for the no-raise case. Three tests
  guarding the liveness mechanism passed against code with that mechanism deleted.
* **SRFI-64 turns any exception in a test's *actual* expression into `#f`**
  (`vendor/chez-srfi/%3a64/testing-impl.scm:568-571`: the R6RS
  `%test-evaluate-with-catch` is `(guard (ex (else #F)) …)`). An assertion
  expecting `#f` therefore passes when the code under test raises. Never make
  `#f` the expected value of an assertion that can raise — use a sentinel the
  failure path cannot produce: `'agree (or (compare …) 'agree)`. A whole
  differential leg reported 79/79 green against a `cmark-gfm` that crashed on
  every fixture, because the helper's raise on a non-zero exit was swallowed.
* **Chez evaluates argument expressions right-to-left in compiled library code**,
  left-to-right when interpreted.
* **A mechanical rename misses tokens that cross line breaks and tokens with no
  separator.** The harness port's four-pass rename left `bytemachine.` (fused,
  a deliberately-wrong test-name prefix) in a spec, and a `decision 0001`
  reference split across two comment lines; the rename-audit spec caught the
  first on its first clean-tree run, and only a phrase-level sweep caught the
  second. Audit with a scanner that lowercases and matches stems, not with the
  rename map itself.
