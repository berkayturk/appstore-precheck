# Design: RAG-grounded Pierre — measured retrieval-augmented grounding (eval-only)

**Date:** 2026-07-17
**Status:** Approved (brainstorming) — implemented
**Depends on:** `eval/` harness (run.sh, build_request.py, score.py, dataset/cases), `guidelines-baseline.json` (`all_sections`)
**Amendment (2026-07-17):** embedding provider switched from Voyage AI to Gemini
(`gemini-embedding-001`, `outputDimensionality: 1024` to match `schema.sql`'s `VECTOR(1024)`) after
implementation — this doc's Voyage references below reflect the original design decision; the code
is the source of truth for the actual provider in use.

## Problem

Pierre's 28 semantic checks (`skills/appstore-precheck/references/pierre-deep-review.md`) judge
guideline compliance from the reviewing LLM's parametric memory of Apple's App Store Review
Guidelines. Phase 0 (`scripts/guideline-drift.sh`) proves those guidelines drift over time — it
fetches the live page and diffs section numbers/text against a baseline — but it only persists a
SHA256 fingerprint + 160-char snapshot per section (`guidelines-fingerprints.json`), never the
full text. Nothing in the current pipeline gives Pierre the actual current guideline prose to
reason against. This project measures whether retrieving and injecting that text (RAG grounding)
measurably improves Pierre's precision/recall on the existing 21-case labeled eval dataset,
particularly on the 6 heuristic Tier B checks where false positives are the known weak point.

## Scope

**Dev-only, lives entirely under `eval/rag/`.** Does not touch `scan.sh`, verdict logic, the
npm/brew-distributed CLI, or the production agent-executed `pierre-deep-review.md` path (where
Pierre *is* the host agent, not a single controllable API call). The one place a single grounded
LLM call can be cleanly built and measured is `eval/lib/build_request.py`, which already assembles
a byte-identical system prompt + per-case user prompt for a direct Anthropic Messages API call —
this is where grounding is injected, behind a new opt-in flag. Nothing here ships to end users;
Postgres/pgvector/Voyage are dev/measurement dependencies only (not added to `package.json`
runtime deps).

## Architecture

### 1. Ingestion — `eval/rag/ingest.sh`

Fetches the live guidelines page and extracts full per-section prose for **every** section in
`guidelines-baseline.json`'s `all_sections` (~130 sections) — not just the ~34 sections
`pierre-deep-review.md` currently cites. Embedding the full corpus (not just the officially-mapped
subset) is what makes semantic search meaningfully different from a lookup table: a check can
surface a neighboring section it isn't explicitly wired to (e.g. a 5.1.3 health query surfacing
5.1.4 kids).

Reuses the parsing logic already proven in `scripts/guideline-drift.sh` (`gd_section_ids`,
`gd_section_text`) — extract that shared logic into `scripts/lib/guideline-text.sh` (sourced by
both `guideline-drift.sh` and `ingest.sh`) rather than duplicating the sed/awk pipeline.

Output: `eval/rag/corpus/sections.json` — `{ "sections": { "<id>": { "text": "<full prose>",
"char_count": N } }, "fetched_on": "<UTC date>", "source_url": "..." }`. This file is committed
(small, ~130 sections of plain text) so embedding/retrieval is reproducible without a live fetch.
Re-running `ingest.sh` is a deliberate human step (like `guideline-drift.sh --reconcile`), not
run automatically.

### 2. Embedding & store — `eval/rag/docker-compose.yml`, `eval/rag/schema.sql`, `eval/rag/embed.py`

- `docker-compose.yml`: single `pgvector/pgvector:pg16` service, local-only, no ports beyond
  localhost, credentials via env vars (never committed).
- `schema.sql`: one table —
  `sections(section_number TEXT PRIMARY KEY, text TEXT NOT NULL, embedding VECTOR(1024))`
  plus an HNSW index on `embedding` (corpus is ~130 rows — index is for realism/practice,
  not performance necessity at this scale; note this explicitly rather than pretending it's needed).
- `embed.py`: reads `sections.json`, calls Voyage AI (`voyage-3`, 1024-dim) once per section
  (batched in a single request where the API allows), upserts into the table. Requires
  `VOYAGE_API_KEY` in the environment — read at request time, never logged, never written to disk
  (same discipline as `ANTHROPIC_API_KEY` in `eval/run.sh`).

Chunking granularity: **one chunk per guideline section**, no sub-splitting. Sections in this
corpus already run ~50–300 words — smaller than typical RAG chunk targets — so splitting further
would fragment single ideas without benefit. This is a deliberate, stated choice, not an
oversight: if a section ever grows much larger at reconciliation time, revisit.

### 3. Retrieval — `eval/rag/retrieve.py`

Given a query string (built from the target check's guideline number + table row + procedure
text — see below), embeds it with the same Voyage model and returns the top-k (k=3) sections by
cosine similarity from pgvector, each with its similarity score and full text.

### 4. Grounding integration — `eval/lib/build_request.py`

Add a `--rag` flag threaded through `eval/run.sh` → `build_request.py`. When set, `build_user()`
gains a new section:

```
## Retrieved guideline text (semantic search, top-3)
### 5.1.1 (similarity: 0.87)
<full section prose>
### 5.1.4 (similarity: 0.71)
...
```

placed before the "Report ONLY the single target check…" closing instruction. The query embedded
for retrieval is the check's table row + procedure block (same text already extracted from
`pierre-deep-review.md` for the prompt) — no new query-authoring step, reuses what
`build_request.py` already parses.

Ungrounded path is completely unchanged — this is a new code path selected by a flag, not a
rewrite of the existing one.

### 5. Measurement

`eval/run.sh` gains `--rag` alongside its existing `--model`/`--repeat`/`--baseline`. The existing
model/prompt mismatch guard (refuses to mix cache dirs) is extended with a third dimension (rag
on/off) so grounded and ungrounded runs never share a cache directory. Run both configurations
across all 21 labeled cases with the same model/repeat settings; `score.py` is unchanged — it
scores whatever cache dir it's pointed at.

Output: a comparison written by hand (not auto-generated) to `docs/rag-eval-results.md` after
human review of both scorecards — precision/recall/F1 per check and per tier, RAG vs baseline,
with particular attention to the 6 Tier B checks. Consistent with the project's standing rule:
no number is published without human confirmation; anything not run stays out of the doc rather
than being marked speculative.

## Out of scope

- `scan.sh`, verdict computation, GREEN/YELLOW/RED logic — untouched.
- Production `pierre-deep-review.md` agent-execution path (Claude Code/Codex/Cursor/Gemini running
  Pierre live) — grounding it would mean adding a retrieval step to the markdown procedure itself
  and giving the host agent a tool to call it; that's a separate, larger design if the eval
  results justify it, not part of this project.
- Shipping pgvector/Postgres/Voyage as a runtime dependency of the distributed CLI.
- Sub-section chunking, multi-vector retrieval, reranking — not justified at this corpus size;
  revisit only if the flat top-k similarity search proves insufficient in practice.

## Testing

- `eval/rag/ingest.sh`: unit-testable against a saved local HTML fixture (same pattern as
  `tests/test-guideline-drift.sh`), no network in tests.
- `embed.py`/`retrieve.py`: integration-tested against the local docker-compose pgvector instance
  (skipped/documented as requiring `docker compose up` + `VOYAGE_API_KEY`, not run in default CI).
- `build_request.py --rag`: unit test that the retrieved-text section is present/absent correctly
  per flag, using a stubbed `retrieve.py` response (no live pgvector needed for this test).
- The actual RAG-vs-baseline F1 comparison is a measurement run, not a pass/fail test — its output
  is a report, not an assertion.
