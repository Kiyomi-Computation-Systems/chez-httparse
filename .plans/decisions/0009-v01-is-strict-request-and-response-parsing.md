# 0009: v0.1 is strict-mode request and response parsing — 190 of the 253 HTTP fixtures; pausing, lenient modes and the URL sub-parser are deferred

Date: 2026-09-13
Status: accepted
Amended by: [0019](0019-the-harness-mode-and-the-two-kinds-of-pause.md) — M9 brought
the 24 `pausing` and 2 `skipBody` fixtures in scope, leaving 37 lenient and 21 URL
deferred. The v0.1 bar this record states was met and shipped unchanged.
Milestone: Gate 0 (.plans/2026-09-13-gate0-http-parser-milestone-plan.md)

## Context

The vendored corpus ([0007](0007-llhttp-corpus-vendored-as-data.md)) partitions
cleanly by what a parser must support to pass each fixture. Measured over the
253 HTTP fixtures at llhttp `v9.4.3`:

| Requirement | Request | Response | Total |
|---|---|---|---|
| strict parsing only | 124 | 66 | **190** |
| a lenient flag | 29 | 8 | 37 |
| pausing from a callback | 13 | 11 | 24 |
| `skipBody` | 1 | 1 | 2 |

Plus 21 URL fixtures in `url.md`. The URL sub-parser is genuinely separable:
`span[url.schema]`, `span[url.host]`, `span[url.path]`, `span[url.query]` and
`span[url.fragment]` appear **only** in `url.md`. Everywhere else — including
`test/request/uri.md`, which is entirely about request-target syntax — the
request target is a single opaque `span[url]`. llhttp builds it as a separate
machine (`llhttp.URL`) for exactly this reason.

The consumer that matters first is the server layer of the architecture
document (§5), which needs `bytes → syntax/events` for requests and responses.
It does not need lenient compatibility modes, and it does not need the parser to
decompose request targets — §6 puts normalisation and decoding above the parser.

Pausing is different in kind from the other two. It is not a feature of HTTP; it
is a property of the parser's control flow, and byte-machine supports it
directly (`make-pause-node`, `callback-pause`, `parser-resume!`). Deferring it
is a decision about corpus coverage, not about whether the machinery exists.

## Decision

1. **v0.1 is strict-mode request and response parsing**: the 190 strict
   fixtures, reached through milestones M1–M7 of the Gate 0 plan.
2. **Requests complete before responses start.** M6 exits with all 124 strict
   request fixtures passing — a usable request parser the server layer can build
   on — and M7 adds the 66 response fixtures as a delta on shared machinery.
3. **Deferred past v0.1, in this order**: pausing and upgrade (24 + 2), lenient
   modes (37), the URL sub-parser (21). Each becomes its own milestone; none is
   abandoned, and all their fixtures are vendored and ratcheted from M1 so the
   deferral is visible as a count rather than an absence.
4. **The ratchet is the exit criterion.** "v0.1 is done" means the manifest
   records 190 fixtures passing and the remaining 84 as deferred-with-reason,
   under [0008](0008-bit-exact-trace-conformance-and-the-ratchet.md)'s two-way
   gate. It is not a judgement call.

## What this rules out

- Shipping v0.1 with a lenient-mode API surface that is stubbed, partially
  wired, or documented as "accepted but ignored". A lenient flag that does not
  change behaviour is worse than one that does not exist.
- Interleaving response support through M2–M6 to "get both at once". The start
  line and the framing decision table are where requests and responses differ;
  everything between is shared, so building requests through the whole stack
  first makes M7 a delta against proven machinery instead of two half-finished
  paths.
- Treating `uri.md` as URL sub-parser work. It is request-target syntax against
  an opaque span, and it belongs to the request milestones.
- Deferring pausing on the theory that byte-machine cannot express it. It can;
  this is a scope choice about corpus coverage.

## Consequences

- The v0.1 release claim is precise and checkable: strict HTTP/1.x request and
  response parsing, 190 of 253 upstream fixtures, with the other 84 enumerated.
  A compatibility claim that names what it does not do is the only kind worth
  publishing.
- The server layer can begin against the parser after M6 rather than waiting for
  the release, since requests are complete at that point.
- Because deferred fixtures are vendored and ratcheted from M1, the day a
  deferred milestone starts, its corpus is already present, already checksummed,
  and already failing for the right reason.
