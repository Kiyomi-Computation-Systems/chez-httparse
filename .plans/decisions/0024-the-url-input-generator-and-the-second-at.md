# 0024: the url is generated input too — and the second `@`

Date: 2026-09-16
Status: accepted
Amends: [0010](0010-the-live-llhttp-oracle-is-local-and-opt-in.md) (a third kind, a third binary, and a seed sweep), [0022](0022-the-url-sub-parser-is-a-second-machine.md) (the asymmetry it left)
Builds on: [0023](0023-the-request-target-is-parsed-not-carried.md)
Milestone: Gate 0 (.plans/2026-09-13-gate0-http-parser-milestone-plan.md), after M11

## Context

[0023](0023-the-request-target-is-parsed-not-carried.md) put the URL machine in
the request target's path and closed the last measured divergence. What it left
behind was written down in the plan as an asymmetry rather than a deferral:

> The live generated-input differential covers `request` and `response` only;
> the url machine's evidence is its 21 fixtures at every chunk size, the
> executor differential, and six oracle-measured cases.

Twenty-one fixtures is not many for a twenty-node machine with six error arms,
and `generate-structured` reaches it only through one field out of ten, from a
pool of ten fixed targets. Every one of those targets parses. **The error arms
had no generated input at all.**

## Decision

1. **`generate-urls` is a third producer**, beside `generate-structured` and
   `generate-mutants`, emitting cases of kind `url`. Its pools are llhttp's own
   decision points read off `src/llhttp/url.ts`: wherever a node has more than
   one edge, both sides of it appear — which is why `:/`, `@@`, `host<com` and
   a byte `URL_CHAR` does not contain sit beside the well-formed spellings.
   They are INPUTS, not expectations.

2. **`url.md` entire is the mutation base list** for the url kind, kept in its
   own `generate-mutants` call rather than added to the message bases. Added
   there it would have changed every message mutant this lane has ever
   produced, and a new divergence would have had two possible causes. Kept
   apart, `HTTPARSE_DIFFERENTIAL_URL_CASES=0` reproduces the pre-url run
   exactly — measured, `agreed=1142`.

3. **A third oracle binary**, built by `tools/oracle/build-oracle.mjs` the way
   `test/md-test.ts`'s `buildURL()` builds it: `new llhttp.URL(p, true)`, both
   exits looped back to the entry, and no `extra` at all. That is the program
   `url.md` was recorded from. `run-oracle.mjs` resolves `url` to it, and
   `drive-trace` resolves `url` to the url bindings and no field initials —
   the kind picks the binary over there and the machine over here.

4. **THE LANE SWEEPS THREE SEEDS**, the one it is given and its two successors.
   See below; this is a measurement, not a precaution.

## What it found, on its first sweep

**llhttp rejects only ADJACENT `@`.** `http://a@b@c/` is a host; only `a@@b`
is `Double @ in url`. This parser refused the second `@` wherever it fell.

Upstream builds `server` and `server_with_at` from one loop, and the edges
inside that loop name `server` **explicitly** rather than the loop variable:

```js
for (const node of [ server, serverWithAt ]) {
  node
    .match(USERINFO_CHARS, server)     // <- server, not node
    .match([ '[', ']' ], server)       // <- server, not node
  if (node !== serverWithAt) { node.match('@', serverWithAt); }
}
serverWithAt.match('@', p.error(ERROR.INVALID_URL, 'Double @ in url'));
```

So `server_with_at` is **one byte wide**: any ordinary host byte sends it
straight back and re-arms `@`. Reading that loop as "the same node twice, minus
one edge" is the mistake, and the code said so in a comment:

> `@` moves to the twin below, which is this node without that edge.

**`url.md`'s "Double `@`" fixture cannot catch it**, because its two `@` are
adjacent — `http://a:b@@hostname:443/`. The corpus cannot tell "no second `@`"
from "no `@` straight after an `@`". Neither can the six oracle-measured exit
cases, which are about the exits.

The fix is two edge targets. The diff in both emitted artifacts is 82 byte
cases each moving from state 10 to state 9, and nothing else.

## The seed sweep, and why it is here

**The default seed did not find it.** Seeds 1, 777 and 20260916 each did;
seed 2 did not.

| seed | unclassified, before the fix |
|---|---|
| 20260915 (default) | **0** |
| 1 | 20 |
| 2 | 0 |
| 777 | 8 |
| 20260916 | 17 |

A lane pinned to one seed is a lane that can be silently lucky, and its green
would have read as evidence. So the run is now the seed it is given and its two
successors — still one number, still reproducible, and any member replays alone
by being named directly. `20260915 + 1` is one of the three that found it, and
re-introducing the bug now turns the DEFAULT run red: **8 unclassified**.

## The evidence

| | before | after |
|---|---|---|
| kinds compared | request, response | **request, response, url** |
| oracle binaries | 2 | **3** |
| agreed, one seed | 1142 | 2573 |
| agreed, the three-seed sweep | — | **7730** |
| unclassified | 0 | 0 |
| fixtures | 274 | 274 |

**The url half is sensitive, measured three ways.** Dropping `#` from
`fragment.match(['?','#'], fragment)` leaves **all 86 other lanes green** —
`url.md`'s 21 at every chunk size included — and turns this lane's
`unclassified` count from 0 to 48. Resolving the `url` kind to the request
binary turns all 1431 new comparisons unclassified and `agreed` back to exactly
1142. Handing a url case to the message machine is a runtime contract
violation, not a divergence.

## Consequences

**AN EMBEDDER'S PARSER NOW ACCEPTS TARGETS IT USED TO REJECT.** The mirror of
[0023](0023-the-request-target-is-parsed-not-carried.md)'s consequence, and the
same reason: llhttp's behaviour, arrived at deliberately. `GET http://a@b@c/p`
was `Double @ in url` and now parses.

**The fix landed in a description that is built twice**, so it is pinned twice:
`unit.url` for the standalone build, where the host is `span[url.host]`, and
`unit.request-target` for the HTTP build, where the whole target is one
`span[url]`. Both expectations are the live binaries' own bytes.

**Three witnesses anchor the url kind**, in the shape
[0018](0018-a-divergence-is-named-and-witnessed-or-it-fails-the-lane.md)
requires even though there is no class to name: the same bytes read as a url
and as a request are two different traces; the exits, which no fixture in the
corpus reaches; and the fragment arm the mutation proved only this lane can
see.

**The property lane is still message-only.** It runs on every pull request and
needs no llhttp, and its two properties — fragmentation invariance, and the two
executors agreeing — hold of the url machine as much as the message one.
Nothing compares `httparse-url-machine` against its interpreted twin on input
the corpus does not contain. That is the next thing, and it is named here
rather than done.
