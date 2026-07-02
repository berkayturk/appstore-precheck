#!/usr/bin/env bash
# tests/test-action-sarif.sh — structural guard: the new Action inputs are opt-in
# (default off) so default Action behavior is unchanged. The network upload step
# is not executed here (documented; validated by integration, not unit tests).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/_assert.sh
source "$HERE/_assert.sh"
A="$HERE/../action.yml"

body="$(cat "$A")"
section "opt-in inputs default off"
assert_contains "$body" "sarif:" "action declares a 'sarif' input"
assert_contains "$body" "annotations:" "action declares an 'annotations' input"
# both defaults must be the string false (opt-in)
assert_eq "$(grep -cE 'default:[[:space:]]*"false"' "$A")" "2" "both new inputs default to \"false\""
section "sarif upload + annotation wiring present"
assert_contains "$body" "github/codeql-action/upload-sarif" "uses upload-sarif for SARIF"
assert_contains "$body" "--format sarif" "produces SARIF via scan.sh --format sarif"
assert_contains "$body" "::warning" "emits warning annotations"
assert_contains "$body" "::error" "emits error annotations"
assert_eq "3" "$(grep -cE 'success\(\) \|\| failure\(\)' "$A")" "all 3 opt-in steps run even when the scan step failed"

echo
if (( fails == 0 )); then echo "[test-action-sarif.sh] OK"; else echo "[test-action-sarif.sh] $fails FAILED"; fi
exit "$fails"
