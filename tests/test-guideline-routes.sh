#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
# shellcheck source=tests/_assert.sh
source tests/_assert.sh
# shellcheck source=scripts/guideline-drift.sh
source scripts/guideline-drift.sh
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
printf '{"covered_by_dynamic":["2.4.1"],"covered_by_vision":["2.3.3"]}' > "$TMP/baseline.json"
assert_eq "$(gd_covered_sections "$TMP/baseline.json" | tr '\n' ' ')" '2.3.3 2.4.1 ' 'all observation routes participate in drift checks'
mkdir -p "$TMP/lib"
printf 'source "$SCRIPT_DIR/lib/scan-extra.sh"\n' > "$TMP/scan.sh"
printf 'set_rule "release-notes"\nwarn "2.3.12 incomplete release notes"\n' > "$TMP/lib/scan-extra.sh"
assert_eq "$(gd_checks_for_section "$TMP/scan.sh" 2.3.12)" release-notes 'sourced static module is attributed to its rule'
exit "$fails"
