#!/usr/bin/env bash
# test-eval-parse.sh — eval/lib/parse_verdict.py verdict extraction from recorded
# Pierre-style API responses, plus a build_request.py smoke test. No network.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
# shellcheck source=tests/_assert.sh
source "$DIR/_assert.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

parse() { # parse <response-json> -> verdict
  printf '%s' "$1" > "$TMP/resp.json"
  python3 "$ROOT/eval/lib/parse_verdict.py" "$TMP/resp.json" | jq -r '.verdict'
}

section "parse_verdict.py"

v="$(parse '{"stop_reason":"end_turn","content":[{"type":"text","text":"REVIEW-FINDING: 2.2 WARN — store copy says beta (release_notes.txt:1)\nPierre: Apple rejects unfinished builds."}]}')"
assert_eq "$v" "finding" "REVIEW-FINDING line -> finding"

v="$(parse '{"stop_reason":"end_turn","content":[{"type":"text","text":"REVIEW-PASS: 2.3.9 — system requestReview only, no incentive copy (ReviewPrompter.swift:9)"}]}')"
assert_eq "$v" "pass" "REVIEW-PASS line -> pass"

v="$(parse '{"stop_reason":"end_turn","content":[{"type":"text","text":"REVIEW-PASS: 2.1 — not applicable (no login UI or account wall)"}]}')"
assert_eq "$v" "not-applicable" "REVIEW-PASS ... not applicable -> not-applicable"

v="$(parse '{"stop_reason":"end_turn","content":[{"type":"text","text":"Looking at the project I see a task list app."}]}')"
assert_eq "$v" "unparseable" "no REVIEW line -> unparseable"

v="$(parse '{"stop_reason":"refusal","content":[]}')"
assert_eq "$v" "unparseable" "refusal stop_reason -> unparseable"

v="$(parse '{"stop_reason":"end_turn","content":[{"type":"text","text":"Here is my analysis first.\n\nREVIEW-FINDING: 2.3.9 WARN — 5-star incentive on paywall (PaywallView.swift:11)"}]}')"
assert_eq "$v" "finding" "REVIEW line after preamble text still parsed"

section "build_request.py"

req="$(python3 "$ROOT/eval/lib/build_request.py" \
  "$ROOT/eval/dataset/cases/check05-beta-in-release-notes.json" claude-sonnet-5 1024)"
assert_eq "$(jq -r '.model' <<<"$req")" "claude-sonnet-5" "model pinned in request body"
assert_eq "$(jq -r '.thinking.type' <<<"$req")" "disabled" "thinking disabled"
assert_contains "$(jq -r '.messages[0].content' <<<"$req")" "public beta" "fixture content embedded"
assert_contains "$(jq -r '.messages[0].content' <<<"$req")" "### 5 — 2.2 Beta / test language" "target check procedure embedded"
assert_absent "$(jq -r '.messages[0].content' <<<"$req")" "### 4 — 2.1 Review notes" "other checks' procedures not embedded"

exit "$fails"
