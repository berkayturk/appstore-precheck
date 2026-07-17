#!/usr/bin/env python3
"""embed.py — embed eval/rag/corpus/sections.json with the Gemini embeddings API
and load into the local pgvector 'sections' table via psql.

Requires GEMINI_API_KEY in the environment (read at request time, never logged,
never written to disk) and RAG_DATABASE_URL pointing at the pgvector instance
started by eval/rag/docker-compose.yml.

Usage: embed.py [--corpus path] [--dry-run]
  --dry-run   print the generated SQL to stdout instead of calling Gemini/psql
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
GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-embedding-001:batchEmbedContents"
MODEL = "models/gemini-embedding-001"
OUTPUT_DIMENSIONALITY = 1024  # matches schema.sql's VECTOR(1024)


def load_corpus(path):
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    return data["sections"]


def build_gemini_request(texts):
    """texts: list[str] -> Gemini batchEmbedContents request body."""
    return {
        "requests": [
            {
                "model": MODEL,
                "content": {"parts": [{"text": text}]},
                "embedContentConfig": {
                    "taskType": "RETRIEVAL_DOCUMENT",
                    "outputDimensionality": OUTPUT_DIMENSIONALITY,
                },
            }
            for text in texts
        ]
    }


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
        GEMINI_URL,
        data=json.dumps(build_gemini_request(texts)).encode("utf-8"),
        headers={"x-goog-api-key": api_key, "Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        body = json.loads(resp.read())
    return [item["values"] for item in body["embeddings"]]


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

    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        print("embed.py: GEMINI_API_KEY is not set", file=sys.stderr)
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
