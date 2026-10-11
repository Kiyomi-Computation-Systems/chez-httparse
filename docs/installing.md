# Installing

There is nothing to compile and nothing to install. You need two folders
from this repository on Chez's library path, and then you can import.

## What you need

- **Chez Scheme 10.4.1 or newer.** Petite Chez won't do: it can't compile
  programs, so the build turns it away.
- **This repository, with its submodule.** The submodule,
  `vendor/byte-machine`, holds the one library the parser needs at run time.

## 1. Get the source

```sh
git clone --recursive https://github.com/Kiyomi-Computation-Systems/chez-httparse.git
```

Already cloned without `--recursive`? Fetch the submodule from inside the
checkout:

```sh
git submodule update --init
```

## 2. Know the two folders

Chez finds a library by its name, inside the folders on its library path.
Everything you import lives under one of two folders:

| Folder                    | Libraries in it                                                                                                              |
|:--------------------------|:-----------------------------------------------------------------------------------------------------------------------------|
| `src/`                    | `(generated httparse-message)`, `(generated httparse-url)`, `(httparse modes)`, `(httparse methods)`, `(httparse decisions)` |
| `vendor/byte-machine/src` | `(byte-machine runtime)`                                                                                                     |

That is the whole dependency list. These libraries import `(rnrs)` and each
other, and nothing else; none of them imports `(chezscheme)`.

`src/` also holds the grammars the parsers are generated from. You never
import those. They matter only if you change the parser (see
[building.md](building.md)).

## 3. Put them on the library path

Pick one of three ways. The examples run from the repository root, so the
paths are relative; from anywhere else, use absolute paths. Separate the two
folders with `:` on macOS and Linux, and `;` on Windows.

**On the command line:**

```sh
chez --libdirs src:vendor/byte-machine/src --program app.sps
```

**In the environment.** Chez reads `CHEZSCHEMELIBDIRS` when it starts:

```sh
export CHEZSCHEMELIBDIRS=/path/to/chez-httparse/src:/path/to/chez-httparse/vendor/byte-machine/src
chez --program app.sps
```

**From Scheme.** A program's imports are resolved before its first line
runs, so set the path in a small launcher and load your program from it:

```scheme
;; run.ss -- start with: chez --script run.ss
(library-directories (list "src" "vendor/byte-machine/src"))
(load-program "app.sps")
```

## 4. Check it works

From the repository root:

```sh
echo '(import (generated httparse-message)) (display "ok") (newline)' \
  | chez -q --libdirs src:vendor/byte-machine/src
```

It prints `ok`. (Your Chez may be called `scheme` or `chezscheme` instead of
`chez`.)

If you forget the second folder, the import fails and says which library it
could not find:

```text
Exception: library (byte-machine runtime) not found
```

Next: [usage.md](usage.md) makes a parser and feeds it a request.
