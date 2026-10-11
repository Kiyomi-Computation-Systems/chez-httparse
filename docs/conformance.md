# Conformance

**The short version:** this parser produces exactly the same output as
llhttp — byte for byte — on **all 274 fixtures** in llhttp's own test
corpus, every HTTP fixture and every URL fixture it ships, however the input
is split into feeds.

| Fixtures | What they cover                     |
|---------:|:------------------------------------|
|      190 | strict request and response parsing |
|       26 | pausing and skipping a body         |
|       37 | the eleven lenient flags            |
|       21 | the URL parser                      |

Strict parsing is the default; the lenient flags are opt-in
([modes.md](modes.md)). The 21 URL fixtures test the separate URL parser,
`(generated httparse-url)`, which reports a target's five parts the way
llhttp's own URL test program does. The message parser reports the target as
one span ([url.md](url.md)).

## What is not covered

Two llhttp behaviours are left out on purpose, and no fixture uses either:

- **`HTTP_BOTH`**, where llhttp guesses whether a request or a response is
  coming. Here you always say which ([modes.md](modes.md)).
- **Forcing an upgrade** by returning 2 from `on_headers_complete`. This
  parser's `on-headers-complete` has no such answer
  ([pausing.md](pausing.md#the-field-and-the-hand-off-can-disagree)).

## How it is checked

Each fixture in llhttp's corpus records the exact trace llhttp prints while
parsing it — every event and span, with its offset:

```text
off=0 message begin
off=0 len=7 span[method]="OPTIONS"
off=7 method complete
...
off=60 headers complete method=6 v=1/1 flags=0 content_length=0
```

The test suite replays every fixture through this parser and compares the
trace it prints with llhttp's, byte for byte.

- **At every chunk size.** Each fixture is fed one byte at a time, two at a
  time, and so on up to the whole input at once. A parser that mishandled a
  token split across two feeds would print a different trace at some size.
  Pull requests run the two extremes, one byte and the whole input; the full
  selection runs every size ([building.md](building.md)).
- **By two parsers.** The committed generated parser and an interpreter run
  straight from the grammar must both pass, and must agree. A generator that
  emitted wrong but well-formed code would not get through.
- **Against a ratchet.** A manifest lists every fixture and its status. The
  check fails if a passing fixture breaks, and also if one marked `deferred`
  starts passing — so every change in either direction is a reviewed diff.
  Today no fixture is `deferred`, and the ratchet checks that the count is
  zero.

The corpus is copied unchanged from llhttp `v9.4.3-1-gee51043`, checksummed,
and never edited.

## Beyond the corpus: a live llhttp

274 passing fixtures says nothing about inputs nobody wrote a fixture for.
So an optional test lane runs a real llhttp binary, built from the same
commit as the corpus, side by side with this parser on **generated** input:
messages assembled from a grammar, and mutated copies of real fixtures. Over
about 110,000 comparisons across four seeds, the two agree everywhere except
the two cases below. Any disagreement outside them fails the lane.

### The two known differences

Both happen only when a feed ends **exactly** at the end of a token. No
fixture does that — every one has another byte after the token — and one
more byte makes the two parsers agree again.

- **One event short.** llhttp reports a keyword as complete on its last
  byte. This parser's keyword table waits for one more byte first.

  ```text
  input "HTTP" (a response, 4 bytes, whole buffer)

  llhttp: ... off=4 protocol complete
  ours:   ... (nothing)
  ```

- **One event too many.** Some completions fire one byte **past** their
  delimiter — `url complete`, `header_field complete`. llhttp needs that
  byte to be present; this parser does not.

  ```text
  input "PUT /url " (9 bytes, whole buffer)

  llhttp: ... off=4 len=4 span[url]="/url"
  ours:   ... off=4 len=4 span[url]="/url" / off=9 url complete
  ```

The first is a limit of the generator's keyword table; the second is a
difference in how the two model a completion.

The request target is **not** a difference, though it might look like one.
llhttp checks a target's structure with its URL rules, and so does this
parser, so a target llhttp refuses is refused here at the same offset with
the same code and reason:

```text
OPTIONS a.com:443 HTTP/1.1

llhttp: off=9 error code=7 reason="Unexpected char in url schema"
ours:   off=9 error code=7 reason="Unexpected char in url schema"
```

### What it found that the corpus could not

Each of these is matched to llhttp, and now pinned by a test that needs no
llhttp:

1. `message begin` fires even when the first byte cannot start any method.
2. Several spaces between the method and the target do not produce an
   **empty** target span. llhttp needs one space and skips the rest, before
   the target and before the protocol; so does this parser.
3. The two RTSP methods are spelled `GET_PARAMETER` and `SET_PARAMETER`, with
   underscores, as llhttp's method table spells them. No fixture uses either.
4. A host with two `@` that are **not** next to each other is accepted:
   llhttp accepts `http://a@b@c/p` and refuses only `a@@b`. The corpus's
   "Double `@`" fixture has its two together, so it cannot tell the rules
   apart.
5. A bare LF after a request's version needs **both** LF-related lenient
   flags. With `OPTIONAL_CR_BEFORE_LF` alone, llhttp still refuses — same
   offset, same reason, different code.
6. A response status line with no reason phrase, ended by a bare LF, is
   accepted with `OPTIONAL_CR_BEFORE_LF` alone.

### A rule that holds only for parses without errors

A resumable parser should print the same trace however its input is split.
That is true **when the parse reaches no error**: 71 of 71 error-free
generated cases were identical at every chunk size. It is false for 13 of
169 that end in an error.

The reason: a span still open when the parse fails is printed only for the
bytes a chunk boundary had already flushed.

```text
ICE/2.0 102 OK / Upgrade:websocket / Trailer : X-T     (a token error)

whole buffer: ... header_value complete / error
one byte:     ... header_value complete /
              off=35 len=7 span[header_field]="Trailer" / error
```

llhttp does exactly the same. The corpus can't show it, because its fixtures
are all cases where the rule holds.

## How the live comparison is built

This section is for anyone changing the comparison itself.

### Pairs of lenient flags

llhttp's fixture harness picks its lenient flags at compile time, one binary
per flag, so it cannot test a **pair** of flags: 55 pairs would need 55
binaries, and none exist. Its only combination fixtures set
`lenient_all`, which turns on **nine** of the eleven, so
`spaces-after-chunk-size` and `header-value-relaxed` are never combined with
anything in the corpus.

So the comparison builds one more llhttp binary, `http-modes-c`: the same
parser with [`tools/oracle/lenient-init.c`](../tools/oracle/lenient-init.c),
a small hook of ours that reads the message type and a flag mask from the
environment. It only sets two fields; every trace line still comes from
llhttp's own code. And it is checked against llhttp's own binaries: with no
flags it must match `http-request-c` and `http-response-c`, and with one
flag it must match `http-request-lenient-headers-c`, which llhttp's harness
builds with none of our code.

The flag combinations follow a fixed schedule — the 11 single flags, all 55
pairs, then all eleven together — so changing the seed changes the input,
not which combinations are covered. Half the cases are malformed in ways the
flags under test should accept, so the lenient path runs to the end; the
other half are malformed at random.

### Requests, responses and URLs

`request` and `response` are two modes of llhttp's message parser. `url` is
its URL parser built on its own — the program `url.md` was recorded from,
which reads URL after URL. Each generated case carries its kind, which picks
the llhttp binary on one side and the parser on the other.
`HTTPARSE_DIFFERENTIAL_URL_CASES=0` turns the URL cases off.

### Three seeds, not one

A run uses the seed you give it and the next two. With the `@` rule above
deliberately broken, the default seed alone finds nothing, while three of
five seeds measured do. A comparison pinned to one seed can be lucky, and
"no disagreements" looks the same either way. `HTTPARSE_DIFFERENTIAL_SEED`
names the run, and any one seed can be replayed on its own.

### The property lane

A second lane needs no llhttp and runs on every pull request. On generated
input, for both the message parser and the URL parser, it checks that an
error-free parse prints the same trace however the input is split, and that
the committed parser agrees with the interpreted grammar.

A property can pass by testing nothing, so each kind of input has its own
minimum number of cases. One minimum over the whole run would be met by the
message cases alone: `HTTPARSE_PROPERTY_URL_CASES=0` shows it — a single
overall minimum still passes, the per-kind ones fail.

The `noScan` marks in `url.md` are checked, not trusted. They mark that
file's four error fixtures, but only three of them actually change with the
chunk size: "Failing on broken schema" closes its span before the error, so
there is nothing left open to flush, and llhttp does not change either.

## Running it yourself

The live comparison is optional and never blocks a merge: llhttp's harness
needs Node and a C toolchain, and the evidence CI needs is already in the
tree.

```sh
git clone https://github.com/nodejs/llhttp ~/src/llhttp
cd ~/src/llhttp && git checkout v9.4.3 && npm install
cd - && cmake --preset dev -DHTTPARSE_LLHTTP_ROOT=$HOME/src/llhttp
ctest --preset pr -R differential
```

Without that variable the lane does not exist at all — it is not skipped,
it is never registered. [building.md](building.md#optional-the-live-llhttp-comparison)
covers what configuring it builds and how to remove it.
