#!/usr/bin/env bash
# tests/test-baseline.sh — --save-baseline / --baseline: show only what is new.
# A baseline is a list of accepted FAIL/WARN findings (rule, file, message). On the
# next run every finding that matches is treated like a .precheck-ignore suppression:
# dropped from the text output and the verdict, still counted, never silently gone.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck source=tests/_assert.sh
source "$HERE/_assert.sh"
SCAN="$ROOT/skills/appstore-precheck/scripts/scan.sh"
FX="$HERE/fixtures/tracking-app"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
run() { APPSTORE_PRECHECK_CONFIG=/nonexistent bash "$SCAN" "$@" 2>"$T/err"; }

section "--save-baseline records the live FAIL/WARN findings"
out="$(run --dir "$FX" --save-baseline "$T/base.json")"
n_issues="$(printf '%s\n' "$out" | grep -cE '^(FAIL|WARN):')"
assert_eq "$([[ -s "$T/base.json" ]] && echo yes)" "yes" "baseline file written"
assert_eq "$(jq -r '.tool' "$T/base.json")" "appstore-precheck" "baseline names the tool"
assert_eq "$(jq '.findings | length' "$T/base.json")" "$n_issues" "one baseline entry per live FAIL/WARN line"
assert_eq "$(jq -r '[.findings[] | select(.severity == "PASS" or .severity == "SKIP")] | length' "$T/base.json")" "0" "PASS and SKIP are never baselined"
assert_eq "$(jq -r '.findings[0] | has("rule_id") and has("message")' "$T/base.json")" "true" "entries carry rule_id and message"
[[ "$n_issues" -gt 0 ]] || { echo "  FAIL: fixture produced no issues to baseline"; fails=$((fails + 1)); }

section "--baseline hides every matched finding from text and verdict"
out="$(run --dir "$FX" --baseline "$T/base.json")"
assert_eq "$(printf '%s\n' "$out" | grep -cE '^(FAIL|WARN):')" "0" "no live FAIL/WARN left after the baseline"
assert_contains "$out" "matched the baseline" "the footer says how many matched"
assert_contains "$(printf '%s\n' "$out" | bash "$ROOT/skills/appstore-precheck/scripts/verdict.sh")" "VERDICT: GREEN" "verdict is computed on what is new"

section "--baseline keeps the matches countable in JSON"
json="$(run --dir "$FX" --baseline "$T/base.json" --format json)"
assert_eq "$(jq -r '.summary.baseline' <<<"$json")" "$n_issues" "summary.baseline counts the matches"
assert_eq "$(jq -r '.summary.fail + .summary.warn' <<<"$json")" "0" "live counts exclude baselined findings"
assert_eq "$(jq -r '[.findings[] | select(.suppressed == true)] | length >= '"$n_issues" <<<"$json")" "true" "matched findings stay in the envelope as suppressed"

section "a baseline from another app matches only findings that are literally the same"
run --dir "$HERE/fixtures/risky-app" --save-baseline "$T/other.json" >/dev/null
# Two apps with no fastlane metadata share the file-less "no support_url.txt" WARNs word for
# word; those ARE the same finding. Anything bound to a file or app-specific text stays live.
shared="$(jq -n --slurpfile a "$T/base.json" --slurpfile b "$T/other.json" \
  '[$a[0].findings[] | [.rule_id, (.file // ""), .message]] as $x | [$b[0].findings[] | [.rule_id, (.file // ""), .message] | select(. as $k | any($x[]; . == $k))] | length')"
json="$(run --dir "$FX" --baseline "$T/other.json" --format json)"
assert_eq "$(jq -r '.summary.baseline' <<<"$json")" "$shared" "only identical rule+file+message pairs match"
assert_eq "$(jq -r '.summary.fail + .summary.warn' <<<"$json")" "$((n_issues - shared))" "app-specific findings stay live"
[[ "$shared" -lt "$n_issues" ]] || { echo "  FAIL: test setup: the two fixtures must differ"; fails=$((fails + 1)); }

section "a missing or malformed baseline is reported, never fatal"
out="$(run --dir "$FX" --baseline "$T/missing.json")"
assert_eq "$(printf '%s\n' "$out" | grep -cE '^(FAIL|WARN):')" "$n_issues" "missing baseline changes nothing"
assert_contains "$(cat "$T/err")" "baseline" "stderr names the baseline problem"
printf 'not json' > "$T/bad.json"
out="$(run --dir "$FX" --baseline "$T/bad.json")"
assert_eq "$(printf '%s\n' "$out" | grep -cE '^(FAIL|WARN):')" "$n_issues" "malformed baseline changes nothing"

section "a new finding shows up next to an otherwise clean baseline"
cp -R "$FX" "$T/app"
run --dir "$T/app" --save-baseline "$T/app.json" >/dev/null
printf 'let s = "https://api.openai.com/v1/chat/completions"\n' > "$T/app/ios/TrackingApp/AI.swift"
out="$(run --dir "$T/app" --baseline "$T/app.json")"
assert_contains "$out" "WARN: 5.1.1 Third-party AI" "the new AI-consent finding is live"
assert_contains "$out" "WARN: 2.1 review-notes-completeness" "and so is the review-notes finding it triggers"
assert_eq "$(printf '%s\n' "$out" | grep -cE '^(FAIL|WARN):')" "2" "nothing from the baseline is live"

section "relative paths are resolved from the caller's directory, not the scan root"
( cd "$T" && APPSTORE_PRECHECK_CONFIG=/nonexistent bash "$SCAN" --dir "$FX" --save-baseline rel.json >/dev/null 2>&1 )
assert_eq "$([[ -s "$T/rel.json" ]] && echo yes)" "yes" "--save-baseline rel.json lands next to the caller"
out="$( cd "$T" && APPSTORE_PRECHECK_CONFIG=/nonexistent bash "$SCAN" --dir "$FX" --baseline rel.json 2>/dev/null )"
assert_eq "$(printf '%s\n' "$out" | grep -cE '^(FAIL|WARN):')" "0" "--baseline rel.json is read from the caller's directory"

section "a message with a tab still matches its own baseline"
mkdir -p "$T/tab/ios/App" "$T/tab/fastlane/metadata/en-US"
printf 'import UIKit\n' > "$T/tab/ios/App/App.swift"
printf 'App\tName\n' > "$T/tab/fastlane/metadata/en-US/name.txt"
printf 'A\tjournal.\n' > "$T/tab/fastlane/metadata/en-US/description.txt"
run --dir "$T/tab" --save-baseline "$T/tab.json" >/dev/null
n_tab="$(jq '.findings | length' "$T/tab.json")"
json="$(run --dir "$T/tab" --baseline "$T/tab.json" --format json)"
assert_eq "$(jq -r '.summary.baseline' <<<"$json")" "$n_tab" "every finding matches again, tabs included"

exit "$fails"
