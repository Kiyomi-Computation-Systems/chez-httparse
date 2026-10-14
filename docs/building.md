# Building and testing

This page is for working on chez-httparse itself. To use the library in
your own project, see [installing.md](installing.md).

## Quick start

```sh
git clone --recursive https://github.com/Kiyomi-Computation-Systems/chez-httparse.git
cd chez-httparse
make test
```

`make test` builds the project and runs the tests a pull request runs.

## What you need

- **Chez Scheme 10.4.1 or newer.** The build looks for `scheme`, `chez` and
  `chezscheme`. Petite is rejected: the compiled test lanes need
  `compile-program`, which Petite lacks.
- **CMake 3.26 or newer.** CI runs 3.31; development uses 4.x.
- **The generator submodule**, `vendor/byte-machine`. Clone with
  `--recursive`, or run `git submodule update --init`.

If the build picks the wrong Chez, or finds none, name it yourself:

```sh
cmake --preset dev -DHTTPARSE_CHEZ_EXECUTABLE=/absolute/path/to/scheme
```

The build's own CMake checks also run with no Scheme installed, through the
[`no-scheme` preset](#test-selections). The optional
[live llhttp comparison](#optional-the-live-llhttp-comparison) needs Node, a
C toolchain and a built llhttp checkout.

## Everyday commands

| Command         | What it does                                           |
|:----------------|:-------------------------------------------------------|
| `make test`     | build, then run the pull-request selection             |
| `make test-all` | build, then run everything, benchmarks included        |
| `make dev`      | build, then run the harness and build-layer self-tests |
| `make build`    | configure and build, without testing                   |
| `make clean`    | remove all build trees                                 |
| `make help`     | list every target (a bare `make` does the same)        |

The rest of the targets:

| Command               | What it does                                                      |
|:----------------------|:------------------------------------------------------------------|
| `make all`            | build the development preset                                      |
| `make doctor`         | report which Chez the build found, then stop                      |
| `make configure`      | configure the development preset without building                 |
| `make prod`           | configure and build the release preset                            |
| `make corpus-refresh` | re-vendor the llhttp corpus (needs `LLHTTP_ROOT=/path/to/llhttp`) |
| `make parser-refresh` | re-emit the checked-in generated parsers                          |
| `make site`           | render docs/ into build/site/ (needs `CMARK_GFM_ROOT`)            |
| `make check-site`     | test the site generator, then check docs/ with it                 |
| `make check-akku`     | install with Akku as a consumer would (needs `akku`)              |

Every target is a thin wrapper over checked-in CMake presets, so you can
run `cmake` and `ctest` yourself instead — and on Windows, where `make` is
not installed by default, you will:

| Target          | Runs                                                                         |
|:----------------|:-----------------------------------------------------------------------------|
| `make dev`      | `cmake --preset dev`, `cmake --build --preset dev`, `ctest --preset harness` |
| `make test`     | the same build, then `ctest --preset pr`                                     |
| `make test-all` | the same build, then `ctest --preset release`                                |
| `make prod`     | `cmake --preset prod`, `cmake --build --preset prod`                         |

To narrow a run, pass `ctest` options through `CTEST_FLAGS` (its default is
`--output-on-failure --no-tests=error`):

```sh
make test CTEST_FLAGS="--output-on-failure --no-tests=error -R conformance"
```

A run that selects no tests fails rather than passing quietly, whether you
use `make` or a preset directly.

## Test selections

[`CMakePresets.json`](../CMakePresets.json) has three build configurations:

| Configure preset | Build tree        | Build type | Notes                                 |
|:-----------------|:------------------|:-----------|:--------------------------------------|
| `dev`            | `build/dev`       | Debug      | tests on                              |
| `prod`           | `build/prod`      | Release    | tests on                              |
| `no-scheme`      | `build/no-scheme` | —          | tests on, `HTTPARSE_REQUIRE_CHEZ=OFF` |

And four test selections. All but `no-scheme` use the `dev` build:

| Test preset | Runs                                                           |
|:------------|:---------------------------------------------------------------|
| `harness`   | the test harness's and the build's own self-tests              |
| `pr`        | what a pull request needs: no benchmarks, no `full-scan` lanes |
| `release`   | every test, benchmarks and `full-scan` lanes included          |
| `no-scheme` | the CMake checks, which need no Scheme runtime                 |

Precisely, `pr` selects the `harness`, `unit`, `verify`, `differential`,
`property`, `determinism`, `conformance`, `portability`, `example` and
`docs` layers, and drops anything labelled `full-scan`. Each preset writes a
JUnit file to `test-results/<preset>.xml` under its build tree.

The corpus replay is registered twice to split its cost.
`httparse.conformance.message.chez.source` feeds every fixture one byte at a
time and as a whole buffer, and runs in `pr`.
`httparse.conformance.message-full-scan.chez.source` feeds every chunk size
from 1 to the input length, and runs only in `release`. See
[conformance.md](conformance.md).

CI builds `dev`, runs `pr` and then `release`, then builds `no-scheme` and
runs its tests.

## Test names

Every test is named `httparse.<layer>.<feature>.<backend>.<mode>` — for
example `httparse.benchmark.throughput.chez.aot`. The layer, backend and
mode become labels, which is what the presets select on.

| Layer          | What its tests show                                       |
|:---------------|:----------------------------------------------------------|
| `harness`      | the test harness proving things about itself              |
| `unit`         | constructors, accessors, single behaviours                |
| `verify`       | the machine verifier's diagnostics, positive and negative |
| `differential` | the interpreted grammar against the generated code        |
| `property`     | properties of generated machines and inputs               |
| `determinism`  | byte-identical output across runs, lanes and platforms    |
| `fixture`      | the private HTTP request fixture                          |
| `conformance`  | the vendored llhttp corpus, byte for byte                 |
| `portability`  | values crossing library boundaries; runtime identity      |
| `example`      | the documented examples, run                              |
| `docs`         | the docs and the Akku manifest, checked against the tree  |
| `benchmark`    | measured rates, printed rather than asserted              |
| `expected-red` | tests that must fail, proving the harness can fail        |

| Backend | Modes                                                                     |
|:--------|:--------------------------------------------------------------------------|
| `chez`  | `source`, run from source; `aot`, run from ahead-of-time compiled objects |
| `cmake` | `direct`, run under `cmake -P` with no Scheme runtime                     |

`full-scan` is one extra label, used only to keep the every-chunk-size
replay out of `pr`.

Filter further with `ctest`'s own options on top of a preset:

```sh
ctest --preset pr -R conformance
ctest --preset release -L aot
```

Tests are registered with `httparse_add_test`
([`cmake/HttparseTesting.cmake`](../cmake/HttparseTesting.cmake)), or
`httparse_add_scheme_lane`
([`cmake/HttparseSchemeLane.cmake`](../cmake/HttparseSchemeLane.cmake)) for
a Scheme program. Both fail the configure step for a malformed name, an
unknown label, a duplicate name or a missing `TIMEOUT`, so a registration
mistake breaks the build instead of becoming a test that never runs.

`source` and `aot` tests run at the same speed; why is in
[performance.md](performance.md#source-and-compiled-run-at-the-same-speed).

## Optional: the live llhttp comparison

This test runs a real llhttp side by side with this parser on generated
input ([conformance.md](conformance.md#beyond-the-corpus-a-live-llhttp)). It
is local and opt-in, never a merge gate. Turn it on by naming a built llhttp
checkout:

```sh
cmake --preset dev -DHTTPARSE_LLHTTP_ROOT=/path/to/llhttp
ctest --preset pr -R differential
```

The checkout needs `npm install` run in it, and `node` must be on `PATH`;
configure fails with a message if either is missing. The build then
compiles llhttp's test binaries into `build/dev/llhttp-oracle/`:
`http-request-c`, `http-response-c`, `url-url-c`, `http-modes-c` and
`http-request-lenient-headers-c`. The test is
`httparse.differential.llhttp.chez.source`.

Once configured, it carries the `differential` label, so `make test` and
`make test-all` run it too. Without the variable it doesn't exist at all.
To remove it again, reconfigure with `-UHTTPARSE_LLHTTP_ROOT`.

[conformance.md](conformance.md#running-it-yourself) has the full clone
steps; [performance.md](performance.md#run-them-yourself) uses the same
binaries to benchmark llhttp.

## Optional: the docs site

The pages in `docs/` also build into a static website, using
[chez-cmark-gfm](https://github.com/Kiyomi-Computation-Systems/chez-cmark-gfm)
to render the Markdown. It isn't a dependency of the library, so you point
at a checkout of it, and you need the `cmark-gfm` shared library installed:

```sh
make check-site CMARK_GFM_ROOT=/path/to/chez-cmark-gfm
make site CMARK_GFM_ROOT=/path/to/chez-cmark-gfm
```

- **`make site`** writes the site to `build/site/`. Open
  `build/site/index.html`, or serve the directory if your browser won't load
  the stylesheet from a local file.
- **`make check-site`** runs the site generator's own tests, then builds
  every page in memory and fails if the menu doesn't list exactly
  `docs/*.md`, if a link or anchor between pages is broken, if a `.md` link
  leaks into the HTML, or if code blocks get reflowed.

Both run Chez directly rather than through CMake, so a distribution's Chez
works too (`make site CHEZ=chezscheme ...`). `SITE_REF` (default `main`)
sets the git ref that links from the site into the repository point at. The
home page is `site/index.md`, and the menu order is in `site/pages.sls`.

Pushing a release tag publishes the site to GitHub Pages
(`.github/workflows/pages.yml`), after running both targets.

## Optional: the Akku package

`Akku.manifest` describes this package for the
[Akku](https://akkuscm.org/) package index. `Akku.lock`, written by
`akku lock`, records the exact dependency versions `akku install` fetches in
a checkout. Two checks keep them honest:

- **The `docs.akku-manifest` lane** runs on every pull request. It fails if:
  - the manifest's version isn't the latest release in `CHANGELOG.md`;
  - the manifest declares no dependency;
  - a dependency's range doesn't start at the version vendored under
    `vendor/`, which is the version every other test runs against;
  - `Akku.lock` doesn't lock a dependency at that same version.

  So the release that adds a heading to `CHANGELOG.md` updates the manifest
  too, and a pin bump updates the manifest's range and runs `akku lock`.
- **`make check-akku`** needs the [`akku`](https://gitlab.com/akkuscm/akku)
  command. It packs this repository and each vendored dependency with
  `git archive`, which is exactly what Akku's archive serves for a tag, and
  installs them into a throwaway consumer project. It fails if `.plans/` or
  `AGENTS.md` is in the archive, or the archive holds no library, if
  anything but exactly the libraries under `src/` installs (a `site/`
  library is named, with its fix: `.akkuignore` must list `site`), or if a
  small program can't parse a request using only the library path Akku sets
  up. `git add` a new file before running it: an untracked file isn't part
  of the package.

What ships is decided by `.gitattributes`: its `export-ignore` rules leave
`.plans/` and `AGENTS.md` out. The site generator ships, but Akku installs
every library it finds outside `test/`, so `.akkuignore` keeps `site/` from
being installed. Akku reads it from the package, so it applies to a
consumer's install and to `akku install` in a clone alike. The generator's
`(site ...)` libraries aren't part of this library, and chez-cmark-gfm
ships the same library names.

## Regenerating checked-in files

Two sets of files are generated and committed. Each has one command that
writes it. Never edit them by hand.

### The llhttp corpus: `make corpus-refresh`

```sh
make corpus-refresh LLHTTP_ROOT=/path/to/llhttp
```

This copies llhttp's test corpus into `test/vendor/llhttp/` from a local
checkout. It empties the directory first, so a fixture llhttp deleted does
not linger, then copies `test/request/*.md`, `test/response/*.md`,
`test/url.md` and `LICENSE` unchanged. It also writes a `PROVENANCE` file
with the upstream commit and tag (`unknown` when git can't say) and a
SHA-256 for every file, which
`httparse.harness.corpus-provenance.cmake.direct` checks.

It refuses to run without `LLHTTP_ROOT`, or when that directory doesn't look
like an llhttp checkout (no `test/request/` or no `LICENSE`). The script is
[`cmake/HttparseCorpusRefresh.cmake`](../cmake/HttparseCorpusRefresh.cmake),
and nothing else writes the corpus.

### The generated parsers: `make parser-refresh`

```sh
make parser-refresh
```

This regenerates both parsers with
[`tools/emit-machine.ss`](../tools/emit-machine.ss):

| Grammar                        | Generated library                    |
|:-------------------------------|:-------------------------------------|
| `src/httparse/grammar.sls`     | `src/generated/httparse-message.sls` |
| `src/httparse/url-grammar.sls` | `src/generated/httparse-url.sls`     |

Run it after editing a grammar, or after moving the `vendor/byte-machine`
pin. The test `httparse.determinism.generated-artifact.chez.source` runs the
same script and compares the bytes, so forgetting to regenerate fails the
tests instead of shipping a stale parser.

**Build before testing.** `make parser-refresh` configures but does not
build. Run `make build` — or `make test`, which builds first — before calling
`ctest` directly. Otherwise the tests run the new parsers against stale
compiled objects, and fail in places your change could not have touched.
