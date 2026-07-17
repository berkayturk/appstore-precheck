#!/usr/bin/env python3
"""retrieve.py — embed a query with the Gemini embeddings API and return the
top-k most similar guideline sections from the local pgvector 'sections' table.

Requires GEMINI_API_KEY and RAG_DATABASE_URL (see embed.py). Prints a JSON array
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
from pathlib import Path

from gemini_client import OUTPUT_DIMENSIONALITY, post_json, truncate_and_normalize

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))
from build_request import PIERRE_MD, extract_check_row, extract_procedure  # noqa: E402

GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-embedding-001:embedContent"
MODEL = "models/gemini-embedding-001"


def query_from_case(case_path):
    case = json.loads(Path(case_path).read_text(encoding="utf-8"))
    pierre_text = PIERRE_MD.read_text(encoding="utf-8")
    check_id = case["check_id"]
    return (extract_check_row(pierre_text, check_id) + "\n"
            + extract_procedure(pierre_text, check_id))


def build_gemini_query_request(query):
    return {
        "content": {"parts": [{"text": query}]},
        "embedContentConfig": {
            "taskType": "RETRIEVAL_QUERY",
            "outputDimensionality": OUTPUT_DIMENSIONALITY,
        },
    }


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


def extract_single_embedding(body):
    """The single (non-batch) embedContent endpoint returns a singular
    {"embedding": {"values": [...]}} shape — different from
    batchEmbedContents' plural {"embeddings": [{"values": [...]}]} (which
    embed.py consumes). Accept both defensively rather than assume one."""
    if "embedding" in body:
        return body["embedding"]["values"]
    if "embeddings" in body:
        return body["embeddings"][0]["values"]
    raise SystemExit(
        f"retrieve.py: unexpected Gemini response shape, no 'embedding'/'embeddings' "
        f"key: {list(body.keys())}"
    )


def fetch_query_embedding(query, api_key):
    body = post_json(GEMINI_URL, build_gemini_query_request(query), api_key, "retrieve.py")
    return truncate_and_normalize(extract_single_embedding(body))


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

    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        print("retrieve.py: GEMINI_API_KEY is not set", file=sys.stderr)
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
