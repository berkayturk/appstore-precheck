#!/usr/bin/env bash
# tests/test-guideline-cite.sh — guideline-cite.sh: the offline, pinned-quote
# citation lookup that lets Pierre quote Apple instead of quoting his memory.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck source=tests/_assert.sh
source "$HERE/_assert.sh"

CITE="$ROOT/skills/appstore-precheck/scripts/guideline-cite.sh"
FP="$HERE/fixtures/guidelines/fingerprints-cite.json"
run() { bash "$CITE" --fingerprints "$FP" "$@" 2>&1; }

section "a pinned section cites Apple verbatim"
out="$(run 2.3.3)"; st=$?
assert_eq "$st" "0" "exit 0 when a citation exists"
assert_contains "$out" "Screenshots should show the app in use" "quote printed verbatim"
assert_contains "$out" "https://developer.apple.com/app-store/review/guidelines/#2.3.3" "deep link printed"
assert_contains "$out" "2026-08-31" "verification date printed"

section "parenthetical suffixes resolve to their anchor section"
# Findings cite 5.1.1(v) and 3.1.1(a); Apple anchors only the numeric stem.
out="$(run '5.1.1(v)')"
assert_contains "$out" "Apps that collect user or usage data" "roman suffix resolved to 5.1.1"
assert_contains "$out" "#5.1.1" "link uses the anchor stem"

section "a stale citation says so instead of pretending to be current"
out="$(run '5.1.1')"
assert_contains "$out" "STALE" "old verification is marked stale"
assert_contains "$out" "2020-01-01" "the stale date is shown, not hidden"
out_fresh="$(run 2.3.3)"
assert_absent "$out_fresh" "STALE" "a recent citation is not marked stale"

section "no pinned quote -> refuse, do not improvise"
# This is the whole point: without a pinned quote the caller must say the wording
# could not be verified, never reconstruct it from memory.
out="$(run 3.1.1)"; st=$?
assert_eq "$st" "3" "exit 3 when the section has no pinned quote"
assert_contains "$out" "NO PINNED CITATION" "explicit machine-readable refusal"
assert_contains "$out" "#3.1.1" "link still offered so a human can read the source"

section "unknown section -> refuse"
out="$(run 4.7.9)"; st=$?
assert_eq "$st" "3" "exit 3 for a section with no entry at all"
assert_contains "$out" "NO PINNED CITATION" "refusal for an unknown section"

section "malformed input is rejected, never guessed at"
out="$(run 'not-a-number')"; st=$?
assert_eq "$st" "64" "exit 64 on a non-guideline argument"
out="$(run)"; st=$?
assert_eq "$st" "64" "exit 64 with no argument"

section "--json is machine-readable"
j="$(run --json 2.3.3)"
assert_eq "2.3.3"  "$(jq -r .guideline <<<"$j")" "json guideline"
assert_eq "false"  "$(jq -r .stale <<<"$j")"     "json stale flag"
assert_eq "true"   "$(jq -r .cited <<<"$j")"     "json cited flag"
assert_contains "$(jq -r .quote <<<"$j")" "Screenshots should show" "json quote"
j2="$(run --json 3.1.1)"
assert_eq "false" "$(jq -r .cited <<<"$j2")" "json cited=false without a pinned quote"
assert_eq "null"  "$(jq -r .quote <<<"$j2")" "json quote is null, never fabricated"

section "--list enumerates what can be cited"
l="$(run --list)"
assert_contains "$l" "2.3.3" "listed a cited section"
assert_contains "$l" "5.1.1" "listed the stale one too"
assert_absent   "$l" "3.1.1" "uncited section not listed as citable"

section "the shipped fingerprint store is wired up and non-empty"
# Guards the real file, not just the fixture: a release must ship pinned quotes.
real="$ROOT/skills/appstore-precheck/guidelines-fingerprints.json"
cited="$(jq '[.sections[]|select(.quote != null and .quote != "")]|length' "$real")"
total="$(jq '.sections|length' "$real")"
assert_gt "$cited" "40" "the shipped store pins quotes for most covered sections"
echo "  (info: $cited/$total covered sections carry a pinned quote)"
# Every pinned quote must be substantial enough to actually cite.
short="$(jq '[.sections[]|select(.quote != null and (.quote|length) < 40)]|length' "$real")"
assert_eq "$short" "0" "no pinned quote is too short to be a citation"
# And every quote must carry a verification date.
undated="$(jq '[.sections[]|select(.quote != null and .quote_verified_on == null)]|length' "$real")"
assert_eq "$undated" "0" "every pinned quote is dated"

exit "$fails"
