# RAG-grounded Pierre (eval-only) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a dev-only pipeline under `eval/` that retrieves the actual current Apple App
Store Review Guidelines text via pgvector semantic search and injects it into Pierre's eval-harness
prompt, so RAG-grounded vs ungrounded precision/recall/F1 can be measured on the existing 21-case
labeled dataset.

**Architecture:** Fetch guideline HTML → extract full per-section prose for every section (not just
the officially-mapped subset) → embed with Voyage AI → store in a local pgvector table → at eval
time, embed the target check's query text, retrieve top-k similar sections, inject them into the
existing `build_request.py` prompt behind a `--rag` flag → run both configurations through the
unmodified `eval/run.sh`/`score.py` pipeline and compare.

**Tech Stack:** Bash + `jq` (ingestion, reusing existing guideline-drift parsing), Python 3 stdlib
only (no new pip dependency — `urllib.request` for Voyage HTTP calls, `subprocess` + `psql` CLI for
Postgres, matching the project's existing stdlib-only Python convention), Docker Compose +
`pgvector/pgvector:pg16` (local, dev-only).

## Global Constraints

- Dev-only: nothing here ships in the npm/brew package, touches `scan.sh`, or changes verdict logic.
- No new pip dependency; Python stays stdlib-only (existing project convention — see
  `eval/lib/validate_case.py`'s docstring).
- Secrets (`VOYAGE_API_KEY`, `RAG_DATABASE_URL`) read from environment only, never logged, never
  written to disk — same discipline as `ANTHROPIC_API_KEY` in `eval/run.sh`.
- Every new bash script follows the existing `set -u` / `gd_main`-style `if [[ "${BASH_SOURCE[0]}"
  == "${0}" ]]` guard pattern so functions are unit-testable by sourcing.
- Every new test file sources `tests/_assert.sh` and uses its `assert_eq`/`assert_contains`/
  `assert_absent`/`assert_not_empty`/`assert_gt` helpers — no new assertion framework.
- No number is published without human confirmation (project-wide rule) — the RAG-vs-baseline
  comparison in Task 8 is a manual review step, not an automated assertion.
- One chunk per guideline section, no sub-splitting (see design spec — sections are already
  short; this is a deliberate choice, not a gap to fill later).

---

### Task 1: Extract shared guideline-text parsing lib

**Files:**
- Create: `scripts/lib/guideline-text.sh`
- Modify: `scripts/guideline-drift.sh:11-49` (remove the function bodies being moved, source the lib)
- Test: `tests/test-guideline-drift.sh` (existing — must pass unchanged, no edits to this file)

**Interfaces:**
- Produces: `gd_section_ids <html-file>` → newline-separated section ids, document order, deduped.
  `gd_section_text <html-file> <id>` → normalized lowercase prose string for that id only.
  `gd_hash` → reads stdin, writes sha256 hex to stdout. All three sourced by both
  `scripts/guideline-drift.sh` and (Task 2) `eval/rag/ingest.sh`.

- [ ] **Step 1: Run the existing test to confirm it passes before touching anything**

Run: `bash tests/test-guideline-drift.sh`
Expected: `SUITE`-style per-assertion `ok:` lines, script exits 0 (all currently pass).

- [ ] **Step 2: Create the shared lib with the three functions moved verbatim**

Create `scripts/lib/guideline-text.sh`:

```bash
#!/usr/bin/env bash
# scripts/lib/guideline-text.sh — shared Apple App Store Review Guidelines HTML
# parsing helpers. Source this; do not execute directly. Used by
# scripts/guideline-drift.sh (drift detection) and eval/rag/ingest.sh (RAG corpus
# ingestion) so the extraction logic has exactly one implementation.

# gd_section_ids <html> -> numeric guideline anchor ids, document order, deduped.
# Requires at least one dotted component so bare top-level category anchors
# (id="1".."5") aren't tracked as drift-able sections — those are just the
# five category headers, not sub-sections with their own prose.
gd_section_ids() {
  grep -oE 'id="[1-5](\.[0-9]+)+"' "$1" 2>/dev/null \
    | sed -E 's/^id="//; s/"$//' \
    | awk '!seen[$0]++'
}

# gd_section_text <html> <id> -> normalized prose for exactly that section.
gd_section_text() {
  local html="$1" want="$2"
  # Replace each opening guideline-anchor tag (e.g. <span id="2.3.3"> or <li id="2.3.3" ...>)
  # with a whole-tag sentinel @@SEC:<id>@@ on its own line, so no partial tag leaks.
  sed -E 's#<[a-zA-Z]+[^>]*id="([1-5](\.[0-9]+)*)"[^>]*>#\'$'\n''@@SEC:\1@@#g' "$html" \
  | awk -v want="$want" '
      {
        if ($0 ~ /^@@SEC:/) {
          id=$0; sub(/^@@SEC:/,"",id); sub(/@@.*/,"",id)
          insec = (id == want)
          sub(/^@@SEC:[^@]*@@/,"")   # drop the sentinel, keep any trailing content on the line
        }
        if (insec) buf = buf $0 " "
      }
      END { printf "%s", buf }
    ' \
  | sed -E 's/<[^>]+>/ /g' \
  | sed -E 's/&amp;/\&/g; s/&lt;/</g; s/&gt;/>/g; s/&#39;/'\''/g; s/&quot;/"/g; s/&nbsp;/ /g' \
  | tr 'A-Z' 'a-z' \
  | tr -s ' \t\n' ' ' \
  | sed -E 's/^ +//; s/ +$//'
}

# gd_hash -> sha256 hex of stdin (portable across macOS/Linux).
gd_hash() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1
  else shasum -a 256 | cut -d' ' -f1; fi
}
```

- [ ] **Step 3: Replace the moved bodies in `scripts/guideline-drift.sh` with a source line**

In `scripts/guideline-drift.sh`, replace lines 11–49 (the `gd_section_ids`, `gd_section_text`,
and `gd_hash` function definitions) with:

```bash
here_lib="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here_lib/lib/guideline-text.sh"
```

Leave everything else in the file (`gd_number_drift`, `gd_checks_for_section`, `gd_main`)
unchanged — they stay in `guideline-drift.sh` since they're specific to drift detection, not
shared with ingestion.

- [ ] **Step 4: Re-run the existing test to confirm zero regression**

Run: `bash tests/test-guideline-drift.sh`
Expected: identical output to Step 1 — every assertion still `ok:`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/guideline-text.sh scripts/guideline-drift.sh
git commit -m "refactor(guideline-drift): extract shared HTML parsing into scripts/lib/guideline-text.sh"
```

---

### Task 2: Full-corpus ingestion — `eval/rag/ingest.sh`

**Files:**
- Create: `eval/rag/ingest.sh`
- Create: `eval/rag/corpus/.gitkeep` (directory placeholder — the real `sections.json` is generated
  by a human running `ingest.sh` against the live page in Task 8, not committed by this task)
- Test: `tests/test-rag-ingest.sh`

**Interfaces:**
- Consumes: `gd_section_text`, `gd_section_ids` from `scripts/lib/guideline-text.sh` (Task 1).
  `guidelines-baseline.json`'s `all_sections` array (existing file, unchanged).
- Produces: `eval/rag/corpus/sections.json` — `{ "sections": { "<id>": { "text": "<prose>",
  "char_count": N }, ... }, "fetched_on": "<UTC date>", "source_url": "<url>" }`. Consumed by
  Task 4's `embed.py`.

- [ ] **Step 1: Write the test against the existing committed fixtures (no new fixture needed)**

Create `tests/test-rag-ingest.sh`:

```bash
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
```

- [ ] **Step 2: Run the test to verify it fails (script doesn't exist yet)**

Run: `bash tests/test-rag-ingest.sh`
Expected: FAIL — `bash: eval/rag/ingest.sh: No such file or directory`

- [ ] **Step 3: Create the directory placeholder**

```bash
mkdir -p eval/rag/corpus
touch eval/rag/corpus/.gitkeep
```

- [ ] **Step 4: Write `eval/rag/ingest.sh`**

Create `eval/rag/ingest.sh`:

```bash
#!/usr/bin/env bash
# eval/rag/ingest.sh — MAINTAINER-ONLY. Fetches the live App Store Review
# Guidelines and extracts full per-section prose for every section listed in
# guidelines-baseline.json's `all_sections`, writing eval/rag/corpus/sections.json.
# Deliberate human step (like guideline-drift.sh --reconcile) — never run
# automatically, never sourced by scan.sh or any user-facing path.
set -u
GD_URL="https://developer.apple.com/app-store/review/guidelines/"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/lib/guideline-text.sh
source "$here/scripts/lib/guideline-text.sh"

ri_main() {
  local html="" baseline="$here/skills/appstore-precheck/guidelines-baseline.json"
  local out="$here/eval/rag/corpus/sections.json"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --html)     html="$2"; shift 2 ;;
      --baseline) baseline="$2"; shift 2 ;;
      --out)      out="$2"; shift 2 ;;
      *) echo "ingest.sh: unknown arg: $1" >&2; return 64 ;;
    esac
  done

  local tmp=""
  if [[ -z "$html" ]]; then
    tmp="$(mktemp)"; curl -sL --max-time 30 "$GD_URL" -o "$tmp" 2>/dev/null; html="$tmp"
  fi
  if [[ ! -s "$html" ]]; then
    echo "ingest.sh: fetch empty/failed; aborting" >&2
    [[ -n "$tmp" ]] && rm -f "$tmp"
    return 1
  fi

  local sections; sections="$(jq -r '.all_sections[]' "$baseline")"
  local obj='{}' sec text
  while IFS= read -r sec; do
    [[ -z "$sec" ]] && continue
    text="$(gd_section_text "$html" "$sec")"
    if [[ -z "$text" ]]; then
      echo "ingest.sh: WARN — $sec not found on live page; skipping" >&2
      continue
    fi
    obj="$(printf '%s' "$obj" | jq --arg s "$sec" --arg t "$text" \
      '.sections[$s] = {text: $t, char_count: ($t | length)}')"
  done <<< "$sections"

  printf '%s' "$obj" \
    | jq --arg date "$(date -u +%F)" --arg url "$GD_URL" \
        '. + {fetched_on: $date, source_url: $url}' \
    > "$out"
  echo "ingest.sh: wrote $out ($(jq '.sections | length' "$out") sections)"
  [[ -n "$tmp" ]] && rm -f "$tmp"
  return 0
}
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then ri_main "$@"; fi
```

```bash
chmod +x eval/rag/ingest.sh
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bash tests/test-rag-ingest.sh`
Expected: every assertion `ok:`, exit 0.

- [ ] **Step 6: Register the test in the suite and lint chain**

In `tests/all.sh`, add to the `SUITE` array (after `"test-guideline-drift.sh"`):

```bash
  "test-rag-ingest.sh" # eval/rag/ingest.sh full-corpus extraction (RAG eval, no network)
```

In `package.json`'s `lint` script, append to the `bash -n` chain (after the `eval/validate.sh` entry):

```
&& bash -n eval/rag/ingest.sh && bash -n tests/test-rag-ingest.sh
```

- [ ] **Step 7: Run the full suite and lint to confirm no regressions**

Run: `npm test && npm run lint`
Expected: `SUITE PASSED` (now 21 files), lint exits 0.

- [ ] **Step 8: Commit**

```bash
git add eval/rag/ingest.sh eval/rag/corpus/.gitkeep tests/test-rag-ingest.sh tests/all.sh package.json
git commit -m "feat(rag): add eval/rag/ingest.sh — full-corpus guideline text extraction"
```

---

### Task 3: pgvector infra — Docker Compose + schema

**Files:**
- Create: `eval/rag/docker-compose.yml`
- Create: `eval/rag/schema.sql`

**Interfaces:**
- Produces: a `sections(section_number TEXT PRIMARY KEY, text TEXT NOT NULL, embedding VECTOR(1024))`
  table, reachable at `postgres://rag:$RAG_DB_PASSWORD@localhost:5433/guideline_rag` once
  `docker compose up` is run. Consumed by Task 4 (`embed.py`) and Task 5 (`retrieve.py`) via
  `RAG_DATABASE_URL`.

No automated test for this task — it requires a running Docker daemon, which isn't guaranteed in
CI. Verification is manual (Step 3 below). This is a deliberate, stated gap, not an oversight —
Tasks 4 and 5 are unit-testable without Docker via their `--dry-run`/`--dry-run-query` modes.

- [ ] **Step 1: Write `eval/rag/schema.sql`**

```sql
-- eval/rag/schema.sql — pgvector schema for the RAG-grounded Pierre eval experiment.
-- Applied automatically by docker-compose.yml on first container start
-- (docker-entrypoint-initdb.d). One chunk per guideline section — see the design
-- spec (docs/specs/2026-07-17-rag-grounded-pierre-eval-design.md) for why no
-- sub-splitting.

CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE IF NOT EXISTS sections (
  section_number TEXT PRIMARY KEY,
  text TEXT NOT NULL,
  embedding VECTOR(1024)  -- voyage-3 dimensionality
);

-- HNSW index: not a performance necessity at ~130 rows, included for realism/
-- practice with pgvector's indexing story (explicitly noted, not silently assumed).
CREATE INDEX IF NOT EXISTS sections_embedding_hnsw
  ON sections USING hnsw (embedding vector_cosine_ops);
```

- [ ] **Step 2: Write `eval/rag/docker-compose.yml`**

```yaml
# eval/rag/docker-compose.yml — local-only pgvector instance for the RAG-grounded
# Pierre eval experiment. Dev tooling: never started by scan.sh, npm/brew install,
# or CI by default. Requires RAG_DB_PASSWORD in the environment.
services:
  pgvector:
    image: pgvector/pgvector:pg16
    environment:
      POSTGRES_USER: rag
      POSTGRES_PASSWORD: ${RAG_DB_PASSWORD:?set RAG_DB_PASSWORD before starting}
      POSTGRES_DB: guideline_rag
    ports:
      - "127.0.0.1:5433:5432"
    volumes:
      - ./schema.sql:/docker-entrypoint-initdb.d/schema.sql:ro
```

- [ ] **Step 3: Manually verify the compose file and schema apply correctly**

Run:
```bash
export RAG_DB_PASSWORD="$(openssl rand -hex 16)"
cd eval/rag && docker compose up -d
docker compose exec -T pgvector psql -U rag -d guideline_rag -c '\d sections'
```
Expected: table description showing `section_number`, `text`, `embedding` columns and the
`sections_embedding_hnsw` index. Then:
```bash
docker compose down
```

- [ ] **Step 4: Commit**

```bash
git add eval/rag/docker-compose.yml eval/rag/schema.sql
git commit -m "feat(rag): add pgvector docker-compose + schema for guideline embeddings"
```

---

### Task 4: Embedding — `eval/rag/embed.py`

**Files:**
- Create: `eval/rag/embed.py`
- Test: `tests/test-rag-embed.sh`

**Interfaces:**
- Consumes: `eval/rag/corpus/sections.json` (Task 2's output shape).
- Produces: (via `--dry-run`) SQL text on stdout for unit testing; (live mode) upserts rows into
  the `sections` table (Task 3) via `psql`. Requires `VOYAGE_API_KEY`, `RAG_DATABASE_URL` env vars.

- [ ] **Step 1: Write the test (dry-run mode, no network/DB)**

Create `tests/test-rag-embed.sh`:

```bash
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/test-rag-embed.sh`
Expected: FAIL — `python3: can't open file '.../eval/rag/embed.py'`

- [ ] **Step 3: Write `eval/rag/embed.py`**

```python
#!/usr/bin/env python3
"""embed.py — embed eval/rag/corpus/sections.json with Voyage AI and load into
the local pgvector 'sections' table via psql.

Requires VOYAGE_API_KEY in the environment (read at request time, never logged,
never written to disk) and RAG_DATABASE_URL pointing at the pgvector instance
started by eval/rag/docker-compose.yml.

Usage: embed.py [--corpus path] [--dry-run]
  --dry-run   print the generated SQL to stdout instead of calling Voyage/psql
              (used by tests — no network, no DB required; embeds zero-vectors)
"""
import json
import os
import subprocess
import sys
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DEFAULT_CORPUS = REPO / "eval" / "rag" / "corpus" / "sections.json"
VOYAGE_URL = "https://api.voyageai.com/v1/embeddings"
MODEL = "voyage-3"


def load_corpus(path):
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    return data["sections"]


def build_voyage_request(texts):
    """texts: list[str] -> Voyage embeddings request body."""
    return {"input": texts, "model": MODEL, "input_type": "document"}


def sql_literal(value):
    """Escape a string for a single-quoted SQL literal."""
    return "'" + value.replace("'", "''") + "'"


def build_upsert_sql(section_numbers, texts, embeddings):
    """section_numbers, texts, embeddings (list[list[float]]) aligned by index
    -> one SQL script upserting every row."""
    lines = []
    for num, text, vec in zip(section_numbers, texts, embeddings):
        vec_literal = "'[" + ",".join(repr(x) for x in vec) + "]'"
        lines.append(
            "INSERT INTO sections (section_number, text, embedding) VALUES "
            f"({sql_literal(num)}, {sql_literal(text)}, {vec_literal}::vector) "
            "ON CONFLICT (section_number) DO UPDATE SET "
            "text = EXCLUDED.text, embedding = EXCLUDED.embedding;"
        )
    return "\n".join(lines)


def fetch_embeddings(texts, api_key):
    req = urllib.request.Request(
        VOYAGE_URL,
        data=json.dumps(build_voyage_request(texts)).encode("utf-8"),
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        body = json.loads(resp.read())
    return [item["embedding"] for item in body["data"]]


def main(argv):
    corpus_path = DEFAULT_CORPUS
    dry_run = False
    args = argv[1:]
    while args:
        arg = args.pop(0)
        if arg == "--corpus":
            corpus_path = Path(args.pop(0))
        elif arg == "--dry-run":
            dry_run = True
        else:
            print(f"embed.py: unknown arg {arg}", file=sys.stderr)
            return 64

    sections = load_corpus(corpus_path)
    section_numbers = sorted(sections)
    texts = [sections[s]["text"] for s in section_numbers]

    if dry_run:
        fake_embeddings = [[0.0] * 4 for _ in texts]
        print(build_upsert_sql(section_numbers, texts, fake_embeddings))
        return 0

    api_key = os.environ.get("VOYAGE_API_KEY")
    if not api_key:
        print("embed.py: VOYAGE_API_KEY is not set", file=sys.stderr)
        return 1
    db_url = os.environ.get("RAG_DATABASE_URL")
    if not db_url:
        print("embed.py: RAG_DATABASE_URL is not set", file=sys.stderr)
        return 1

    embeddings = fetch_embeddings(texts, api_key)
    sql = build_upsert_sql(section_numbers, texts, embeddings)
    result = subprocess.run(["psql", db_url, "-v", "ON_ERROR_STOP=1"],
                             input=sql, text=True)
    return result.returncode


if __name__ == "__main__":
    sys.exit(main(sys.argv))
```

```bash
chmod +x eval/rag/embed.py
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/test-rag-embed.sh`
Expected: every assertion `ok:`, exit 0.

- [ ] **Step 5: Register in suite and lint, run full suite**

In `tests/all.sh` `SUITE` array, add after `"test-rag-ingest.sh"`:
```bash
  "test-rag-embed.sh" # eval/rag/embed.py SQL generation (RAG eval, no network)
```
In `package.json` lint chain, append: `&& bash -n tests/test-rag-embed.sh`

Run: `npm test && npm run lint`
Expected: `SUITE PASSED` (22 files), lint exits 0.

- [ ] **Step 6: Commit**

```bash
git add eval/rag/embed.py tests/test-rag-embed.sh tests/all.sh package.json
git commit -m "feat(rag): add eval/rag/embed.py — Voyage embedding + pgvector upsert"
```

---

### Task 5: Retrieval — `eval/rag/retrieve.py`

**Files:**
- Create: `eval/rag/retrieve.py`
- Test: `tests/test-rag-retrieve.sh`

**Interfaces:**
- Consumes: `extract_check_row`, `extract_procedure`, `PIERRE_MD` imported from
  `eval/lib/build_request.py` (existing functions, unchanged — reused, not duplicated).
- Produces: (via `--dry-run-query`) SQL text on stdout for unit testing; (live mode) a JSON array
  `[{"section_number": str, "text": str, "similarity": float}, ...]` on stdout, consumed by
  Task 7's `eval/run.sh --rag` wiring.

- [ ] **Step 1: Write the test (dry-run-query mode, no network/DB)**

Create `tests/test-rag-retrieve.sh`:

```bash
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/test-rag-retrieve.sh`
Expected: FAIL — `python3: can't open file '.../eval/rag/retrieve.py'`

- [ ] **Step 3: Write `eval/rag/retrieve.py`**

```python
#!/usr/bin/env python3
"""retrieve.py — embed a query with Voyage AI and return the top-k most similar
guideline sections from the local pgvector 'sections' table.

Requires VOYAGE_API_KEY and RAG_DATABASE_URL (see embed.py). Prints a JSON array
of {section_number, text, similarity} to stdout, ordered most-similar first.

Usage:
  retrieve.py "<query text>" [--top-k N] [--dry-run-query]
  retrieve.py --case <case.json> [--top-k N] [--dry-run-query]

--case builds the query from the same table-row + procedure text
eval/lib/build_request.py embeds in the prompt (single source of truth — no
duplicated check-text extraction).
"""
import json
import os
import subprocess
import sys
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))
from build_request import PIERRE_MD, extract_check_row, extract_procedure  # noqa: E402

VOYAGE_URL = "https://api.voyageai.com/v1/embeddings"
MODEL = "voyage-3"


def query_from_case(case_path):
    case = json.loads(Path(case_path).read_text(encoding="utf-8"))
    pierre_text = PIERRE_MD.read_text(encoding="utf-8")
    check_id = case["check_id"]
    return (extract_check_row(pierre_text, check_id) + "\n"
            + extract_procedure(pierre_text, check_id))


def build_voyage_query_request(query):
    return {"input": [query], "model": MODEL, "input_type": "query"}


def build_similarity_sql(embedding, top_k):
    vec_literal = "'[" + ",".join(repr(x) for x in embedding) + "]'::vector"
    return (
        "SELECT json_agg(row_to_json(t)) FROM ("
        "SELECT section_number, text, "
        f"1 - (embedding <=> {vec_literal}) AS similarity "
        "FROM sections "
        f"ORDER BY embedding <=> {vec_literal} "
        f"LIMIT {int(top_k)}"
        ") t;"
    )


def fetch_query_embedding(query, api_key):
    req = urllib.request.Request(
        VOYAGE_URL,
        data=json.dumps(build_voyage_query_request(query)).encode("utf-8"),
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        body = json.loads(resp.read())
    return body["data"][0]["embedding"]


def main(argv):
    args = argv[1:]
    if not args:
        print("usage: retrieve.py \"<query>\"|--case <case.json> [--top-k N] [--dry-run-query]",
              file=sys.stderr)
        return 64

    query = None
    case_path = None
    if args[0] == "--case":
        args.pop(0)
        case_path = args.pop(0)
    else:
        query = args.pop(0)

    top_k = 3
    dry_run_query = False
    while args:
        arg = args.pop(0)
        if arg == "--top-k":
            top_k = int(args.pop(0))
        elif arg == "--dry-run-query":
            dry_run_query = True
        else:
            print(f"retrieve.py: unknown arg {arg}", file=sys.stderr)
            return 64

    if case_path is not None:
        query = query_from_case(case_path)

    if dry_run_query:
        fake_embedding = [0.0] * 4
        print(build_similarity_sql(fake_embedding, top_k))
        return 0

    api_key = os.environ.get("VOYAGE_API_KEY")
    if not api_key:
        print("retrieve.py: VOYAGE_API_KEY is not set", file=sys.stderr)
        return 1
    db_url = os.environ.get("RAG_DATABASE_URL")
    if not db_url:
        print("retrieve.py: RAG_DATABASE_URL is not set", file=sys.stderr)
        return 1

    embedding = fetch_query_embedding(query, api_key)
    sql = build_similarity_sql(embedding, top_k)
    result = subprocess.run(["psql", db_url, "-t", "-A", "-v", "ON_ERROR_STOP=1", "-c", sql],
                             capture_output=True, text=True)
    if result.returncode != 0:
        print(f"retrieve.py: query failed: {result.stderr}", file=sys.stderr)
        return 1
    rows = json.loads(result.stdout.strip() or "[]")
    print(json.dumps(rows))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
```

```bash
chmod +x eval/rag/retrieve.py
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/test-rag-retrieve.sh`
Expected: every assertion `ok:`, exit 0.

- [ ] **Step 5: Register in suite and lint, run full suite**

In `tests/all.sh` `SUITE` array, add after `"test-rag-embed.sh"`:
```bash
  "test-rag-retrieve.sh" # eval/rag/retrieve.py similarity-query generation (RAG eval, no network)
```
In `package.json` lint chain, append: `&& bash -n tests/test-rag-retrieve.sh`

Run: `npm test && npm run lint`
Expected: `SUITE PASSED` (23 files), lint exits 0.

- [ ] **Step 6: Commit**

```bash
git add eval/rag/retrieve.py tests/test-rag-retrieve.sh tests/all.sh package.json
git commit -m "feat(rag): add eval/rag/retrieve.py — pgvector top-k similarity retrieval"
```

---

### Task 6: Grounding integration — `eval/lib/build_request.py --retrieved`

**Files:**
- Modify: `eval/lib/build_request.py` (add `format_retrieved`, extend `build_user` and `main`)
- Test: `tests/test-rag-build-request.sh`

**Interfaces:**
- Consumes: a JSON file matching `retrieve.py`'s output shape
  (`[{"section_number", "text", "similarity"}, ...]`).
- Produces: `build_user(case, pierre_text, retrieved=None)` — backward compatible (existing
  3-arg callers unaffected); when `retrieved` is a non-empty list, the returned prompt string
  gains a `## Retrieved guideline text` section. CLI gains an optional `--retrieved <path>` flag,
  consumed by Task 7's `eval/run.sh --rag`.

- [ ] **Step 1: Write the test**

Create `tests/test-rag-build-request.sh`:

```bash
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/test-rag-build-request.sh`
Expected: FAIL on the grounded assertions — `--retrieved` is not yet a recognized flag
(`build_request.py: unknown arg` or similar, since the flag doesn't exist yet).

- [ ] **Step 3: Modify `eval/lib/build_request.py`**

Add this function after `extract_procedure` (around line 50):

```python
def format_retrieved(retrieved):
    """retrieved: list of {section_number, text, similarity} -> markdown block."""
    parts = [f"## Retrieved guideline text (semantic search, top-{len(retrieved)})"]
    for item in retrieved:
        parts.append(
            f"### {item['section_number']} (similarity: {item['similarity']:.2f})\n"
            f"{item['text']}"
        )
    return "\n\n".join(parts)
```

Replace the `build_user` function (lines 78–100) with:

```python
def build_user(case, pierre_text, retrieved=None):
    check_id = case["check_id"]
    parts = [
        f"# Target check: {check_id} (guideline {case['guideline']})",
        "Table row from the 28-check catalog:",
        extract_check_row(pierre_text, check_id),
        "## Procedure",
        extract_procedure(pierre_text, check_id),
        "## Project files",
    ]
    fixture_dir = DATASET / case["fixture"]
    for rel, content in fixture_files(fixture_dir):
        parts.append(f"### {rel}\n```\n{content.rstrip()}\n```")
    fetched = case.get("fetched_urls") or {}
    if fetched:
        parts.append("## Pre-fetched URL contents")
        for kind in sorted(fetched):
            parts.append(f"### {kind}\n```\n{fetched[kind].rstrip()}\n```")
    if retrieved:
        parts.append(format_retrieved(retrieved))
    parts.append(
        f"Run check {check_id} now and output its single REVIEW-PASS: or "
        "REVIEW-FINDING: line."
    )
    return "\n\n".join(parts)
```

Replace `main` (lines 109–134) with:

```python
def main(argv):
    args = argv[1:]
    if len(args) < 3:
        print("usage: build_request.py <case.json> <model> <max_tokens> [--retrieved <path>]",
              file=sys.stderr)
        return 64
    case_path, model, max_tokens_s = args[0], args[1], args[2]
    rest = args[3:]
    retrieved = None
    while rest:
        arg = rest.pop(0)
        if arg == "--retrieved":
            retrieved = json.loads(Path(rest.pop(0)).read_text(encoding="utf-8"))
        else:
            print(f"build_request.py: unknown arg {arg}", file=sys.stderr)
            return 64

    case = json.loads(Path(case_path).read_text(encoding="utf-8"))
    pierre_text = PIERRE_MD.read_text(encoding="utf-8")
    model_name = model
    max_tokens = int(max_tokens_s)
    body = {
        "model": model_name,
        "max_tokens": max_tokens,
        "output_config": {"effort": "low"},
        "system": [{
            "type": "text",
            "text": build_system(pierre_text),
            "cache_control": {"type": "ephemeral"},
        }],
        "messages": [{"role": "user", "content": build_user(case, pierre_text, retrieved)}],
    }
    if not thinking_always_on(model_name):
        body["thinking"] = {"type": "disabled"}
    json.dump(body, sys.stdout, ensure_ascii=False)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
```

- [ ] **Step 4: Run the new test and the existing eval-parse test to verify both pass**

Run: `bash tests/test-rag-build-request.sh && bash tests/test-eval-parse.sh`
Expected: every assertion `ok:` in both files, both exit 0 (the existing test's 3-positional-arg
calls are unaffected since `retrieved` defaults to `None`).

- [ ] **Step 5: Register in suite and lint, run full suite**

In `tests/all.sh` `SUITE` array, add after `"test-eval-parse.sh"`:
```bash
  "test-rag-build-request.sh" # eval/lib/build_request.py --retrieved flag (RAG eval, no network)
```
In `package.json` lint chain, append: `&& bash -n tests/test-rag-build-request.sh`

Run: `npm test && npm run lint`
Expected: `SUITE PASSED` (24 files), lint exits 0.

- [ ] **Step 6: Commit**

```bash
git add eval/lib/build_request.py tests/test-rag-build-request.sh tests/all.sh package.json
git commit -m "feat(rag): build_request.py --retrieved — inject retrieved guideline text into the prompt"
```

---

### Task 7: `eval/run.sh --rag` wiring

**Files:**
- Modify: `eval/run.sh`
- Test: `tests/test-rag-run-guard.sh`

**Interfaces:**
- Consumes: `eval/rag/retrieve.py --case <path> --top-k N` (Task 5),
  `eval/lib/build_request.py ... --retrieved <path>` (Task 6).
- Produces: `manifest.json` gains a `rag: true|false` field; the model/prompt cache-dir mismatch
  guard gains a third `rag` check so grounded and ungrounded runs can never share a cache dir.

- [ ] **Step 1: Write the test — exercise only the early guard path (no network)**

Create `tests/test-rag-run-guard.sh`:

```bash
#!/usr/bin/env bash
# test-rag-run-guard.sh — eval/run.sh refuses to mix grounded/ungrounded runs in
# one cache dir. Exercises only the guard path, which runs before any curl call.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
# shellcheck source=tests/_assert.sh
source "$DIR/_assert.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export ANTHROPIC_API_KEY="dummy-guard-test-key"

mkdir -p "$TMP/run"
prompt_sha="$(shasum -a 256 "$ROOT/skills/appstore-precheck/references/pierre-deep-review.md" | awk '{print $1}')"
jq -n --arg model "claude-sonnet-5" --arg prompt_sha "$prompt_sha" \
  '{model:$model, prompt_sha256:$prompt_sha, rag:false}' > "$TMP/run/manifest.json"

section "run.sh --rag mismatch guard"

out="$(bash "$ROOT/eval/run.sh" --model claude-sonnet-5 --rag --out "$TMP/run" --cases 'check05-*' 2>&1)"
rc=$?
assert_eq "$rc" "1" "run.sh exits 1 when rag flag disagrees with cached manifest"
assert_contains "$out" "refusing to mix grounded/ungrounded runs" "clear error message for rag mismatch"

exit "$fails"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/test-rag-run-guard.sh`
Expected: FAIL — `--rag` is not yet a recognized flag (`run.sh: unknown arg '--rag'`).

- [ ] **Step 3: Modify `eval/run.sh`**

In the defaults block (around line 17-22), add:
```bash
RAG=0
```

In the arg-parsing `case` block (around lines 24-33), add before the closing `esac`:
```bash
    --rag)      RAG=1; shift ;;
```

Change the `--baseline` output-dir default (line 36) to include the rag suffix:
```bash
[[ $BASELINE -eq 1 && -z "$OUT" ]] && OUT="$ROOT/eval/baseline/$(date -u +%F)-$MODEL$([[ $RAG -eq 1 ]] && echo "-rag")"
```

In the manifest-mismatch guard block (around lines 72-83), add a third check after the existing
`prev_prompt` check, before the closing `fi`:
```bash
  prev_rag="$(jq -r '.rag // false' "$OUT/manifest.json")"
  want_rag="$([[ $RAG -eq 1 ]] && echo true || echo false)"
  if [[ "$prev_rag" != "$want_rag" ]]; then
    echo "run.sh: $OUT was produced with rag=$prev_rag — refusing to mix grounded/ungrounded runs (use --out <fresh dir>)" >&2
    exit 1
  fi
```

In the manifest-writing `jq -n` call (around lines 85-93), add the `rag` field:
```bash
jq -n --arg model "$MODEL" --arg date "$(date -u +%FT%TZ)" \
      --arg sha "$dataset_sha" --arg glob "$GLOB" --arg thinking "$THINKING" \
      --arg prompt_sha "$prompt_sha" \
      --argjson repeat "$REPEAT" --argjson max_tokens "$MAX_TOKENS" \
      --argjson rag "$([[ $RAG -eq 1 ]] && echo true || echo false)" \
  '{model:$model, max_tokens:$max_tokens, thinking:$thinking, effort:"low",
    repeat:$repeat, cases_glob:$glob, dataset_sha256:$sha,
    prompt_sha256:$prompt_sha, run_date:$date, rag:$rag,
    api:"https://api.anthropic.com/v1/messages", generator:"eval/run.sh"}' \
  > "$OUT/manifest.json"
```

Replace the request-build line (around line 101):
```bash
  python3 "$ROOT/eval/lib/build_request.py" "$case_file" "$MODEL" "$MAX_TOKENS" > "$req" || {
    echo "run.sh: request build failed for $case_id" >&2; rm -f "$req"; exit 1; }
```
with:
```bash
  if [[ $RAG -eq 1 ]]; then
    retrieved_file="$OUT/$case_id/retrieved.json"
    python3 "$ROOT/eval/rag/retrieve.py" --case "$case_file" --top-k 3 > "$retrieved_file" || {
      echo "run.sh: retrieval failed for $case_id" >&2; exit 1; }
    python3 "$ROOT/eval/lib/build_request.py" "$case_file" "$MODEL" "$MAX_TOKENS" \
      --retrieved "$retrieved_file" > "$req" || {
      echo "run.sh: request build failed for $case_id" >&2; rm -f "$req"; exit 1; }
  else
    python3 "$ROOT/eval/lib/build_request.py" "$case_file" "$MODEL" "$MAX_TOKENS" > "$req" || {
      echo "run.sh: request build failed for $case_id" >&2; rm -f "$req"; exit 1; }
  fi
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/test-rag-run-guard.sh`
Expected: every assertion `ok:`, exit 0. (The guard exits before any curl call, so the dummy
`ANTHROPIC_API_KEY` never needs to be valid.)

- [ ] **Step 5: Run the full suite and lint (bash -n on run.sh) to confirm no regressions**

Run: `npm test && npm run lint`
Expected: `SUITE PASSED` (25 files — add `"test-rag-run-guard.sh"` to `tests/all.sh` `SUITE` array
first, after `"test-rag-build-request.sh"`), lint exits 0 (`eval/run.sh` is already in the
`bash -n` chain from before this project; add `bash -n tests/test-rag-run-guard.sh` to the chain
too).

- [ ] **Step 6: Commit**

```bash
git add eval/run.sh tests/test-rag-run-guard.sh tests/all.sh package.json
git commit -m "feat(rag): eval/run.sh --rag — wire retrieval into the request pipeline"
```

---

### Task 8: Runbook + end-to-end wiring check — `eval/rag/README.md`

**Files:**
- Create: `eval/rag/README.md`

**Interfaces:**
- Produces: the documented procedure a human follows to actually generate the RAG-vs-baseline
  comparison. No new code interfaces — this task is the operational glue between Tasks 1–7 and
  the human-reviewed publication step the project's standing rule requires.

- [ ] **Step 1: Write `eval/rag/README.md`**

```markdown
# RAG-grounded Pierre — eval-only experiment

Measures whether giving Pierre's eval-harness prompt the actual current Apple guideline text
(via pgvector semantic search) changes precision/recall/F1 on the 21-case labeled dataset,
versus the existing ungrounded baseline. See
`docs/specs/2026-07-17-rag-grounded-pierre-eval-design.md` for the full design.

Dev-only: nothing here ships in the npm/brew package or affects `scan.sh`.

## One-time setup

1. Generate the full-corpus text (deliberate human step, like `guideline-drift.sh --reconcile`):
   ```bash
   bash eval/rag/ingest.sh
   ```
   Writes `eval/rag/corpus/sections.json`. Review the WARN lines (if any) for sections that
   failed to extract before proceeding.

2. Start the local pgvector instance:
   ```bash
   export RAG_DB_PASSWORD="$(openssl rand -hex 16)"
   export RAG_DATABASE_URL="postgres://rag:$RAG_DB_PASSWORD@localhost:5433/guideline_rag"
   (cd eval/rag && docker compose up -d)
   ```

3. Embed the corpus (requires `VOYAGE_API_KEY`):
   ```bash
   export VOYAGE_API_KEY="..."
   python3 eval/rag/embed.py
   ```

## Running the comparison

```bash
# Ungrounded baseline (existing behavior, unchanged):
bash eval/run.sh --model claude-sonnet-5 --baseline

# Grounded run (writes to eval/baseline/<date>-claude-sonnet-5-rag/):
bash eval/run.sh --model claude-sonnet-5 --baseline --rag
```

Score each independently — `eval/score.py` is unchanged:
```bash
python3 eval/score.py --run eval/baseline/<date>-claude-sonnet-5
python3 eval/score.py --run eval/baseline/<date>-claude-sonnet-5-rag
```

## Publishing results

Per the project's standing rule, no number is published without human confirmation. After
reviewing both scorecards side by side, write the comparison by hand to
`docs/rag-eval-results.md` — per-check and per-tier precision/recall/F1, RAG vs baseline, with
particular attention to the 6 Tier B checks (4, 5, 7, 10, 15, 28), where grounding is expected to
matter most. Do not include configurations that weren't actually run.

## Teardown

```bash
(cd eval/rag && docker compose down)
```
```

- [ ] **Step 2: Verify the full test suite and lint are green end-to-end**

Run: `npm test && npm run lint`
Expected: `SUITE PASSED` (25 files), lint exits 0. This confirms every RAG file added across
Tasks 1–7 is syntactically valid and its unit tests pass together, with zero regressions to the
pre-existing 20 test files.

- [ ] **Step 3: Commit**

```bash
git add eval/rag/README.md
git commit -m "docs(rag): add eval/rag/README.md — setup, run, and publication runbook"
```

---

## Self-Review Notes

- **Spec coverage:** Ingestion (Task 2), pgvector store (Task 3), Voyage embedding (Task 4),
  retrieval (Task 5), grounding integration point in `build_request.py` (Task 6), measurement
  wiring in `run.sh` (Task 7), and the human-reviewed publication runbook (Task 8) — every
  component in the approved design doc has a corresponding task. The shared-lib refactor (Task 1)
  was not in the original design's component list but is required by Task 2 to avoid duplicating
  `guideline-drift.sh`'s parsing logic, consistent with the design's "reuses the parsing logic
  already proven in `scripts/guideline-drift.sh`" line.
- **No placeholders:** every step shows complete, runnable code — no TBD/TODO, no "add
  appropriate error handling" without showing the handling.
- **Type/interface consistency:** `retrieve.py`'s output shape
  (`section_number`/`text`/`similarity`) matches exactly what `format_retrieved` in
  `build_request.py` (Task 6) expects, and matches the stub JSON used in Task 6's test. `--rag`
  in `run.sh` (Task 7) calls `retrieve.py --case` (Task 5) and `build_request.py --retrieved`
  (Task 6) with the exact flag names and file-path conventions defined in those tasks.
