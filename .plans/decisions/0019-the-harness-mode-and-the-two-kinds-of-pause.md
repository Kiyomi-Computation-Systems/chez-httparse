# 0019: a parser is bound in a harness mode, and an embedder's pause is the one with no declared reason — pausing and `skipBody` come in scope

Date: 2026-09-15
Status: accepted
Amends: [0009](0009-v01-is-strict-request-and-response-parsing.md) (its deferral of pausing and `skipBody`)
Milestone: Gate 0 (.plans/2026-09-13-gate0-http-parser-milestone-plan.md), M9

## Context

[0009](0009-v01-is-strict-request-and-response-parsing.md) put 24 `pausing`
fixtures and 2 `skipBody` fixtures outside v0.1. Both are now in. What made
them a milestone rather than a line of code is that neither is a property of
the INPUT: upstream's harness decides both before the first byte, and the
parser has to be told.

`test/md-test.ts` turns a fixture's meta into a compiler define —
`-DLLHTTP__TEST_PAUSE_<NAME>=1` or `-DLLHTTP__TEST_SKIP_BODY=1` — and caches
one compiled binary per mode. `test/fixtures/extra.c` then guards the matching
callback. The two are exclusive in the C preprocessor:

```c
#ifdef LLHTTP__TEST_PAUSE_ON_HEADERS_COMPLETE
  return LLPARSE__ERROR_PAUSE;
#elif defined(LLHTTP__TEST_SKIP_BODY)
  llparse__print(p, endp, "skip body");
  return 1;
#else
  return 0;
#endif
```

**Two pauses print differently and nothing in the word says which.** A
callback answering `LLPARSE__ERROR_PAUSE` prints the bare `off=N pause`; the
upgrade pause prints `off=N error code=22 reason="Pause on CONNECT/Upgrade"`.
A driver that could not tell them apart would render a deliberate pause where
a parser had merely stopped — and no trace could show the mistake, because the
two shapes are the only evidence there is.

## Decision

1. **A parser is bound in a harness mode, and the mode is a required
   argument.** `trace-recorder-bindings` takes `#f`, `(pause <llhttp callback
   name>)` or `(skip-body)`. It is one argument and not two flags, because
   upstream's `#elif` makes a both-at-once build impossible and a
   representable-but-unbuildable combination is a bug waiting for a fixture.
   Required for the reason the message type is required ([0014](0014-the-adapter-may-read-parser-fields.md)
   and the type's own argument): a parser upstream has not been told its mode
   does not exist.

2. **The pause points are a table read out of `extra.c`, keyed by upstream's
   spelling.** Fifteen rows, listed by taking the function each
   `#ifdef LLHTTP__TEST_PAUSE_*` sits inside. Two of them are not a fold of
   their key: `on_chunk_extension_name` guards the macro inside
   `llhttp__on_chunk_extension_name_complete`, not the span callback of the
   same name. A mechanical underscore-to-hyphen derivation would arm a
   callback upstream never pauses in.

3. **An embedder's pause is the one with no declared reason.** A pause reason
   is declared on a NODE, so the machine's own pause node carries one
   ([0015](0015-generated-abi-7-and-a-pause-carries-its-reason.md)) and a
   callback answering `callback-pause` cannot. Measured with a probe before it
   was written here: `(status paused pause #f consumed 0 next 0)`. A reasonless
   pause renders as the bare word; a reasoned one renders as llhttp's error
   line; **a reasonless pause nobody asked for is refused**, as it was before
   M9.

4. **`skipBody` is a flag the decision callback sets, not a jump.**
   `on-headers-complete` becomes the grammar's second decision callback, and
   its `skip-body` branch stores `F_SKIPBODY` before rejoining the body
   decision — which is what `http.ts` does with the C return value 1.
   A jump would not do: `llhttp__after_headers_complete` reads the flag in two
   places, and a branch can only serve one of them.

5. **The pausing and `skipBody` rows leave the deferred class.** The class is
   derived from each fixture's own meta ([0008](0008-bit-exact-trace-conformance-and-the-ratchet.md)
   item 6), so this is two lines removed from `ratchet-fixture-class` and 26
   rows re-classed in one reviewed diff. 216 in scope, 58 deferred.

## What this rules out

- **Deriving the pause points from the fixture meta by string surgery.** Two
  of fifteen rows would be wrong, and both would arm a five-argument span
  callback through a two-argument door.

- **Reading "the parser paused" as "the harness asked it to".** The armed mode
  is recorded on the recorder, and an unarmed reasonless pause still refuses.
  A parser that stopped where llhttp does not cannot borrow the vocabulary.

- **An embedder-settable field.** `parser-field-ref` is read-only with no
  mutating sibling, and upstream states that as a design decision rather than
  an omission — machine-field access from a callback is read-only so that the
  interpreted and generated lanes cannot diverge. The fourth upstream brief
  prices the gap; M9 needed no part of it, because a decision callback's
  branch key is the same expressive power for this purpose.

## Consequences

**The upgrade disjunct is transcribed, not measured.**
`upgrade && (CONNECT || SKIPBODY || !hasBody)` is in `src/native/http.c` and
is now in the grammar, but no vendored fixture arms skip-body on an upgrade.
Its unit case asserts the consequence the C states — the declared body is not
read — and names itself as source-derived. The recorded half sits beside it so
the pair says which arm the flag changed. The live differential
([0010](0010-the-live-llhttp-oracle-is-local-and-opt-in.md)) is where this
becomes measurable, and it should be run against this arm when next built.

**No parser change was needed for pausing.** Every event node already declared
its pause continuation as the place an unpaused run would have gone, so all 24
fixtures passed on the lane's first run at every chunk size. The milestone was
vocabulary, not behaviour — which is worth recording, because the gap had been
open since M4 and had been read as a parser gap.
