# Contributing to chez-httparse

Thanks for helping. A **small fix**, such as a typo, a doc fix, or a bug with a
test that shows it, needs only the checks below. **Bigger work**, such as a new
export, a change to the grammar, or a change to what the parser accepts or
refuses, starts as an issue, so the design is agreed before the code is
written. The parser is a port of [llhttp](https://github.com/nodejs/llhttp),
and llhttp is the judge: what it accepts and refuses is what this parser
accepts and refuses, so a change to that is a design decision, not a fix.

## Setup

You need Chez Scheme 10.4.1 or newer and CMake 3.26 or newer.
[docs/building.md](docs/building.md) has the rest.

```sh
git clone --recursive https://github.com/Kiyomi-Computation-Systems/chez-httparse.git
cd chez-httparse
make test
```

`make help` lists every target. A clone without `--recursive` needs
`git submodule update --init` for the generator at `vendor/byte-machine`.

## The checks

CI runs these on every pull request, on Linux. Keep them green:

- `make test`: the pull-request selection passes. It replays llhttp's corpus,
  checks `docs/reference.md` against the real exports, and checks
  `Akku.manifest` and `Akku.lock` against `CHANGELOG.md` and the pin.
- `make test-all`: every test, benchmarks and the every-chunk-size replay
  included.
- `cmake --preset no-scheme` then `ctest --preset no-scheme`: the build's own
  CMake checks, with no Scheme installed.
- `make check-help`: every target has a description in `make help`.

Two more run where their tools are installed. CI doesn't run them on pull
requests:

- `make check-site CMARK_GFM_ROOT=/path/to/chez-cmark-gfm`: the docs site
  builds, and every link and anchor in it resolves. It also runs before each
  release tag publishes the site.
- `make check-akku`: installs the package with Akku as a user would. It needs
  `akku`.

## When you change…

- **A grammar** (`src/httparse/grammar.sls` or `url-grammar.sls`): run
  `make parser-refresh` and commit what it writes to `src/generated/`. The
  `determinism.generated-artifact` lane fails until you do. It configures but
  doesn't build, so run `make test` after it, not `ctest`.
- **The `vendor/byte-machine` pin:** move it on a commit of its own and run
  `make parser-refresh`. Move `Akku.manifest`'s range for it and run
  `akku lock` too; the `docs.akku-manifest` lane fails until all three agree.
- **The llhttp corpus:** files under `test/vendor/llhttp/` are never edited by
  hand. `make corpus-refresh LLHTTP_ROOT=/path/to/llhttp` re-vendors them.
  Name any new third-party code or test data, and its license, in NOTICE.
- **An export:** document it in `docs/reference.md`. The `docs.reference` lane
  fails until the reference lists exactly what each of this project's
  libraries exports.
- **The Makefile:** give each new target a `## ` description, so `make help`
  lists it. `make check-help` fails until it has one.
- **`docs/`:** it is for people using the library. Keep it short and plain. A
  new page goes in `docs/` and in `site/pages.sls`, the nav's order;
  `make check-site` fails until both name it.
- **What ships:** a release archive is `git archive` of the tag. A new
  top-level path that is only for development needs an `export-ignore` rule
  in `.gitattributes`; `make check-akku` checks what the archive holds.

## Code

- Libraries are R6RS `.sls` files under `src/`, and each holds its own code:
  no shared include files.
- **Functional core, imperative shell.** The libraries under `src/` are pure
  and import only `(rnrs)`, the generator's libraries and each other, never
  `(chezscheme)`. Chez-specific code stays in the build and the tests.
- Each export has a comment giving its type, Typed Racket style:
  `;; httparse-lenient-bit : Symbol -> Nat`.
- R6RS forbids assigning an exported variable, so reach mutable state through
  procedures.
- The library runs on macOS, Linux and Windows, on x86-64 and arm64. CI runs
  Linux only, so say in the pull request where you tested.
- Comments and docs say what the code does and why, in the present tense.
  They don't cite issues, pull requests, plans or dates; that history belongs
  in commits and CHANGELOG.md.

## Tests

- Write the test first, and watch it fail before you make it pass. A test
  that passes whether the code is right or wrong is worse than none.
- A change in behavior comes with a test that fails without it.
- An expected number comes from llhttp, never from a run of this parser: a
  number read off the code under test keeps passing after the code is wrong.
- A lane is a program in `test/common/` using `(httparse test harness)`,
  registered in `test/CMakeLists.txt`. `ctest --preset pr -R <name>` runs the
  lanes whose names match.
- Test what the code does, never what a comment says.

## Pull requests

- Commit messages and PR titles follow
  [Conventional Commits](https://www.conventionalcommits.org): `feat:`,
  `fix:`, `docs:`, `test:`, `refactor:`, `chore:`.
- Name branches `feat/<slug>`, `fix/<slug>`, `docs/<slug>` and so on.
- Pull requests are squash-merged, so the PR title becomes the commit's.
- A change users can see gets an entry under `## [Unreleased]` in
  [CHANGELOG.md](CHANGELOG.md).

## How the project is developed

Each lasting decision gets a numbered record in `.plans/decisions/`.
[AGENTS.md](AGENTS.md) holds the project's rules in full, and the lessons
behind them. Following them is encouraged for features, not demanded of
small fixes. Neither is in a release archive; read them in the repository.

## Security

Don't open a public issue for a suspected vulnerability.
[SECURITY.md](SECURITY.md) says how to report it privately.
