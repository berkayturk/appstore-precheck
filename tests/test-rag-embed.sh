#!/usr/bin/env bash
# test-rag-embed.sh — eval/rag/embed.py SQL generation, no network/DB (--dry-run).
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
# shellcheck source=tests/_assert.sh
source "$DIR/_assert.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/corpus.json" <<'JSON'
{ "sections": { "2.3.3": { "text": "screenshots should show the app in use", "char_count": 39 } },
  "fetched_on": "2026-07-17", "source_url": "https://developer.apple.com/app-store/review/guidelines/" }
JSON

sql="$(python3 "$ROOT/eval/rag/embed.py" --corpus "$TMP/corpus.json" --dry-run)"

section "embed.py --dry-run"
assert_contains "$sql" "INSERT INTO sections" "generates an INSERT statement"
assert_contains "$sql" "'2.3.3'" "section number embedded as SQL literal"
assert_contains "$sql" "ON CONFLICT (section_number) DO UPDATE" "upsert on conflict"
assert_contains "$sql" "::vector" "embedding cast to vector type"

section "embed.py build_gemini_request field placement"

req_shape="$(cd "$ROOT/eval/rag" && python3 -c "
import embed

# The v1beta REST endpoint reads taskType/outputDimensionality at the top level
# of each request item (per the official curl examples); a nested
# embedContentConfig object is silently ignored — which is exactly how the
# 3072-dim regression slipped through. Assert the fields sit at the top level
# and the ignored nesting is gone.
req = embed.build_gemini_request(['some text'])['requests'][0]
print(req.get('taskType'))
print(req.get('outputDimensionality'))
print('embedContentConfig' in req)
")"
assert_eq "$(echo "$req_shape" | sed -n '1p')" "RETRIEVAL_DOCUMENT" "taskType is a top-level request field"
assert_eq "$(echo "$req_shape" | sed -n '2p')" "1024" "outputDimensionality is a top-level request field"
assert_eq "$(echo "$req_shape" | sed -n '3p')" "False" "no silently-ignored embedContentConfig nesting"

section "embed.py fetch_embeddings batching (no network — _fetch_batch stubbed)"

batch_sizes="$(cd "$ROOT/eval/rag" && python3 -c "
import embed

seen_batch_sizes = []

def fake_fetch_batch(texts, api_key):
    seen_batch_sizes.append(len(texts))
    return [[0.0] * 4 for _ in texts]

embed._fetch_batch = fake_fetch_batch
result = embed.fetch_embeddings(['x'] * 125, 'fake-key')
assert len(result) == 125, f'expected 125 embeddings, got {len(result)}'
print(','.join(str(n) for n in seen_batch_sizes))
")"
assert_eq "$batch_sizes" "100,25" "125 texts split into a 100-batch then a 25-batch (Gemini's per-request cap)"

section "embed.py main() rejects wrong-dimension embeddings before calling psql"

wrong_dim_output="$(cd "$ROOT/eval/rag" && GEMINI_API_KEY=fake RAG_DATABASE_URL=fake python3 -c "
import sys
import embed

# Simulate the exact failure mode that caused a live Postgres error: Gemini
# returning un-truncated (native 3072-dim) vectors that slipped past
# truncate_and_normalize somehow. embed.py must catch this itself, with a
# clear message, rather than letting psql fail with a cryptic dimension error.
embed.fetch_embeddings = lambda texts, api_key: [[0.0] * 3072 for _ in texts]
sys.argv = ['embed.py', '--corpus', '$TMP/corpus.json']
rc = embed.main(sys.argv)
print(f'exit_code={rc}')
" 2>&1)"
assert_contains "$wrong_dim_output" "exit_code=1" "main() exits 1 instead of invoking psql"
assert_contains "$wrong_dim_output" "wrong dimension after truncate_and_normalize" "diagnostic names the actual defect"
assert_contains "$wrong_dim_output" "2.3.3=3072d" "diagnostic names the specific section and its actual dimension"

exit "$fails"
