# 0007: the llhttp corpus is vendored as data, verbatim and checksummed, and parsed at test time

Date: 2026-09-13
Status: accepted
Milestone: Gate 0 (.plans/2026-09-13-gate0-http-parser-milestone-plan.md)

## Context

The architecture document (§4) makes llhttp the behavioural reference and says
the most valuable upstream asset is the accumulated behaviour and test corpus,
not the generated C. A Gate 0 survey of llhttp at `v9.4.3` (commit
`ee51043701d8b90ef647cf04790cbb1c55889825`, one commit past the tag, MIT,
© 2018 Fedor Indutny) establishes what that corpus actually is:

- **23 markdown files, 288K**, under `test/request/`, `test/response/`, and
  `test/url.md`.
- **253 HTTP fixtures**, each exactly one `<!-- meta={...} -->`, one ` ```http `
  input block, and one ` ```log ` expected block — a clean 1:1:1. Plus **21 URL
  fixtures** in `url.md`, which carry no required `meta` (the driver defaults it
  when the input key is `url`).
- Each expected block is a **byte-offset event trace**, not a pass/fail verdict:
  `off=13 len=4 span[url]="/url"`, `off=60 headers complete method=6 v=1/1
  flags=0 content_length=0`, `off=22 error code=8 reason="..."`. Roughly 20
  distinct line shapes over 4,754 expected lines.
- Input decoding is **pure text transformation**: strip the trailing newline,
  remove backslash-escaped newlines, normalise all newlines to CRLF, then expand
  `\r \n \t \f \xHH` and octal escapes. The upstream driver also supports
  `${...}` inline JavaScript — **no fixture in the corpus uses it**.
- Expected blocks expand `\t` and `\f`; a line beginning with `/` is a regular
  expression. Exactly two such lines exist, both in `url.md`.
- Inputs reach the reference binary as C strings, so **no fixture contains a NUL
  byte**.

So the corpus is data — small, self-contained, and already carrying its own
oracle. What it is not is code we need to run.

## Decision

1. **Vendor the 23 `.md` files verbatim** into `test/vendor/llhttp/`, preserving
   upstream's directory shape, alongside upstream's `LICENSE` and a `PROVENANCE`
   file recording the upstream URL, tag, commit SHA, retrieval date, and a
   SHA-256 per file.
2. **A registered spec verifies the manifest.** A vendored file whose bytes do
   not match its recorded checksum fails the build. Drift is a test failure, not
   a discovery.
3. **Refresh is a target, not a ritual**: `make corpus-refresh` re-copies from a
   checkout named by a variable (`LLHTTP_ROOT` or equivalent), never a hardcoded
   developer path, and leaves a reviewable diff plus a rewritten `PROVENANCE`.
   0002's rule against in-tree references to a sibling checkout holds here.
4. **The corpus is parsed at test time by a Scheme loader**, never transcoded to
   s-expressions at vendor time. The loader is a pure function from file bytes to
   fixture records and is tested as one.
5. **The `${...}` escape is not implemented, and the loader refuses a fixture
   containing it** with a diagnostic naming the file and block. If upstream ever
   adds one, we learn it from a failing build rather than from a fixture that
   quietly decoded to the literal text `${...}`.
6. **Vendored fixtures are never edited.** If we come to believe a fixture is
   wrong, or that our parser is right to disagree with it, that is an entry in
   the conformance ratchet and a decision record — never a change to the
   vendored bytes. A golden we may edit when it disagrees with us is not a
   golden.
7. **Attribution**: upstream `LICENSE` retained beside the files, with a note in
   `README.org` and `CHANGELOG.md`. This is test data; it is not part of the
   distributed library.

## What this rules out

- A git submodule for the corpus: 14MB and a Node toolchain dragged in for 288K
  of data, plus a second checkout step in CI, buying only a pointer bump we can
  get from a checksummed copy and a refresh target.
- Vendor-time transcoding to Scheme data: it manufactures a derived artifact
  that hides upstream drift and turns every refresh into a merge conflict, and
  it moves the decoding logic to a place no test exercises against upstream's
  own inputs.
- A refresh that lands without a `PROVENANCE` rewrite, or a checksum manifest
  regenerated in the same commit as the change it was supposed to catch.
- Implementing `${...}` speculatively because upstream's driver has it.

## Consequences

- The conformance suite runs offline with no network, no Node, and no C
  toolchain, which is what makes it affordable under the Linux-only CI
  arrangement of [0004](0004-ci-covers-the-linux-cell-alone.md).
- The 21 URL fixtures land in-tree even though the URL sub-parser is outside
  v0.1 scope. They sit in the ratchet as out-of-scope rather than being left
  out of the vendor, so the day the sub-parser starts they are already present
  and already checksummed.
- Upstream corpus changes are visible as a diff of data, reviewable
  fixture-by-fixture, and each one meets a ratchet that says which fixtures we
  claimed to pass.
