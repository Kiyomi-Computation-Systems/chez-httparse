# Upstream brief: deliver a span that closes having delivered nothing

**For a fresh session working in `byte-machine` (not this repository).**
Recorded here under decision 0006 item 4 — every gap the shakeout consumer
finds is recorded, including the ones we work around.

Repository: `github.com/Kiyomi-Computation-Systems/byte-machine`, local checkout
`~/github/byte-machine`, branch `main` at `e9f8d9c`. All line numbers below are
`main`'s, not tag `v0.1.0`'s. Read `AGENTS.md` and `.superpowers/` first: this
project has its own milestone/slice ritual, decision records in `.decisions/`,
a `CHANGELOG.md` and a release ledger, and this work is expected to go through
them rather than around them.

---

## 1. The ask, in one paragraph

A byte-machine span that opens and closes **having delivered no bytes at all**
currently notifies its consumer of nothing. The span-data callback is never
invoked, so a consumer cannot distinguish "this optional field was present and
empty" from "this field never happened". Make an empty span observable, without
reintroducing the spurious deliveries the current suppression exists to prevent.

## 2. Why — the consumer, and the evidence

`chez-httparse` is building an HTTP/1 parser on byte-machine and measuring it
against llhttp's recorded test corpus, where conformance is **bit-exact trace
equality**. llhttp announces empty spans; byte-machine cannot. Concretely, for
the input `GET /foo bar/ HTTP/1.1` llhttp records:

```
off=9 url complete
off=9 len=0 span[protocol]=""          <-- byte-machine cannot produce this
off=9 error code=8 reason="Expected HTTP/, RTSP/ or ICE/"
```

Everything else matches: same accept/reject, same bytes consumed, same error at
the same offset. Measured, not assumed — that run was made through the
reference interpreter against the real fixture.

**This is not an exotic case.** Seven expectations in llhttp's corpus are empty
spans, and the shapes are ordinary HTTP:

| shape | count |
|---|---|
| a header with an empty value (`Line4:`) | 4 |
| a status line with no reason phrase (`HTTP/1.1 200 `) | 1 |
| a malformed request target producing an empty protocol | 1 |
| lenient-mode variants | 1 |

Five of them are inside chez-httparse's v0.1 scope. Empty header values are
common in real traffic, so this cannot be routed around indefinitely.

**Generality test** (chez-httparse decision 0006, which governs what goes
upstream): *would another byte-oriented protocol grammar hit this?* Any protocol
with optional fields hits it immediately. The downstream workaround — an extra
node pair per span to announce emptiness — repeats identically for every span in
every grammar, which is why this belongs here rather than in the consumer.

## 3. Where the behaviour lives

`src/byte-machine/runtime.sls:585`:

```scheme
(define (byte-machine-span-fragment-step/v1 parser state offset f bv to continue)
  (let ((from (parser-span-mark parser)))
    (if (or (>= from to) (unbound-callback? f))
        (list 'goto continue)
        ...)))
```

`from >= to` is the suppression. The file's own comment (around `:560`) states
the design: **one procedure delivers every span fragment**, so that the empty
check is written once rather than three times.

## 4. The four call sites, and what each needs

This is the part that makes the change non-trivial. The single shared procedure
serves callers with *different* requirements:

| site | what it is | needs |
|---|---|---|
| `runtime.sls:617` | the **feed-boundary flush** in `parser-feed!`, on `need-input` only | **keep suppressing** — a read boundary landing exactly at a span start must not fire a zero-byte callback |
| `runtime.sls:861` | the interpreter's **feed-loop span-end** | **should deliver** an empty span |
| `runtime.sls:1172` | the **EOF-side span-end** in `parser-finish!` | **keep suppressing** — and see the trap below |
| `compile.sls:423` | the **emitted** span-end arm, i.e. generated code | **should deliver**, and must agree with `:861` exactly |

## 5. The hard part: emptiness is a property of the SPAN, not the fragment

The naive fix — delete or invert `from >= to` — is wrong, and wrong in a way
that unit tests on single-buffer inputs will not catch.

A span split across two feeds can have an empty **final fragment** while being a
perfectly non-empty **span**: the boundary flush delivers the bytes, the mark is
re-anchored to the next slice's `start`, and then the span ends on that slice's
first byte with `from == to`. Delivering an empty fragment there would announce
"empty" for a span that was not empty.

So the question a span end must answer is *"has anything been delivered for this
span at all?"*, which is state the runtime does not currently keep. Expect to
need a per-span "delivered anything yet" flag, cleared by
`byte-machine-span-open/v1` and set on each delivery.

## 6. Traps found while investigating — please don't rediscover these

**`runtime.sls:1172` depends on the suppression firing.** Its own comment says
so: it passes `empty-bv` and the literal cursor `0` *because* "a mark is never
negative, so `from >= to` holds for EVERY mark and the empty-fragment
suppression fires whatever the mark says." Change the shared procedure's
behaviour and this EOF path starts delivering a spurious empty fragment for
every span end reached at end of input.

**The paused-resume double-delivery hazard.** The comment above `:617` records
that nothing advances the mark after a delivery, so an arm added in the wrong
place "would DELIVER THAT FRAGMENT A SECOND TIME" on resume. Any new state you
add has to survive pause/resume without re-firing.

**`reserved-member-3` is a drift-guarded identifier set.** `compile.sls`'s
comment warns that binding a new local in the emitted body — e.g. rendering
`(let ((m ...)) ...)` around the span arm — moves that list, both of its FINDs,
and `test/common/member3-drift-tests.sps`'s twice-asserted count. Prefer a shape
that keeps the emitted text unchanged.

**Keeping the emitted text unchanged is worth real effort.** If generated code's
call to `byte-machine-span-fragment-step/v1` is untouched and only the runtime's
internals change, the determinism goldens do not re-baseline and the
generated-runtime ABI need not move. One promising shape: let
`byte-machine-span-fragment-step/v1` keep its exact signature and gain the
deliver-if-never-delivered behaviour, and give the flush (`:617`) and the EOF arm
(`:1172`) a separate internal entry point that retains the unconditional
suppression. Emitted code only ever reaches the span-end path, so it would need
no edit. **This is a suggestion from outside the codebase, not a design — please
verify it against the invariants before committing to it.**

## 7. Acceptance criteria

1. A span that opens and closes having delivered nothing invokes its data
   callback exactly once, with an empty range.
2. A span split across feed boundaries, whose final fragment is empty, delivers
   **only** its real bytes — no trailing empty delivery.
3. A boundary flush that finds nothing accumulated delivers nothing.
4. The EOF-side span-end delivers nothing spurious.
5. Pause and resume across any of the above deliver each fragment exactly once.
6. `interpreter ≡ generated` holds — the existing differential lanes
   (`differential-span-tests.sps`, `differential-callback-tests.sps`,
   `differential-counted-span-tests.sps`, and the property suite) stay green.
7. Determinism goldens: either unchanged, or re-baselined deliberately with the
   move explained in the slice report.
8. The CMake and Scheme mutation suites keep their declared-totals discipline —
   totals **recounted from the rewritten manifests, never predicted**. New
   behaviour gets new mutations; an uncaught mutation strengthens a test rather
   than loosening it.

## 8. Decisions the implementer owns

- Whether the new state is a parser slot, a span-declaration property, or
  something else.
- Whether this warrants an ABI bump. The emitted↔runtime contract's *shape* may
  be unchanged while its *behaviour* is not, so a stale generated object meeting
  a new runtime is worth thinking about even if nothing structural moved.
- Whether empty delivery is unconditional or opt-in per span declaration. The
  consumer needs it unconditionally for HTTP; an opt-in would still work but
  costs a declaration field.
- Whether this is a v0.2 release or a patch on v0.1.

## 9. What not to do

- Do not simply delete the `from >= to` check. See §5 and §6.
- Do not solve it by having consumers infer emptiness from the *absence* of a
  data callback before the completion event. chez-httparse's decision 0008
  forbids its trace adapter from computing anything it was not told, and that
  inference is exactly the kind of logic that makes a wrong parser look right.
- Do not change the consumer-visible callback signature. `(f parser ctx bv from
  to)` with `from == to` is the natural shape for an empty delivery.

## 10. How the consumer will pick this up

`chez-httparse` pins byte-machine by gitlink, currently at `v0.1.0`
(`c38e76f`), and treats a pin bump as a first-class event: its own pull request,
re-measured fingerprints for affected goldens, and a `CHANGELOG.md` entry on
both sides. It targets generated ABI 5 and asserts that number by reading it out
of emitted text, so an ABI move there will fail loudly rather than silently —
which is the intended behaviour, not a problem to avoid.
