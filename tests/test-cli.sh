#!/usr/bin/env bash
# tests/test-cli.sh — asserts the npx CLI wrapper (bin/cli.js) shells out to the
# bundled scan.sh + verdict.sh, prints the verdict, and maps it to an exit code.
# Each fixture is copied to a temp dir OUTSIDE the repo's git tree (like run.sh) so
# the scanner treats it as the project root. Requires node + bash.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/_assert.sh
source "$DIR/_assert.sh"
REPO="$(cd "$DIR/.." && pwd)"
CLI="$REPO/bin/cli.js"
FIXTURES="$DIR/fixtures"

if ! command -v node >/dev/null 2>&1; then
  echo "test-cli: node not found, skipping (CLI is an optional npx entry point)"
  exit 0
fi

# run_cli <fixture> [args...] -> sets $OUT and $CODE
OUT=""; CODE=0
run_cli() {
  local fixture="$1"; shift
  local tmp; tmp="$(mktemp -d)"
  cp -R "$FIXTURES/$fixture/." "$tmp/"
  OUT="$(node "$CLI" --dir "$tmp" "$@" 2>&1)"; CODE=$?
  rm -rf "$tmp"
}

section "clean-app -> GREEN, exit 0"
run_cli "clean-app"
assert_contains "$OUT" "VERDICT: GREEN" "verdict is GREEN"
assert_contains "$OUT" "---END-OF-SCAN---" "scan output is passed through verbatim"
assert_eq "$CODE" "0" "exit code 0 for GREEN"

section "sample-app -> RED, exit 1 (default --fail-on RED)"
run_cli "sample-app"
assert_contains "$OUT" "VERDICT: RED" "verdict is RED"
assert_eq "$CODE" "1" "exit code 1 for RED"

section "tracking-app -> YELLOW; default fail-on RED does not fail"
run_cli "tracking-app"
assert_contains "$OUT" "VERDICT: YELLOW" "verdict is YELLOW (0 FAIL, 5+ WARN)"
assert_eq "$CODE" "0" "YELLOW does not trip the default RED gate"

section "tracking-app with --fail-on YELLOW -> exit 1"
run_cli "tracking-app" --fail-on YELLOW
assert_eq "$CODE" "1" "--fail-on YELLOW fails on a YELLOW verdict"

section "--version prints the package version"
ver="$(node "$CLI" --version 2>&1)"; vcode=$?
pkg_ver="$(node -p "require('$REPO/package.json').version")"
assert_eq "$ver" "$pkg_ver" "--version matches package.json"
assert_eq "$vcode" "0" "--version exits 0"

section "--help exits 0 and shows usage"
help="$(node "$CLI" --help 2>&1)"; hcode=$?
assert_contains "$help" "Usage:" "help shows usage"
assert_eq "$hcode" "0" "--help exits 0"

section "unknown option is a usage error (exit 64)"
node "$CLI" --bogus >/dev/null 2>&1; bcode=$?
assert_eq "$bcode" "64" "bad usage exits 64"

section "clean-app --format sarif -> SARIF doc, exit 0"
run_cli "clean-app" --format sarif
assert_contains "$OUT" '"version": "2.1.0"' "cli passes --format sarif through to the scanner"
assert_eq "$CODE" "0" "non-text format exits 0"

section "--format bad value -> exit 64"
run_cli "clean-app" --format xml
assert_eq "$CODE" "64" "invalid --format exits 64"

section "--dir inside a git repo scans the subdir, not the git toplevel"
# Regression guard: scan.sh used to snap to `git rev-parse --show-toplevel`,
# silently ignoring --dir for tracked monorepo subdirectories.
mono="$(mktemp -d)"
git -C "$mono" init -q
mkdir -p "$mono/apps"
cp -R "$FIXTURES/clean-app/." "$mono/apps/ios-app/"
OUT="$(node "$CLI" --dir "$mono/apps/ios-app" 2>&1)"; CODE=$?
assert_contains "$OUT" "ios='./ios/CleanApp'" "layout detected relative to --dir, not the enclosing git root"
assert_contains "$OUT" "VERDICT: GREEN" "subdir scan reaches the same GREEN as a standalone scan"
assert_eq "$CODE" "0" "exit 0 for the subdir GREEN"
rm -rf "$mono"

section "relative --dir/--out/--app resolve against the caller's cwd, not --dir"
# The scanner child runs with cwd=--dir, so a relative value used to be re-resolved
# against the scanned project (and --out then landed inside it, where it is refused).
rel="$(cd "$(mktemp -d)" && pwd -P)"
mkdir -p "$rel/proj"
cp -R "$FIXTURES/clean-app/." "$rel/proj/"
( cd "$rel" && node "$CLI" --dir proj --build --dry-run --metadata --out rel-out --format json >"$rel/out.json" 2>"$rel/err.txt" ); CODE=$?
assert_eq "$CODE" "0" "relative --dir/--out scan exits 0"
if [[ -f "$rel/rel-out/summary.json" ]]; then echo "  ok: relative --out lands under the caller's cwd"
else echo "  FAIL: relative --out did not land under the caller's cwd"; fails=$((fails + 1)); fi
if [[ ! -e "$rel/proj/rel-out" ]]; then echo "  ok: nothing written inside the scanned project"
else echo "  FAIL: relative --out was resolved against --dir"; fails=$((fails + 1)); fi
mkdir -p "$rel/shim"
printf '#!/bin/sh\nprintf "%%s\\n" "$@" >> "%s/args.log"\n' "$rel" > "$rel/shim/bash"
chmod +x "$rel/shim/bash"
( cd "$rel" && PATH="$rel/shim:$PATH" node "$CLI" --dir proj --app build/Sample.app --out rel-out >/dev/null 2>&1 )
args="$(cat "$rel/args.log" 2>/dev/null)"
assert_contains "$args" "$rel/build/Sample.app" "relative --app is passed as an absolute path from the caller's cwd"
assert_contains "$args" "$rel/rel-out" "relative --out is passed as an absolute path from the caller's cwd"
assert_contains "$args" "$rel/proj" "relative --dir is passed as an absolute path"
rm -rf "$rel"

echo
if (( fails == 0 )); then echo "test-cli: ALL PASSED"; else echo "test-cli: $fails FAILED"; fi
exit "$fails"
