#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCAN="skills/appstore-precheck/scripts"
# shellcheck source=tests/_assert.sh
source "$ROOT/tests/_assert.sh"
# shellcheck source=skills/appstore-precheck/scripts/findings.sh
source "$ROOT/$SCAN/findings.sh"
# shellcheck source=skills/appstore-precheck/scripts/suppress.sh
source "$ROOT/$SCAN/suppress.sh"

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

# --- rule-id everywhere ---
cat > "$work/.precheck-ignore" <<'EOF'
# comment line ignored
account-no-delete            # suppress this rule everywhere
ats-arbitrary-loads  ios/Legacy/
vendor/
EOF
load_precheck_ignore "$work"

is_suppressed "account-no-delete" "" ""            && r=0 || r=1
assert_eq "$r" "0" "rule-id suppressed everywhere"

is_suppressed "private-api" "" ""                  && r=0 || r=1
assert_eq "$r" "1" "unlisted rule not suppressed"

# --- rule + path scoped ---
is_suppressed "ats-arbitrary-loads" "ios/Legacy/Info.plist" "" && r=0 || r=1
assert_eq "$r" "0" "rule suppressed under matching path"
is_suppressed "ats-arbitrary-loads" "ios/App/Info.plist" ""    && r=0 || r=1
assert_eq "$r" "1" "rule not suppressed outside path"

# --- path exclusion collected ---
assert_eq "$(precheck_prune_globs | tr '\n' ' ' | grep -c vendor)" "1" "vendor path glob collected"

# --- rule 42 (last catalog entry) is suppressible — off-by-one regression guard ---
cat > "$work/.precheck-ignore" <<'EOF'
screenshot-dimensions
EOF
err42="$(load_precheck_ignore "$work" 2>&1 >/dev/null)"
assert_eq "$(printf '%s' "$err42" | grep -c 'unknown rule-id')" "0" "rule 42 recognized as a catalog rule (no unknown-rule warning)"
load_precheck_ignore "$work"   # reload outside command substitution: state must land in this shell
is_suppressed "screenshot-dimensions" "" "" && r=0 || r=1
assert_eq "$r" "0" "rule 42 (screenshot-dimensions) suppressed everywhere"

# --- unknown rule-id reported, not treated as rule ---
cat > "$work/.precheck-ignore" <<'EOF'
not-a-real-rule
EOF
err="$(load_precheck_ignore "$work" 2>&1 >/dev/null)"
assert_contains "$err" "unknown rule-id" "unknown rule-id reported on stderr"

# --- inline: on-line and line-above ---
src="$work/Sample.swift"
printf '%s\n' \
  'let a = 1 // precheck:ignore private-api' \
  '// precheck:ignore' \
  'let b = 2' \
  'let c = UIWebView()   // just mentions precheck:ignore in prose after code' > "$src"
_SUPP_RULES=""; _SUPP_RULE_PATH=""; _SUPP_PATHS=""      # inline path is independent of file rules
is_suppressed "private-api" "$src" "1" && r=0 || r=1
assert_eq "$r" "0" "inline scoped marker on the flagged line"
is_suppressed "anything" "$src" "3" && r=0 || r=1
assert_eq "$r" "0" "bare inline marker on the line above"
is_suppressed "kids-wording" "$src" "1" && r=0 || r=1
assert_eq "$r" "1" "scoped inline marker does not suppress a different rule"
is_suppressed "private-api" "$src" "4" && r=0 || r=1
assert_eq "$r" "1" "prose mention of marker is not a directive"

# --- inline: plist-style HTML comment marker ---
plist="$work/Info.plist"
printf '%s\n' \
  '<!-- precheck:ignore -->' \
  '<key>NSAllowsArbitraryLoads</key>' \
  '<!-- precheck:ignore ats-arbitrary-loads -->' > "$plist"
_SUPP_RULES=""; _SUPP_RULE_PATH=""; _SUPP_PATHS=""      # inline path is independent of file rules
is_suppressed "private-api" "$plist" "1" && r=0 || r=1
assert_eq "$r" "0" "bare plist-close marker suppresses any rule"
is_suppressed "ats-arbitrary-loads" "$plist" "1" && r=0 || r=1
assert_eq "$r" "0" "bare plist-close marker does not capture -- as a rule"
is_suppressed "ats-arbitrary-loads" "$plist" "3" && r=0 || r=1
assert_eq "$r" "0" "scoped plist-close marker suppresses its own rule"
is_suppressed "private-api" "$plist" "3" && r=0 || r=1
assert_eq "$r" "1" "scoped plist-close marker does not suppress a different rule"

# --- integration: .precheck-ignore suppresses a real finding ---
app="$(mktemp -d)"; trap 'rm -rf "$work" "$app"' EXIT
mkdir -p "$app/App"
cat > "$app/App/ContentView.swift" <<'EOF'
import SwiftUI
let legacy = UIWebView()   // triggers private-api §11
EOF
cat > "$app/App/Info.plist" <<'EOF'
<?xml version="1.0"?><plist><dict></dict></plist>
EOF
# A present-but-empty PrivacyInfo.xcprivacy keeps the unrelated §1 privacy-manifest
# check silent (no Required Reason API usage in this fixture, none declared either),
# so the ONLY FAIL in this fixture is the private-api one under test.
cat > "$app/App/PrivacyInfo.xcprivacy" <<'EOF'
<?xml version="1.0"?><plist><dict></dict></plist>
EOF

run_scan() { (cd "$app" && PRECHECK_VERSION="test" bash "$ROOT/$SCAN/scan.sh" "$@" 2>/dev/null); }

base_json="$(run_scan --format json)"
assert_eq "$(printf '%s' "$base_json" | jq '[.findings[]|select(.rule_id=="private-api" and .severity=="FAIL")]|length')" "1" "private-api fails without ignore"
assert_eq "$(printf '%s' "$base_json" | jq -r .verdict)" "RED" "verdict RED without ignore"

printf 'private-api\n' > "$app/.precheck-ignore"
supp_json="$(run_scan --format json)"
assert_eq "$(printf '%s' "$supp_json" | jq '.summary.suppressed')" "1" "suppressed count is 1"
assert_eq "$(printf '%s' "$supp_json" | jq '[.findings[]|select(.rule_id=="private-api" and .suppressed==false)]|length')" "0" "no live private-api finding"
assert_eq "$(printf '%s' "$supp_json" | jq -r .verdict)" "GREEN" "suppressed FAIL no longer forces RED"

# text mode: the FAIL line is gone, footer present, verdict via verdict.sh flips
supp_txt="$(run_scan)"
assert_eq "$(printf '%s' "$supp_txt" | grep -cE '^FAIL:.*Private')" "0" "suppressed FAIL absent from text"
assert_contains "$supp_txt" "suppressed via .precheck-ignore" "text footer reports suppression"
vtxt="$(printf '%s' "$supp_txt" | bash "$ROOT/$SCAN/verdict.sh" | grep '^VERDICT:')"
assert_contains "$vtxt" "GREEN" "verdict.sh sees GREEN after suppression"

# byte-identity: remove ignore -> output identical to a clean run
rm -f "$app/.precheck-ignore"
a="$(run_scan)"; b="$(run_scan)"
assert_eq "$a" "$b" "text output stable and footer-free with no ignore file"
assert_eq "$(printf '%s' "$a" | grep -c 'suppressed via')" "0" "no footer when nothing suppressed"

echo "test-suppress: OK"
exit "$fails"
