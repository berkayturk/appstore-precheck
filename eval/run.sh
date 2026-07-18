#!/usr/bin/env bash
# run.sh — call the Anthropic Messages API for each eval case and cache raw responses.
#   --model <id>     model to pin (default claude-sonnet-5)
#   --repeat <N>     repeats per case for the consistency metric (default 3)
#   --cases <glob>   case-file basename glob, e.g. 'check05-*' (default all)
#   --out <dir>      output dir (default eval/runs/<UTC timestamp>)
#   --baseline       shorthand: write to eval/baseline/<UTC date>-<model> (commit this dir)
#
# Requires ANTHROPIC_API_KEY in the environment (read at request time, never
# logged, never written to disk). Scoring is offline: eval/score.py re-reads the
# cached responses, so re-scoring never re-bills.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CASES_DIR="$ROOT/eval/dataset/cases"
API_URL="https://api.anthropic.com/v1/messages"

MODEL="claude-sonnet-5"
REPEAT=3
GLOB="*"
OUT=""
BASELINE=0
MAX_TOKENS=1024
RAG=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model)    MODEL="$2"; shift 2 ;;
    --repeat)   REPEAT="$2"; shift 2 ;;
    --cases)    GLOB="$2"; shift 2 ;;
    --out)      OUT="$2"; shift 2 ;;
    --baseline) BASELINE=1; shift ;;
    --rag)      RAG=1; shift ;;
    *) echo "run.sh: unknown arg '$1'" >&2; exit 64 ;;
  esac
done
# Resolved after parsing so --baseline picks up a --model given in any order.
# The model is part of the dir name so two models can never share a cache dir.
[[ $BASELINE -eq 1 && -z "$OUT" ]] && OUT="$ROOT/eval/baseline/$(date -u +%F)-$MODEL$([[ $RAG -eq 1 ]] && echo "-rag")"
[[ -z "$OUT" ]] && OUT="$ROOT/eval/runs/$(date -u +%Y%m%dT%H%M%SZ)"

# Fable/Mythos-tier models have always-on thinking: build_request.py omits the
# thinking field for them (explicit config is a 400), and their thinking tokens
# draw from max_tokens, so the budget needs headroom. The manifest records both.
case "$MODEL" in
  claude-fable*|claude-mythos*) THINKING="always-on (model default)"; MAX_TOKENS=8192 ;;
  *)                            THINKING="disabled" ;;
esac

[[ -n "${ANTHROPIC_API_KEY:-}" ]] || {
  echo "run.sh: ANTHROPIC_API_KEY is not set (export it; it is never logged)" >&2
  exit 1; }
command -v jq >/dev/null 2>&1 || { echo "run.sh: jq is required" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "run.sh: python3 is required" >&2; exit 1; }
[[ "$REPEAT" =~ ^[0-9]+$ && "$REPEAT" -ge 1 ]] || {
  echo "run.sh: --repeat must be a positive integer" >&2; exit 64; }
(( REPEAT % 2 == 1 )) || echo "run.sh: note — even --repeat can produce majority ties" >&2

bash "$ROOT/eval/validate.sh" >/dev/null || {
  echo "run.sh: dataset validation failed — fix cases before running" >&2; exit 1; }

mkdir -p "$OUT"

# Fingerprints: the dataset hash pins what was measured, the prompt hash pins
# which pierre-deep-review.md the requests were built from — a prompt edit
# invalidates cached responses, and the manifest must make that visible.
dataset_sha="$(cd "$ROOT/eval/dataset" && find . -type f ! -name .DS_Store -print0 \
  | sort -z | xargs -0 shasum -a 256 | shasum -a 256 | awk '{print $1}')"
prompt_sha="$(shasum -a 256 \
  "$ROOT/skills/appstore-precheck/references/pierre-deep-review.md" | awk '{print $1}')"

# Resume guard: cached rep files are only reusable if they were produced with
# the same model AND the same prompt. Refuse to mix rather than silently skip
# or mislabel (a missing prompt fingerprint counts as a different prompt).
if [[ -s "$OUT/manifest.json" ]]; then
  prev_model="$(jq -r '.model' "$OUT/manifest.json")"
  if [[ "$prev_model" != "$MODEL" ]]; then
    echo "run.sh: $OUT already holds a $prev_model run — refusing to mix models in one cache dir (use --out <fresh dir>)" >&2
    exit 1
  fi
  prev_prompt="$(jq -r '.prompt_sha256 // "unrecorded"' "$OUT/manifest.json")"
  if [[ "$prev_prompt" != "$prompt_sha" ]]; then
    echo "run.sh: $OUT was produced with a different pierre-deep-review.md (prompt sha $prev_prompt) — refusing to mix prompt versions (use --out <fresh dir>)" >&2
    exit 1
  fi
  prev_rag="$(jq -r '.rag // false' "$OUT/manifest.json")"
  want_rag="$([[ $RAG -eq 1 ]] && echo true || echo false)"
  if [[ "$prev_rag" != "$want_rag" ]]; then
    echo "run.sh: $OUT was produced with rag=$prev_rag — refusing to mix grounded/ungrounded runs (use --out <fresh dir>)" >&2
    exit 1
  fi
fi

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

total=0; failed=0
for case_file in "$CASES_DIR"/$GLOB.json; do
  [[ -e "$case_file" ]] || { echo "run.sh: no cases match '$GLOB'" >&2; exit 1; }
  case_id="$(basename "$case_file" .json)"
  mkdir -p "$OUT/$case_id"
  req="$(mktemp)"
  if [[ $RAG -eq 1 ]]; then
    retrieved_file="$OUT/$case_id/retrieved.json"
    python3 "$ROOT/eval/rag/retrieve.py" --case "$case_file" --top-k 3 > "$retrieved_file" || {
      echo "run.sh: retrieval failed for $case_id" >&2; rm -f "$req"; exit 1; }
    python3 "$ROOT/eval/lib/build_request.py" "$case_file" "$MODEL" "$MAX_TOKENS" \
      --retrieved "$retrieved_file" > "$req" || {
      echo "run.sh: request build failed for $case_id" >&2; rm -f "$req"; exit 1; }
  else
    python3 "$ROOT/eval/lib/build_request.py" "$case_file" "$MODEL" "$MAX_TOKENS" > "$req" || {
      echo "run.sh: request build failed for $case_id" >&2; rm -f "$req"; exit 1; }
  fi
  rep=1
  while [[ $rep -le $REPEAT ]]; do
    out_file="$OUT/$case_id/rep$rep.json"
    if [[ -s "$out_file" ]]; then         # cached from an interrupted run — skip
      rep=$((rep + 1)); continue
    fi
    total=$((total + 1))
    http_code="$(curl -sS -o "$out_file" -w '%{http_code}' \
      --max-time 120 --retry 2 --retry-delay 5 \
      -H "x-api-key: $ANTHROPIC_API_KEY" \
      -H "anthropic-version: 2023-06-01" \
      -H "content-type: application/json" \
      --data-binary @"$req" "$API_URL")" || http_code="000"
    if [[ "$http_code" != "200" ]]; then
      failed=$((failed + 1))
      echo "run.sh: $case_id rep$rep HTTP $http_code: $(jq -r '.error.message? // "network error"' "$out_file" 2>/dev/null)" >&2
      rm -f "$out_file"                    # never cache a non-200 body as a result
    else
      verdict="$(python3 "$ROOT/eval/lib/parse_verdict.py" "$out_file" | jq -r '.verdict')"
      echo "run.sh: $case_id rep$rep -> $verdict"
    fi
    rep=$((rep + 1))
  done
  rm -f "$req"
done

echo "run.sh: wrote $OUT (requests: $total, failed: $failed)"
[[ $failed -eq 0 ]] || exit 1
