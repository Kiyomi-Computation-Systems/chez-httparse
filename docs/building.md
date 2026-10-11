# Building and testing

This page is for working on chez-httparse itself. To use the library from
your own project, see [installing.md](installing.md).

## Requirements

- Chez Scheme 10.4.1 or newer. Discovery tries `scheme`, `chez` and
  `chezscheme`, and rejects Petite: the ahead-of-time lanes need
  `compile-program`, which Petite does not provide.
- CMake 3.26 or newer. CI runs 3.31; development uses 4.x.
- The generator submodule, `vendor/byte-machine`. Clone with `--recursive`,
  or run `git submodule update --init`.

The CMake-layer specifications also run with no Scheme installed, through
the [`no-scheme` preset](#presets). The optional
[live llhttp differential](#the-live-llhttp-differential) needs Node, a C
toolchain and a built llhttp checkout.

If discovery picks the wrong `scheme`, or finds none, name the executable
yourself:

```sh
cmake --preset dev -DHTTPARSE_CHEZ_EXECUTABLE=/absolute/path/to/scheme
```

## Make targets

A bare `make` prints the target list rather than building; `make help` does
the same. Every target wraps a checked-in CMake preset, so you can run the
`cmake` and `ctest` commands directly instead, including on Windows, where
`make` is not in the base install.

| target                | what it does                                                   |
|-----------------------|----------------------------------------------------------------|
| `make help`           | list these targets (shown when you run a bare `make`)          |
| `make all`            | build the development preset                                   |
| `make doctor`         | report the discovered Chez toolchain, then stop                |
| `make configure`      | configure the development preset without building              |
| `make build`          | configure and build the development preset                     |
| `make dev`            | build, then run the harness and build-layer self-tests         |
| `make test`           | build, then run the pull-request selection                     |
| `make test-all`       | build, then run the complete selection                         |
| `make prod`           | configure and build the release preset                         |
| `make clean`          | remove all build trees                                         |
| `make corpus-refresh` | re-vendor the llhttp corpus (needs `LLHTTP_ROOT=/path/to/llhttp`) |
| `make parser-refresh` | re-emit the checked-in generated parser                        |

What each test target runs, as the equivalent commands:

| target          | runs                                                                 |
|-----------------|----------------------------------------------------------------------|
| `make dev`      | `cmake --preset dev`, `cmake --build --preset dev`, `ctest --preset harness` |
| `make test`     | the same build, then `ctest --preset pr`                             |
| `make test-all` | the same build, then `ctest --preset release`                        |
| `make prod`     | `cmake --preset prod`, `cmake --build --preset prod`                 |

The `ctest` calls add `CTEST_FLAGS`, which defaults to
`--output-on-failure --no-tests=error`. Override it, or `CMAKE` and `CTEST`,
on the command line:

```sh
make test CTEST_FLAGS="--output-on-failure --no-tests=error -R conformance"
```

An empty selection is a failure, never a silent pass. The test presets say
so themselves (`"noTestsAction": "error"`), so the preset path and the
`make` path refuse the same thing.

## Presets

[`CMakePresets.json`](../CMakePresets.json) defines three configure presets,
each with a build preset of the same name:

| configure preset | build tree         | build type | notes                                       |
|------------------|--------------------|------------|---------------------------------------------|
| `dev`            | `build/dev`        | Debug      | tests on                                    |
| `prod`           | `build/prod`       | Release    | tests on                                    |
| `no-scheme`      | `build/no-scheme`  | —          | tests on, `HTTPARSE_REQUIRE_CHEZ=OFF`       |

The four test presets select lanes by label. All but `no-scheme` run
against the `dev` build:

| test preset | selects                                                                                                     |
|-------------|-------------------------------------------------------------------------------------------------------------|
| `harness`   | the `harness` layer only: the harness and build-layer self-tests                                            |
| `pr`        | the `harness`, `unit`, `verify`, `differential`, `property`, `determinism`, `conformance`, `portability` and `example` layers, minus anything labelled `full-scan` |
| `release`   | every registered lane, `benchmark` and `full-scan` included                                                 |
| `no-scheme` | every lane in the `no-scheme` build: the `cmake`-backend specifications, none of which needs a Scheme runtime |

Each writes a JUnit file to `test-results/<preset>.xml` under its build
tree.

The one conformance lane is registered twice, so the presets can split its
cost: `httparse.conformance.message.chez.source` replays every fixture one
byte at a time and as a whole buffer, and runs in `pr`;
`httparse.conformance.message-full-scan.chez.source` replays every chunk
size from 1 to the input length, carries `full-scan`, and runs only in
`release`. See [conformance.md](conformance.md) for what the corpus checks.

CI configures and builds `dev`, runs `pr` then `release`, then configures
`no-scheme` and runs its test preset.

## Lane names

Every test is named `httparse.<layer>.<feature>.<backend>.<mode>`, for
example `httparse.benchmark.throughput.chez.aot`. The layer, backend and
mode become labels automatically, which is what the presets filter on.

| layer          | the evidence it produces                                       |
|----------------|----------------------------------------------------------------|
| `harness`      | the test harness proving things about itself                   |
| `unit`         | constructors, accessors, single-behaviour semantics            |
| `verify`       | verifier diagnostics, positive and negative                    |
| `differential` | reference interpreter against generated code                   |
| `property`     | generated machines and inputs                                  |
| `determinism`  | byte-identical emission across runs, lanes, and platform cells |
| `fixture`      | the private HTTP request fixture                               |
| `conformance`  | the vendored llhttp corpus, bit-exact                          |
| `portability`  | values crossing library boundaries; runtime identity           |
| `example`      | the documented end-to-end examples                             |
| `benchmark`    | measured rates, reported rather than asserted                  |
| `expected-red` | tests that must fail, proving the harness can fail             |

| backend | modes                                                                  |
|---------|------------------------------------------------------------------------|
| `chez`  | `source`, run from source; `aot`, run from ahead-of-time compiled objects |
| `cmake` | `direct`, run under `cmake -P` with no Scheme runtime                  |

`full-scan` is the one extra label: a selector with no layer, backend or
mode meaning, used only to keep the every-chunk-size replay out of `pr`.

Select lanes with `ctest`'s own filters on top of a preset:

```sh
ctest --preset pr -R conformance
ctest --preset release -L aot
```

Lanes are registered with `httparse_add_test`
([`cmake/HttparseTesting.cmake`](../cmake/HttparseTesting.cmake)), or with
`httparse_add_scheme_lane`
([`cmake/HttparseSchemeLane.cmake`](../cmake/HttparseSchemeLane.cmake)) for
a Scheme program. Both refuse at configure time a name that does not have
five valid segments, an unknown label, a duplicate name, or a missing
`TIMEOUT`: a registration mistake is a build failure, not a test that
quietly never runs.

Why a `source` lane and an `aot` lane cost the same is in
[performance.md](performance.md#source-and-compiled-cost-the-same-and-that-is-a-measurement).

## The live llhttp differential

A lane that runs a live llhttp against generated input. It is local and
opt-in, never a merge gate. Turn it on by naming a built llhttp checkout:

```sh
cmake --preset dev -DHTTPARSE_LLHTTP_ROOT=/path/to/llhttp
ctest --preset pr -R differential
```

The checkout must have had `npm install` run in it, and `node` must be on
`PATH`; configure fails with an error if either is missing. The build then
compiles the oracle binaries with llhttp's own test harness, into
`build/dev/llhttp-oracle/`: `http-request-c`, `http-response-c`,
`url-url-c`, `http-modes-c` and `http-request-lenient-headers-c`. The lane
is `httparse.differential.llhttp.chez.source`.

Once configured, the lane carries the `differential` label, so `make test`
and `make test-all` run it too. Without the variable it is absent — not
skipped, not registered at all. To drop it again, reconfigure with
`-UHTTPARSE_LLHTTP_ROOT`.

[conformance.md](conformance.md#running-it-yourself) has the full clone and
checkout steps, what the lane compares and what it has found;
[performance.md](performance.md#taking-these-yourself) uses the same
binaries for llhttp's `bench` mode.

## Regenerating checked-in files

Two kinds of file in the tree are derived, and each has one target that
writes it. Never edit either by hand.

### The llhttp corpus: `make corpus-refresh`

```sh
make corpus-refresh LLHTTP_ROOT=/path/to/llhttp
```

This re-vendors llhttp's conformance corpus into `test/vendor/llhttp/` from
a local checkout. It empties that directory first, so a fixture upstream
deleted does not linger, then copies `test/request/*.md`,
`test/response/*.md`, `test/url.md` and `LICENSE` verbatim. It writes a
`PROVENANCE` file recording the upstream commit and tag (`unknown` when git
cannot say) and a SHA-256 for every file, which
`httparse.harness.corpus-provenance.cmake.direct` checks.

It refuses to run without `LLHTTP_ROOT`, or when the directory does not
look like an llhttp checkout (no `test/request/` or no `LICENSE`). The
script is [`cmake/HttparseCorpusRefresh.cmake`](../cmake/HttparseCorpusRefresh.cmake),
and it is the only thing that writes the corpus.

### The generated parsers: `make parser-refresh`

```sh
make parser-refresh
```

This re-emits both generated parsers with
[`tools/emit-machine.ss`](../tools/emit-machine.ss):

| grammar                       | generated library                    |
|-------------------------------|--------------------------------------|
| `src/httparse/grammar.sls`    | `src/generated/httparse-message.sls` |
| `src/httparse/url-grammar.sls`| `src/generated/httparse-url.sls`     |

Run it after any grammar edit, or after moving the `vendor/byte-machine`
pin. The determinism lane, `httparse.determinism.generated-artifact.chez.source`,
runs the same script and compares bytes, so a grammar edit without a refresh
fails it rather than shipping a stale parser.

`make parser-refresh` configures but does not build. Run `make build` (or
`make test`, which builds first) before calling `ctest` directly, or the
lanes run the new generated sources against stale compiled objects — which
shows up as failures in lanes the change could not have touched.
