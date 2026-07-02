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

# Count only catalog-tagging set_rule calls (non-empty slug); the IAP-gate's
# `set_rule ""` reset (Fix C) is intentionally excluded — it is not a section tag.
assert_eq "42" "$(grep 'set_rule "' "$SCAN" | grep -vc 'set_rule ""')" "all 42 catalog sections tagged"

# Version provenance: the JSON envelope must report the TOOL's own version (read
# from skills/appstore-precheck/SKILL.md), never the scanned repo's package.json,
# and never fall back to "dev" in normal operation.
expected_version="$(grep -m1 -E '^[[:space:]]*version:' "$HERE/../skills/appstore-precheck/SKILL.md" 2>/dev/null | sed -E 's/.*version:[[:space:]]*//; s/[[:space:]]*$//')"
d="$(mktemp -d)"; cp -R "$HERE/fixtures/risky-app/." "$d/"
jv="$(cd "$d" && APPSTORE_PRECHECK_CONFIG=/nonexistent bash "$SCAN" --format json 2>/dev/null)"
assert_eq "$(jq -r .version <<<"$jv")" "$expected_version" "version field equals the tool's own SKILL.md version"
assert_eq "$([[ "$(jq -r .version <<<"$jv")" == "dev" ]] && echo yes || echo no)" "no" "version is not 'dev'"
rm -rf "$d"

# No leak from scanned app: drop a package.json with a *different* version at the
# fixture root and confirm scan.sh still reports the TOOL's version, not the
# scanned app's. Regression test for the package.json-based derivation bug.
d="$(mktemp -d)"; cp -R "$HERE/fixtures/risky-app/." "$d/"
echo '{"version":"42.0.7"}' > "$d/package.json"
jv2="$(cd "$d" && APPSTORE_PRECHECK_CONFIG=/nonexistent bash "$SCAN" --format json 2>/dev/null)"
assert_eq "$(jq -r .version <<<"$jv2")" "$expected_version" "version field is the tool's version, not the scanned app's package.json"
assert_eq "$([[ "$(jq -r .version <<<"$jv2")" == "42.0.7" ]] && echo leaked || echo clean)" "clean" "scanned app's package.json version did not leak"
rm -rf "$d"

# IAP-gate PASS must not inherit §7's rule_id when no IAP signals exist at all.
d="$(mktemp -d)"; cp -R "$HERE/fixtures/no-iap-app/." "$d/"
jv3="$(cd "$d" && APPSTORE_PRECHECK_CONFIG=/nonexistent bash "$SCAN" --format json 2>/dev/null)"
iap_rule="$(jq -r '[.findings[]|select(.message|test("no in-app purchase"))][0].rule_id' <<<"$jv3")"
assert_eq "$iap_rule" "" "IAP-gate PASS has an empty rule_id (not inherited from §7)"
rm -rf "$d"

exit "$fails"
