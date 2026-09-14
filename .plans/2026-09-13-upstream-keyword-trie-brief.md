# Upstream brief: a keyword-table primitive that tolerates prefixes and case

**For a fresh session working in `byte-machine` (not this repository).**
Recorded here under decision 0006 item 4. This is the *second* upstream brief;
the other is `.plans/2026-09-13-upstream-empty-span-brief.md`. They are
independent changes to different surfaces and can be done in either order —
see §11.

Repository: `github.com/Kiyomi-Computation-Systems/byte-machine`, local checkout
`~/github/byte-machine`, branch `main` at `e9f8d9c`. Line numbers are `main`'s,
not tag `v0.1.0`'s. Read `AGENTS.md` and `.superpowers/` first: this project has
its own milestone/slice ritual, decision records in `.decisions/`, a
`CHANGELOG.md` and a release ledger.

---

## 1. The ask

byte-machine has `make-sequence-dispatch-node`, whose stated purpose is matching
one of several fixed byte sequences. **Neither of the two keyword tables an HTTP
parser needs can use it.** Provide a construct that can: matching a set of
keywords where one may be a proper prefix of another, and optionally matching
case-insensitively.

## 2. Why — two independent consumers, both measured

**(a) The HTTP method table.** llhttp matches the request method against a table
of 47 names. `make-sequence-dispatch-node` rejects that case list outright:
`GET` is a proper prefix of `GET-PARAMETER`. Checked across all 47 names, that
is the only such pair — and one is enough to make the construct unusable.

The prefix relation is not incidental to the grammar; it is load-bearing
behaviour. `MKCOLA / HTTP/1.1` must record `span[method]="MKCOL"` and then fail
at offset 5, while `GET-PARAMETER / HTTP/1.1` must match whole. The rule that
produces both is *terminate at a complete keyword when the next byte does not
continue toward a longer one*.

**(b) Case-insensitive header matching.** HTTP field names are case-insensitive
(RFC 9110 §5.1), and so are the `Connection` and `Transfer-Encoding` values that
drive framing. `make-sequence-case` takes an exact list of byte values.

## 3. What it costs today, measured

Both consumers are implemented downstream as generated tries of byte-dispatch
nodes, one node per distinct prefix. Measured against byte-machine at `v0.1.0`,
through the generated lane:

| table | keywords | trie nodes | emitted |
|---|---|---|---|
| HTTP methods (case-sensitive, one prefix pair) | 47 | **242** | — |
| header names (`content-length`, `transfer-encoding`, `connection`, `upgrade`) | 4 | 52 | 22,118 B |
| `Connection` values (`keep-alive`, `close`, `upgrade`) | 3 | 28 | 11,489 B |
| `Transfer-Encoding` value (`chunked`) | 1 | 11 | 4,368 B |

333 nodes for 55 keywords. The request-line grammar alone — which is *only* the
start line, no headers, no body — currently emits **120,178 bytes** of generated
Scheme, and the method trie is the bulk of it. A single construct would be a
handful of nodes and should lower to a table rather than to hundreds of states.

## 4. Why the obvious fix is the wrong one

A case-insensitivity *flag* on `make-sequence-case` would close (b) and leave
(a) open, because it would inherit the prefix rejection at
`src/byte-machine/verify.sls:596`:

```scheme
(if (or (byte-prefix? (car as) (car others))
        (byte-prefix? (car others) (car as)))
    (cons (make-diagnostic 'ambiguous-sequence-prefix (node-name n)
                           "one alternative is a terminal prefix of another")
          found)
    found)
```

Worse, it would be **less** capable than what a consumer can already build by
hand: a Gate 0 spike measured a hand-built trie disambiguating `close` from
`closed` correctly, in both cases, where `make-sequence-dispatch-node` refuses
the pair. A new primitive that cannot do what the workaround does is not worth
shipping.

That rejection is correct *for the node as designed* — a sequence dispatch with
no notion of what follows genuinely cannot choose between `GET` and
`GET-PARAMETER`. The gap is the missing notion, not the check.

## 5. The semantics the consumers need

1. **Longest match that the input actually continues.** At a complete keyword,
   if the next byte continues toward a longer keyword, continue; otherwise take
   this keyword.
2. **The delimiter is not consumed.** On taking a keyword, control reaches that
   keyword's target with the following byte still unread, so the grammar decides
   what must follow. This is what makes `MKCOLA` fail *after* the span closes
   and the completion event fires, at the right offset.
3. **A no-match route**, taken when no keyword can be reached from the bytes
   seen.
4. **Optional case-insensitivity per table**, matching ASCII letters in either
   case. The method table is case-SENSITIVE (RFC 9110 §9.1) and header names are
   not, so this is per-table, not global.
5. **Spans compose with it.** The method span opens before the table and closes
   at the matched length — `span[method]="MKCOL"`, five bytes, from six bytes of
   input. Whatever shape this takes must let a span close at the keyword
   boundary rather than at a delimiter.
6. **End of input mid-table** must be routable, as every byte-reading node's is.

## 6. Constraints and traps

- **The verifier's prefix pass** (`verify.sls:600`, `pass-sequence-ambiguity`)
  must keep rejecting genuinely ambiguous sequence dispatches. If the new
  construct is a distinct node kind, that pass should not apply to it; if it is
  a relaxation of the existing kind, the pass needs to know which nodes opted in.
- **`interpreter ≡ generated`.** Both executors must implement the new kind and
  agree — `differential-sequence-tests.sps` and
  `differential-sequence-node-tests.sps` are the precedent, and the property
  suite draws machines over every IR construct, so a new kind belongs in its
  generator.
- **Determinism goldens** re-baseline if emitted text changes; that is expected
  here and should be deliberate and explained, unlike the empty-span brief where
  keeping the text stable is worth effort.
- **ABI.** A new node kind changes what the emitter emits and probably what the
  runtime must understand. Whether `current-abi-version` moves is yours to
  decide; the consumer asserts the ABI by reading it out of emitted text, so a
  bump surfaces loudly rather than silently.
- **Mutation suites** keep their declared-totals discipline: totals recounted
  from the rewritten manifests, never predicted.
- **Lowering cost is the point.** If the new construct lowers to one state per
  prefix, it has moved the problem rather than solved it. A table-driven lowering
  is what turns 242 nodes into something a compiler and a human can both read.

## 7. Acceptance criteria

1. A table containing both `GET` and `GET-PARAMETER` verifies and compiles.
2. Fed `GET-PARAMETER `, it takes the long keyword; fed `GET `, the short one;
   fed `GETX`, it takes `GET` and leaves `X` unread for the next node.
3. A table containing `close` and `closed` distinguishes them — the case a
   hand-built trie already handles and the current construct refuses.
4. A case-insensitive table matches `Content-Length`, `content-length` and
   `cOnTeNt-LeNgTh` to the same target, and a case-sensitive one does not.
5. A span opened before the table closes at the matched keyword's length.
6. Interpreter and generated lanes agree on all of the above, under the property
   suite as well as hand-written lanes.
7. The emitted size for a 47-keyword table is substantially below today's
   242-node equivalent — this is the change's whole justification, so measure it
   and record the before/after in the slice report.

## 8. Decisions the implementer owns

- A new node kind, or a relaxation of `make-sequence-dispatch-node` with an
  explicit terminator concept.
- Whether case-insensitivity is a property of the table, of each case, or a
  separate construct.
- How the table lowers — jump table, nested dispatch, something else.
- Whether `ambiguous-sequence-prefix` survives at all once a construct exists
  that handles the shape it rejects.
- Whether this is v0.2 or a v0.1 patch.

## 9. What not to do

- Do not add case-insensitivity alone. It closes the smaller half and leaves the
  method table impossible; see §4.
- Do not simply delete the prefix check. Without a terminator notion the node
  cannot decide, and the check is what says so honestly.
- Do not lower to one state per prefix. That is the workaround, in the compiler.

## 10. How the consumer will pick this up

`chez-httparse` pins byte-machine by gitlink at `v0.1.0` (`c38e76f`) and treats
a bump as a first-class event: its own pull request, re-measured fingerprints,
and a `CHANGELOG.md` entry on both sides. It will replace its generated tries
with the new construct and report the node and byte counts before and after.

## 11. Sequencing against the other brief

The empty-span brief touches the runtime's span delivery; this one touches the
IR, verifier, lowering and emitter. They do not overlap in code. The empty-span
change is the smaller and is worth doing first if only one can be done, because
it unblocks corpus fixtures the consumer cannot otherwise reach at all — whereas
this one replaces a workaround that, while ugly and large, currently works.
