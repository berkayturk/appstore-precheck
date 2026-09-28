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
    `  npx appstore-precheck dynamic --build [options]\n` +
    `  npx appstore-precheck verify --profile <json> --evidence <json> --decisions <json> --out <json>\n` +
    `  npx appstore-precheck review-packet --source-root <path> --profile <json> --out <directory>\n` +
    `  npx appstore-precheck review --repo <path> --prepare\n` +
    `  npx appstore-precheck review --bundle <json> --live\n` +
    `\n` +
    `Runs the static scanner over the current directory and prints a\n` +
    `GREEN / YELLOW / RED verdict. It never edits your project files.\n` +
    `Dynamic build/run is opt-in and executes a temporary project copy.\n` +
    `\n` +
    `Options:\n` +
    `  --dir <path>        Directory to scan (default: current directory)\n` +
    `  --fail-on <level>   Exit non-zero at RED (default) or YELLOW\n` +
    `  --format <fmt>      Output format: text (default), json, or sarif\n` +
    `  --build             Build a simulator app in a temporary project copy\n` +
    `  --app <path>        Inspect and run an existing simulator .app\n` +
    `  --metadata          Review local fastlane metadata\n` +
    `  --no-runtime        Build/inspect without launching the app\n` +
    `  --demo-login        Opt in to env-configured test login (three fresh attempts)\n` +
    `  --asc-version-id <id> Select the intended App Store version\n` +
    `  --asc-info-id <id>  Select the intended App Store app info\n` +
    `  --asc-app-id <id>   Opt in to read-only App Store Connect metadata\n` +
    `  --check-urls        Opt in to public support/privacy URL HEAD checks\n` +
    `  --dynamic-blocking  Block only unanimous launch/demo-login failures\n` +
    `  --out <path>        Keep the opt-in report outside the project\n` +
    `  --dry-run           Plan an opt-in build without executing it\n` +
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
  const opts = { dir: process.cwd(), failOn: 'RED', format: 'text', build: false,
    app: null, metadata: false, ascAppId: null, checkUrls: false,
    dynamicBlocking: false, out: null, dryRun: false, noRuntime: false, demoLogin: false, ascVersionId: null, ascInfoId: null };
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
    if (a === '--build') { opts.build = true; continue; }
    if (a === '--app' || a === '--asc-app-id' || a === '--out') {
      const value = argv[++i];
      if (!value) fail(`${a} requires a value`, 64);
      if (a === '--app') opts.app = value;
      else if (a === '--asc-app-id') { opts.ascAppId = value; opts.metadata = true; }
      else opts.out = value;
      continue;
    }
    if (a === '--no-runtime') { opts.noRuntime = true; continue; }
    if (a === '--demo-login') { opts.demoLogin = true; continue; }
    if (a === '--asc-version-id' || a === '--asc-info-id') {
      const value = argv[++i];
      if (!value) fail(`${a} requires an ID`, 64);
      if (a === '--asc-version-id') opts.ascVersionId = value;
      else opts.ascInfoId = value;
      continue;
    }
    if (a === '--metadata') { opts.metadata = true; continue; }
    if (a === '--check-urls') { opts.checkUrls = true; opts.metadata = true; continue; }
    if (a === '--dynamic-blocking') { opts.dynamicBlocking = true; continue; }
    if (a === '--dry-run') { opts.dryRun = true; continue; }
    fail(`unknown option: ${a} (try --help)`, 64);
  }
  return opts;
}

function main() {
  if (process.argv[2] === 'review-packet') {
    const script = path.join(PKG_ROOT, 'skills', 'appstore-precheck', 'scripts', 'manual-review-packet.py');
    const result = spawnSync('python3', ['-B', script, ...process.argv.slice(3)], { stdio: 'inherit' });
    if (result.error) fail('python3 is required for manual evidence packets', 70);
    process.exit(result.signal ? 70 : (result.status || 0));
  }
  if (process.argv[2] === 'verify') {
    const script = path.join(PKG_ROOT, 'skills', 'appstore-precheck', 'scripts', 'verification-report.py');
    const result = spawnSync('python3', ['-B', script, ...process.argv.slice(3)], { stdio: 'inherit' });
    if (result.error) fail('python3 is required for evidence verification', 70);
    process.exit(result.signal ? 70 : (result.status || 0));
  }
  if (process.argv[2] === 'review') {
    const script = path.join(PKG_ROOT, 'skills', 'appstore-precheck', 'scripts', 'semantic-review.py');
    const result = spawnSync('python3', ['-B', script, ...process.argv.slice(3)], { stdio: 'inherit' });
    if (result.error) fail('python3 is required for optional semantic review', 70);
    process.exit(result.signal ? 70 : (result.status || 0));
  }
  const dynamic = process.argv[2] === 'dynamic';
  const opts = parseArgs(process.argv.slice(dynamic ? 3 : 2));
  if (dynamic && !opts.build && !opts.app) fail('dynamic requires --build or --app', 64);
  if (opts.build && opts.app) fail('use --build or --app', 64);
  if (opts.noRuntime && (opts.demoLogin || opts.dynamicBlocking)) fail('--no-runtime conflicts with demo login or dynamic blocking', 64);

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
  if (opts.build) scanArgs.push('--build');
  if (opts.app) scanArgs.push('--app', opts.app);
  if (opts.metadata) scanArgs.push('--metadata');
  if (opts.ascAppId) scanArgs.push('--asc-app-id', opts.ascAppId);
  if (opts.checkUrls) scanArgs.push('--check-urls');
  if (opts.dynamicBlocking) scanArgs.push('--dynamic-blocking');
  if (opts.out) scanArgs.push('--out', opts.out);
  if (opts.dryRun) scanArgs.push('--dry-run');
  if (opts.noRuntime) scanArgs.push('--no-runtime');
  if (opts.demoLogin) scanArgs.push('--demo-login');
  if (opts.ascVersionId) scanArgs.push('--asc-version-id', opts.ascVersionId);
  if (opts.ascInfoId) scanArgs.push('--asc-info-id', opts.ascInfoId);
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
  // A usage/setup failure must not become GREEN from an empty transcript.
  if (scan.status !== 0) fail(`scanner failed (exit ${scan.status})`, scan.status || 70);

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
