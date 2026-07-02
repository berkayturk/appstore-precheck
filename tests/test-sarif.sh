#!/usr/bin/env bash
# tests/test-sarif.sh — unit tests for sarif.sh render_sarif (SARIF 2.1.0 from findings buffer).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/_assert.sh
source "$HERE/_assert.sh"
# shellcheck source=skills/appstore-precheck/scripts/findings.sh
source "$HERE/../skills/appstore-precheck/scripts/findings.sh"
# shellcheck source=skills/appstore-precheck/scripts/sarif.sh
source "$HERE/../skills/appstore-precheck/scripts/sarif.sh"
PRECHECK_VERSION="9.9.9"

section "empty buffer -> valid empty SARIF"
FINDINGS_TMP="$(mktemp)"; : > "$FINDINGS_TMP"
out="$(render_sarif)"
assert_eq "2.1.0" "$(jq -r .version <<<"$out")" "version 2.1.0"
assert_eq "appstore-precheck" "$(jq -r '.runs[0].tool.driver.name' <<<"$out")" "driver name"
assert_eq "9.9.9" "$(jq -r '.runs[0].tool.driver.version' <<<"$out")" "driver version"
assert_eq "0" "$(jq -r '.runs[0].results|length' <<<"$out")" "no results when empty"
assert_eq "true" "$(jq -e 'has("$schema")' <<<"$out")" "schema present"
rm -f "$FINDINGS_TMP"

section "FAIL/WARN mapped; PASS + suppressed excluded; locations"
FINDINGS_TMP="$(mktemp)"; : > "$FINDINGS_TMP"
set_rule "private-api";          _record FAIL "2.5.1 Private API used" "ios/App/A.swift" "7"
set_rule "ats-arbitrary-loads";  _record WARN "1.6 ATS disabled" "ios/App/Info.plist" "12"
set_rule "min-functionality-nav";_record WARN "4.2 No nav"      # no file/line
set_rule "screenshots-per-locale"; _record PASS "2.3.3 Screenshots ok"
# a suppressed finding
_record_suppressed WARN "2.3.10 suppressed thing" "x" "1"
out="$(render_sarif)"
assert_eq "3" "$(jq -r '.runs[0].results|length' <<<"$out")" "only 3 issues (2 FAIL/WARN with location + 1 unlocated WARN; no PASS/suppressed)"
assert_eq "error" "$(jq -r '.runs[0].results[]|select(.ruleId=="private-api").level' <<<"$out")" "FAIL -> error"
assert_eq "warning" "$(jq -r '.runs[0].results[]|select(.ruleId=="ats-arbitrary-loads").level' <<<"$out")" "WARN -> warning"
assert_eq "ios/App/A.swift" "$(jq -r '.runs[0].results[]|select(.ruleId=="private-api").locations[0].physicalLocation.artifactLocation.uri' <<<"$out")" "located finding uri"
assert_eq "7" "$(jq -r '.runs[0].results[]|select(.ruleId=="private-api").locations[0].physicalLocation.region.startLine' <<<"$out")" "located finding startLine"
assert_eq "0" "$(jq -r '.runs[0].results[]|select(.ruleId=="min-functionality-nav").locations|length' <<<"$out")" "unlocated finding -> empty locations"
assert_eq "true" "$(jq -e '.runs[0].tool.driver.rules|map(.id)|index("private-api")!=null' <<<"$out")" "rule metadata for private-api present"
assert_eq "2.5.1" "$(jq -r '.runs[0].tool.driver.rules[]|select(.id=="private-api").shortDescription.text' <<<"$out")" "rule shortDescription = guideline"
rm -f "$FINDINGS_TMP"

section "scan.sh --format sarif end-to-end"
SCAN="$HERE/../skills/appstore-precheck/scripts/scan.sh"
tmp="$(mktemp -d)"; cp -R "$HERE/fixtures/sample-app/." "$tmp/"
e2e="$(cd "$tmp" && APPSTORE_PRECHECK_CONFIG=/nonexistent bash "$SCAN" --format sarif 2>/dev/null)"
rm -rf "$tmp"
assert_eq "2.1.0" "$(jq -r .version <<<"$e2e")" "e2e: valid SARIF version"
assert_eq "true" "$(jq -e '.runs[0].results|length > 0' <<<"$e2e")" "e2e: sample-app produces results"
assert_eq "true" "$(jq -e '[.runs[0].results[].level]|any(.=="error" or .=="warning")' <<<"$e2e")" "e2e: results carry error/warning levels"

section "scan.sh --format bad value -> exit 64"
tmp="$(mktemp -d)"; cp -R "$HERE/fixtures/clean-app/." "$tmp/"
( cd "$tmp" && APPSTORE_PRECHECK_CONFIG=/nonexistent bash "$SCAN" --format xml >/dev/null 2>&1 ); code=$?
rm -rf "$tmp"
assert_eq "64" "$code" "invalid --format exits 64"

echo
if (( fails == 0 )); then echo "[test-sarif.sh] OK"; else echo "[test-sarif.sh] $fails FAILED"; fi
exit "$fails"
