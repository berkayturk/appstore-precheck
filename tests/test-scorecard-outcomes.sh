#!/usr/bin/env bash
# tests/test-scorecard-outcomes.sh — scorecard-outcomes.sh section rendering + honesty floor.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/_assert.sh
source "$ROOT/tests/_assert.sh"
SO="$ROOT/scripts/scorecard-outcomes.sh"

section "empty ledger -> no outcomes section, no rate"
tmp="$(mktemp -d)"; printf '[]\n' > "$tmp/l.json"
out="$(OUTCOMES_LEDGER="$tmp/l.json" bash "$SO")"
assert_contains "$out" "Real App Store outcomes (n=0)" "empty shows n=0 heading"
assert_contains "$out" "No real App Store outcomes recorded yet" "empty shows placeholder"
assert_absent "$out" "%" "no percentage when empty"
rm -rf "$tmp"

section "small ledger (n=3) -> raw tally, too-small note, no rate"
tmp="$(mktemp -d)"
cat > "$tmp/l.json" <<'JSON'
[
 {"outcome_label":"predicted-and-flagged","apple_decision":"rejected"},
 {"outcome_label":"missed","apple_decision":"rejected"},
 {"outcome_label":"approved-clean","apple_decision":"approved"}
]
JSON
out="$(OUTCOMES_LEDGER="$tmp/l.json" bash "$SO")"
assert_contains "$out" "Real App Store outcomes (n=3)" "n=3 heading"
assert_contains "$out" "too small to compute a meaningful rate" "too-small note present"
assert_absent "$out" "%" "no percentage below the floor"
assert_absent "$out" "Survivorship-bias" "no survivorship caveat below floor (no rate shown)"
rm -rf "$tmp"

section "at floor (n=10) -> tally + directional line + survivorship caveat"
tmp="$(mktemp -d)"
{
  echo "["
  for _ in $(seq 1 6); do echo "{\"outcome_label\":\"predicted-and-flagged\",\"apple_decision\":\"rejected\"},"; done
  for _ in $(seq 1 3); do echo "{\"outcome_label\":\"missed\",\"apple_decision\":\"rejected\"},"; done
  echo "{\"outcome_label\":\"approved-clean\",\"apple_decision\":\"approved\"}"
  echo "]"
} > "$tmp/l.json"
jq empty "$tmp/l.json"    # sanity: valid JSON
out="$(OUTCOMES_LEDGER="$tmp/l.json" bash "$SO")"
assert_contains "$out" "Real App Store outcomes (n=10)" "n=10 heading"
assert_contains "$out" "9 real rejections" "directional line counts rejections (6 flagged + 3 missed)"
assert_contains "$out" "Survivorship-bias caveat" "survivorship caveat present at/above floor"
rm -rf "$tmp"

if (( fails == 0 )); then echo "test-scorecard-outcomes: OK"; else echo "test-scorecard-outcomes: $fails FAILURE(S)"; exit 1; fi
