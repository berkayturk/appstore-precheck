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

exit "$fails"
