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
assert_eq "$checks" "$(printf 'screenshots-per-locale\nscreenshot-dimensions')" "2.3.3 maps to exactly its two real checks (§7 + §7b; no comment-boundary false extra)"

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

# --- gd_main: bad args must never break the caller (non-blocking contract) ---
gd_main --bogus >/dev/null 2>&1; assert_eq "$?" "0" "unknown flag exits 0 (non-blocking)"
gd_main --html >/dev/null 2>&1;  assert_eq "$?" "0" "flag with missing value exits 0 (non-blocking)"


# --- gd_main --reconcile: missing covered section must not become an empty placeholder ---
cat > "$FIX/baseline-missing.json" <<'JSON'
{ "all_sections": ["1.2","2.3.3","3.1.1","5.1.1","4.9"],
  "covered_by_scan": ["2.3.3","4.9"],
  "covered_by_pierre_deep_review": [] }
JSON
recfp="$FIX/reconcile-out.json"
rout="$(gd_main --reconcile --html "$FIX/sample.html" \
               --baseline "$FIX/baseline-missing.json" \
               --fingerprints "$recfp"; echo "RC=$?")"
assert_contains "$rout" "WARN: reconcile — 4.9 not found on live page" "reconcile warns and skips a section missing from the live page"
assert_contains "$rout" "WARN: guideline-drift section-number change: REMOVED 4.9" "reconcile also surfaces number drift for the missing section"
assert_contains "$rout" "RC=0" "reconcile still exits 0 despite a missing section"
missing_entry="$(jq -r '.sections["4.9"] // "ABSENT"' "$recfp")"
assert_eq "$missing_entry" "ABSENT" "no placeholder entry written for the missing section"
present_entry="$(jq -r '.sections["2.3.3"].fingerprint // ""' "$recfp")"
[ -n "$present_entry" ] && r=0 || r=1
assert_eq "$r" "0" "present covered section still gets a real fingerprint"
rm -f "$FIX/baseline-missing.json" "$recfp"

# --- consistency: every covered section has a fingerprint; no orphan fingerprints ---
BASE="$ROOT/skills/appstore-precheck/guidelines-baseline.json"
FP="$ROOT/skills/appstore-precheck/guidelines-fingerprints.json"
covered_sorted="$(jq -r '((.covered_by_scan // []) + (.covered_by_pierre_deep_review // []) + (.covered_by_dynamic // []) + (.covered_by_vision // [])) | unique[]' "$BASE" | sort)"
fp_sorted="$(jq -r '.sections | keys[]' "$FP" | sort)"
missing="$(comm -23 <(printf '%s\n' "$covered_sorted") <(printf '%s\n' "$fp_sorted"))"
orphan="$(comm -13 <(printf '%s\n' "$covered_sorted") <(printf '%s\n' "$fp_sorted"))"
assert_eq "$missing" "" "every covered section has a fingerprint entry"
assert_eq "$orphan" "" "no fingerprint for a non-covered section"
# every fingerprint is a 64-hex sha256
bad="$(jq -r '.sections | to_entries[] | select(.value.fingerprint | test("^[0-9a-f]{64}$") | not) | .key' "$FP")"
assert_eq "$bad" "" "all fingerprints are 64-hex sha256"

# --- --reconcile must not silently destroy pinned citations ---------------------
# Rebuilding each entry from scratch used to drop every `quote`, and a later
# --quotes run would then re-date them all as if freshly verified. An unchanged
# section keeps its quote and its original verification date; a CHANGED section
# loses it on purpose, because the old wording is now wrong.
section "reconcile preserves quotes for unchanged sections, drops them for changed ones"
rec_tmp="$(mktemp -d)"
rec_fp="$rec_tmp/fp.json"
# 2.3.3 will be unchanged; 1.2 gets a deliberately wrong fingerprint (= "drifted").
unchanged_hash="$(printf '%s' "$(gd_section_text "$FIX/sample.html" "2.3.3")" | gd_hash)"
jq -n --arg h "$unchanged_hash" '{
  sections: {
    "2.3.3": {fingerprint:$h, snapshot:"s", quote:"Screenshots should show the app in use.", quote_verified_on:"2026-01-01"},
    "1.2":   {fingerprint:"stale-hash", snapshot:"s", quote:"An outdated quote.", quote_verified_on:"2026-01-01"}
  }, reconciled_on:"2026-01-01"}' > "$rec_fp"
jq -n '{all_sections:["1.2","2.3.3"], covered_by_scan:["1.2","2.3.3"], covered_by_pierre_deep_review:[]}' > "$rec_tmp/base.json"
rec_out="$(gd_main --html "$FIX/sample.html" --baseline "$rec_tmp/base.json" \
             --fingerprints "$rec_fp" --scan "$ROOT/skills/appstore-precheck/scripts/scan.sh" --reconcile 2>&1)"
assert_eq "Screenshots should show the app in use." "$(jq -r '.sections["2.3.3"].quote' "$rec_fp")" \
  "unchanged section keeps its pinned quote"
assert_eq "2026-01-01" "$(jq -r '.sections["2.3.3"].quote_verified_on' "$rec_fp")" \
  "and keeps its original verification date (not re-dated as freshly verified)"
assert_eq "null" "$(jq -r '.sections["1.2"].quote' "$rec_fp")" \
  "changed section loses its now-wrong quote"
assert_contains "$rec_out" "pinned quote was dropped" "and the drop is announced, not silent"
rm -rf "$rec_tmp"

# --- bare category anchors surface as "N.0" (Apple's "Guideline 4.0 - Design") ---
# Apple's rejection notices cite the category intro prose as N.0 (4.0 is the #1
# removal guideline in Apple's 2024 transparency report), but the live page anchors
# that prose only as <span id="4"> — there is no id="4.0". The parser therefore maps
# a bare category id to "N.0" so the intro prose is trackable, and the text helpers
# accept "N.0" and resolve it back to the bare anchor.
cat_tmp="$(mktemp -d)"
cat > "$cat_tmp/cat.html" <<'HTML'
<span id="globalnav-4"></span>
<h2><span id="4">4. Design</span></h2>
<p>Apple customers place a high value on products that are simple.</p>
<h3><span id="4.1">4.1 Copycats</span></h3><p>Come up with your own ideas.</p>
<h2><span id="5">5. Legal</span></h2><p>Apps must comply with all legal requirements.</p>
HTML
cids="$(gd_section_ids "$cat_tmp/cat.html" | tr '\n' ' ')"
assert_eq "$cids" "4.0 4.1 5.0 " "bare category anchors surface as N.0, in order; globalnav id ignored"
c40="$(gd_section_text "$cat_tmp/cat.html" "4.0")"
assert_contains "$c40" "apple customers place a high value" "4.0 resolves to the category intro prose"
assert_absent   "$c40" "copycats" "4.0 stops at the first sub-section (4.1)"
assert_eq "$(gd_section_text "$cat_tmp/cat.html" "4")" "$c40" "bare 4 and 4.0 extract the same prose"
assert_contains "$(gd_section_quote "$cat_tmp/cat.html" "4.0")" "Apple customers place a high value" "4.0 is quotable in original case"
rm -rf "$cat_tmp"

echo "test-guideline-drift: OK"
exit "$fails"
