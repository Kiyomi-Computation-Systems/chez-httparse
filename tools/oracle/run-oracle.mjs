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
//   cases file, one per line:  <kind> <from>:<to> <hex-input> [<lenient-mask>]
//     -- with no mask field the line goes to upstream's own binary for that
//        kind; WITH one (even `0`) it goes to `http-modes-c`
//   out file,   one per line:  ok <hex-stdout>  |  fail <code> <hex-output>
//
// THE MASK IS WHY A FOURTH BINARY EXISTS. Upstream's fixture harness picks
// its init hook with a `-D` at compile time and ships one hook per (kind,
// single flag), so no combination of flags can be asked of `http-request-c`
// at all. `http-modes-c` is the same parser built with our own init hook,
// which reads the mask and the kind out of the environment -- see
// `tools/oracle/lenient-init.c`. A line with no mask, or a mask of 0, keeps
// using upstream's own binaries, so every strict comparison is still made
// against the program the corpus was recorded from.
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const [binDir, casesFile, outFile] = process.argv.slice(2);
if (!binDir || !casesFile || !outFile) {
  console.error('usage: run-oracle.mjs <bin-dir> <cases-file> <out-file>');
  process.exit(2);
}

// The kind names the PARSER, not a mode of one parser: `url` is llhttp's URL
// sub-parser built standalone, and its binary is named the way upstream's own
// harness names it.
const bins = {
  request: path.join(binDir, 'http-request-c'),
  response: path.join(binDir, 'http-response-c'),
  url: path.join(binDir, 'url-url-c'),
  // One of upstream's own single-flag binaries, built with its own `-D` and
  // none of our code. The differential holds `http-modes-c` to it.
  'request-lenient-headers': path.join(binDir, 'http-request-lenient-headers-c'),
};

const modesBin = path.join(binDir, 'http-modes-c');

const lines = fs.readFileSync(casesFile, 'utf8').split('\n').filter((l) => l.length > 0);
const out = [];

for (const line of lines) {
  const [kind, spec, hex, flags] = line.split(' ');
  // A LINE WITH NO FOURTH FIELD GOES TO UPSTREAM'S OWN BINARY, and that is
  // the rule rather than `mask === 0`: it keeps every strict comparison
  // against the program the corpus was recorded from, and it still lets a
  // caller write an explicit `0` to ask for the modes binary at no flags --
  // which is how the differential checks the two are the same program.
  const useModes = flags !== undefined;
  const mask = useModes ? Number.parseInt(flags, 10) : 0;
  if (!Number.isInteger(mask) || mask < 0) {
    console.error(`bad lenient mask ${JSON.stringify(flags)}`);
    process.exit(3);
  }
  if (useModes && kind === 'url') {
    // llhttp's url binary is built with no init hook at all, so there is no
    // field for a flag to set. Answering anyway would silently compare a
    // strict parse against a lenient one.
    console.error('the url parser has no lenient flags');
    process.exit(3);
  }
  const bin = useModes ? modesBin : bins[kind];
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
  const r = spawnSync(bin, [spec, input], {
    maxBuffer: 64 * 1024 * 1024,
    env: {
      ...process.env,
      HTTPARSE_ORACLE_LENIENT: String(mask),
      HTTPARSE_ORACLE_RESPONSE: kind === 'response' ? '1' : '0',
    },
  });
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
