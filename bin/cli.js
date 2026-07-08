#!/usr/bin/env node
'use strict';

// appstore-precheck CLI: a thin Node wrapper so the scanner runs with no clone,
// via `npx appstore-precheck`. It shells out to the bundled scan.sh + verdict.sh,
// prints their output verbatim, and maps the verdict to an exit code (mirroring
// the GitHub Action). It does not reimplement any check; the Bash scripts are the
// single source of truth.

const { spawnSync } = require('child_process');
const path = require('path');
const fs = require('fs');

const PKG_ROOT = path.resolve(__dirname, '..');
const SCAN = path.join(PKG_ROOT, 'skills', 'appstore-precheck', 'scripts', 'scan.sh');
const VERDICT = path.join(PKG_ROOT, 'skills', 'appstore-precheck', 'scripts', 'verdict.sh');

function pkgVersion() {
  try {
    return JSON.parse(fs.readFileSync(path.join(PKG_ROOT, 'package.json'), 'utf8')).version;
  } catch (_) {
    return 'unknown';
  }
}

function printHelp() {
  process.stdout.write(
    `appstore-precheck ${pkgVersion()} - read-only iOS App Store pre-submission scan\n` +
    `\n` +
    `Usage:\n` +
    `  npx appstore-precheck [options]\n` +
    `\n` +
    `Runs the static scanner over the current directory and prints a\n` +
    `GREEN / YELLOW / RED verdict. Read-only: it never edits your files.\n` +
    `\n` +
    `Options:\n` +
    `  --dir <path>        Directory to scan (default: current directory)\n` +
    `  --fail-on <level>   Exit non-zero at RED (default) or YELLOW\n` +
    `  --format <fmt>      Output format: text (default), json, or sarif\n` +
    `  -v, --version       Print the version and exit\n` +
    `  -h, --help          Show this help and exit\n` +
    `\n` +
    `Exit codes: 0 ok, 1 verdict at or past --fail-on, 64 bad usage,\n` +
    `70 environment error (bash or scanner not available).\n` +
    `\n` +
    `Requires bash, git, grep, and find on PATH (macOS / Linux; on Windows\n` +
    `use WSL or Git Bash). jq and python3 unlock the config + exact-length checks.\n`
  );
}

function fail(message, code) {
  process.stderr.write(`appstore-precheck: ${message}\n`);
  process.exit(code);
}

function parseArgs(argv) {
  const opts = { dir: process.cwd(), failOn: 'RED', format: 'text' };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '-h' || a === '--help') { printHelp(); process.exit(0); }
    if (a === '-v' || a === '--version') { process.stdout.write(pkgVersion() + '\n'); process.exit(0); }
    if (a === '--dir') {
      opts.dir = argv[++i];
      if (!opts.dir) fail('--dir requires a path', 64);
      continue;
    }
    if (a === '--fail-on') {
      const v = (argv[++i] || '').toUpperCase();
      if (v !== 'RED' && v !== 'YELLOW') fail('--fail-on must be RED or YELLOW', 64);
      opts.failOn = v;
      continue;
    }
    if (a === '--format') {
      const v = (argv[++i] || '').toLowerCase();
      if (v !== 'text' && v !== 'json' && v !== 'sarif') fail('--format must be text, json, or sarif', 64);
      opts.format = v;
      continue;
    }
    fail(`unknown option: ${a} (try --help)`, 64);
  }
  return opts;
}

function main() {
  const opts = parseArgs(process.argv.slice(2));

  if (!fs.existsSync(SCAN) || !fs.existsSync(VERDICT)) {
    fail('bundled scanner scripts are missing from the package', 70);
  }
  if (!fs.existsSync(opts.dir) || !fs.statSync(opts.dir).isDirectory()) {
    fail(`not a directory: ${opts.dir}`, 64);
  }

  // --dir is passed through explicitly: scan.sh treats it as authoritative,
  // so a monorepo subdirectory is scanned as requested instead of snapping to
  // the enclosing git toplevel.
  const scanArgs = [SCAN, '--dir', opts.dir];
  if (opts.format !== 'text') scanArgs.push('--format', opts.format);
  const scan = spawnSync('bash', scanArgs, {
    cwd: opts.dir,
    encoding: 'utf8',
    maxBuffer: 32 * 1024 * 1024,
  });
  if (scan.error && scan.error.code === 'ENOENT') {
    fail('bash is required to run the scanner (install bash, or use WSL / Git Bash on Windows)', 70);
  }
  if (scan.error) fail(`failed to run the scanner: ${scan.error.message}`, 70);
  if (scan.signal) fail(`scanner was killed by signal ${scan.signal}`, 70);

  const scanOut = scan.stdout || '';
  process.stdout.write(scanOut);

  if (opts.format !== 'text') {
    process.exit(scan.status === 0 ? 0 : (scan.status || 0));
  }

  const verdict = spawnSync('bash', [VERDICT], { input: scanOut, encoding: 'utf8' });
  if (verdict.error) fail(`failed to compute the verdict: ${verdict.error.message}`, 70);
  const summary = verdict.stdout || '';

  process.stdout.write('----------------------------------------\n');
  process.stdout.write(summary.endsWith('\n') ? summary : summary + '\n');

  const m = summary.match(/^VERDICT:\s*(\w+)/m);
  const v = m ? m[1] : 'UNKNOWN';

  let code = 0;
  if (opts.failOn === 'YELLOW') {
    code = v === 'GREEN' ? 0 : 1;
  } else {
    code = v === 'RED' ? 1 : 0;
  }
  process.exit(code);
}

main();
