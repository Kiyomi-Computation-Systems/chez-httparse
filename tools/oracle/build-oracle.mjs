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

for (const ty of ['request', 'response']) {
  const p = new LLParse();
  const entry = new llhttp.HTTP(p).build().entry;
  await build(p, entry, `http-${ty}`, {
    extra: ['-DLLHTTP__TEST_HTTP', path.join(root, 'src', 'native', 'http.c')],
  }, ty);
  // llparse-test-fixture writes `<name>-c` into the checkout's own build dir.
  const src = path.join(root, 'test', 'tmp', `http-${ty}-c`);
  const dst = path.join(outDir, `http-${ty}-c`);
  fs.copyFileSync(src, dst);
  fs.chmodSync(dst, 0o755);
  built.push(dst);
}

fs.writeFileSync(path.join(outDir, 'VERSION'), `${pkg.version}\n`);
console.log(`llhttp ${pkg.version}: ${built.join(' ')}`);
