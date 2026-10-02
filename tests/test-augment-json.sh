#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
# shellcheck source=tests/_assert.sh
source tests/_assert.sh
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
printf '{"checks":{"one":{"status":"SKIP"},"two":{"status":"NEEDS_REVIEW"}}}' > "$TMP/run-results.json"
jq -n --arg out "$TMP" '{tiers:{metadata:"RAN"},output_dir:$out,run_results:($out+"/run-results.json"),input_errors:[],obligations:["must not embed"]}' > "$TMP/summary.json"
json="$(printf '{"version":"test","findings":[],"summary":{"verdict":"GREEN"}}' | python3 -B skills/appstore-precheck/scripts/augment-json.py --opt-summary "$TMP/summary.json")"
assert_eq "$(jq -r .version <<<"$json")" test 'existing envelope survives'
assert_eq "$(jq -r .coverage_run.check_status_counts.SKIP <<<"$json")" 1 'run summary counts actual skipped checks'
assert_eq "$(jq -r .coverage_run.check_status_counts.NEEDS_REVIEW <<<"$json")" 1 'present declarations counted as unverified'
assert_absent "$json" obligations 'obligations not embedded'
assert_eq "$(jq -r .optional_review.output_dir <<<"$json")" "$TMP" 'retained temporary output is discoverable'
exit "$fails"
