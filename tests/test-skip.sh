#!/usr/bin/env bash
# tests/test-skip.sh — the SKIP (not-audited) line class.
# A check that could not run is not a pass. SKIP records that distinction without
# touching the verdict arithmetic, so a clean-looking GREEN can still be shown to
# rest on checks that never executed.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck source=tests/_assert.sh
source "$HERE/_assert.sh"
SCAN="$ROOT/skills/appstore-precheck/scripts/scan.sh"
VERDICT="$ROOT/skills/appstore-precheck/scripts/verdict.sh"

section "verdict.sh counts SKIP separately and never lets it change the verdict"
out="$(printf 'PASS: a\nSKIP: b\nSKIP: c\n' | bash "$VERDICT")"; st=$?
assert_eq "$st" "0" "SKIP alone stays GREEN"
assert_contains "$out" "VERDICT: GREEN" "verdict unaffected by SKIP"
assert_contains "$out" "skip=2" "SKIP counted in COUNTS"
assert_contains "$out" "TOKEN: write" "token still written"
# Five SKIPs must NOT tip GREEN into YELLOW the way five WARNs do.
out="$(printf 'SKIP: a\nSKIP: b\nSKIP: c\nSKIP: d\nSKIP: e\n' | bash "$VERDICT")"; st=$?
assert_eq "$st" "0" "five SKIPs are still GREEN"
assert_contains "$out" "skip=5" "all five counted"
# Indented SKIP text under a finding must not be counted as a top-level one.
out="$(printf 'FAIL: x\n      SKIP: not a real line\n' | bash "$VERDICT")"
assert_contains "$out" "skip=0" "indented SKIP text is not counted"

section "scan.sh emits SKIP when the store listing was never seen"
d="$(mktemp -d)"; cp -R "$HERE/fixtures/ai-chat-app/." "$d/"
out="$(cd "$d" && APPSTORE_PRECHECK_CONFIG=/nonexistent bash "$SCAN" 2>&1)"
assert_contains "$out" "SKIP: metadata" "a repo with no fastlane metadata reports the gap"
assert_contains "$out" "did not run" "the SKIP says the checks did not run"
assert_contains "$out" "App Store Connect" "the SKIP tells the user how to close the gap"
# It must name a real count, derived from the catalogue rather than hardcoded.
n="$(grep -oE 'SKIP: metadata[^0-9]*([0-9]+) store-listing check' <<<"$out" | grep -oE '[0-9]+' | head -1)"
assert_gt "${n:-0}" "5" "the SKIP names how many checks were skipped"
rm -rf "$d"

section "a repo WITH metadata does not report the gap"
d="$(mktemp -d)"; cp -R "$HERE/fixtures/risky-app/." "$d/"
out="$(cd "$d" && APPSTORE_PRECHECK_CONFIG=/nonexistent bash "$SCAN" 2>&1)"
assert_absent "$out" "SKIP: metadata" "metadata present -> no metadata SKIP"
rm -rf "$d"

section "a pasted listing can be audited by re-running the scanner (absolute metadataDir)"
# This is what SKILL.md tells the agent to do instead of judging pasted text by eye:
# write it to a temp fastlane tree OUTSIDE the repo and point the scanner at it. The
# repo stays untouched, the SKIP disappears because the checks ran, and the findings
# are ordinary scanner lines that count.
app="$(mktemp -d)"; cp -R "$HERE/fixtures/ai-chat-app/." "$app/"
paste="$(mktemp -d)"; mkdir -p "$paste/fastlane/metadata/en-US"
printf 'Flashlight FREE'    > "$paste/fastlane/metadata/en-US/name.txt"
printf 'lorem ipsum dolor'  > "$paste/fastlane/metadata/en-US/subtitle.txt"
printf 'A light.'           > "$paste/fastlane/metadata/en-US/description.txt"
printf 'light'              > "$paste/fastlane/metadata/en-US/keywords.txt"
printf '{"metadataDir":"%s"}' "$paste/fastlane/metadata" > "$paste/precheck.json"
before="$(find "$app" -type f | sort | md5)"
out="$(cd "$app" && APPSTORE_PRECHECK_CONFIG="$paste/precheck.json" bash "$SCAN" 2>&1)"
after="$(find "$app" -type f | sort | md5)"
assert_absent   "$out" "SKIP: metadata" "the listing checks ran, so no metadata SKIP"
assert_contains "$out" "WARN: 2.1 Metadata content" "placeholder copy in the pasted listing is found"
assert_contains "$out" "WARN: 2.3.1 Pricing language" "pricing language in the pasted name is found"
assert_contains "$out" "WARN: 4.3 Saturated category" "the pasted category exposure is found"
assert_eq "$before" "$after" "the repo itself was not touched"
rm -rf "$app" "$paste"

section "the SKIP names the skipped rules, derived from the catalogue"
d="$(mktemp -d)"; cp -R "$HERE/fixtures/ai-chat-app/." "$d/"
out="$(cd "$d" && APPSTORE_PRECHECK_CONFIG=/nonexistent bash "$SCAN" 2>&1)"
assert_contains "$out" "saturated-category" "the newest metadata rule is in the skipped list (nothing hardcoded)"
assert_absent   "$out" "(2.1, 2.3.x" "the stale hardcoded guideline enumeration is gone"
rm -rf "$d"

section "a rule-scoped SKIP can be acknowledged via .precheck-ignore"
d="$(mktemp -d)"; cp -R "$HERE/fixtures/ai-chat-app/." "$d/"
printf 'screenshots-per-locale\n' > "$d/.precheck-ignore"
out="$(cd "$d" && APPSTORE_PRECHECK_CONFIG=/nonexistent bash "$SCAN" 2>&1)"
assert_absent   "$out" "SKIP: 2.3.3 Screenshots" "acknowledged screenshot gap is not re-reported"
assert_contains "$out" "SKIP: metadata" "the store-listing SKIP has no rule and cannot be silenced"
rm -rf "$d"

section "SKIP is a first-class finding in --format json"
d="$(mktemp -d)"; cp -R "$HERE/fixtures/ai-chat-app/." "$d/"
j="$(cd "$d" && APPSTORE_PRECHECK_CONFIG=/nonexistent bash "$SCAN" --format json 2>/dev/null)"
assert_gt "$(jq '[.findings[]|select(.severity=="SKIP")]|length' <<<"$j")" "0" "SKIP findings present in JSON"
assert_gt "$(jq -r '.summary.not_audited' <<<"$j")" "0" "summary.not_audited counts them"
# The FAIL tally must equal the FAIL findings alone — SKIP must not leak into it.
assert_eq "$(jq -r '.summary.fail' <<<"$j")" "$(jq '[.findings[]|select(.severity=="FAIL")]|length' <<<"$j")" \
  "SKIP does not inflate the FAIL count"
# A SKIP establishes nothing: no evidence class, no confidence, no build qualifier —
# even when it sits under a rule that has all three.
assert_eq "0" "$(jq '[.findings[]|select(.severity=="SKIP" and (.evidence != null or .confidence != null))]|length' <<<"$j")" \
  "no SKIP carries an evidence class or confidence"
assert_eq "0" "$(jq '[.findings[]|select(.severity=="SKIP" and .needs_build_verification==true)]|length' <<<"$j")" \
  "no SKIP claims to need build verification"
# And it must not be counted as an issue in the confidence roll-up.
assert_eq "0" "$(jq -r '.summary.by_confidence.unclassified' <<<"$j")" "SKIP is not rolled up as an issue"

section "SKIP never reaches SARIF"
s="$(cd "$d" && APPSTORE_PRECHECK_CONFIG=/nonexistent bash "$SCAN" --format sarif 2>/dev/null)"
assert_eq "0" "$(jq '[.runs[0].results[]|select(.message.text|test("^SKIP"))]|length' <<<"$s")" \
  "SARIF carries no SKIP results"
rm -rf "$d"

section "rules_with_evidence backs the derived count"
# shellcheck source=skills/appstore-precheck/scripts/evidence.sh
source "$ROOT/skills/appstore-precheck/scripts/findings.sh"
source "$ROOT/skills/appstore-precheck/scripts/evidence.sh"
assert_gt "$(rules_with_evidence metadata | wc -l | tr -d ' ')" "5" "several rules read fastlane metadata"
assert_eq "" "$(rules_with_evidence not-a-class)" "unknown class yields nothing"
# Every listed rule must really be classified that way.
bad=0
while IFS= read -r r; do
  [[ -z "$r" ]] && continue
  [[ "$(rule_evidence "$r")" == "metadata" ]] || { echo "  FAIL: $r listed but not metadata-classed"; bad=$((bad+1)); }
done < <(rules_with_evidence metadata)
assert_eq "$bad" "0" "the listing matches the catalogue"

exit "$fails"
