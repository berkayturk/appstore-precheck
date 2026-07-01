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

echo "test-suppress: OK"
exit "$fails"
