#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/_assert.sh
source "$HERE/_assert.sh"
S="$HERE/../skills/appstore-precheck/scripts"
result="$(APPSTORE_PRECHECK_CONFIG=/nonexistent bash "$S/scan.sh" --dir "$HERE/fixtures/no-iap-app" --format json)"
assert_eq "$(jq -r '.coverage_sections.denominator' <<< "$result")" "102" "run denominator comes from baseline"
assert_eq "$(jq -r '.coverage_sections.human_only' <<< "$result")" "9" "human-only gaps stay explicit"
assert_eq "$(jq -r '.coverage_sections.skip' <<< "$result")" "$(jq -r '.coverage_sections.skipped_sections | unique | length' <<< "$result")" "SKIP counts unique leaf sections"
assert_eq "$(jq -r '.coverage_sections.touched_sections | index("2.4.1")' <<< "$result")" "null" "unexecuted iPad route is not touched"
assert_eq "$(jq -r '.coverage_sections.not_run_routes | join(",")' <<< "$result")" "deep,dynamic,vision" "optional routes are not claimed executed"
assert_eq "$(jq -r '.coverage_sections.touched' <<< "$result")" "$(jq '.coverage_sections.touched_sections | length' <<< "$result")" "issue sections counted"
# Exercise missing input without adding a legacy scanner finding or touching its section.
SCRIPT_DIR="$S"
# shellcheck source=skills/appstore-precheck/scripts/lib/coverage-run.sh
source "$S/lib/coverage-run.sh"
COVERAGE_GAPS_JSON='[{"rule_id":"metadata-extra","guideline":"2.3.12","status":"SKIP","reason":"metadata unavailable"}]'
probe="$(printf '{"findings":[],"summary":{"not_audited":2}}' | coverage_run_json)"
assert_eq "$(jq -r .coverage_sections.skip <<<"$probe")" 1 "added input gap counts as one section"
assert_eq "$(jq -r .summary.not_audited <<<"$probe")" 1 "summary counts actual check gaps"
assert_eq "$(jq -r .coverage_sections.touched <<<"$probe")" 0 "missing metadata never touches a section"
assert_eq "$(jq -r '.coverage_sections.gaps[0].reason' <<<"$probe")" 'metadata unavailable' "gap has a useful reason"
exit "$fails"
