# 0016: a `*-finish` fixture prints a field, and the driver never ends the parse

Date: 2026-09-15
Status: accepted
Amends: [0008](0008-bit-exact-trace-conformance-and-the-ratchet.md), item 5 (how the driver treats the `*-finish` types)
Milestone: M6

## Context

[0008](0008-bit-exact-trace-conformance-and-the-ratchet.md) made conformance
bit-exact textual equality against the vendored expected blocks, and the driver
has since M1 treated `request-finish` and `response-finish` as the fixture
types where the input ENDS — feeding everything and then calling
`parser-finish!`, which drives this parser to its `eof-target`s.

That model came from the name. It is wrong, and M6 read the hook:

```c
void llhttp__test_finish(llparse_t* s) {
  llparse__print(NULL, NULL, "finish=%d", s->finish);
}
```

`test/fixtures/index.ts` defines `LLPARSE__TEST_FINISH` for exactly those two
types, and the hook it names is one line. It **prints a field**. It never calls
`llhttp_finish`, so no callback fires and no end-of-input state is entered.
`off=NULL finish=N` is the value of `s->finish` after the last byte, and
nothing more.

The old model produced an `unexpected-eof` the oracle never records, which the
adapter refused — correctly, under [0008](0008-bit-exact-trace-conformance-and-the-ratchet.md)
item 2. The refusal was right and the model behind it was not, and the refusal
is what kept three fixtures honestly failing for four milestones instead of
passing for a wrong reason.

## Decision

1. **The driver never calls `parser-finish!`.** Every fixture is fed and then
   read; no fixture type drives this parser to an end-of-input state.

2. **A `*-finish` fixture gains one line, `off=NULL finish=N`, read off the
   parser's `finish` field.** This is [0014](0014-the-adapter-may-read-parser-fields.md)
   again — the adapter may READ a parser field and may not DERIVE one — and
   the field is llhttp's own, with llhttp's own three values.

3. **A fourth `finish` value is refused.** `llhttp_finish` calls `abort()` on
   one; there is nothing to rename.

4. **A `*-finish` fixture that did not parse cleanly is refused, not guessed,
   and the refusal lives in the adapter.** The hook prints unconditionally, but
   whether llparse's driver still calls it after a failed `llparse_execute` is
   not visible from the vendored sources, and all four `*-finish` fixtures in
   the corpus parse cleanly — so no trace records the combination. Putting the
   refusal in the adapter makes it a FAILING FIXTURE rather than a crashed
   lane, which matters immediately: `response/finish.md#1` is gated as
   `not-yet` and errors exactly as expected.

## Consequences

Two of the three request finish fixtures were already byte-exact without their
last line, because an open span is flushed when a feed ends — which is where
`span[header_field]="Content-Leng"` comes from. Only the line itself was
missing.

`parser-finish!` is now unused by the conformance lane. It stays part of the
generated runtime's API and is still exercised by the generator's own lanes;
what this record says is that no llhttp fixture asks for it.

The general lesson is recorded in AGENTS.md rather than here: a fixture type's
NAME is not its semantics, and the hook that produces a line is readable in
the vendored tree.
