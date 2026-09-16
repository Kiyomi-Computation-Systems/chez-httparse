# 0020: lenient modes are in, a flag at a time, and the ratchet is what says which — 253 of 253

Date: 2026-09-16
Status: accepted
Amended by: [0021](0021-the-modes-are-settable-fields-and-the-fourth-brief-is-discharged.md) — item 1 only. The eleven optional
callbacks and the twenty-two-node ask chain are gone; `lenient-flags` is a
settable field. Items 2 onward are untouched.
Amends: [0009](0009-v01-is-strict-request-and-response-parsing.md) (its deferral of lenient modes)
Builds on: [0019](0019-the-harness-mode-and-the-two-kinds-of-pause.md)
Milestone: Gate 0 (.plans/2026-09-13-gate0-http-parser-milestone-plan.md), M10

## Context

[0009](0009-v01-is-strict-request-and-response-parsing.md) deferred 37 lenient
fixtures. They need **all eleven** of llhttp's `LENIENT_FLAGS`, because three of
the 37 are typed `lenient-all` and that hook sets nine at once.

Like pausing and `skipBody` before them, none is a property of the input:
`test/md-test.ts` compiles in `-DLLPARSE__TEST_INIT=llhttp__test_init_<type>`
and the hook writes `s->lenient_flags` before the first byte. Unlike those two,
a mode here is a **set** rather than a choice, and that is what made the
milestone more than a line of code.

## Decision

1. **Eleven optional decision callbacks, asked once, ahead of the entry.**
   `parser-field-ref` was read-only with no mutating sibling at the pinned
   `v0.4.0`, so the embedder's answer arrives as a branch key — the shape
   [0017](0017-the-message-kind-is-a-decision-callback-not-a-field-the-embedder-writes.md)
   established for the message kind, applied eleven times. The chain is the
   MACHINE'S ENTRY, so it runs once per parser and the restart between messages
   re-enters below it.

   **This is superseded in fact, and deliberately not in this branch.**
   byte-machine `v0.5.0` shipped settable fields and a `make-parser` inits
   argument in answer to this project's fourth brief, and names the collapse it
   offers: eleven optional callbacks and twenty-two entry nodes become one
   settable field and one argument. The pin move is its own work, on its own
   branch, so that the 253-fixture ratchet can prove it changes nothing. A
   dependency bump folded into a behaviour milestone is a red lane nobody can
   attribute.

2. **Every leniency is one `lenient-fork`**, a mask test on the `lenient-flags`
   field, because that is all `testLenientFlags` is upstream. Thirty-two of them
   across the eleven flags, and the flag is therefore read in exactly one shape.

3. **`lenient-flags` is its own field and not part of `flags`.** The restart
   between two messages stores zero over `flags`; a mode the embedder chose must
   survive that. Upstream separates them for the same reason.

4. **The ratchet scopes a lenient fixture by whether its flags are
   IMPLEMENTED**, not by whether it is lenient. One list in `ratchet.sls`, and a
   slice is one name added to it with its fixtures re-classed in the same
   reviewed diff. That is what made an eleven-flag milestone land in seven
   slices without ever leaving the tree red or the manifest ahead of the parser.

5. **A site's coverage is measured, not assumed.** Each fork is disabled in turn
   and the lanes counted. Thirty of thirty-two are reached by the corpus;
   the two that are not carry unit cases measured against purpose-built lenient
   oracle binaries.

## What this rules out

- **Reading a flag's sites out of `src/llhttp/*.ts` alone.** One site is in the
  hand-written C — `llhttp__after_headers_complete` suppresses a request's
  invalid-transfer-encoding refusal if EITHER `LENIENT_CHUNKED_LENGTH` or
  `LENIENT_TRANSFER_ENCODING` is set. Grepping the grammar for flag names cannot
  find it, and four fixtures across two flags failed at that one line.

- **Assuming a fixture that passes has exercised the code you wrote for it.**
  The disable sweep is cheap and it found two sites no fixture reaches.

## Consequences

**One divergence is reasoned rather than measured, and is marked as one.** Under
`HEADER_VALUE_RELAXED` alone, a NUL in a header value sends llhttp around
`header_value_relaxed → header_value_otherwise → header_value_relaxed` with no
byte consumed, forever: `RELAXED_HEADER_CHARS` excludes NUL, CR and LF, and the
fall-back node handles only CR and LF. This generator's verifier refuses that as
a zero-progress cycle and is right to. So the three bytes upstream leaves to the
fall-back are handled in the node: CR and LF as `after-value` handles them, NUL
as the `Invalid header value char` a strict parse gives.

**No oracle can settle it.** The fixture binary takes its input as argv, so a
NUL cannot be fed to it — the same limit that fixed M8's generated-input lane at
bytes 1..127. Stated here so that a later reader does not mistake an unmeasured
choice for a measured one.

**Upstream's chunk-size arm needs two flags to work.** `OPTIONAL_CR_BEFORE_LF`
sends a bare LF after a chunk size to `chunk_size_almost_done`, which then wants
the LF it has just consumed. With that flag alone the parse still fails, at
`Expected LF after chunk size`; only `lenient_all`, which sets both it and
`OPTIONAL_LF_AFTER_CR`, gets through. Transcribed faithfully rather than
repaired.
