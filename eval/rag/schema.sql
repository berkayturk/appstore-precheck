-- eval/rag/schema.sql — pgvector schema for the RAG-grounded Pierre eval experiment.
-- Applied automatically by docker-compose.yml on first container start
-- (docker-entrypoint-initdb.d). One chunk per guideline section — see the design
-- spec (docs/specs/2026-07-17-rag-grounded-pierre-eval-design.md) for why no
-- sub-splitting.

CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE IF NOT EXISTS sections (
  section_number TEXT PRIMARY KEY,
  text TEXT NOT NULL,
  embedding VECTOR(1024)  -- gemini-embedding-001, truncated via outputDimensionality
);

-- HNSW index: not a performance necessity at ~130 rows, included for realism/
-- practice with pgvector's indexing story (explicitly noted, not silently assumed).
CREATE INDEX IF NOT EXISTS sections_embedding_hnsw
  ON sections USING hnsw (embedding vector_cosine_ops);
