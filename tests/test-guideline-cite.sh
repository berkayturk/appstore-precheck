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

section "category intro sections (N.0) link to the bare category anchor"
# Apple cites the Design intro as "Guideline 4.0", but the page anchors it as id="4".
out="$(run 4.0)"; st=$?
assert_eq "$st" "0" "4.0 is citable"
assert_contains "$out" "Apple customers place a high value" "4.0 quote printed"
assert_contains "$out" "https://developer.apple.com/app-store/review/guidelines/#4" "link uses the bare category anchor"
assert_absent   "$out" "#4.0" "no dangling #4.0 anchor (the page has none)"
assert_eq "$(run --json 4.0 | jq -r .url)" "https://developer.apple.com/app-store/review/guidelines/#4" "json url uses the bare anchor"

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

section "--verify-live turns age-based staleness into change-based staleness"
# Age is only a proxy: an untouched section stays correct for years, and a section
# Apple edited yesterday is wrong while still looking fresh. --verify-live re-hashes
# the live text and compares it to the pinned fingerprint. Driven off a LOCAL cached
# page here, so the test never touches the network.
FIXHTML="$HERE/fixtures/guidelines/sample.html"
# shellcheck source=skills/appstore-precheck/scripts/lib/guideline-text.sh
source "$ROOT/skills/appstore-precheck/scripts/lib/guideline-text.sh"
live_hash="$(printf '%s' "$(gd_section_text "$FIXHTML" "2.3.3")" | gd_hash)"

vfp="$(mktemp)"
runlive() { GUIDELINE_CITE_CACHE="$FIXHTML" bash "$CITE" --fingerprints "$vfp" --verify-live "$@" 2>&1; }

# (a) Pinned fingerprint MATCHES the live text: an ancient pin is confirmed current.
jq -n --arg h "$live_hash" '{sections:{"2.3.3":{fingerprint:$h, snapshot:"s",
  quote:"Screenshots should show the app in use, and not merely the title art.",
  quote_verified_on:"2019-01-01"}}}' > "$vfp"
out="$(runlive 2.3.3)"; st=$?
assert_eq "$st" "0" "unchanged section verifies clean"
assert_absent   "$out" "STALE" "a confirmed-unchanged section is not stale, however old the pin"
assert_contains "$out" "verified against the live page" "says the check actually ran"
assert_eq "false" "$(runlive --json 2.3.3 | jq -r .stale)"   "json: not stale"
assert_eq "false" "$(runlive --json 2.3.3 | jq -r .changed)" "json: not changed"

# (b) Pinned fingerprint does NOT match: the quote is out of date even if pinned today.
jq -n '{sections:{"2.3.3":{fingerprint:"a-fingerprint-that-does-not-match", snapshot:"s",
  quote:"Some wording Apple no longer uses.",
  quote_verified_on:"2026-09-01"}}}' > "$vfp"
out="$(runlive 2.3.3)"; st=$?
assert_eq "$st" "4" "a changed section exits 4"
assert_contains "$out" "CHANGED" "the change is stated, not implied by age"
assert_contains "$out" "OUT OF DATE" "and the caller is told not to quote it as current"
assert_eq "true" "$(runlive --json 2.3.3 | jq -r .changed)" "json: changed"
assert_eq "true" "$(runlive --json 2.3.3 | jq -r .stale)"   "json: changed implies stale"

# (c) Without --verify-live the same store is judged on age alone -> still fresh.
out="$(bash "$CITE" --fingerprints "$vfp" 2.3.3)"; st=$?
assert_eq "$st" "0" "offline mode is unchanged by the new flag"
assert_absent "$out" "CHANGED" "offline mode makes no claim about the live page"
rm -f "$vfp"

section "--verify-live degrades safely when the page cannot be fetched"
vfp2="$(mktemp)"
jq -n '{sections:{"2.3.3":{fingerprint:"x", snapshot:"s", quote:"A pinned quote about screenshots.",
  quote_verified_on:"2026-09-01"}}}' > "$vfp2"
# A fetch that fails must not crash, must not claim verification, and must not touch
# the network in this test: the URL is overridden to a file that does not exist, so
# curl fails instantly and offline. The cache is a fresh temp path, never /dev/null —
# an earlier version of this test pointed there, which would have had the script
# `rm -f /dev/null` if run as root.
vcache="$(mktemp -d)/cache.html"
out="$(GUIDELINE_CITE_URL="file:///nonexistent/guidelines.html" GUIDELINE_CITE_CACHE="$vcache" \
       bash "$CITE" --fingerprints "$vfp2" --verify-live 2.3.3 2>&1)"; st=$?
assert_eq "$st" "0" "a failed live check still returns the pinned quote"
assert_absent "$out" "verified against the live page" "and never claims a verification it did not do"
assert_contains "$out" "A pinned quote about screenshots" "the pinned quote is still delivered"
[[ -e "$vcache" ]] && r=1 || r=0
assert_eq "$r" "0" "no empty cache file is left behind"
# A non-regular file at the cache path is refused, never read from or deleted.
out="$(GUIDELINE_CITE_URL="file:///nonexistent" GUIDELINE_CITE_CACHE="$(dirname "$vcache")" \
       bash "$CITE" --fingerprints "$vfp2" --verify-live 2.3.3 2>&1)"; st=$?
assert_eq "$st" "0" "a directory at the cache path degrades safely"
assert_contains "$out" "not a regular file" "and says why"
[[ -d "$(dirname "$vcache")" ]] && r=1 || r=0
assert_eq "$r" "1" "the directory was not deleted"
rm -rf "$(dirname "$vcache")" "$vfp2"

section "the shipped fingerprint store is wired up and non-empty"
# Guards the real file, not just the fixture: a release must ship pinned quotes.
real="$ROOT/skills/appstore-precheck/guidelines-fingerprints.json"
cited="$(jq '[.sections[]|select(.quote != null and .quote != "")]|length' "$real")"
total="$(jq '.sections|length' "$real")"
# Expanding the fingerprint inventory must not require copying Apple paragraphs.
# Pin every previously shipped quotation by hash; new sections may be hash-only.
assert_gt "$total" "0" "the shipped fingerprint store is non-empty"
python3 - "$real" "$HERE/golden/quote-hashes-v1.19.0.json" <<'PYTEST'
import hashlib, json, sys
sections = json.load(open(sys.argv[1]))['sections']
expected = json.load(open(sys.argv[2]))
assert expected
for section, digest in expected.items():
    quote = sections.get(section, {}).get('quote', '')
    assert hashlib.sha256(quote.encode()).hexdigest() == digest, section
print('PASS: all %d legacy quotation hashes preserved' % len(expected))
PYTEST
assert_eq "$?" "0" "all legacy quotes are preserved without demanding new quotations"
echo "  (info: $cited/$total covered sections carry a pinned quote)"
# Every pinned quote must be substantial enough to actually cite.
short="$(jq '[.sections[]|select(.quote != null and (.quote|length) < 40)]|length' "$real")"
assert_eq "$short" "0" "no pinned quote is too short to be a citation"
# And every quote must carry a verification date.
undated="$(jq '[.sections[]|select(.quote != null and .quote_verified_on == null)]|length' "$real")"
assert_eq "$undated" "0" "every pinned quote is dated"

section "hash-only source records never fabricate a quotation"
for section_id in 1.3 3.2.2 4.5.4 1.1.1 2.4.2 2.5.14; do
  out="$(bash "$CITE" --fingerprints "$real" "$section_id" 2>&1)"; st=$?
  assert_eq "$st" "3" "$section_id has a fingerprint but no pinned quote"
  assert_contains "$out" "NO PINNED CITATION" "source hash is not substituted for a citation"
done

exit "$fails"
