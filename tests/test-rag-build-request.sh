#!/usr/bin/env bash
# test-rag-build-request.sh — eval/lib/build_request.py --retrieved flag (RAG
# grounding), no network/DB — a stub retrieved-context JSON file is passed directly.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
# shellcheck source=tests/_assert.sh
source "$DIR/_assert.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/retrieved.json" <<'JSON'
[{"section_number": "2.2", "text": "beta testing demos and betas don't belong on the app store", "similarity": 0.91}]
JSON

section "build_request.py --retrieved"

req_ungrounded="$(python3 "$ROOT/eval/lib/build_request.py" \
  "$ROOT/eval/dataset/cases/check05-beta-in-release-notes.json" claude-sonnet-5 1024)"
assert_absent "$(jq -r '.messages[0].content' <<<"$req_ungrounded")" "Retrieved guideline text" \
  "no retrieved section when --retrieved omitted (baseline path unchanged)"

req_grounded="$(python3 "$ROOT/eval/lib/build_request.py" \
  "$ROOT/eval/dataset/cases/check05-beta-in-release-notes.json" claude-sonnet-5 1024 \
  --retrieved "$TMP/retrieved.json")"
content="$(jq -r '.messages[0].content' <<<"$req_grounded")"
assert_contains "$content" "## Retrieved guideline text" "retrieved section header present"
assert_contains "$content" "### 2.2 (similarity: 0.91)" "section number + similarity formatted"
assert_contains "$content" "beta testing demos and betas don't belong" "retrieved text embedded"

exit "$fails"
