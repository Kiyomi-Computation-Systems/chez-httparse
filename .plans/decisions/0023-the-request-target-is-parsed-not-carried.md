# 0023: the request target is parsed, not carried — the last measured divergence closes

Date: 2026-09-16
Status: accepted
Amends: [0022](0022-the-url-sub-parser-is-a-second-machine.md) (its "what this milestone did not do"), [0018](0018-a-divergence-is-named-and-witnessed-or-it-fails-the-lane.md) (one class retired)
Builds on: [0022](0022-the-url-sub-parser-is-a-second-machine.md)
Milestone: Gate 0 (.plans/2026-09-13-gate0-http-parser-milestone-plan.md), after M11

## Context

M11 built llhttp's URL machine and passed all 21 `url.md` fixtures, and
[0022](0022-the-url-sub-parser-is-a-second-machine.md) said plainly what it had
not done: the HTTP parser still carried its request target as one opaque span
and read on where llhttp's structural check stopped. That was the
`url-machine` divergence class — **45 of the 1142 comparisons** the live
differential makes, and the largest of the three by a wide margin.

The machine existed. It was not in the path.

## Decision

1. **The URL subgraph is spliced into the HTTP request target**, in its other
   configuration: the five part spans STUBBED and one `url-span` across the
   whole target. That is upstream's `new URL(p, false)`, and it is what every
   `uri.md` fixture is written against — the target is still one `span[url]`.

2. **The entry is chosen by the method**, as upstream chooses it:

   ```js
   .otherwise(this.isEqual('method', METHODS.CONNECT, {
     equal: url.entry.connect, notEqual: url.entry.normal }))
   ```

   `CONNECT 0-home0.netscape.com:443 HTTP/1.0` has no scheme and no leading
   slash, so `url-start` refuses its first byte; the connect entry skips
   `start` and opens at the host.

3. **The exits were already right and are unchanged.** `url-close-sp`,
   `url-close-cr` and `url-close-lf` have been upstream's `skipToHTTP`,
   `skipCRLF` and `skipToHTTP09` since M2 — the subgraph is handed them as its
   three exit targets and the caller keeps owning the whole-url span's end.

4. **The `url-machine` divergence class is DELETED, not left at zero.** A class
   with no members is a class that will quietly readmit one.
   [0018](0018-a-divergence-is-named-and-witnessed-or-it-fails-the-lane.md)'s
   two remaining classes are unchanged.

## The evidence

| | before | after |
|---|---|---|
| agreed | 1097 | **1142** |
| url-machine | 45 | **class deleted** |
| late-complete | 4 | 4 |
| unclassified | 0 | 0 |

Every one of the 45 became an agreement; nothing moved into another class.
**274 fixtures unchanged**, which is the other half of the claim: a structural
refusal that broke a recorded target would have shown up there first.

The emitted parser grows **434 → 450 states** and 41 912 bytes. That is what
the refusal costs.

## Two things this turned up

**The verifier found a real bug in the configuration, and only the second
build could have.** `#f` as a span state meant "inside the url, between
parts" — where the whole-url span IS open. The entry nodes run BEFORE it
opens, and needed a state of their own. With separate spans the two coincide,
so the standalone build was correct by accident; the HTTP build was not, and
`inconsistent-span-state` named the exact path from `start` to
`url-entry-connect`. **A description built once is a description tested in one
configuration.**

**The witness went red before anyone looked at the counts.** That is what
[0018](0018-a-divergence-is-named-and-witnessed-or-it-fails-the-lane.md) buys:
each class is anchored to llhttp's own bytes for one reduced input, so a class
that stops existing announces itself rather than sitting at zero. The witness
is kept and INVERTED — same input, same oracle, now asserting the two traces
are one list. A count going to zero is a number; two identical traces are the
behaviour.

## Consequences

**AN EMBEDDER'S PARSER NOW REJECTS TARGETS IT USED TO ACCEPT.** This is the
first change in this project's history that makes a previously-parsed message
an error, and it is not a bug fix in the usual sense — it is llhttp's
behaviour, arrived at deliberately. `OPTIONS a.com:443 HTTP/1.1` was parsed to
completion and is now `Unexpected char in url schema` at offset 9. Anything
relying on the parser's permissiveness about targets will see errors it did
not see before, and `docs/api.org` says so under the callback list.

**No `span[url]` precedes such an error.** The target span is open when the url
machine refuses, and an error abandons an open span rather than flushing it —
the same rule `span[method]` follows, and what `request/uri.md#7` already
recorded.

**`httparse-url-bytes` is deleted.** It was the stand-in for `URL_CHAR` that
the opaque loop used, and its own comment said the finer rules "belong to the
slice that reproduces that error". This is that slice.

**Two of the three measured divergences remain**, both `late-complete`, both
about a completion event at the exact end of input, and both already recorded.
