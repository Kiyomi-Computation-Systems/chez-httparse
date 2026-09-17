// Build the two live llhttp oracle binaries from a checkout named at run time.
//
// Decision 0010 puts a live llhttp behind a local, opt-in lane: the checkout
// is named by a variable, never hardcoded, and the lane is ABSENT rather than
// failing when it is unset. This script is the part that needs the checkout.
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
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';
import fs from 'node:fs';
import path from 'node:path';

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

// THE THIRD BINARY IS A DIFFERENT PARSER, not a third mode of the first.
// Decision 0022: llhttp's URL sub-parser is its own machine, and `url.md` was
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
