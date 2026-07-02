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

echo "test-guideline-drift: OK"
exit "$fails"
