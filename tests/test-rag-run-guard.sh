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
