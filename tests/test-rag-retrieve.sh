#!/usr/bin/env bash
# test-rag-retrieve.sh — eval/rag/retrieve.py SQL generation, no network/DB.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
# shellcheck source=tests/_assert.sh
source "$DIR/_assert.sh"

section "retrieve.py --dry-run-query (free-text query)"

sql="$(python3 "$ROOT/eval/rag/retrieve.py" "privacy policy purpose strings" --top-k 3 --dry-run-query)"
assert_contains "$sql" "ORDER BY embedding <=>" "orders by cosine distance"
assert_contains "$sql" "LIMIT 3" "top-k limit applied"
assert_contains "$sql" "1 - (embedding <=>" "similarity computed as 1 - cosine distance"

section "retrieve.py --case (reuses build_request.py's check-text extraction)"

case_sql="$(python3 "$ROOT/eval/rag/retrieve.py" --case \
  "$ROOT/eval/dataset/cases/check05-beta-in-release-notes.json" --dry-run-query)"
assert_contains "$case_sql" "ORDER BY embedding <=>" "--case mode also builds a similarity query"

exit "$fails"
