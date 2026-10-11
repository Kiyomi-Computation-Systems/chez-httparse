# Conformance

The claim is narrow and checkable: **HTTP/1.x request and response parsing,
byte-exact against llhttp's own recorded traces, for all 274 fixtures in its
conformance corpus** — every HTTP fixture and every URL fixture it ships, at
every chunk size.

Of the 274:

| fixtures | exercise                            |
|---------:|:------------------------------------|
|      190 | strict request and response parsing |
|       26 | pausing and `skipBody`              |
|       37 | the eleven lenient flags            |
|       21 | the url sub-parser                  |

Strict is the **default**; lenient is opt-in. The eleven flags are a bitset
you hand [`make-parser`](reference.md#make-parser-procedure), not eleven
callbacks it asks you — see [modes.md](modes.md).

**The 21 URL fixtures test a second parser, and they pass.** They exercise
`(generated httparse-url)`, whose five separate spans exist only in llhttp's
own url binary. The HTTP parser's request target is one `span[url]`; see
[url.md](url.md).

Outside the corpus, two llhttp behaviours are not reproduced:

- `HTTP_BOTH`, which sniffs whether a request or a response is coming. You
  choose the type when you make the parser; see [modes.md](modes.md).
- An `on_headers_complete` that returns 2 to force an upgrade. See
  [connection.md](connection.md) for what you do instead.

No fixture uses either. A compatibility claim is only worth publishing if it
names what it does not do.

## How conformance is measured

llhttp's test corpus is not a list of inputs. Each fixture carries the exact
trace llhttp's own instrumented parser prints for it, offset by offset:

```text
off=0 message begin
off=0 len=7 span[method]="OPTIONS"
off=7 method complete
...
off=60 headers complete method=6 v=1/1 flags=0 content_length=0
```

The corpus is vendored verbatim from llhttp `v9.4.3-1-gee51043`,
checksummed, and never edited. Every in-scope fixture is replayed **at every
chunk size from 1 to its length**, and the parser's rendered trace is
compared byte for byte. That is where resumability is tested: a parser that
mishandled a token split across feeds would produce a different trace at
some size. The pull-request selection replays the two extremes — one byte at
a time and the whole buffer — and the complete selection replays every size;
see [building.md](building.md).

Two executors run the same fixtures and must agree: the committed generated
parser and a reference interpreter built from the grammar. A code generator
that emitted something wrong but well-formed does not pass.

The result is a **ratchet**: a manifest naming every fixture and its status.
It fails both when a passing fixture breaks and when one marked `deferred`
starts passing, so a change in either direction is a reviewed diff.

## Nothing is out

Every fixture the corpus ships is gated and passing: **274 of 274**. No
fixture is marked `deferred`, and the ratchet asserts that as a count of
zero rather than by having no such rows.

**That is a statement about fixtures, not about every difference from
llhttp.** The divergences below are found by generated input the corpus does
not contain. There are two, and they are the same narrow case seen from both
sides.

## Divergences from llhttp, measured

A live llhttp binary, built from the same commit the corpus came from, runs
against generated input the corpus does not contain: messages assembled from
a grammar, and mutants of real fixtures. Over ~110,000 comparisons across
four seeds, every disagreement falls into one of the classes below. An
unclassified one fails the lane.

### Not a divergence: the request target is parsed, not carried

```text
OPTIONS a.com:443 HTTP/1.1

llhttp: off=9 error code=7 reason="Unexpected char in url schema"
ours:   off=9 error code=7 reason="Unexpected char in url schema"
```

llhttp runs a URL sub-parser over the request target and rejects targets
whose **structure** is wrong. So does this parser: the same URL machine runs
over the request target, so a target llhttp refuses is refused here, at the
same offset, with the same code and reason.

**The target is one `span[url]`**, which is what every `request/uri.md`
fixture is written against. llhttp builds the same machine two ways — five
separate spans for its `url` binary, one whole span inside the HTTP parser —
and so does this parser.

**This makes the parser strict about targets.** A target with the wrong
structure is an error, not a span. That is llhttp's behaviour, reproduced
deliberately; see [url.md](url.md).

### A completion event at the exact end of the input

Two mirrored cases, both visible **only** when a feed ends exactly at a
token boundary. No recorded fixture does: every one has a byte after the
token.

- **One event short.** llhttp fires a keyword's completion on the keyword's
  last byte. The state-machine generator's keyword table reports
  `need-input` there and takes the terminal edge only when a further byte
  arrives.

  ```text
  input "HTTP" (a response, 4 bytes, whole buffer)

  llhttp: ... off=4 protocol complete
  ours:   ... (nothing)
  ```

- **One event too many.** Where a completion fires one byte **past** its
  delimiter — `url complete`, `header_field complete` — llhttp needs that
  byte to be present and this parser does not.

  ```text
  input "PUT /url " (9 bytes, whole buffer)

  llhttp: ... off=4 len=4 span[url]="/url"
  ours:   ... off=4 len=4 span[url]="/url" / off=9 url complete
  ```

One more byte in either case and the two agree exactly. The first is a
limitation of the generator's keyword table; the second is a modelling
difference.

## A property that is true only with its qualifier

A resumable parser should produce the same trace however the bytes arrive.
**That holds for a parse that reaches no error**: over generated input, 71
of 71 error-free cases were invariant across chunk sizes. It is false for 13
of 169 that error.

A span still open when the parse fails is printed only for the bytes a chunk
boundary already flushed:

```text
ICE/2.0 102 OK / Upgrade:websocket / Trailer : X-T     (a token error)

whole buffer: ... header_value complete / error
one byte:     ... header_value complete /
              off=35 len=7 span[header_field]="Trailer" / error
```

llhttp does exactly the same. The unqualified property is false, and the
corpus cannot show it, because upstream's fixtures are ones the qualifier
holds for.

## What the differential reaches that the corpus does not

Each of these is a behaviour no corpus fixture reaches, matched to llhttp
and pinned by an offline check:

1. `message begin` fires even when the first byte is one no method may start
   with. No fixture begins with such a byte.
2. Repeated spaces between the method and the target do not produce an
   **empty** target span. llhttp requires one space and skips the rest; so
   does this parser, before the target and before the protocol.
3. The two RTSP methods are spelled `GET_PARAMETER` and `SET_PARAMETER`.
   That is how llhttp's map keys them — underscores, as RFC 2326 spells
   them — and only `'M-SEARCH'` is quoted and hyphenated. No fixture uses
   either.
4. A host holding two `@` that are not adjacent is accepted. llhttp accepts
   `http://a@b@c/p` and refuses only `a@@b`. `url.md`'s "Double `@`"
   fixture has its two adjacent, so neither the corpus nor the
   oracle-measured cases can tell the two rules apart.
5. A bare LF after a request's version needs **both** lf flags. With
   `OPTIONAL_CR_BEFORE_LF` alone llhttp still refuses, at the same offset,
   with the same reason and a different code. Only a flag **pair** can see
   it.
6. A response status line with no reason phrase, ending in a bare LF, is
   accepted under `OPTIONAL_CR_BEFORE_LF` alone. Disabling each lenient fork
   in turn cannot find a site like this one, because a fork that is not
   there is not a site.

## Both properties, both machines

The property lane needs no llhttp and runs on every pull request. It asks
two things of generated input:

- a parse that reaches no error produces the same trace however the bytes
  arrive, and
- the shipped artifact agrees with the interpreted grammar.

It asks both of **both** machines, the message parser and the url
sub-parser, each with its own artifact and its own twin.

Every floor in that lane is **per kind**. Both properties pass vacuously
over a run that selected nothing, so both are guarded by a floor. One floor
over the whole run would be satisfied by the message kinds alone, whatever
the url machine contributes. `HTTPARSE_PROPERTY_URL_CASES=0` shows it: the
global floor passes, the per-kind ones fail.

`url.md`'s `noScan` annotation is **checked, not quoted**. It marks that
file's four error fixtures; only three of them actually diverge across chunk
sizes. "Failing on broken schema" closes its schema span before the error,
so no chunk boundary has an open span to flush early — and llhttp does not
diverge on it either.

## Lenient flags, in combination

Upstream's fixture harness picks its init hook with a `-D` at compile time
and ships one per (kind, single flag). So you cannot ask it about a **pair**
of flags at all: 55 pairs would be 55 binaries, and no hook exists for any
of them. Its only combination fixtures are three `*-lenient-all` ones, and
`lenient_all` sets **nine of the eleven**, leaving `spaces-after-chunk-size`
and `header-value-relaxed` combined with nothing anywhere in the corpus.

A fourth oracle binary, `http-modes-c`, is the same parser graph built with
[`tools/oracle/lenient-init.c`](../tools/oracle/lenient-init.c), an init
hook of ours that reads the kind and a flag mask from the environment. It
assigns two integer fields and prints nothing. Every trace line still comes
from upstream's `extra.c`, so the comparison never reads a trace printer of
ours.

**It is held to upstream's own binaries rather than argued into place.** At
no flags it must equal `http-request-c` and `http-response-c`; at one flag
it must equal `http-request-lenient-headers-c`, built by upstream's harness
with none of our code.

The flag subsets **walk a fixed schedule** — 11 singletons, then all 55
pairs, then the whole set — so the seed moves the input rather than the
coverage. A random draw over 55 pairs needs hundreds of cases, and "probably
covered" is not a coverage claim.

Half the cases **match** their malformations to the subset they were given,
so the lenient path is walked to the end; the other half draw them
independently.

## The kinds and the binaries

`request` and `response` are two modes of llhttp's message parser. `url` is
its URL sub-parser built standalone — `test/md-test.ts`'s `buildURL()`, with
both exits looped back to the entry, which is the program `url.md` was
recorded from. The kind travels with each generated case and picks the
binary on llhttp's side and the machine on ours, so a url case is never
asked of a message parser.

`HTTPARSE_DIFFERENTIAL_URL_CASES=0` turns the url kind off and leaves the
request and response kinds as they are.

## One seed is not a lane

A run is the seed you give it and its **two successors**, and that is a
measurement rather than a precaution. With the `@` rule above broken, the
default seed alone finds nothing; three of five seeds measured find it. A
lane pinned to one seed can be silently lucky, and `unclassified=0` reads as
evidence either way.

`HTTPARSE_DIFFERENTIAL_SEED` still names the run with one number, and any
member of a sweep replays alone when you name it directly.

## Running it yourself

The differential is local and opt-in, never a merge gate: llhttp's own test
harness needs Node and a C toolchain, and the evidence CI needs is already
checked in.

```sh
git clone https://github.com/nodejs/llhttp ~/src/llhttp
cd ~/src/llhttp && git checkout v9.4.3 && npm install
cd - && cmake --preset dev -DHTTPARSE_LLHTTP_ROOT=$HOME/src/llhttp
ctest --preset pr -R differential
```

Without that variable the lane is **absent** — not skipped, not failing,
not registered at all. [building.md](building.md#the-live-llhttp-differential)
covers what configuring it builds and how to remove it again.
