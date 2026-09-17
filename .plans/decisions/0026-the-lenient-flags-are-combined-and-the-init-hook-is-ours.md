# 0026: the lenient flags are combined, and one init hook is ours

Date: 2026-09-17
Status: accepted
Amends: [0010](0010-the-live-llhttp-oracle-is-local-and-opt-in.md) (a fourth binary whose init hook is not upstream's), [0020](0020-lenient-modes-a-flag-at-a-time.md) (a thirty-third site its sweep could not count)
Builds on: [0024](0024-the-url-input-generator-and-the-second-at.md), [0025](0025-both-properties-are-asked-of-both-machines.md)
Milestone: Gate 0 (.plans/2026-09-13-gate0-http-parser-milestone-plan.md), after M11

## Context

[0020](0020-lenient-modes-a-flag-at-a-time.md) landed eleven lenient flags
across thirty-two forks and measured each fork's coverage by disabling it and
counting red lanes. What it could not measure was **combinations**, and the
reason is upstream's harness rather than any choice of ours:

- `llparse-test-fixture` calls `LLPARSE__TEST_INIT(&s)` once, and the hook is
  chosen by a `-D` **at compile time**.
- `test/fixtures/extra.c` supplies 24 hooks — one per (kind, single flag),
  plus two `*_lenient_all`. **There is no hook for any pair.** 55 pairs would
  be 55 binaries.
- And `lenient_all` is a misnomer: it sets **nine of the eleven**, leaving
  `SPACES_AFTER_CHUNK_SIZE` and `HEADER_VALUE_RELAXED` combined with nothing,
  anywhere in the corpus.

So upstream's corpus tests combinations exactly three times, all all-on.
Meanwhile 0020 had already been bitten twice by cross-flag behaviour, both
times by a fixture failing rather than by looking:

- `llhttp__after_headers_complete` suppresses a request's
  invalid-transfer-encoding refusal if **either** `LENIENT_CHUNKED_LENGTH`
  **or** `LENIENT_TRANSFER_ENCODING` is set — in hand-written C, where
  grepping the grammar cannot find it.
- A bare LF after a chunk size needs **both** `OPTIONAL_CR_BEFORE_LF` and
  `OPTIONAL_LF_AFTER_CR`.

Two known interactions out of 55 pairs, found by accident.

## Decision

1. **`generate-lenient` is a fourth producer**, and a `gen-case` carries the
   flags the embedder is to set. Every other producer returns an empty list,
   which is strict.

2. **THE SUBSETS WALK A FIXED SCHEDULE, THEY ARE NOT DRAWN.** Eleven
   singletons, then all 55 pairs, then the whole set: 67 entries, case *i*
   takes entry *i* mod 67. A random draw over 55 pairs needs hundreds of
   cases, and "probably covered" is not a coverage claim. **The seed moves
   the input, not the subset**, so two seeds put the same 67 subsets against
   different messages.

3. **The flag names come from `(httparse modes)`**, not a list written in the
   generator, so a flag added to the parser enters the schedule rather than
   being silently skipped.

4. **A FOURTH ORACLE BINARY, WHOSE INIT HOOK IS OURS.** `http-modes-c` is the
   same parser graph as `http-request-c`, built with
   `tools/oracle/lenient-init.c`, which reads the kind and a mask from the
   environment. One binary answers for any combination.

5. **A line with no mask field goes to upstream's own binary.** Not
   `mask === 0`: that rule keeps every strict comparison against the program
   the corpus was recorded from, and still lets a caller write an explicit
   `0` to ask the modes binary for a strict parse — which is how the two are
   held to each other.

6. **Half the cases match their malformations to their subset.** See below.

## Is the hook inside decision 0010's rule?

[0010](0010-the-live-llhttp-oracle-is-local-and-opt-in.md) says this project
**calls** upstream's harness rather than reimplementing it, because "a
hand-rolled C driver printing the same lines would be a second implementation
of the very format the comparison depends on".

What that protects is the **trace printer**. `lenient-init.c` assigns two
integer fields; it prints nothing, parses nothing and decides nothing, and
every line the oracle emits still comes from upstream's `extra.c`. The
comparison is not made circular by it.

**But "inside the rule" is an argument, so the lane measures it.** Two
equivalences, between them pinning both fields the hook writes:

- **At no flags, `http-modes-c` is `http-request-c`** — and, separately, is
  `http-response-c`, which is the half that would survive a hook that always
  said REQUEST.
- **At one flag, `http-modes-c` is upstream's own dedicated binary.**
  `http-request-lenient-headers-c` is built by upstream's harness with
  `-DLLPARSE__TEST_INIT=llhttp__test_init_request_lenient_headers` and none
  of our code. A hook setting the wrong bit would otherwise be invisible,
  because both sides of every lenient comparison would be wrong together.

Both were watched failing: swapping `LENIENT_HEADERS` for
`LENIENT_CHUNKED_LENGTH` in the hook reddens the single-flag witness and puts
9 comparisons outside the classifier; making the hook ignore the response
environment variable reddens the response half of the no-flags witness.

## What it found

### A bare LF after a request's version needs two flags

| flags | llhttp | this parser, before |
|---|---|---|
| strict | error 9 | error 9 |
| `optional-lf-after-cr` | error 9 | error 9 |
| **`optional-cr-before-lf`** | **error 2** | **accepted** |
| both | accepted | accepted |

Upstream's `.match('\n', ...)` **consumes**, so the lenient arm arrives at
`req_http_complete_crlf` — a node that wants an LF the input has already
spent — and falls through to the *other* flag's strict arm. With
`optional-cr-before-lf` alone the parse still fails, **at the same offset and
with the same reason**, and a different code: `Expected CRLF after version`
as `strict` (2) rather than as `invalid-version` (9).

Reading the reason alone cannot tell the two apart, which is how this parser
came to jump straight to the headers. **This is the third interaction of the
shape 0020 records twice.**

### And a thirty-third fork, which no sweep could have counted

`res_status_code_otherwise` — a response whose status line has **no reason
phrase** and ends in a bare LF — has an LF arm gated on
`OPTIONAL_CR_BEFORE_LF` that this parser had as a flat error. 0020's disable
sweep counted 32 forks and measured every one; **a fork that is not there is
not a site.**

Unlike the request side, one flag is enough here: upstream's lenient arm goes
straight to `onStatusComplete` rather than to a node that wants the LF again.
The two sites read alike and behave differently, so both are now written
down.

No fixture upstream ships reaches it. `Invalid response status` appears
nowhere in the 274 — which `corpus-load-tests.sps` already pinned — and a
status line with no reason phrase *and* a bare LF is two unusual things at
once.

## The generator's own defect, and what found it

The property lane's mode floor fired on its first run: **4 of 134 lenient
inputs parsed without an error.** Drawn freely, an input dies at the first
malformation its subset cannot excuse, and fragmentation invariance is a
property of parses that reach *no* error — so that half of the lane had
almost nothing to hold of.

So half the cases are now **matched**: a malformation is offered only when
the flag that excuses it is in the subset. 4 → 32 at the default seed. The
other half stay **free**, drawn independently, and both of the findings above
came from free cases.

The floor is what said so, which is decision 0025's lesson arriving one
milestone later: a floor over all modes is satisfied by strict alone.

## The cache did not see our source, and a mutation that caught nothing found it

`llparse-test-fixture` keys its build on the generated header, the generated
C and `commonArgs.join(' ')`, then **skips the compile when a file with that
digest already exists**. Our hook reaches it as a *path* in that argument
list, so editing the hook left the digest unchanged and the stale binary was
relinked: a deliberately wrong hook produced a byte-identical oracle and a
green differential.

Measured, not guessed — it is why the first mutation above appeared to catch
nothing. The fix is to put the file's content hash into the arguments as a
define nothing reads, so the digest moves whenever the file does.

**A derived artifact that can stop describing its source is exactly what
`determinism.generated-artifact` exists for on the Scheme side.** This one
had no such lane and needed none once the cache key was right.

## The evidence

| | before | after |
|---|---|---|
| oracle binaries | 3 | **5** |
| flag combinations tested anywhere | 3 fixtures, all all-on | **all 55 pairs, every run** |
| differential `agreed` | 7730 | **9603** |
| unclassified | 0 | 0 |
| property lane, error-free by mode | strict only | **strict 180 · lenient 32** |
| property lane, executor comparisons by mode | strict only | **strict 480 · lenient 201** |
| lenient forks in the grammar | 32 | **33** |
| fixtures | 274 | 274 |

Six seeds at 201 lenient cases each: `unclassified=0` at every one, with both
named classes appearing.

## Consequences

**A MESSAGE YOU USED TO PARSE MAY NOW BE REFUSED, and one you used to see
refused may now parse.** The request-line fix is stricter under
`optional-cr-before-lf` alone; the status-line fork is more permissive under
the same flag. Both are llhttp's behaviour, and `CHANGELOG.md` and
`docs/api.org` say so.

**`lenient_all` is nine flags, not eleven**, and anyone reading upstream's
fixtures should know it. Written down here because the name says otherwise.

**The differential grew a knob per kind.** `HTTPARSE_DIFFERENTIAL_LENIENT_CASES`
defaults to 67 — one full pass of the schedule — and the property lane's to
201, because only its matched half feeds the error-free floor.

**HTTP_BOTH is still unreachable and still deliberate.** The hook could set
it in one line; this parser has no `start_req_or_res` to compare against, so
the hook treats an unset or unknown value as a request, exactly as
`llhttp__test_init_request` does.
