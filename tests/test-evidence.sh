#!/usr/bin/env bash
# tests/test-evidence.sh — evidence.sh per-rule evidence class + confidence level,
# the derived build-verification qualifier, and the completeness invariant that
# every catalogued rule carries both labels.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck source=tests/_assert.sh
source "$HERE/_assert.sh"
# shellcheck source=skills/appstore-precheck/scripts/findings.sh
source "$ROOT/skills/appstore-precheck/scripts/findings.sh"
# shellcheck source=skills/appstore-precheck/scripts/evidence.sh
source "$ROOT/skills/appstore-precheck/scripts/evidence.sh"

section "vocabularies are closed sets"
assert_eq "$EVIDENCE_CLASSES"  "metadata manifest resource build-setting source" "evidence vocabulary"
assert_eq "$CONFIDENCE_LEVELS" "validator-blocking review-risk judgment-call"    "confidence vocabulary"

section "per-rule classification (spot checks)"
# §55 concludes from a source grep; Apple tests on NAT64 and a human rejects the failure.
assert_eq "source"      "$(rule_evidence ipv4-literal)"   "ipv4-literal concludes from source"
assert_eq "review-risk" "$(rule_confidence ipv4-literal)" "ipv4-literal is a reviewer call, not an upload gate"
assert_eq "ipv4-literal" "$(rule_slug 55)" "§55 is catalogued"
# Reads only fastlane metadata, and App Store Connect enforces the limit mechanically.
assert_eq "metadata"          "$(rule_evidence metadata-char-limits)"   "char-limits reads metadata"
assert_eq "validator-blocking" "$(rule_confidence metadata-char-limits)" "char-limits is mechanically enforced"
# Reads Info.plist only — a file that ships essentially as authored.
assert_eq "manifest"   "$(rule_evidence ats-arbitrary-loads)"   "ATS reads Info.plist"
assert_eq "review-risk" "$(rule_confidence ats-arbitrary-loads)" "ATS is a human-reviewer call"
# Screenshot PNGs are shipped resources.
assert_eq "resource"   "$(rule_evidence screenshot-dimensions)" "screenshot dims read a resource"
# LastUpgradeCheck is a pbxproj build setting, not the SDK the archive was built with.
assert_eq "build-setting"      "$(rule_evidence xcode-sdk-requirement)"   "SDK minimum reads a build setting"
assert_eq "validator-blocking" "$(rule_confidence xcode-sdk-requirement)" "SDK minimum is an upload gate"
# Purpose-string cross-check concludes from a source grep: dead code makes it wrong.
assert_eq "source"             "$(rule_evidence usage-description-crosscheck)"   "purpose-string parity concludes from source"
assert_eq "validator-blocking" "$(rule_confidence usage-description-crosscheck)" "missing purpose string blocks upload"
# Explicitly heuristic rules must never claim more than judgment-call.
assert_eq "judgment-call" "$(rule_confidence min-functionality-nav)" "nav heuristic is a judgment call"
assert_eq "judgment-call" "$(rule_confidence webview-wrapper)"       "webview fingerprint is a judgment call"
assert_eq "judgment-call" "$(rule_confidence paywall-urgency)"       "urgency copy is a judgment call"

section "research-backed corrections (2026-09-01)"
# App Store Connect holds a build at "Missing Compliance" until the encryption
# question is answered — one click. Friction, not a rejection: not validator-blocking.
assert_eq "judgment-call" "$(rule_confidence export-compliance)" "export compliance is friction, not a block"
# ATT: ITMS-90683 fires for NSUserTrackingUsageDescription whenever the framework is
# linked, reachable or not — so this one really is mechanical.
assert_eq "validator-blocking" "$(rule_confidence att-usage)" "ATT purpose string is upload-validated (ITMS-90683)"
# SDK floor: ITMS-90725 at upload since 2026-04-28.
assert_eq "validator-blocking" "$(rule_confidence xcode-sdk-requirement)" "SDK minimum is upload-validated (ITMS-90725)"

section "unknown rules stay empty (never guessed)"
assert_eq "" "$(rule_evidence not-a-rule)"   "unknown rule has no evidence class"
assert_eq "" "$(rule_confidence not-a-rule)" "unknown rule has no confidence"
assert_eq "" "$(rule_evidence '')"           "empty rule id has no evidence class"

section "needs_build_verification is DERIVED, never stored"
# The validator runs against the built product. Source and build-setting evidence
# are pre-build indirections (dead code, #if DEBUG, excluded targets, per-config
# settings), so a validator-blocking claim from them is not yet established.
assert_eq "true"  "$(needs_build_verification source validator-blocking)"        "source + validator -> needs build"
assert_eq "true"  "$(needs_build_verification build-setting validator-blocking)" "build-setting + validator -> needs build"
assert_eq "false" "$(needs_build_verification manifest validator-blocking)"      "manifest + validator -> established"
assert_eq "false" "$(needs_build_verification metadata validator-blocking)"      "metadata + validator -> established"
assert_eq "false" "$(needs_build_verification resource validator-blocking)"      "resource + validator -> established"
# The qualifier only ever applies to a validator-blocking claim.
assert_eq "false" "$(needs_build_verification source review-risk)"   "source + review-risk -> no qualifier"
assert_eq "false" "$(needs_build_verification source judgment-call)" "source + judgment -> no qualifier"

section "human-readable label"
assert_eq "evidence: source · validator-blocking · needs build verification" \
  "$(evidence_label source validator-blocking)" "label carries the qualifier"
assert_eq "evidence: metadata · review-risk" \
  "$(evidence_label metadata review-risk)" "label omits the qualifier when established"
assert_eq "" "$(evidence_label '' '')" "no label without a classification"

section "completeness invariant: every catalogued rule is classified"
missing_ev=0 missing_cf=0 bad_vocab=0 walked=0
# The bound is walked, not hardcoded: a hardcoded 53 silently stopped covering §54.
while IFS= read -r slug; do
  [[ -z "$slug" ]] && continue
  walked=$((walked + 1))
  ev="$(rule_evidence "$slug")"; cf="$(rule_confidence "$slug")"
  [[ -z "$ev" ]] && { echo "  FAIL: $slug has no evidence class"; missing_ev=$((missing_ev + 1)); }
  [[ -z "$cf" ]] && { echo "  FAIL: $slug has no confidence level"; missing_cf=$((missing_cf + 1)); }
  [[ -n "$ev" ]] && ! grep -qw -- "$ev" <<<"$EVIDENCE_CLASSES"  && { echo "  FAIL: $slug evidence '$ev' not in vocabulary"; bad_vocab=$((bad_vocab + 1)); }
  [[ -n "$cf" ]] && ! grep -qw -- "$cf" <<<"$CONFIDENCE_LEVELS" && { echo "  FAIL: $slug confidence '$cf' not in vocabulary"; bad_vocab=$((bad_vocab + 1)); }
done < <(catalogue_slugs)
assert_gt "$walked" "54" "the catalogue walk reached §55 (bound is derived, not hardcoded)"
assert_eq "$missing_ev" "0" "every rule has an evidence class"
assert_eq "$missing_cf" "0" "every rule has a confidence level"
assert_eq "$bad_vocab"  "0" "every label is in the closed vocabulary"

section "every rule the scanner actually sets is classified"
# Guards against a rule being added to scan.sh without a classification.
unclassified=0
# Ids ending in "-not-audited" are gap records (a SKIP that can be acknowledged by
# id), not checks: they establish nothing, so they carry no labels and sit outside
# the catalogue. The suffix is the convention; is_gap_record owns it.
while IFS= read -r slug; do
  [[ -z "$slug" ]] && continue
  is_gap_record "$slug" && continue
  [[ -z "$(rule_evidence "$slug")" || -z "$(rule_confidence "$slug")" ]] && {
    echo "  FAIL: scan.sh sets '$slug' but it is unclassified"; unclassified=$((unclassified + 1)); }
done < <(grep -oE 'set_rule "[^"]+"' "$ROOT/skills/appstore-precheck/scripts/scan.sh" \
         | sed -E 's/set_rule "//; s/"$//' | sort -u)
assert_eq "true"  "$(is_gap_record store-listing-not-audited && echo true || echo false)" "gap-record convention recognised"
assert_eq "false" "$(is_gap_record ats-arbitrary-loads && echo true || echo false)"      "an ordinary rule is not a gap record"
assert_eq "$unclassified" "0" "no scan.sh rule is missing a classification"

section "findings.sh records the labels"
FINDINGS_TMP="$(mktemp)"; : > "$FINDINGS_TMP"
set_rule "usage-description-crosscheck"
_record FAIL "5.1.1 camera capture API used but Info.plist is missing NSCameraUsageDescription" "App/Cam.swift" "12"
rec="$(sed -n '1p' "$FINDINGS_TMP")"
assert_eq "source"             "$(jq -r .evidence <<<"$rec")"   "evidence on the record"
assert_eq "validator-blocking" "$(jq -r .confidence <<<"$rec")" "confidence on the record"
assert_eq "true"               "$(jq -r .needs_build_verification <<<"$rec")" "derived qualifier on the record"
assert_eq "https://developer.apple.com/app-store/review/guidelines/#5.1.1" \
  "$(jq -r .guideline_url <<<"$rec")" "guideline deep link on the record"

section "set_evidence refines a single finding, then resets"
# §2's empty-purpose-string branch reads Info.plist directly, so it must not
# inherit the rule-level 'source' floor.
set_evidence "manifest"
_record FAIL "5.1.1 Purpose String — empty usage description" "App/Info.plist" "3"
rec2="$(sed -n '2p' "$FINDINGS_TMP")"
assert_eq "manifest" "$(jq -r .evidence <<<"$rec2")" "override applied"
assert_eq "false"    "$(jq -r .needs_build_verification <<<"$rec2")" "override changes the derivation"
set_rule "usage-description-crosscheck"
_record FAIL "5.1.1 camera capture API used" "App/Cam.swift" "12"
rec3="$(sed -n '3p' "$FINDINGS_TMP")"
assert_eq "source" "$(jq -r .evidence <<<"$rec3")" "set_rule clears the override"

section "a PASS never claims to need build verification"
# The qualifier is about an unestablished violation; a PASS asserts no violation.
set_rule "att-usage"
_record PASS "5.1.2 ATT — not used (no tracking)"
recp="$(tail -1 "$FINDINGS_TMP")"
assert_eq "source"             "$(jq -r .evidence <<<"$recp")"   "PASS keeps its evidence class"
assert_eq "validator-blocking" "$(jq -r .confidence <<<"$recp")" "PASS keeps its confidence"
assert_eq "false" "$(jq -r .needs_build_verification <<<"$recp")" "PASS drops the qualifier"
# The same rule as a WARN still carries it.
_record WARN "5.1.2 ATT framework imported but NSUserTrackingUsageDescription missing"
recw="$(tail -1 "$FINDINGS_TMP")"
assert_eq "true" "$(jq -r .needs_build_verification <<<"$recw")" "the same rule as a WARN keeps it"

section "unknown rule records null labels, never a guess"
set_rule ""
_record WARN "9.9 something outside the catalog"
rec4="$(tail -1 "$FINDINGS_TMP")"
assert_eq "null" "$(jq -r .evidence <<<"$rec4")"   "no evidence class invented"
assert_eq "null" "$(jq -r .confidence <<<"$rec4")" "no confidence invented"
assert_eq "false" "$(jq -r .needs_build_verification <<<"$rec4")" "unclassified never claims build verification"
rm -f "$FINDINGS_TMP"

section "render_json rolls confidence up into the summary"
FINDINGS_TMP="$(mktemp)"; : > "$FINDINGS_TMP"
set_rule "metadata-char-limits"; _record FAIL "2.3.1 name too long"
set_rule "webview-wrapper";      _record WARN "4.2.3 wrapper"
set_rule "paywall-urgency";      _record WARN "3.1.2 urgency"
PRECHECK_VERSION="9.9.9"
out="$(render_json)"
assert_eq "1" "$(jq -r '.summary.by_confidence["validator-blocking"]' <<<"$out")" "validator-blocking rolled up"
assert_eq "2" "$(jq -r '.summary.by_confidence["judgment-call"]' <<<"$out")"      "judgment-call rolled up"
assert_eq "0" "$(jq -r '.summary.by_confidence["review-risk"]' <<<"$out")"        "absent level reported as zero"
assert_eq "0" "$(jq -r '.summary.needs_build_verification' <<<"$out")"            "none need build verification here"
rm -f "$FINDINGS_TMP"

section "SARIF carries the labels as result properties"
# shellcheck source=skills/appstore-precheck/scripts/sarif.sh
source "$ROOT/skills/appstore-precheck/scripts/sarif.sh"
FINDINGS_TMP="$(mktemp)"; : > "$FINDINGS_TMP"
set_rule "usage-description-crosscheck"
_record FAIL "5.1.1 camera capture API used" "App/Cam.swift" "12"
set_rule "ats-arbitrary-loads"
_record WARN "1.6 ATS disabled" "App/Info.plist" "3"
set_rule ""
_record WARN "9.9 uncatalogued"
sar="$(render_sarif)"
r0="$(jq -c '.runs[0].results[0].properties' <<<"$sar")"
assert_eq "source"             "$(jq -r .evidence <<<"$r0")"   "SARIF evidence property"
assert_eq "validator-blocking" "$(jq -r .confidence <<<"$r0")" "SARIF confidence property"
assert_eq "true"               "$(jq -r .needsBuildVerification <<<"$r0")" "SARIF build-verification flag"
assert_eq "https://developer.apple.com/app-store/review/guidelines/#5.1.1" \
  "$(jq -r .guidelineUrl <<<"$r0")" "SARIF guideline deep link"
assert_eq "false" "$(jq -r '.runs[0].results[1].properties.needsBuildVerification' <<<"$sar")" \
  "manifest-evidence result needs no build verification"
assert_eq "null" "$(jq -r '.runs[0].results[2].properties' <<<"$sar")" \
  "unclassified result carries no properties bag"
rm -f "$FINDINGS_TMP"

section "guideline_url derivation"
assert_eq "https://developer.apple.com/app-store/review/guidelines/#5.1.1" "$(guideline_url 5.1.1)" "plain number"
assert_eq "https://developer.apple.com/app-store/review/guidelines/#5.1.1" "$(guideline_url '5.1.1(v)')" "roman suffix trimmed to its anchor"
assert_eq "https://developer.apple.com/app-store/review/guidelines/#3.1.1" "$(guideline_url '3.1.1(a)')" "letter suffix trimmed to its anchor"
assert_eq "" "$(guideline_url 'export-compliance')" "non-guideline token yields no link"
assert_eq "" "$(guideline_url '5')" "bare category is not a section anchor"
assert_eq "https://developer.apple.com/app-store/review/guidelines/#4" "$(guideline_url 4.0)" "N.0 (category intro) links to the bare category anchor"
assert_eq "" "$(guideline_url '')" "empty yields no link"

exit "$fails"
