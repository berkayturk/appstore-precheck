#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/_assert.sh
source "$ROOT/tests/_assert.sh"
# shellcheck source=scripts/guideline-drift.sh
source "$ROOT/scripts/guideline-drift.sh"

FIX="$ROOT/tests/fixtures/guidelines"

# --- gd_section_ids: only numeric guideline anchors, in order, deduped ---
ids="$(gd_section_ids "$FIX/sample.html" | tr '\n' ' ')"
assert_eq "$ids" "1.2 2.3.3 3.1.1 5.1.1 " "section ids extracted in order, globalnav id ignored"

# --- gd_section_text: exact id, not a prefix; normalized prose ---
t="$(gd_section_text "$FIX/sample.html" "2.3.3")"
assert_contains "$t" "screenshots should show the app in use" "2.3.3 prose extracted + lowercased"
assert_absent "$t" "in-app purchase" "2.3.3 does not bleed into 3.1.1"
assert_absent "$t" "<strong>" "tags stripped"
assert_absent "$t" "id=" "no id= attribute leaks into normalized prose"
assert_absent "$t" "<" "no tag fragment (opening/dangling) leaks into normalized prose"
assert_absent "$t" "@@SEC" "no sentinel leaks into normalized prose"

# id="3.1.1" must not be matched by a request for id="3.1"
t31="$(gd_section_text "$FIX/sample.html" "3.1")"
assert_eq "$t31" "" "no section 3.1 present (3.1.1 is not a prefix match)"

# --- gd_hash: stable + differs on change ---
h1="$(printf 'hello world' | gd_hash)"
h2="$(printf 'hello world' | gd_hash)"
h3="$(printf 'hello worlds' | gd_hash)"
assert_eq "$h1" "$h2" "hash is stable"
[ "$h1" != "$h3" ] && r=0 || r=1
assert_eq "$r" "0" "hash changes when text changes"

# --- gd_number_drift: added + removed vs baseline.all_sections ---
printf '1.2\n2.3.3\n3.1.1\n5.1.1\n4.9\n' > "$FIX/live-added.ids"    # 4.9 is new; nothing removed
drift="$(gd_number_drift "$FIX/live-added.ids" "$FIX/baseline.json")"
assert_contains "$drift" "ADDED 4.9" "new live section flagged as ADDED"
assert_absent "$drift" "REMOVED" "nothing removed when live is a superset"
printf '1.2\n3.1.1\n5.1.1\n' > "$FIX/live-removed.ids"              # 2.3.3 gone
drift2="$(gd_number_drift "$FIX/live-removed.ids" "$FIX/baseline.json")"
assert_contains "$drift2" "REMOVED 2.3.3" "missing baseline section flagged as REMOVED"
rm -f "$FIX/live-added.ids" "$FIX/live-removed.ids"

# --- gd_checks_for_section: derives the affected scan rule-id from scan.sh ---
checks="$(gd_checks_for_section "$ROOT/skills/appstore-precheck/scripts/scan.sh" "2.3.3")"
assert_contains "$checks" "screenshots-per-locale" "2.3.3 maps to its scan check"
assert_eq "$checks" "screenshots-per-locale" "2.3.3 maps to exactly its scan check (no comment-boundary false extra)"

c511="$(gd_checks_for_section "$ROOT/skills/appstore-precheck/scripts/scan.sh" "5.1.1")"
assert_contains "$c511" "privacy-manifest-parity" "5.1.1 maps to its real checks"
assert_absent "$c511" "safari-extension" "5.1.1 does not pick up the §38 header-comment false extra"

# --- gd_main: --html mode, number+text drift, degraded fetch ---

# A tiny baseline whose covered lists point at the fixture sections.
cat > "$FIX/baseline-cov.json" <<'JSON'
{ "all_sections": ["1.2","2.3.3","3.1.1","5.1.1"],
  "covered_by_scan": ["2.3.3","3.1.1","5.1.1"],
  "covered_by_pierre_deep_review": [] }
JSON

out="$(gd_main --html "$FIX/sample.html" \
               --baseline "$FIX/baseline-cov.json" \
               --fingerprints "$FIX/fingerprints.json" \
               --scan "$ROOT/skills/appstore-precheck/scripts/scan.sh"; echo "RC=$?")"
assert_contains "$out" "RC=0" "drift check is non-blocking (exit 0)"
assert_contains "$out" "3.1.1" "the stale-hash section is flagged as text drift"
assert_contains "$out" "external-purchase-link" "the text-drift WARN names 3.1.1's scan check"
assert_absent "$out" "WARN: guideline text drift — 2.3.3" "unchanged section 2.3.3 not flagged"

# degraded fetch: empty html file -> degraded WARN, still exit 0
: > "$FIX/empty.html"
deg="$(gd_main --html "$FIX/empty.html" --baseline "$FIX/baseline-cov.json" \
               --fingerprints "$FIX/fingerprints.json" --scan "$ROOT/skills/appstore-precheck/scripts/scan.sh"; echo "RC=$?")"
assert_contains "$deg" "degraded" "empty fetch produces a degraded WARN"
assert_contains "$deg" "RC=0" "degraded fetch still exits 0"
rm -f "$FIX/baseline-cov.json" "$FIX/empty.html"

echo "test-guideline-drift: OK"
exit "$fails"
