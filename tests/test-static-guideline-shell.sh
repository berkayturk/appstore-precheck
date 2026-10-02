#!/usr/bin/env bash
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/_assert.sh
source "$DIR/_assert.sh"
SCRIPT_DIR="$DIR/../skills/appstore-precheck/scripts"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
META_DIR="$ROOT/missing" INFO_PLIST="$ROOT/Info.plist"
GREP_PRUNE=( --exclude-dir=Pods --exclude-dir=Ignored )
# shellcheck source=skills/appstore-precheck/scripts/findings.sh
source "$SCRIPT_DIR/findings.sh"
# shellcheck source=skills/appstore-precheck/scripts/evidence.sh
source "$SCRIPT_DIR/evidence.sh"
warn() { printf 'WARN:%s:%s:%s\n' "$_CURRENT_RULE" "$1" "${2:-}" >> "$ROOT/output"; }
pass() { printf 'PASS:%s:%s\n' "$_CURRENT_RULE" "$1" >> "$ROOT/output"; }
skip() { printf 'SKIP:%s:%s\n' "$_CURRENT_RULE" "$1" >> "$ROOT/output"; }
mkdir "$ROOT/Ignored"
printf '%s\n' 'let web = UIWebView()' > "$ROOT/Ignored/Ignored.swift"
printf '%s\n' 'let label = "Restart your device"' > "$ROOT/App.swift"
# shellcheck source=skills/appstore-precheck/scripts/lib/scan-guidelines.sh
source "$SCRIPT_DIR/lib/scan-guidelines.sh"
assert_contains "$(cat "$ROOT/output")" 'WARN:device-restart-instructions:2.4.4' 'literal guideline and slug emitted'
assert_eq "$(grep '^WARN:device-restart-instructions:' "$ROOT/output" | awk -F: '{print $NF}')" 'App.swift' 'finding path preserves exact relative filename'
assert_absent "$(cat "$ROOT/output")" 'WARN:browser-engine' 'GREP_PRUNE excludes custom directory'
assert_absent "$(cat "$ROOT/output")" 'PASS:release-notes-specificity' 'missing metadata never passes'
assert_eq "$(printf '%s' "$COVERAGE_GAPS_JSON" | jq '[.[] | select(.rule_id == "release-notes-specificity" and .status == "SKIP")] | length')" 1 'missing metadata explicit coverage gap'
assert_eq "$(printf '%s' "$COVERAGE_GAPS_JSON" | jq '[.[] | select(.rule_id == "metadata-emoji-icon-not-audited")] | length')" 1 'icon pixels explicitly unaudited'
for n in $(seq 56 71); do
  slug="$(rule_slug "$n")"
  assert_not_empty "$slug" "section $n registered"
  assert_not_empty "$(rule_evidence "$slug")" "section $n evidence classified"
  assert_eq "$(rule_confidence "$slug")" judgment-call "section $n honest heuristic confidence"
done
# Missing optional tools must preserve honest gaps even in text-only environments.
COVERAGE_GAPS_JSON='[]'
command() {
  if [[ "$1" == '-v' && "$2" == jq ]]; then return 1; fi
  builtin command "$@"
}
# shellcheck source=skills/appstore-precheck/scripts/lib/scan-guidelines.sh
source "$SCRIPT_DIR/lib/scan-guidelines.sh"
unset -f command
assert_eq "$(printf '%s' "$COVERAGE_GAPS_JSON" | jq length)" 16 'unavailable reader yields 16 unique rule gaps'
exit "$fails"
