# Upstream brief: a parser cannot be started in a mode

**For a fresh session working in `byte-machine` (not this repository).**
Recorded here under decision 0006 item 4 — every gap the shakeout consumer
finds is recorded, including the ones it works around.

Repository: `github.com/Kiyomi-Computation-Systems/byte-machine`, local
checkout `~/github/byte-machine`. This consumer is pinned at `v0.4.0`
(`18fcc8b`), generated ABI 7. Read `AGENTS.md` and `.superpowers/` first: that
project has its own milestone/slice ritual, decision records, a `CHANGELOG.md`
and a release ledger, and this work is expected to go through them rather than
around them.

This is the **fourth** brief from this consumer. The first three — the empty
span, the keyword table, and a pause's reason — all shipped, at `v0.2.0`,
`v0.3.0` and `v0.4.0`.

**This one is not blocking, and the workaround is three nodes.** It is filed
because the gap is general and the workaround has a cost worth pricing, not
because a milestone is waiting on it. Decision 0006 item 2 keeps a small local
workaround downstream; this brief exists so the eventual design has a real
grammar behind it.

---

## 1. The ask, in one paragraph

A field's initial value belongs to the **machine**, not to the parser.
`make-parser` fills every field from the declarations the compiled machine
carries, and `(byte-machine runtime)` exports `parser-field-ref` with no
mutating sibling. So two parsers built from one machine cannot start in two
different states, and a grammar whose behaviour depends on a mode the EMBEDDER
chooses has no way to be told the mode. Give a parser a way to start somewhere
other than the declared initials — an argument to `make-parser`, a writer, or
something better.

## 2. Why — the consumer, and the evidence

chez-httparse reproduces llhttp's behaviour bit-exactly against llhttp's own
vendored trace corpus. llhttp parses requests and responses with **one machine
and one entry state**, and which start line it reads comes from a field the
embedder writes before the first byte:

```c
/* llhttp test/fixtures/extra.c */
void llhttp__test_init_response(llparse_t* s) {
  s->type = HTTP_RESPONSE;
}
```

```js
/* llhttp src/llhttp/http.ts */
const switchType = this.load('type', {
  [TYPE.REQUEST]: n('start_req'),
  [TYPE.RESPONSE]: n('start_res'),
}, n('start_req_or_res'));
```

This is not an HTTP-specific shape. Any protocol with a client half and a
server half over a shared grammar has it, and so does any format with a
strict/lenient or version-selected dialect. It passes decision 0006 item 1's
generality test.

**What it costs today.** Three ways out were available downstream:

| way | cost |
|---|---|
| emit the graph twice, once per initial value | doubles a 234 KB checked-in artifact, its determinism lane, and every lane that loads it — to encode one integer |
| a second entry node per mode | refused: with one entry, the other mode's nodes are `unreachable-node` |
| a `decision` callback whose branches STORE the value | three nodes, and what this consumer shipped |

The third is what M7 used, recorded as this consumer's decision 0017. It works,
and it is not obviously worse than a field writer — the embedder answers a
question instead of writing a value, the `required?` flag makes forgetting
impossible, and the branch targets keep the field as the real state. What it
costs is a callback invocation per message where llhttp has a field load, and a
binding the embedder must supply for something that is a constant for the life
of the parser.

## 3. What the shape probably is not

Two designs look obvious and both have a problem this consumer can already see.

**A `parser-field-set!` exported beside `parser-field-ref`.** The runtime's own
comment says the read-only-ness is a design decision rather than an oversight,
and a general writer would let a caller change `content-length` mid-parse
between feeds — which is not a mode, it is corruption. If a writer is the
answer it probably wants to be restricted to a parser that has not consumed a
byte, or to fields declared settable.

**An initial-values argument to `make-parser`.** Cleaner, because it cannot
apply mid-parse, and it composes with `parser-reset!` — which restores the
DECLARED initials today and would have to restore these instead, or the mode
would silently vanish on the first reset. That interaction is the part worth
designing carefully: a reset that forgets the mode is the same bug as a default,
arriving later.

Either way the verifier has something to say. A field with an embedder-chosen
initial is one whose declared initial no longer bounds its value at entry, and
any pass that reasons about field ranges at the entry state needs to know.

## 4. What this consumer can offer

- A real grammar that needs it: `src/httparse/grammar.sls`, node `switch-type`
  and the two `type-store-*` nodes it branches to, plus every `(list 'type ...)`
  branch downstream.
- A before/after node count, if a primitive lands: the workaround is three nodes
  and one required callback declaration.
- The decision record with the alternatives priced:
  `.plans/decisions/0017-the-message-kind-is-a-decision-callback-not-a-field-the-embedder-writes.md`.
