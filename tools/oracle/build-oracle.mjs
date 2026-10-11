// Build the two live llhttp oracle binaries from a checkout named at run time.
//
// The live llhttp oracle is a local, opt-in lane: the checkout is named by a
// variable, never hardcoded, and the lane is ABSENT rather than failing when
// it is unset. This script is the part that needs the checkout.
//
// IT DOES NOT REIMPLEMENT UPSTREAM'S HARNESS, IT CALLS IT. The binaries that
// produced the vendored corpus are built by llhttp's own test/fixtures/index.ts
// on top of llparse-test-fixture, and a hand-rolled C driver printing the same
// lines would be a second implementation of the very format the comparison
// depends on. So this imports that module by absolute path -- which is also
// how its own bare imports keep resolving against the checkout's node_modules
// rather than ours.
//
// Usage: node --import tsx build-oracle.mjs <llhttp-root> <out-dir>
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';
import fs from 'node:fs';
import path from 'node:path';

const here = path.dirname(fileURLToPath(import.meta.url));

// THE FIXTURE CACHE DOES NOT HASH OUR SOURCE, ONLY THE ARGUMENT LIST.
// `llparse-test-fixture` keys its build on the generated header, the
// generated C and `commonArgs.join(' ')`, then skips the compile when a file
// with that digest already exists. Our init hook reaches it as a PATH in that
// argument list, so editing the hook leaves the digest unchanged and the
// stale binary is relinked -- measured, not guessed: a deliberately wrong
// hook produced a byte-identical oracle and a green differential.
//
// So its content goes into the arguments, as a define nothing reads. The
// digest then moves whenever the file does, which is the only thing the cache
// looks at.
function sourceRevision(file) {
  return createHash('sha256').update(fs.readFileSync(file)).digest('hex').slice(0, 16);
}

const [root, outDir] = process.argv.slice(2);
if (!root || !outDir) {
  console.error('usage: build-oracle.mjs <llhttp-root> <out-dir>');
  process.exit(2);
}

const require = createRequire(path.join(root, 'package.json'));
const { LLParse } = require('llparse');
const llhttp = (await import(pathToFileURL(path.join(root, 'src', 'llhttp.ts')))).default;
const { build } = await import(pathToFileURL(path.join(root, 'test', 'fixtures', 'index.ts')));

fs.mkdirSync(outDir, { recursive: true });

// The version the binaries are built from is written beside them. The corpus
// records the commit it was vendored from, and a differential run against a
// DIFFERENT llhttp would report version drift as parser divergence -- so the
// lane compares these two and says which it is.
const pkg = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'));
const built = [];

// llparse-test-fixture writes `<name>-c` into the checkout's own build dir.
function collect(name) {
  const src = path.join(root, 'test', 'tmp', `${name}-c`);
  const dst = path.join(outDir, `${name}-c`);
  fs.copyFileSync(src, dst);
  fs.chmodSync(dst, 0o755);
  built.push(dst);
}

for (const ty of ['request', 'response']) {
  const p = new LLParse();
  const entry = new llhttp.HTTP(p).build().entry;
  await build(p, entry, `http-${ty}`, {
    extra: ['-DLLHTTP__TEST_HTTP', path.join(root, 'src', 'native', 'http.c')],
  }, ty);
  collect(`http-${ty}`);
}

// THE FOURTH BINARY IS THE ONE UPSTREAM CANNOT BE ASKED FOR. Its init hook is
// ours (`tools/oracle/lenient-init.c`) and takes its mode from the
// environment, so one binary answers for any COMBINATION of lenient flags --
// upstream's hooks are one per (kind, single flag) and are chosen by a `-D`
// at compile time, so 55 pairs would be 55 binaries and no hook exists for
// any of them. That still calls upstream's harness rather than reimplementing
// it: the hook assigns two integer fields and prints nothing, so every trace
// line still comes from upstream's `extra.c`.
//
// IT IS BUILT FROM THE SAME GRAPH as `http-request-c`. Only the init differs,
// which is what lets the differential hold it to upstream's own binaries at
// an empty mask and at each single flag.
{
  const p = new LLParse();
  const entry = new llhttp.HTTP(p).build().entry;
  await build(p, entry, 'http-modes', {
    extra: [
      '-DLLHTTP__TEST_HTTP',
      path.join(root, 'src', 'native', 'http.c'),
      `-DLLPARSE__TEST_INIT=chez_httparse__test_init_modes`,
      `-DCHEZ_HTTPARSE_INIT_REVISION=${sourceRevision(path.join(here, 'lenient-init.c'))}`,
      path.join(here, 'lenient-init.c'),
    ],
  }, 'none');
  collect('http-modes');
}

// AND ONE OF UPSTREAM'S OWN LENIENT BINARIES, built the way `md-test.ts`
// builds it -- `ty` in `allowedTypes`, so upstream's harness pushes
// `-DLLPARSE__TEST_INIT=llhttp__test_init_request_lenient_headers` and our
// file is not involved at all. It exists so the differential can hold
// `http-modes-c` to it at that flag: an init hook of ours that set the wrong
// bit, or set it at the wrong time, would otherwise be invisible.
{
  const p = new LLParse();
  const entry = new llhttp.HTTP(p).build().entry;
  await build(p, entry, 'http-request-lenient-headers', {
    extra: ['-DLLHTTP__TEST_HTTP', path.join(root, 'src', 'native', 'http.c')],
  }, 'request-lenient-headers');
  collect('http-request-lenient-headers');
}

// THE THIRD BINARY IS A DIFFERENT PARSER, not a third mode of the first.
// llhttp's URL sub-parser is its own machine, and `url.md` was
// recorded from THIS build of it -- `test/md-test.ts`'s `buildURL()`, copied
// here line for line rather than approximated:
//
//   * `separateSpans = true`, so the span table holds schema/host/path/query/
//     fragment and `url` is a stub. The HTTP parser is built the other way
//     round, and the two are not interchangeable.
//   * BOTH EXITS LOOPED BACK TO THE ENTRY, which is a property of the test
//     build and not of the URL parser: in a real llhttp they join the HTTP
//     machine at `HTTP/`. It is why one input can hold several urls.
//   * No `extra` at all. `url` is not in `allowedTypes`, so upstream's
//     harness pushes no `-DLLPARSE__TEST_INIT` and there is no init hook --
//     which is the same thing as saying a url parser has no `s->type`.
{
  const p = new LLParse();
  const node = new llhttp.URL(p, true).build();
  node.exit.toHTTP.otherwise(node.entry.normal);
  node.exit.toHTTP09.otherwise(node.entry.normal);
  await build(p, node.entry.normal, 'url-url', { extra: [] }, 'url');
  collect('url-url');
}

fs.writeFileSync(path.join(outDir, 'VERSION'), `${pkg.version}\n`);
console.log(`llhttp ${pkg.version}: ${built.join(' ')}`);
