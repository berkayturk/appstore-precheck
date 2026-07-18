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

   The corpus file is deliberately **not committed** (gitignored): it is the full prose of
   Apple's copyrighted guidelines and this repo is public. Provenance lives in the file's own
   `fetched_on`/`source_url` fields; a re-fetched corpus may differ if Apple has revised the
   page since a published result.

2. Start the local pgvector instance:
   ```bash
   export RAG_DB_PASSWORD="$(openssl rand -hex 16)"
   export RAG_DATABASE_URL="postgres://rag:$RAG_DB_PASSWORD@localhost:5433/guideline_rag"
   (cd eval/rag && docker compose up -d)
   ```

3. Embed the corpus (requires `GEMINI_API_KEY`):
   ```bash
   export GEMINI_API_KEY="..."
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
