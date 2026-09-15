// Feed a batch of inputs to the live llhttp oracle binaries and write back
// what they printed.
//
// WHY A BATCH FILE AND NOT A PIPE. The fixture binary takes its input as an
// ARGV STRING (llparse-test-fixture's `main`), so the input has to reach it
// as a process argument -- and building that argument inside a shell command
// would mean escaping CR, LF, quotes and backslashes correctly for every
// generated input. Node passes argv without a shell, so the escaping question
// does not arise; the cases cross as hex for the same reason.
//
// This is deliberately the only piece of the differential that is not Scheme:
// it spawns processes and touches the filesystem, and it decides nothing. The
// comparison is made by the lane.
//
// Usage: node run-oracle.mjs <bin-dir> <cases-file> <out-file>
//   cases file, one per line:  <kind> <from>:<to> <hex-input>
//   out file,   one per line:  ok <hex-stdout>  |  fail <code> <hex-output>
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const [binDir, casesFile, outFile] = process.argv.slice(2);
if (!binDir || !casesFile || !outFile) {
  console.error('usage: run-oracle.mjs <bin-dir> <cases-file> <out-file>');
  process.exit(2);
}

const bins = {
  request: path.join(binDir, 'http-request-c'),
  response: path.join(binDir, 'http-response-c'),
};

const lines = fs.readFileSync(casesFile, 'utf8').split('\n').filter((l) => l.length > 0);
const out = [];

for (const line of lines) {
  const [kind, spec, hex] = line.split(' ');
  const bin = bins[kind];
  if (!bin) {
    // A kind with no binary is a caller error, and answering anyway would
    // compare the wrong parser.
    console.error(`no oracle binary for kind ${JSON.stringify(kind)}`);
    process.exit(3);
  }
  // Latin-1 is a byte-for-byte mapping on the way in; the generator holds
  // every input to [1,127] precisely because argv is encoded as UTF-8 and a
  // high byte would arrive as two.
  const input = Buffer.from(hex ?? '', 'hex').toString('latin1');
  const r = spawnSync(bin, [spec, input], { maxBuffer: 64 * 1024 * 1024 });
  if (r.error) {
    out.push(`fail spawn ${Buffer.from(String(r.error)).toString('hex')}`);
  } else if (r.signal) {
    out.push(`fail ${r.signal} ${Buffer.concat([r.stdout, r.stderr]).toString('hex')}`);
  } else if (r.status !== 0) {
    out.push(`fail ${r.status} ${Buffer.concat([r.stdout, r.stderr]).toString('hex')}`);
  } else {
    out.push(`ok ${r.stdout.toString('hex')}`);
  }
}

fs.writeFileSync(outFile, out.join('\n') + (out.length ? '\n' : ''));
