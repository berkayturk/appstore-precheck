#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/_assert.sh
source "$HERE/_assert.sh"
SCAN="$HERE/../skills/appstore-precheck/scripts/scan.sh"

# Golden: text output for risky-app must be byte-identical with and without the change.
tmp="$(mktemp -d)"; cp -R "$HERE/fixtures/risky-app/." "$tmp/"
text="$(cd "$tmp" && APPSTORE_PRECHECK_CONFIG=/nonexistent bash "$SCAN" 2>&1)"
assert_contains "$text" "WARN: 1.6 App Transport Security" "text mode still emits warnings"
assert_contains "$text" "---END-OF-SCAN---" "text mode reaches end marker"

# JSON mode: valid JSON, no text lines leaked, findings present.
json="$(cd "$tmp" && APPSTORE_PRECHECK_CONFIG=/nonexistent bash "$SCAN" --format json 2>/dev/null)"
echo "$json" | jq -e . >/dev/null; assert_eq "0" "$?" "json mode emits valid JSON"
assert_eq "appstore-precheck" "$(jq -r .tool <<<"$json")" "tool field"
has16="$(jq '[.findings[]|select(.guideline=="1.6")]|length > 0' <<<"$json")"
assert_eq "true" "$has16" "ATS (guideline 1.6) finding present in JSON"
assert_eq "" "$(printf '%s' "$json" | grep -c 'WARN: ' | sed 's/0//')" "no text WARN lines leaked into JSON"
rm -rf "$tmp"

# Coverage: every FAIL/WARN finding must carry a non-empty catalog rule_id. Sections
# without a set_rule call silently inherit the previous section's slug instead of
# leaving it empty, so this only catches *missing* tags, not *wrong* ones — paired
# with the structural assert below (one set_rule per section) to close that gap.
for fx in risky-app risky-app-2 tracking-app; do
  d="$(mktemp -d)"; cp -R "$HERE/fixtures/$fx/." "$d/"
  j="$(cd "$d" && APPSTORE_PRECHECK_CONFIG=/nonexistent bash "$SCAN" --format json 2>/dev/null)"
  empties="$(jq '[.findings[]|select(.severity!="PASS" and (.rule_id==""))]|length' <<<"$j")"
  assert_eq "0" "$empties" "$fx: every FAIL/WARN finding has a catalog rule_id"
  rm -rf "$d"
done

assert_eq "41" "$(grep -c 'set_rule "' "$SCAN")" "all 41 sections tagged"

exit "$fails"
