# Installing

There is nothing to build and no `make install`. You clone the repository
with its submodule, put two directories on Chez's library path, and import.

## Requirements

- **Chez Scheme 10.4.1 or newer.** That is the floor this project verifies;
  the build's discovery tries `scheme`, `chez` and `chezscheme` in turn.
- **Not Petite.** Petite has no `compile-program`, so the build rejects it
  and it is not a supported configuration.
- **The generator submodule**, `vendor/byte-machine`. The parser's one
  runtime dependency lives there.

## Getting the source

```sh
git clone --recursive https://github.com/Kiyomi-Computation-Systems/chez-httparse.git
```

If you already cloned without `--recursive`, fetch the submodule from the
checkout:

```sh
git submodule update --init
```

## The two library roots

Chez finds a library by its name, under the directories on its library
path. Two roots hold everything an embedder imports:

| Root                     | Holds                                                                 |
|--------------------------|-----------------------------------------------------------------------|
| `src/`                   | `(generated httparse-message)`, `(generated httparse-url)`, `(httparse modes)`, `(httparse methods)`, `(httparse decisions)` |
| `vendor/byte-machine/src` | `(byte-machine runtime)`                                             |

At run time that is the whole dependency set. The generated parsers import
`(rnrs)` and `(byte-machine runtime)` only, the runtime imports `(rnrs)` and
two private libraries beside it, and the three `(httparse …)` libraries
import `(rnrs)` alone. Nothing imports `(chezscheme)`.

`src/` also holds the grammars the parsers are generated from. You never
import those; they are for regenerating the parser (see
[building.md](building.md)).

## Putting them on the library path

Relative paths resolve against the current directory, so the examples below
run from the repository root. From anywhere else, give absolute paths. The
separator between roots is `:` on Unix and `;` on Windows.

**On the command line**, with `--libdirs`:

```sh
chez --libdirs src:vendor/byte-machine/src --program app.sps
```

**From the environment**, with `CHEZSCHEMELIBDIRS`, which Chez reads at
startup:

```sh
export CHEZSCHEMELIBDIRS=/path/to/chez-httparse/src:/path/to/chez-httparse/vendor/byte-machine/src
chez --program app.sps
```

**From Scheme**, with `library-directories`. A program's imports are
resolved before its body runs, so set the path in a launcher script and
load the program from there:

```scheme
;; run.ss -- start with: chez --script run.ss
(library-directories (list "src" "vendor/byte-machine/src"))
(load-program "app.sps")
```

Leave out the second root and the import fails by name:

```text
Exception: library (byte-machine runtime) not found
```

## Checking it works

From the repository root:

```sh
echo '(import (generated httparse-message)) (display "ok") (newline)' \
  | chez -q --libdirs src:vendor/byte-machine/src
```

It prints `ok`. Your binary may be called `scheme` or `chezscheme` rather
than `chez`.

Next, [usage.md](usage.md) makes a parser and feeds it a request.
