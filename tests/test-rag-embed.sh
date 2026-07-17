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

exit "$fails"
