#!/bin/sh
# check-akku: install this package with Akku the way a consumer would, and
# check what lands on the consumer's library path.
#
# A consumer project is made in a temporary directory. Its Akku.lock points
# each package at a directory unpacked from `git archive`, which is exactly
# what Akku's archive serves for a tag (for the vendored dependency's 0.8.0,
# its archive and `git archive v0.8.0` list the same 210 files): this
# checkout, and, for each dependency Akku.manifest names, the copy vendored
# at vendor/<name>. So .gitattributes' export-ignore rules apply. `git stash
# create` snapshots tracked files as they are on disk, so uncommitted edits
# to them, and new files once `git add`ed, are what gets tested. Before
# installing:
#
#   0. the archive must leave out the design records and agent instructions
#      (.plans, AGENTS.md) and still hold the libraries, so that an empty
#      archive cannot pass. `akku install` unpacks the whole package into a
#      consumer's .akku/src/<name>/, not only its libraries, so whatever the
#      archive holds reaches every consumer. The docs site's generator,
#      site/, does ship; check 1 keeps its (site ...) libraries uninstalled.
#
# After `akku install`:
#
#   1. this package's libraries in .akku/list must be exactly the .sls files
#      git tracks under src/. A test, site or tool library would land on
#      every consumer's library path, and a missing one would fail at import.
#      The docs site generator's (site ...) libraries are named first: Akku
#      reads .akkuignore from the unpacked archive, and its `site` line is
#      what keeps them out.
#   2. every dependency must have installed at least one library.
#   3. test/akku/consumer.sps, run with only the library path that
#      .akku/bin/activate sets, must parse a request.
#
# Needs akku, chez and git on PATH; AKKU and CHEZ override the first two.
set -eu

AKKU=${AKKU:-akku}
CHEZ=${CHEZ:-chez}
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/check-akku.XXXXXX")
trap 'rm -rf "$work"' EXIT

fail() { echo "check-akku: $*" >&2; exit 1; }

# copy_archive SRC DEST: `git archive` of SRC's tracked files as they are on
# disk, kept as DEST.tar and unpacked into DEST. `git stash create` commits
# the working tree without touching it, and prints nothing when the tree is
# clean. A pipeline's status is its last command's, so the archive goes
# through a file: under set -e, a failing git or tar fails the script.
copy_archive() {
  mkdir -p "$2"
  ref=$(cd "$1" && git stash create)
  (cd "$1" && git archive --format=tar "${ref:-HEAD}") > "$2.tar"
  (cd "$2" && tar -xf -) < "$2.tar"
}

# The package's name and version, then one dependency name per line.
cat > "$work/manifest.ss" <<'EOF'
(with-input-from-file "Akku.manifest"
  (lambda ()
    (let loop ()
      (let ((d (read)))
        (cond ((eof-object? d) (error 'check-akku "no akku-package form"))
              ((and (pair? d) (eq? (car d) 'akku-package))
               (display (car (cadr d))) (display " ")
               (display (cadr (cadr d))) (newline)
               (for-each (lambda (dep) (display (car dep)) (newline))
                         (cond ((assq 'depends (cddr d)) => cdr)
                               (else '()))))
              (else (loop)))))))
EOF
manifest=$(cd "$root" && "$CHEZ" -q --script "$work/manifest.ss")
package=$(echo "$manifest" | sed -n '1s/ .*//p')
version=$(echo "$manifest" | sed -n '1s/.* //p')
depends=$(echo "$manifest" | sed '1d')

copy_archive "$root" "$work/pkg/$package"

# 0. What the archive ships: no design records, and the libraries.
tar -tf "$work/pkg/$package.tar" > "$work/archive.txt"
awk -F/ '!seen[$1]++ { print $1 }' "$work/archive.txt" > "$work/archive-top.txt"
for record in .plans AGENTS.md; do
  if grep -qxF "$record" "$work/archive-top.txt"; then
    fail "the package would ship $record; .gitattributes must mark it export-ignore"
  fi
done
grep -qxF src/generated/httparse-message.sls "$work/archive.txt" ||
  fail "the archive holds no src/generated/httparse-message.sls, so it cannot be what the package is built from"

lock="((name \"$package\") (location (directory \"$work/pkg/$package\")))"
for dep in $depends; do
  [ -f "$root/vendor/$dep/.git" ] || [ -d "$root/vendor/$dep/.git" ] ||
    fail "dependency $dep is not vendored at vendor/$dep (git submodule update --init?)"
  sub="$work/pkg/$package/vendor/$dep"
  [ -d "$sub" ] && [ -z "$(ls -A "$sub")" ] ||
    fail "vendor/$dep in the copy of $package is not an empty directory, as git tracks a submodule"
  copy_archive "$root/vendor/$dep" "$work/pkg/$dep"
  lock="$lock ((name \"$dep\") (location (directory \"$work/pkg/$dep\")))"
done

mkdir "$work/consumer"
cd "$work/consumer"
cat > Akku.manifest <<EOF
#!r6rs
(import (akku format manifest))
(akku-package ("check-akku-consumer" "0.0.0")
  (synopsis "check-akku's consumer") (authors "check-akku") (license "MIT")
  (depends ("$package" "^$version")))
EOF
cat > Akku.lock <<EOF
#!r6rs
(import (akku format lockfile))
(projects $lock)
EOF

echo "check-akku: installing $package $version and its dependencies: $depends"
"$AKKU" install > install.log 2>&1 || { cat install.log >&2; fail "akku install failed"; }

# 1. This package's libraries are exactly src/.
awk -F '\t' -v p="$package" '$2 == p && $3 == "r6rs-library" { sub("^\\.akku/lib/", "", $1); print $1 }' \
  .akku/list | sort > installed.txt
site=$(awk '/^site\// { printf "%s%s", sep, $0; sep = " " }' installed.txt)
[ -z "$site" ] ||
  fail "$package installs the docs site generator's libraries ($site): .akkuignore must list site"
(cd "$root" && git ls-files -- 'src/*.sls' | sed 's#^src/##' | sort) > expected.txt
diff -u expected.txt installed.txt > libraries.diff ||
  { cat libraries.diff >&2; fail "$package installs a different set of libraries than src/ (- missing, + extra)"; }

# 2. Each dependency installed something.
for dep in $depends; do
  awk -F '\t' -v p="$dep" '$2 == p && $3 == "r6rs-library"' .akku/list | grep -q . ||
    fail "dependency $dep installed no library"
done

# 3. A consumer parses a request with only Akku's library path.
cp "$root/test/akku/consumer.sps" consumer.sps
# The single quotes are deliberate: $0 is expanded by the inner shell.
# shellcheck disable=SC2016
out=$(env -u CHEZSCHEMELIBDIRS R6RS_PATH= R7RS_PATH= LD_LIBRARY_PATH= DYLD_LIBRARY_PATH= \
        sh -c '. .akku/bin/activate && exec "$0" --program consumer.sps' "$CHEZ") ||
  fail "consumer.sps failed with Akku's library path"
[ "$out" = "GET /index.html complete" ] ||
  fail "consumer.sps printed '$out', not 'GET /index.html complete'"

echo "check-akku: no internal paths in the archive, $(wc -l < installed.txt | tr -d ' ') libraries from src/, and a consumer parsed a request"
