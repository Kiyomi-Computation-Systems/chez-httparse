# Performance

What the parser costs in memory and time, and how it compares with
[llhttp](https://github.com/nodejs/llhttp), the C parser it is checked
against. Every figure below was measured on an Apple M-series laptop with
Chez Scheme 10.4.1 (`tarm64osx`), at the generator pin each section names.

## At a glance

| Characteristic                                   | Measured                                                   |
|:-------------------------------------------------|:-----------------------------------------------------------|
| Memory does not grow with the size of a body     | 2,912 B per parse with a 10-byte body; 2,960 B with 10,000 |
| Feeding in small pieces does not build up        | 444 B per feed on a 50-byte message; 384 B on 10,043 bytes |
| A header name cannot be used to inflate memory   | 0 B extra, however much of a known name it matches         |
| Speed, a typical request in one piece            | 80–82 MB/s, about 275,000 requests a second                |
| Speed, a response with a 1 KB body               | 390–401 MB/s, about 355,000 responses a second             |
| Speed, the worst case: one byte per feed         | 13 MB/s, about 44,000 requests a second                    |
| Building a new parser                            | about 1.9 µs — keep one per connection                     |
| Compared with llhttp, on llhttp's own benchmark  | llhttp is 8.8–12.2× faster                                 |
| Compiled ahead of time versus loaded from source | the same speed                                             |
| Wrapping llhttp through the FFI instead          | a straightforward wrapper is no faster than this parser    |

What this means when you embed it:

- **Feed whatever the socket gives you.** Small reads cost more calls, not
  more memory per call, and the result is the same as one big read.
- **Keep one parser per connection.** It parses message after message; a new
  parser per message adds about 1.9 µs each time.
- **Large bodies are free to pass through.** A body callback gets a position
  in your buffer, never a copy.

The rest of this page backs each line up.

## Memory

The allocation lane, `httparse.property.allocation`, runs on every pull
request. It checks shapes, not exact byte counts: a number copied from the
parser into a test only records what the parser did, not what it should do.

### A bigger body costs no more memory

A body callback receives `(bv from to)`, a position in your bytevector.
Nothing is copied, so a large body costs what a small one does.

| Message                        | Allocated per whole-buffer parse |
|:-------------------------------|---------------------------------:|
| `POST` with a 10-byte body     |                          2,912 B |
| `POST` with a 10,000-byte body |                          2,960 B |

A thousand times more body, 1.6% more memory. A parser that copied spans
would show a thousandfold difference.

Both messages carry the same headers, so a cost paid once per header is in
both figures and cancels out. The generator keeps two such costs out of the
parse: a callback answers with its next state rather than a freshly
allocated `(goto TARGET)`, and the keyword tables that read `POST`,
`HTTP/1.1` and `Content-Length` match in place rather than copying the
prefix at every byte.

These are the compiled lane's figures, identical on all 40 runs measured.
The source lane can read a few bytes higher on the two `POST`s; see
[Source and compiled run at the same speed](#source-and-compiled-run-at-the-same-speed).

### Small feeds do not add up

Each [`parser-feed!`](reference.md#parser-feed-procedure) returns a result,
so a parse fed in pieces allocates once per feed. What must not happen is a
per-feed cost that grows as the message goes on — the sign of re-reading or
re-copying input already consumed.

| Message, fed one byte at a time | Allocated per feed |
|:--------------------------------|-------------------:|
| 50 bytes                        |              444 B |
| 10,043 bytes                    |              384 B |

Flat, across a message two hundred times longer.

The figure is the difference between a byte-at-a-time parse and a
whole-buffer one, divided by the length. The byte-at-a-time parse pays one
cost the whole-buffer one never does: a keyword split across feeds is kept
between them as a list, rebuilt at each feed. So a change that makes only
the whole-buffer parse cheaper **raises** this figure.

### A header name cannot inflate memory

The parser reads five header names by name: `connection`,
`content-length`, `proxy-connection`, `transfer-encoding` and `upgrade`. A
keyword table that copied its matched prefix at every byte would cost about
k²/2 for a name matching k bytes, and a client choosing its header names
would choose the parser's memory use: 97 `Transfer-Encodinx` fields would
cost 138 times the request's own size. This parser's table matches in place.

The lane checks a request whose 17-byte field name begins with the first k
bytes of `Transfer-Encoding` (compiled lane):

| k bytes matched |   0 |   1 |   4 |   8 |  16 |
|:----------------|----:|----:|----:|----:|----:|
| Extra memory    | 0 B | 0 B | 0 B | 0 B | 0 B |

The whole parse is 2,928 bytes at every k. The check allows 32 bytes of
drift — half the 64 bytes one matched byte would cost a copying table —
because the source and compiled lanes' averages can differ by a few bytes.

## Speed

The throughput lane, `httparse.benchmark.throughput`, prints its figures but
does not fail a pull request on them: a rate moves with the machine and with
whatever else is running. It fails only on a change of **kind** — an
accidental quadratic, a per-byte allocation, a rescan.

With the generator pinned at `v0.7.0`, building a new parser for each
message:

| Input                                        |      Messages/s |    MB/s |
|:---------------------------------------------|----------------:|--------:|
| 308-byte request, 8 headers, in one piece    | 272,340–278,260 |   80–82 |
| 1,166-byte response, 1 KB body, in one piece | 350,684–360,563 | 390–401 |
| the same request, one byte per feed          |   43,835–44,444 |      13 |

The ranges are the middle half of 80 runs. Single runs can stall — the
slowest read 17,021 messages a second on the one-byte row — so read these
as an order of magnitude, not a specification.

**One byte per feed is the worst case**, and it is about six times slower,
because the parser pays its per-feed costs 308 times instead of once. Each
feed re-enters the generated parser through its entry dispatch, and makes
one bookkeeping call costing about 2 ns. A whole-buffer parse pays these
once and cannot see them.

**These figures include building a parser per message.** That costs about
1.9 µs — more than half of a 308-byte request's time at this speed. Reusing
one parser, as llhttp's benchmark below does, roughly doubles the rate.

## Compared with llhttp

llhttp is a C parser generated from a state-machine description, and it is
what this parser's behaviour is checked against. On llhttp's own benchmark,
llhttp is **8.8 to 12.2 times faster**.

| Input                                |     llhttp | chez-httparse | Ratio |
|:-------------------------------------|-----------:|--------------:|------:|
| 703 B request, 8 headers, big cookie | 2,515 MB/s |    205.6 MB/s | 12.2× |
| 520 B chunked `POST`                 | 1,654 MB/s |    165.1 MB/s | 10.0× |
| 52 B URL                             | 2,020 MB/s |    229.8 MB/s |  8.8× |

Chez 10.4.1 at `optimize-level 0`, llhttp 9.4.3, the generator pinned at
`v0.7.0`. Each figure is the median of seven rounds, llhttp's binaries and
the Scheme program alternating within each round. Both sides count a
megabyte as 2²⁰ bytes, as llhttp's output does, and every one of the
381,842 and 516,222 repetitions of the two requests completed a message.

A ratio taken in one sitting holds across machines better than a rate does,
and it says how much of the cost is this parser rather than parsing itself.

### How it was measured

The benchmark is llhttp's own. `llparse-test-fixture`, the harness that
builds the binaries this project compares traces against, has a `bench`
mode; llhttp's `npm run bench` drives it. The callbacks still fire but print
nothing, so what is timed is the parse and its dispatch. This project's
benchmark bindings do the same: bound, called, and doing nothing.

Upstream sizes its loop by a fixed total of **bytes** — 8 GiB — so a short
input does not shrink the measured interval. It keeps **one parser** for the
whole loop and feeds it the input again each time, so a keep-alive request
is parsed as the next message on the same connection. The Scheme side does
the same, so neither side pays to build a parser inside the timed region.

**The URL row is mostly a fragment.** The input ends inside its fragment and
the parser is never reset, so from the second repetition on both parsers
read each copy as more fragment bytes. That is what upstream's loop
measures, and the Scheme side reproduces it rather than correcting it.

**A parser per message costs about 1.9 µs.** Building a fresh parser for
each repetition instead gives 130.7 and 101.2 MB/s on the two requests —
19.2× and 16.3× — and the extra time per message is the same on both.

### Why the gap is what it is

The ratio is a real difference in cost between the two parsers, and it
depends on how the generator emits the parser's dispatch.

Chez compiles `(case st ...)` over integer keys as a linear scan, about
0.31 ns for each arm skipped, so a parser dispatching through one `case`
pays for wherever its busiest states happen to be numbered. The message
parser has 530 states. The generator emits its hot paths another way:

- **Every state is a procedure**, and a jump to a state known when the code
  is generated is a direct tail call: **0.80 ns, against 185.85 ns** for the
  same state through the scan.
- **A byte class is a range test**, not one arm per byte: 1.25 ns for a
  lowercase letter, which is most of HTTP, against 21.60.
- **A callback answers with its next state**, always one of the literals the
  generator wrote, rather than a freshly allocated `(goto TARGET)` — 128
  bytes of garbage per header.
- **The entry dispatch is a binary search**: ten comparisons over 530
  states, where a scan averages 265.

Reordering the arms of such a `case`, which changes nothing about what it
does, shows the effect directly: in a scanning build, the request target's
cost moves from 239.8 to 42.4 ns per byte, with the URL parser unmoved as a
control.
[The design record](../.plans/decisions/0027-the-cost-is-dispatch-position-not-grammar.md)
has the measurements.

## Would wrapping llhttp be faster?

llhttp is ten to twelve times faster, Chez has a foreign-function interface,
and llhttp builds a shared library — so why parse in Scheme? Because **the
speed does not survive the crossing into Scheme.**

### Each callback has to cross the boundary

The comparison above is llhttp calling callbacks that do nothing. A real
wrapper has to deliver every span to Scheme, and each delivery crosses the
C-to-Scheme boundary.

For the 703-byte request, llhttp fires **47 callbacks** and parses in
**248 ns**. A Chez `foreign-callable` crossing costs **150 ns**. So 47
crossings take 7.0 µs against 0.25 µs of parsing: **96% of a naive
wrapper's time is the boundary, not the parse.**

**This parser reads the whole 703-byte request in 3.3 µs** (205.6 MB/s,
above). A naive wrapper's crossings alone take twice as long.

The same 47 callbacks into C are almost free: a shim recording every event
runs at 1,934 MB/s against 2,546 with nothing bound — 347 ns against 263 ns,
or **1.8 ns an event**, against 150 ns for a crossing into Scheme.
Eighty-three times cheaper.

### The figures

llhttp 9.4.3 on the same two inputs, every row taken in one sitting on one
harness, medians of three runs. These were taken with the generator at an
earlier pin, `v0.5.0-6-g114a1ab`, and the Scheme row built a new parser per
message.

| What runs                             | 703 B safe | 703 B unsafe | 520 B safe | 520 B unsafe |
|:--------------------------------------|-----------:|-------------:|-----------:|-------------:|
| chez-httparse, pure Scheme            | 101.7 MB/s |   154.4 MB/s |  59.9 MB/s |    88.4 MB/s |
| llhttp + FFI, a crossing per callback |  96.7 MB/s |    95.7 MB/s |  58.9 MB/s |    59.9 MB/s |
| llhttp + FFI, a crossing per message  | 240.3 MB/s |   1,356 MB/s | 152.7 MB/s |   826.5 MB/s |
| llhttp + FFI, no callbacks bound      | 2,837 MB/s |   2,783 MB/s | 1,784 MB/s |   1,812 MB/s |

"Safe" is `optimize-level 0`, which this project ships. "Unsafe" is
`optimize-level 3`, applied to the **whole** harness — the
`foreign-callable` bodies and the decoding loop as well as this parser.

**Only the first row depends on this parser, and it has moved since.** The
current figure for the 703-byte request is 205.6 MB/s at level 0 reusing one
parser, or 130.7 with a new parser per message. Against that, the naive
wrapper runs at under half the speed of pure Scheme, and the batched
wrapper's lead at level 0 shrinks to about 1.2×. The llhttp rows do not
depend on this parser and stand. The comparisons below are against the row
as measured.

- **A wrapper written the obvious way loses**: 0.95× and 0.98× safe, 0.62×
  and 0.68× unsafe. It loses more at level 3, because the parser gains from
  unsafe code and a boundary crossing does not.
- **A wrapper designed around the boundary** buys 2.4–2.6× safe and
  8.8–9.4× unsafe.
- **llhttp's own speed is out of reach** from Scheme: the bottom row is
  llhttp talking to nobody.

The crossing cost falls out of the table: 703 bytes at 96.7 MB/s is 7.27 µs,
the same parse with nothing bound is 0.24 µs, and the difference over 47
callbacks is **150 ns a crossing**.

### The design matters, and so does `optimize-level`

The third row is a C shim that appends `(kind, offset, length)` to an array
as llhttp's callbacks fire. Scheme crosses **once per message**, then walks
the array and makes one call per event, the way a span binding is called.
Nothing is copied: the bytevector goes to C as `u8*`, so the wrapper hands
back the same `(bv from to)` this parser's callbacks receive. That handoff
measured free — 2,821 MB/s with the input in a Scheme bytevector, against
2,837 in foreign memory.

That row is where `optimize-level` decides the answer. A 703-byte message
costs 2.79 µs through the batched wrapper safe and 0.49 µs unsafe, against
0.24 µs with nothing bound — so **delivering 47 events costs 2,550 ns safe
and 253 ns unsafe**, about 54 ns an event against 5.4. `foreign-ref` checks
every field it reads, and level 3 drops that check. The whole distance
between 240 MB/s and 1,356 MB/s is that one switch.

**This parser feels the same switch: 101.7 → 154.4 MB/s, fifty-two per
cent.** With no linear scan left in its dispatch, most of its time is
bounds-checked memory access — `bytevector-u8-ref` and the `fx` operations
around it — which is exactly what level 3 stops checking. A parser
dominated by a scan would barely notice, because a scan costs the same at
every level.

So the headline 8.8× is really **8.8× if the decoding runs unsafe**, and
unsafe Scheme reading a C-written array is a different proposition on bytes
from a socket than in a benchmark. Safe against safe, it is 2.4×. The pure
Scheme parser could claim its own 52% the same way, by giving up the bounds
checks on offsets an attacker controls — the same trade, one layer down.

### What was checked, so these are not flattered

- **Both ends reproduce the benchmark at the same pin.** Measured with a new
  parser per message, the llhttp comparison read this parser at 102.2 MB/s
  on the 703-byte request and llhttp at 2,607; the pure-Scheme row lands on
  the first and the no-callbacks row on the second.
- **The event count reproduces from the C side.** The shim records **47**
  events for the 703-byte request, the count the crossing arithmetic uses.
- **The handoff is free, and was measured, not assumed.** Passing the
  bytevector to C as `u8*` measures 2,821 MB/s against 2,837 for foreign
  memory, inside the run-to-run spread. Copying in is not affordable: 21.6 µs
  for 703 bytes would swallow the wrapper's whole advantage.
- **Every parse completed.** A parser that fails on the first byte is fast
  and meaningless. The Scheme row counts `on-message-complete` against the
  repetitions — 381,842 of 381,842 on the 703-byte input, 516,222 of 516,222
  on the chunked one. The per-callback row counts the same event through its
  own `foreign-callable`, the per-message row counts kind 12 in the array,
  and the no-callbacks row checks `llhttp_execute`'s error number on every
  call.
- **Medians of three runs at each level.** Read the ratios, not the rates,
  and read 0.95× and 0.98× as "the same": the table shows that a naive
  wrapper is not ahead, not which of two figures 3% apart is larger.

### What it leaves out

Speed is the easy half. A wrapper also brings a C toolchain into the build,
a shared library per platform, and llhttp's struct layout copied into an
`ftype` — a generated struct with no stable ABI, tied to the version it was
generated from. And it would not replace llhttp as the reference: a wrapper
produces callbacks, not trace lines, so checking it would need a trace
printer of our own — a second implementation of the very format being
checked.

## How the numbers are taken

### Counting allocation

Chez's `bytes-allocated` reports what is allocated **right now**, so a
garbage collection inside a measured region makes the difference negative —
a region once read as allocating −33,122 bytes. The lane reads the
cumulative count from the statistics record instead, and checks that the
counter never goes backwards, so a counter that stopped counting could not
pass.

### Timing throughput

The clock reads whole milliseconds, so a region that finishes in a few of
them is mostly rounding — and the shorter the interval, the **larger** the
rate it reports. So the lane does not use a fixed repetition count. Each
case doubles its repetitions until the region takes 50 ms, and prints the
count it reached; two runs need not agree on it. A 10 ms floor catches
calibration giving up.

The ranges come from 80 runs, 40 in each mode, alternating with a second
build in the same sitting, so a slow drift in the machine lands on both.

### Source and compiled run at the same speed

Every cost lane runs twice: `.chez.source` from source, `.chez.aot` from
objects compiled ahead of time. You might expect the compiled lane to be
faster. It is not, because Chez compiles source when it loads it. A hot loop
of 20,000,000 iterations under Chez 10.4.1:

| How the same code ran                        | Steady state |
|:---------------------------------------------|-------------:|
| `--script`, from source                      |        27 ms |
| `--program`, from a `compile-program` object |        28 ms |
| from source, with `(current-eval interpret)` |       455 ms |

Compiling ahead of time buys startup — the allocation lane takes 0.63 s from
source and 0.16 s compiled — not speed. The compiled lane exists to show the
figures hold in the configuration this project ships. The two runs print
their mode beside every figure; nothing compares them automatically, because
a parser whose cost depended on when it was compiled is not worth inventing
a check for.

The two lanes agree on four of the six allocation figures. On the two
`POST`s, over 40 runs each, the source lane read 2,917 or 2,918 B on 26 runs
where the compiled lane read 2,912 on all 40, and 2,965 once against 2,960.
The runtime's `abandon-span!` is involved: with its body emptied, or cut to
either of its two reads, the source lane reads 2,912. A garbage collection
forced just before the region removes the difference, and so does measuring
each of the 200 parses separately; padding the heap or deepening the stack
does not. The cause is not known. It is 0.2%, nothing the lane checks is
near it, and the compiled lane, which is what ships, does not show it.

### Run them yourself

The allocation and throughput lanes:

```sh
ctest --preset release -R 'allocation|throughput'
```

**The llhttp benchmark** needs a built llhttp checkout, named the same way
the live differential names one:

```sh
cmake --preset dev -DHTTPARSE_LLHTTP_ROOT=/path/to/llhttp
cmake --build build/dev
build/dev/llhttp-oracle/http-request-c bench "$(printf 'GET / HTTP/1.1\r\nHost: x\r\n\r\n')"
```

The inputs are the three in llhttp's `bench/native.ts`, after its `request`
template strips indentation and newlines: 703, 520 and 52 bytes. Pass them
to the binary byte for byte — `$(cat file)` drops the final `\n` of
`\r\n\r\n`, and a request without it never completes.

The Scheme side is not in this tree, and it is short:

1. For each request, make **one** message parser of type `request`.
2. Bind the 25 callbacks to procedures that return `callback-continue`.
3. Feed it the whole input 2²⁸ / *len* times — 256 MiB, a second or more
   per input.
4. Count `on-message-complete` and check it equals the repetitions.
5. Time the loop alone.

For the URL, do the same with `httparse-url-machine` and its five span
callbacks. To see the parser-construction cost, make a new parser for each
repetition instead.

These figures are recorded, not gated. A ratio is steady enough to gate on,
but taking one needs Node, a C toolchain and an llhttp build, and a check
that only a developer's machine can run stops meaning anything.

**The FFI comparison** is not in this tree either: llhttp tooling stays
local and opt-in, and a benchmark that needs a C toolchain is the thing this
parser exists not to need. It is about two hundred lines:

1. `npm run build` in an llhttp checkout, then `clang -O3 -dynamiclib` over
   `build/c/llhttp.c`, `src/native/{api,http}.c` and the shim below.
2. `load-shared-object`, then take three sizes from clang rather than from
   this page: `sizeof(llhttp_t)` is 96, `sizeof(llhttp_settings_t)` is 200,
   and `offsetof(llhttp_t, data)` is 48 at 9.4.3. `HTTP_REQUEST` is 1.
3. The settings block is 25 pointers in the declaration order of
   `struct llhttp_settings_s`, so slot *i* is at byte *8i*. For the
   per-callback row each is a `foreign-callable` — `lock-object`'d, or the
   collector moves the address C is holding — with the ten data callbacks at
   `(void* void* size_t) int` and the fifteen events at `(void*) int`.
4. For the batched row, a C shim owning those 25 and appending
   `(kind, offset, length)` to a caller-owned array, reached through
   `parser->data`. Scheme resets the count, executes, and walks the array.
5. Size the loop by a fixed total of **bytes**, as upstream's `bench` mode
   does.
6. Count completions on every row: through its own `foreign-callable`, as
   kind 12 in the array, or from `llhttp_execute`'s error number.

For the Scheme row, set `optimize-level` before the generated library is
compiled — which means loading it with `eval` rather than a static
`import`, since an import resolves at expansion.
