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

section "retrieve.py build_gemini_query_request field placement"

query_shape="$(cd "$ROOT/eval/rag" && python3 -c "
import retrieve

# Same contract as embed.py's request builder: taskType/outputDimensionality
# must be top-level REST fields — a nested embedContentConfig is silently
# ignored by the v1beta endpoint.
body = retrieve.build_gemini_query_request('some query')
print(body.get('taskType'))
print(body.get('outputDimensionality'))
print('embedContentConfig' in body)
")"
assert_eq "$(echo "$query_shape" | sed -n '1p')" "RETRIEVAL_QUERY" "taskType is a top-level request field"
assert_eq "$(echo "$query_shape" | sed -n '2p')" "1024" "outputDimensionality is a top-level request field"
assert_eq "$(echo "$query_shape" | sed -n '3p')" "False" "no silently-ignored embedContentConfig nesting"

section "retrieve.py.extract_single_embedding (both Gemini response shapes)"

shapes_result="$(cd "$ROOT/eval/rag" && python3 -c "
import retrieve

# Real shape from the single embedContent endpoint (singular 'embedding').
singular = retrieve.extract_single_embedding({'embedding': {'values': [1, 2, 3]}})
print(singular)

# Defensive fallback: batchEmbedContents' plural shape, in case a future
# Gemini API version or endpoint switch returns it here too.
plural = retrieve.extract_single_embedding({'embeddings': [{'values': [4, 5, 6]}]})
print(plural)

try:
    retrieve.extract_single_embedding({'unexpected': 'shape'})
    print('NO_EXCEPTION_RAISED')
except SystemExit as exc:
    print(str(exc))
")"
assert_eq "$(echo "$shapes_result" | sed -n '1p')" "[1, 2, 3]" "singular {embedding: {values}} shape extracted"
assert_eq "$(echo "$shapes_result" | sed -n '2p')" "[4, 5, 6]" "plural {embeddings: [{values}]} shape also accepted"
assert_contains "$(echo "$shapes_result" | sed -n '3p')" "unexpected Gemini response shape" "unrecognized shape raises a clear SystemExit, not a bare KeyError"

exit "$fails"
