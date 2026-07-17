"""gemini_client.py — shared Gemini embeddings HTTP client with 429 retry/backoff.

Used by embed.py (document embeddings) and retrieve.py (query embeddings) so the
rate-limit retry logic exists in exactly one place. Free-tier quota is per
minute, so a burst of requests (a 125-section corpus, or a full eval run
looping over cases) routinely hits 429 — this retries using the delay the API
itself recommends (google.rpc.RetryInfo), rather than a blind fixed backoff.
"""
import json
import sys
import time
import urllib.error
import urllib.request

MAX_RETRIES = 5
DEFAULT_RETRY_DELAY = 15.0
OUTPUT_DIMENSIONALITY = 1024  # matches schema.sql's VECTOR(1024)


def truncate_and_normalize(vector):
    """Matryoshka (MRL) truncation to OUTPUT_DIMENSIONALITY dims, then
    L2-normalize. gemini-embedding-001 supports requesting a smaller
    embedding directly via embedContentConfig.outputDimensionality, but in
    practice the API has been observed to ignore it and return the full
    native size (3072) regardless — this enforces the OUTPUT_DIMENSIONALITY
    contract client-side no matter what the API actually returns. Cosine
    distance (pgvector's `<=>` operator, used throughout this project) is
    scale-invariant, so normalizing here does not change similarity
    rankings — it only satisfies the model's documented requirement that
    truncated (non-native-size) embeddings be renormalized by the caller."""
    truncated = vector[:OUTPUT_DIMENSIONALITY]
    norm = sum(x * x for x in truncated) ** 0.5
    return [x / norm for x in truncated] if norm else truncated


def parse_retry_delay(error_body_json):
    """error_body_json: raw HTTPError response body (str) -> seconds to wait,
    read from the API's own RetryInfo detail when present, else
    DEFAULT_RETRY_DELAY."""
    try:
        body = json.loads(error_body_json)
        for detail in body.get("error", {}).get("details", []):
            if detail.get("@type", "").endswith("RetryInfo"):
                delay = detail.get("retryDelay", "")
                if delay.endswith("s"):
                    return float(delay[:-1])
    except (json.JSONDecodeError, ValueError, TypeError):
        pass
    return DEFAULT_RETRY_DELAY


def post_json(url, body, api_key, caller):
    """POST body as JSON to url with the Gemini API key header, retrying on 429
    up to MAX_RETRIES times using the API's advertised retry delay (+1s
    buffer). caller: label used in error/retry messages (e.g. "embed.py").
    Raises SystemExit with the API's error detail on a non-429 failure or
    once retries are exhausted."""
    data = json.dumps(body).encode("utf-8")
    for attempt in range(1, MAX_RETRIES + 1):
        req = urllib.request.Request(
            url, data=data,
            headers={"x-goog-api-key": api_key, "Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                return json.loads(resp.read())
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="replace")
            if exc.code != 429 or attempt == MAX_RETRIES:
                raise SystemExit(f"{caller}: Gemini API error {exc.code}: {detail}") from None
            delay = parse_retry_delay(detail) + 1
            print(f"{caller}: rate limited (429), retrying in {delay:.0f}s "
                  f"(attempt {attempt}/{MAX_RETRIES})", file=sys.stderr)
            time.sleep(delay)
