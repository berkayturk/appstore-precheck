#!/usr/bin/env bash
# test-rag-ingest.sh — eval/rag/ingest.sh full-corpus extraction, no network.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
# shellcheck source=tests/_assert.sh
source "$DIR/_assert.sh"

FIX="$ROOT/tests/fixtures/guidelines"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

bash "$ROOT/eval/rag/ingest.sh" --html "$FIX/sample.html" --baseline "$FIX/baseline.json" \
  --out "$TMP/sections.json"

section "ingest.sh --html (offline fixture)"

assert_eq "$(jq '.sections | length' "$TMP/sections.json")" "4" "all 4 fixture sections extracted"
assert_contains "$(jq -r '.sections["2.3.3"].text' "$TMP/sections.json")" \
  "screenshots should show the app in use" "2.3.3 full prose captured"
assert_gt "$(jq -r '.sections["2.3.3"].char_count' "$TMP/sections.json")" "10" \
  "char_count populated"
assert_eq "$(jq -r '.source_url' "$TMP/sections.json")" \
  "https://developer.apple.com/app-store/review/guidelines/" "source_url recorded"
assert_not_empty "$(jq -r '.fetched_on' "$TMP/sections.json")" "fetched_on date recorded"

exit "$fails"
