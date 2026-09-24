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

mkdir -p "$REPO/.planning"
private_probe="$(mktemp -d "$REPO/.planning/pack-privacy.XXXXXX")"
work="$(mktemp -d)"; trap 'rm -rf "$work" "$private_probe"' EXIT
# Synthetic private files prove that the archive exclusion works on clean CI too.
printf 'synthetic private evidence\n' > "$private_probe/source-snapshot.html"
printf 'SYNTHETIC_ONLY=true\n' > "$private_probe/.env"
printf '{}\n' > "$private_probe/test-asc-key.json"

section "npm pack produces a tarball"
tarball="$(cd "$REPO" && npm --cache "$work/npm-cache" pack --pack-destination "$work" 2>/dev/null | tail -1)"
assert_contains "$tarball" "appstore-precheck-" "npm pack names the tarball"
[[ -n "$tarball" && -f "$work/$tarball" ]] || { echo "  FAIL: tarball not found at $work/$tarball"; exit 1; }

section "private source archives and credentials stay outside the package"
private_entries="$(tar -tzf "$work/$tarball" | grep -E '(^|/)(\.planning|\.typesafe-cache|\.git)(/|$)|(^|/)\.env$|asc-key[^/]*\.json$|^package/eval/rag/corpus/sections\.json$' || true)"
assert_eq "$private_entries" "" "tarball excludes private archives, corpus and credentials"

section "extracted package is self-contained"
tar -xzf "$work/$tarball" -C "$work"
PKG="$work/package"
[[ -f "$PKG/bin/cli.js" ]] || { echo "  FAIL: bin/cli.js missing from tarball"; fails=$((fails+1)); }
[[ -f "$PKG/skills/appstore-precheck/scripts/scan.sh" ]] || { echo "  FAIL: bundled scan.sh missing from tarball"; fails=$((fails+1)); }

expected_version="$(node -p "require('$REPO/package.json').version")"
got_version="$(node "$PKG/bin/cli.js" --version)"
assert_eq "$got_version" "$expected_version" "extracted CLI reports the packaged version"

section "extracted optional TypeSafe command is self-contained"
review="$(node "$PKG/bin/cli.js" review --bundle "$PKG/skills/appstore-precheck/references/typesafe-example.json" --dry-run 2>&1)"; review_code=$?
assert_eq "$review_code" "0" "packaged semantic review prepares requests without repo-only dependencies"
assert_eq "$(printf '%s' "$review" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["requests"]))')" "10" \
  "all ten semantic workflows are packaged"

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
