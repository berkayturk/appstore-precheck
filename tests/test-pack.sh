#!/usr/bin/env bash
# tests/test-pack.sh — prove the published npm tarball is self-contained.
# Every other test runs against the working tree; if `files` in package.json
# ever drops skills/ (or bin/), npx would break in the field with no test
# failing. This packs the real tarball, extracts it, and runs the CLI from the
# extracted layout only.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/_assert.sh
source "$DIR/_assert.sh"
REPO="$(cd "$DIR/.." && pwd)"
FIXTURES="$DIR/fixtures"

if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
  echo "test-pack: node/npm not found, skipping (packaging test needs npm)"
  exit 0
fi

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

section "npm pack produces a tarball"
tarball="$(cd "$REPO" && npm pack --pack-destination "$work" 2>/dev/null | tail -1)"
assert_contains "$tarball" "appstore-precheck-" "npm pack names the tarball"
[[ -f "$work/$tarball" ]] || { echo "  FAIL: tarball not found at $work/$tarball"; fails=$((fails+1)); }

section "extracted package is self-contained"
tar -xzf "$work/$tarball" -C "$work"
PKG="$work/package"
[[ -f "$PKG/bin/cli.js" ]] || { echo "  FAIL: bin/cli.js missing from tarball"; fails=$((fails+1)); }
[[ -f "$PKG/skills/appstore-precheck/scripts/scan.sh" ]] || { echo "  FAIL: bundled scan.sh missing from tarball"; fails=$((fails+1)); }

expected_version="$(node -p "require('$REPO/package.json').version")"
got_version="$(node "$PKG/bin/cli.js" --version)"
assert_eq "$got_version" "$expected_version" "extracted CLI reports the packaged version"

section "extracted CLI scans a fixture end-to-end"
app="$work/app"
mkdir -p "$app"
cp -R "$FIXTURES/clean-app/." "$app/"
OUT="$(node "$PKG/bin/cli.js" --dir "$app" 2>&1)"; CODE=$?
assert_contains "$OUT" "VERDICT: GREEN" "packaged scanner produces the GREEN verdict"
assert_eq "$CODE" "0" "packaged CLI exits 0 on GREEN"

echo
if (( fails == 0 )); then echo "test-pack: ALL PASSED"; else echo "test-pack: $fails FAILED"; fi
exit "$fails"
