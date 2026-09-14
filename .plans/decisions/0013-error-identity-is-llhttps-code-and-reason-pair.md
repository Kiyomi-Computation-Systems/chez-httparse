# 0013: an error's identity is llhttp's (code, reason) pair — one code symbol per llhttp number, and the reason verbatim

Date: 2026-09-13
Status: accepted
Refines: [0008](0008-bit-exact-trace-conformance-and-the-ratchet.md), decision items 2 and 3
Milestone: M2 Slice ③ (.plans/2026-09-13-gate0-http-parser-milestone-plan.md)

## Context

The corpus records an error as one line carrying two things: `off=N error
code=C reason="R"`. [0008](0008-bit-exact-trace-conformance-and-the-ratchet.md)
item 2 says the adapter that renders our errors into that line **may rename,
never compute**, and item 3 keeps llhttp's *integers* out of the public Scheme
API. Neither settles what our error declarations must distinguish, and M2
Slice ③ is the first slice where it matters: it adds ten error declarations,
three of which share a code and two of which share a reason.

**Measured over the vendored corpus at `v9.4.3`:** 42 distinct `(code, reason)`
pairs, over **17 codes** and **41 reasons**. Eight codes carry more than one
reason — code 2 carries seven, and codes 7, 8, 9, 10, 11 and 15 carry four each.
And exactly one reason appears under **two different codes**: `"Expected CRLF
after version"` is code **9** when there is no CR at all and code **2** when a CR
is not followed by LF.

So neither half identifies an error. A code alone cannot: llhttp's four
code-8 reasons are four different failures, and reproducing "Expected HTTP/,
RTSP/ or ICE/" where llhttp reports "Invalid method for HTTP/x.x request" is a
trace mismatch. A reason alone cannot either, and the one collision that proves
it is inside this very slice.

Before this slice, the grammar carried one `invalid-line-ending` code for both
CRLF failures and messages of our own invention beside messages lifted from
llhttp. Either choice is defensible; having both without a rule is not.

## Decision

1. **One code symbol per llhttp error number this parser can produce.** The
   symbol is descriptive (`invalid-version`, `invalid-constant`, `strict`), the
   mapping to a number is one-to-one, and a symbol is never reused across two
   llhttp numbers. `invalid-line-ending` is retired: it spanned llhttp's 9 and
   2, which is exactly the thing that cannot be rendered.
2. **The reason string is llhttp's, verbatim**, wherever we reproduce an llhttp
   behaviour. Not paraphrased, not re-worded to match our own naming, not
   normalised in case or punctuation.
3. **An error's identity is the pair.** Every error declaration is a distinct
   `(code symbol, reason)` pair, and both halves are checked in tests, because
   the corpus checks both.
4. **The adapter therefore renames one thing and passes the other through.** It
   maps a code symbol to llhttp's integer — a total table over a closed set,
   failing hard on an unmapped symbol — and emits the reason as it found it.
   This is the least an adapter can do and still be a rename, which is the
   direction [0008](0008-bit-exact-trace-conformance-and-the-ratchet.md) item 2
   points.
5. **A placeholder is named as one.** `bad-url`'s reason is ours, not llhttp's,
   because llhttp's four code-7 reasons belong to the URL sub-parser that
   [0009](0009-v01-is-strict-request-and-response-parsing.md) defers. It is the
   only one left in the request line, and it is a placeholder until that slice.

## What this rules out

- A code symbol chosen for our taxonomy's convenience that maps to two llhttp
  numbers, or to none.
- An adapter that reconstructs a reason from a code, a node name, or an offset.
  A reason our parser did not produce is a trace the parser did not justify,
  which is the failure mode [0008](0008-bit-exact-trace-conformance-and-the-ratchet.md)
  exists to prevent.
- Improving on llhttp's wording. `"Expected SOURCE method for ICE/x.x request"`
  is not a sentence we would write, and rewriting it breaks conformance for no
  gain — the wording is part of the interface being reproduced.
- Treating `parser-error-code` as sufficient in a test. A check that asserts the
  code alone passes for three of the four code-8 failures.

## Consequences

- This library's public error messages are llhttp's. That is a deliberate
  consequence of aiming at bit-exact trace parity, and it is visible in the
  grammar rather than hidden in a test-only table.
- Adding a behaviour means reading llhttp's reason string out of its source or
  the corpus, not inventing one. Slice ③ took all ten of its strings from
  `src/llhttp/http.ts` and checked them against the fixtures that record them.
- An llhttp release that re-words a reason shows up as a conformance failure at
  the corpus refresh, alongside the fixture whose expected block moved — which
  is the same signal, in the same place, as a renumbered code.
