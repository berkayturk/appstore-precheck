#!/usr/bin/env bash
# tests/test-design-40.sh — Guideline 4.0 (Design) coverage.
# 4.0 is Apple's #1 removal reason (2024 transparency report: 42,252) and was
# absent from guidelines-baseline.json, so drift could never see it. The live page
# anchors the Design intro only as id="4"; the parser maps it to "4.0" (see
# tests/test-guideline-drift.sh). This file pins the baseline, the citation and the
# deep-review check that give 4.0 coverage.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck source=tests/_assert.sh
source "$HERE/_assert.sh"
SK="$ROOT/skills/appstore-precheck"
BASE="$SK/guidelines-baseline.json"

section "baseline tracks the category intro sections"
for n in 1.0 2.0 3.0 4.0 5.0; do
  assert_contains "$(jq -r '.all_sections[]' "$BASE")" "$n" "$n in all_sections (parser emits every bare category anchor as N.0)"
done
assert_contains "$(jq -r '.covered_by_pierre_deep_review[]' "$BASE")" "4.0" "4.0 is covered by deep review"
assert_absent   "$(jq -r '.covered_by_scan[]' "$BASE")" "4.0" "4.0 is NOT claimed by the static scan (design quality is a human call)"

section "4.0 is citable, verbatim, and links to the bare anchor"
cite="$(bash "$SK/scripts/guideline-cite.sh" 4.0)"; st=$?
assert_eq "$st" "0" "4.0 has a pinned quote"
assert_contains "$cite" "simple, refined, innovative, and easy to use" "the pinned quote is Apple's 4.0 intro"
assert_contains "$cite" "guidelines/#4" "deep link to the category anchor"
assert_absent   "$cite" "#4.0" "no dangling #4.0 anchor (the page has none)"
assert_contains "$(jq -r '.sections | keys[]' "$SK/guidelines-fingerprints.json")" "4.0" "4.0 has a fingerprint so text drift is watched"

section "deep-review check 31 asks the 4.0 question"
ref="$SK/references/pierre-deep-review.md"
assert_contains "$(cat "$ref")" "| 31 | **4.0** |" "check 31 row present in the table"
assert_contains "$(cat "$ref")" "### 31 — 4.0" "check 31 procedure present"
assert_contains "$(grep -A4 '### 31 — 4.0' "$ref")" "Tier B" "check 31 is Tier B (heuristic)"
deep_count="$(jq -r '[.checks[]] | length' "$SK/references/review-catalog.json")"
assert_contains "$(cat "$ref")" "$deep_count checks" "reference count matches the catalog"
assert_contains "$(cat "$SK/SKILL.md")" "check 31 (4.0 design quality)" "SKILL.md links the canonical check 31 table"
assert_contains "$(cat "$ROOT/README.md")" "$deep_count deep semantic checks" "README count matches the catalog"

exit "$fails"
