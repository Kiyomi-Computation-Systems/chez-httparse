# Upstream brief: a pause should say why, the way an error does

**For a fresh session working in `byte-machine` (not this repository).**
Recorded here under decision 0006 item 4 — every gap the shakeout consumer
finds is recorded, including the ones it works around.

Repository: `github.com/Kiyomi-Computation-Systems/byte-machine`, local
checkout `~/github/byte-machine`. This consumer is pinned at `v0.3.0`
(`9c027fd`). Read `AGENTS.md` and `.superpowers/` first: that project has its
own milestone/slice ritual, decision records, a `CHANGELOG.md` and a release
ledger, and this work is expected to go through them rather than around them.

This is the **third** brief from this consumer. The first two — the empty span
and the keyword table — both shipped, at `v0.2.0` and `v0.3.0`.

---

## 1. The ask, in one paragraph

A machine that reaches a **pause node** yields `status = 'paused` and **no
other information at all**: the parser result's error slot is `#f`. A consumer
that pauses for more than one reason cannot tell its caller which reason, and a
consumer that renders parser outcomes as text cannot render a pause without
inventing words for it. Give a pause the same (code, reason) identity an error
already has, without turning it into an error — a paused parser is resumable
and an errored one is not, and that distinction is the whole point of the node.

## 2. Why — the consumer, and the evidence

chez-httparse reproduces llhttp's behaviour bit-exactly against llhttp's own
vendored trace corpus. llhttp pauses in several places, and every one of them
carries a code and a message:

```ts
const upgradePause = p.pause(ERROR.PAUSED_UPGRADE, 'Pause on CONNECT/Upgrade');
```

Its test harness prints a pause the way it prints an error, so the corpus
records lines like

```
off=127 message complete
off=127 error code=22 reason="Pause on CONNECT/Upgrade"
```

**Seven request fixtures in scope for this consumer's v0.1 end on exactly that
line**, and it cannot produce it. Its trace adapter may rename parser output
into llhttp's vocabulary and may never compute (its decisions 0008 and 0014),
so with nothing to rename it refuses — the fixtures fail honestly, and stay
failing until this gap closes.

Note what is NOT the problem: llhttp's other "pause", the HTTP/2 preface, is
`p.error(ERROR.PAUSED_H2_UPGRADE, 'Pause on PRI/Upgrade')` — an error despite
the word in its message — and that one renders fine today. The distinction is
exactly the one this brief is about: one of them resumes and one does not.

**Measured rather than read.** A probe machine with a single pause node,
fed the byte that reaches it:

```
(status paused error #f stream-offset 1)
```

and every `'paused` result in `runtime.sls` is constructed with `#f` in the
error slot — the pause-node arm, the callback-pause arm, and both of the
`parser-finish!` arms.

## 3. Where the behaviour lives

* `src/byte-machine/private/ir.sls` — `make-pause-node name continuation
  source-label`. Three fields; no error declaration, unlike `make-error-node`,
  which takes one.
* `src/byte-machine/runtime.sls` — five `make-parser-result 'paused ... #f`
  sites: the interpreter's pause arm, the callback-pause arm, and the
  `parser-finish!` arms for each.
* `src/byte-machine/compile.sls` — the generated arms
  (`byte-machine-make-feed-outcome/v1 (quote paused) pos #f ...`). The `#f` in
  that position is the outcome's error slot, so a generated parser has the same
  hole and **the ABI moves if the slot is filled**.
* The `&byte-machine` error-declaration machinery already does everything
  needed: a declaration is `(name code reason label)`, error nodes name one,
  and the runtime builds a parser-error from it. A pause wants the same.

## 4. Acceptance criteria

1. `make-pause-node` takes an **optional** error declaration name, or a pause
   declaration in the same shape. A pause without one keeps today's behaviour
   exactly, so no existing machine changes.
2. A paused `parser-result` for a pause that declares one reports a value
   carrying the code and the reason — ideally the same shape `parser-error`
   already has, so a consumer's rename table needs no second kind.
3. `status` stays `'paused`. A pause must remain **resumable**, and the
   lifecycle rows (`paused-feed`, `paused-finish`) must not change.
4. The reason survives a resume and a re-pause: pausing twice at two different
   nodes reports two different reasons, not the first one twice.
5. Interpreted and generated executors agree, and the generated ABI is bumped
   if the outcome shape moves — with the ABI lane reading the new number out of
   the emitted text, as `v0.3.0` did for ABI 6.
6. A size measurement before and after, as the keyword-table work recorded.

## 5. Traps found while investigating

* **A pause is not an error and must not become one.** The tempting shortcut
  downstream is an error node, because the corpus line is textually identical
  and no fixture resumes. It is wrong: the parser would be unresumable, and no
  test in the corpus can see the difference. This consumer declined that
  shortcut and is waiting instead.
* **There are two pause paths, not one.** The pause NODE and a callback
  returning `callback-pause` both produce `'paused`. The callback one parks
  `current` on the callback's declared pause continuation. Whatever identity is
  added must cover both, or a consumer gets a reason for one and `#f` for the
  other — which is worse than `#f` for both.
* **`parser-finish!` pauses too**, at its own arms, and those build the result
  from a different code path than the feed arms.
* The empty-span work at `v0.2.0` showed how much care the "keep the emitted
  text unchanged unless it must change" guard is worth; the same applies here,
  and the reserved-member drift guard is still the thing that notices.

## 6. What not to do

* Do not fold the reason into the existing error slot in a way that makes
  `parser-result-error` non-`#f` for a pause **without** also making the
  paused/errored distinction obvious to a consumer that only checks that slot.
  A consumer written before this change may treat "has an error" as "failed".
* Do not make the declaration mandatory. Existing machines pause for one
  obvious reason and should not have to name it.
* Do not design this from this brief alone. Per decision 0006 item 3, the slice
  that does the work owns the design — a primitive designed from a survey is a
  guess with a version number.

## 7. How the consumer will pick this up

Move the gitlink pin, re-measure, and add the row to the trace adapter's error
table — `paused-upgrade . 22` beside the `paused-h2-upgrade . 23` that is
already there. Seven fixtures should go from `not-yet` to `passing` in the same
commit, and the adapter's `trace-recorder-note-paused!`, which today exists
only to refuse, becomes a rename like every other row.
