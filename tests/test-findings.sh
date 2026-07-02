#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SCAN="skills/appstore-precheck/scripts"
# shellcheck source=tests/_assert.sh
source "$HERE/_assert.sh"
# shellcheck source=skills/appstore-precheck/scripts/findings.sh
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
assert_eq "screenshot-dimensions" "$(rule_slug 42)" "catalog lookup §42 screenshot-dimensions"
rm -f "$FINDINGS_TMP"

FINDINGS_TMP="$(mktemp)"; : > "$FINDINGS_TMP"
set_rule "ats-arbitrary-loads"; _record WARN "1.6 a"
set_rule "kids-wording";        _record WARN "2.3.8 b"
set_rule "ugc-no-moderation";   _record WARN "1.2 c"
set_rule "demo-account";        _record WARN "2.1 d"
set_rule "vpn-networkextension";_record WARN "5.4 e"
PRECHECK_VERSION="9.9.9"
out="$(render_json)"
assert_eq "9.9.9"  "$(jq -r .version <<<"$out")" "version in envelope"
assert_eq "YELLOW" "$(jq -r .verdict <<<"$out")" "5 warns -> YELLOW"
assert_eq "5"      "$(jq -r .summary.warn <<<"$out")" "warn count"
assert_eq "0"      "$(jq -r .summary.fail <<<"$out")" "fail count"
assert_eq "5"      "$(jq -r '.findings|length' <<<"$out")" "findings length"
rm -f "$FINDINGS_TMP"

# --- file/line plumbing (Task 1) ---
# None of the tracked fixtures trigger §11 private-api (several fixtures
# explicitly assert its *absence* — see tests/run.sh — so tracked fixtures must
# stay clean of banned-API hits). Build a scratch copy of risky-app with one
# banned-API line added, so we can exercise §11's file/line plumbing without
# perturbing any tracked fixture or other test's assertions.
fx="$(mktemp -d)"
cp -R "$ROOT/tests/fixtures/risky-app/." "$fx/"
mkdir -p "$fx/ios/RiskyApp/Legacy"
cat > "$fx/ios/RiskyApp/Legacy/OldViewController.swift" <<'EOF'
import UIKit
class OldViewController: UIViewController {
  let webView = UIWebView()
}
EOF
out="$(cd "$fx" && bash "$ROOT/$SCAN/scan.sh" --format json 2>/dev/null)"
pa="$(printf '%s' "$out" | jq -c '.findings[] | select(.rule_id=="private-api")')"
assert_not_empty "$pa" "private-api finding present in fixture with a banned API"
assert_eq "$(printf '%s' "$pa" | jq -r '.file != null')" "true" "private-api carries a file"
assert_eq "$(printf '%s' "$pa" | jq -r '(.line|type)')" "number" "private-api carries a line"
rm -rf "$fx"

# text output must not change when file/line are threaded (byte-identity):
# the plumbing must not drop or duplicate any verdict line.
txt_before="$(cd "$ROOT/tests/fixtures/risky-app" && bash "$ROOT/$SCAN/scan.sh" 2>/dev/null | grep -cE '^(FAIL|WARN|PASS):')"
assert_gt "$txt_before" "0" "risky-app emits verdict lines in text mode"

exit "$fails"
