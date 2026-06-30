#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/_assert.sh"
source "$HERE/../skills/appstore-precheck/scripts/findings.sh"

FINDINGS_TMP="$(mktemp)"; : > "$FINDINGS_TMP"
set_rule "ats-arbitrary-loads"
_record WARN "1.6 App Transport Security disabled" "ios/App/Info.plist" "12"
set_rule "private-api"
_record FAIL "2.5.1 Private API used"

line1="$(sed -n '1p' "$FINDINGS_TMP")"
assert_eq "ats-arbitrary-loads" "$(jq -r .rule_id <<<"$line1")" "rule_id recorded"
assert_eq "WARN"                "$(jq -r .severity <<<"$line1")" "severity recorded"
assert_eq "1.6"                 "$(jq -r .guideline <<<"$line1")" "guideline from message"
assert_eq "ios/App/Info.plist"  "$(jq -r .file <<<"$line1")" "file recorded"
assert_eq "12"                  "$(jq -r .line <<<"$line1")" "line recorded (number)"
line2="$(sed -n '2p' "$FINDINGS_TMP")"
assert_eq "null" "$(jq -r .file <<<"$line2")" "file null when omitted"
assert_eq "ats-arbitrary-loads" "$(rule_slug 23)" "catalog lookup §23"
assert_eq "" "$(rule_slug 999)" "catalog lookup unknown -> empty"
rm -f "$FINDINGS_TMP"
exit "$fails"
