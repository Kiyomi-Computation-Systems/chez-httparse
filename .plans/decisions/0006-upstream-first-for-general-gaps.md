# 0006: chez-httparse is byte-machine's shakeout consumer — general gaps are fixed upstream, HTTP-specific ones are worked around here

Date: 2026-09-13
Status: accepted
Milestone: Gate 0 (.plans/2026-09-13-gate0-http-parser-milestone-plan.md)

## Context

byte-machine reached `v0.1.0` with an HTTP request fixture of its own
(`test/support/harness/byte-machine/test/http-machine.sls`, grown across its
Milestone 8 through request line, headers, framing, chunked bodies, trailers
and pipelining). That fixture is good evidence, but it is not a consumer: it was
written by the same hand as the generator, and its grammar was chosen to
exercise the IR. Every constructor it needed existed, because the grammar was
picked partly for that.

This project is the first grammar byte-machine did not get to choose. Behavioural
compatibility with llhttp fixes what the grammar must express, down to the byte;
the generator either expresses it or it does not. That is what makes this a
shakeout rather than another fixture.

The Gate 0 survey already found one gap. HTTP field names are case-insensitive
(RFC 9110 §5.1), and framing turns on recognising `Content-Length`,
`Transfer-Encoding` and `Connection` whatever their case. byte-machine has no
transform or case-folding primitive: `make-sequence-case` matches an exact list
of byte values, and `make-sequence-dispatch-node` is the construct whose whole
purpose is matching fixed byte sequences. llhttp gets this from llparse's
`toLowerUnsafe()` transform, which byte-machine has no analogue of.

It can be worked around downstream — a trie of byte-dispatch nodes with a
two-element byte set per letter, generated programmatically from a list of
keyword strings. **Gate 0 built that workaround and measured it** rather than
reasoning about it, against byte-machine at the 0005 pin, through the generated
lane and not only the interpreter:

| trie | keywords | nodes | emitted |
|---|---|---|---|
| header names (`content-length`, `transfer-encoding`, `connection`, `upgrade`) | 4 | 52 | 22,118 B |
| `Connection` values (`keep-alive`, `close`, `upgrade`) | 3 | 28 | 11,489 B |
| `Transfer-Encoding` value (`chunked`) | 1 | 11 | 4,368 B |

All verify and compile through the public API alone. Behaviour is correct across
case (`cOnTeNt-LeNgTh:` → the same terminal as `content-length:`), and correct
at the boundaries that matter: `Connection-Foo:` and `conten:` both fall to the
not-a-known-keyword branch rather than matching.

Two findings change the shape of the argument.

**The workaround is not lossy; it is unverified.** A trie with an explicit
terminator byte disambiguates `close` from `closed` correctly in both cases —
measured — where `make-sequence-dispatch-node` would *reject* that pair outright
as `ambiguous-sequence-prefix`. So the trie is strictly *more* expressive than
the construct it replaces. What is actually given up is not a guarantee about
the grammar but a check on the builder: nothing verifies the trie generator, so
a bug in it is caught only by this project's own tests.

**A naive upstream primitive would be worse than the workaround.** Adding a
case-insensitive flag to `make-sequence-case` would inherit that same
prefix-ambiguity rejection, and would therefore fail on exactly the `close` /
`closed` shape the trie handles today. That is a concrete constraint on any
eventual design, and it is the kind of thing only a real grammar surfaces —
which is the whole argument for item 3 below.

## Decision

1. **A gap is fixed upstream when it is general, and worked around here when it
   is HTTP-specific.** The test for generality: would another byte-oriented
   protocol grammar hit the same wall? Case-insensitive keyword matching passes
   that test. A table of HTTP method names does not.
2. **A general gap goes upstream when the downstream workaround would be large,
   or would leave a correctness-critical builder unchecked.** A small, local
   workaround stays here even if the gap is general; not every rough edge is
   worth a release. Case-insensitive matching goes upstream on *size and
   generality* — 91 nodes and ~38 KB of generated code for eight keywords,
   against roughly three nodes for a primitive — and on the unchecked-builder
   argument, **not** on a claim that the workaround is wrong. It is not.
3. **The upstream change is designed in the slice that hits it, not at Gate 0.**
   This record names the known gap and the policy. It deliberately does not
   specify the primitive, because the right shape depends on constraints —
   verifier passes, lowering, the differential property suite — that are only
   fully in view once a real grammar is pressing on them. A primitive designed
   from a survey is a guess with a version number.
4. **Every gap is recorded, including the ones we work around.** The slice
   report names it; a gap that changed a decision gets its own record here. A
   shakeout whose findings live only in the diff has not shaken anything out.
5. **Upstream changes follow byte-machine's own process** — its milestone and
   slice ritual, its mutation and differential suites, its release ledger — and
   arrive here only as a pin bump under [0005](0005-byte-machine-pinned-by-gitlink-generated-abi-5.md)
   item 3. This repository never carries a patched copy of the generator.

## What this rules out

- Silently routing around a general gap because a workaround was quicker. The
  workaround may still win under item 2, but it wins on the record, not by
  default — as it does here for M4, measured.
- Blocking a milestone on an upstream release that a measured workaround makes
  unnecessary. Upstream-first is a rule about where a *fix* belongs, not a
  licence to stall.
- Adding primitives to byte-machine at Gate 0 on the strength of this survey.
  The case-insensitivity gap is named here as expected work, not as an approved
  design.
- Letting a downstream workaround become upstream's API by accident — shipping
  the trie generator here and later promoting it verbatim because it exists.
- Treating byte-machine's v0.1 API freeze as binding on this project's ability
  to ask for a v0.2.

## Consequences

- Some slices will block on an upstream change, a byte-machine release, and a
  pin bump. The milestone plan sequences work so that round trip is not on the
  critical path in more than one place at a time, and a slice that can proceed
  with a temporary workaround does so rather than stalling.
- byte-machine gains a consumer-driven changelog: entries that exist because a
  real grammar needed them. That is the return on the shakeout, and it is worth
  more than this parser shipping a few weeks sooner.
- **M4 is not blocked.** The gap surfaces there — the first point a header
  *name* drives a decision rather than only a span — but the measured workaround
  means M4 ships with the trie and does not wait on an upstream release. The
  byte-machine work is therefore scheduled *after* M4 lands, when the real
  grammar can specify the primitive and a before/after node count can price it.
- M3 handles field names as opaque spans and does not need the gap closed, so
  the plan reaches M4 with the rest of the header machinery already proven.
- The trie generator is this project's code until a primitive replaces it: it is
  tested here as a pure function from keyword list to node list, and it sits
  behind one procedure so the eventual swap is contained.
