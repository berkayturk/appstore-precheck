#!/usr/bin/env bash
# test-eval-score.sh — eval/score.py metric math on a fixed synthetic run:
# known labels + recorded verdicts -> known precision/recall/F1, Tier-B FP rate,
# consistency, UNLABELED handling. No network, no real dataset dependence.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
# shellcheck source=tests/_assert.sh
source "$DIR/_assert.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
DATASET="$TMP/dataset"; RUN="$TMP/run"
mkdir -p "$DATASET/cases" "$RUN"

mk_case() { # mk_case <id> <check_id> <tier> <expected> <confirmed>
  cat > "$DATASET/cases/$1.json" <<EOF
{"id":"$1","check_id":$2,"tier":"$3","guideline":"9.9","expected":"$4",
 "rationale":"synthetic test case for scorer math","label_confirmed":$5,
 "fixture":"fixtures/$1/"}
EOF
}

mk_reps() { # mk_reps <id> <verdict1> <verdict2> <verdict3>
  local id="$1"; shift
  mkdir -p "$RUN/$id"
  local i=1 line
  for verdict in "$@"; do
    case "$verdict" in
      finding) line="REVIEW-FINDING: 9.9 WARN — synthetic" ;;
      pass)    line="REVIEW-PASS: 9.9 — synthetic clean" ;;
      na)      line="REVIEW-PASS: 9.9 — not applicable (synthetic)" ;;
    esac
    jq -n --arg t "$line" \
      '{stop_reason:"end_turn",content:[{type:"text",text:$t}]}' \
      > "$RUN/$id/rep$i.json"
    i=$((i + 1))
  done
}

# Fixed corpus: TP + FP on Tier B, FN + TN on Tier A, one UNLABELED.
mk_case check05-tp 5 B finding true;  mk_reps check05-tp finding finding finding
mk_case check05-fp 5 B pass true;     mk_reps check05-fp finding finding pass
mk_case check03-fn 3 A finding true;  mk_reps check03-fn pass pass pass
mk_case check18-tn 18 A pass true;    mk_reps check18-tn na na na
mk_case check07-un 7 B pass false;    mk_reps check07-un pass pass pass

jq -n '{model:"claude-test",max_tokens:1024,thinking:"disabled",effort:"low",
        repeat:3,cases_glob:"*",dataset_sha256:"deadbeefdeadbeefdeadbeef",
        run_date:"2026-01-01T00:00:00Z",api:"test",generator:"test"}' \
  > "$RUN/manifest.json"

card="$(python3 "$ROOT/eval/score.py" --run "$RUN" --dataset "$DATASET")"

section "aggregate metrics (TP=1 FP=1 FN=1 TN=1)"
assert_contains "$card" "| all | 4 | 1 | 1 | 1 | 1 | 0.50 | 0.50 | 0.50 |" \
  "all-tier row: precision/recall/F1 = 0.50"
assert_contains "$card" "| A (high-confidence) | 2 | 0 | 0 | 1 | 1 | 1.00 | 0.00 | 0.00 |" \
  "Tier-A row: FN drives recall to 0.00"
assert_contains "$card" "| B (heuristic) | 2 | 1 | 1 | 0 | 0 | 0.50 | 1.00 | 0.67 |" \
  "Tier-B row: 1 TP + 1 FP"

section "Tier-B FP rate and consistency"
assert_contains "$card" "**Tier-B false-positive rate:** 1.00 (1 FP over 1 clean Tier-B case(s))" \
  "Tier-B FP rate = FP/(FP+TN) with counts shown"
assert_contains "$card" "**Consistency:** 3/4 case(s) unanimous across 3 repeats (0.75)" \
  "consistency = unanimous share, majority vote flagged"
assert_contains "$card" "Non-unanimous cases (majority used for scoring): \`check05-fp\`" \
  "non-unanimous case is flagged by id"

section "UNLABELED and not-applicable handling"
assert_contains "$card" "4 scored, 1 UNLABELED" "unconfirmed label counted as UNLABELED"
assert_contains "$card" "| 7 | B | 9.9 | check07-un | pass | UNLABELED |" \
  "UNLABELED case shown in breakdown, not folded into metrics"
assert_contains "$card" "| 18 | A | 9.9 | check18-tn | pass | not-applicable |" \
  "predicted not-applicable counts as negative (TN), shown verbatim"

section "--check gate"
out="$(cd "$ROOT" && python3 eval/score.py --check 2>&1)"; rc=$?
assert_eq "$rc" "0" "--check exits 0 against the committed scorecard"
if [ -d "$ROOT/eval/baseline" ] && [ -n "$(ls -A "$ROOT/eval/baseline" 2>/dev/null)" ]; then
  assert_contains "$out" "Tier-A F1" "--check reports the Tier-A F1 floor when a baseline exists"
  n_baselines="$(find "$ROOT/eval/baseline" -mindepth 2 -maxdepth 2 -name manifest.json | wc -l | tr -d ' ')"
  assert_contains "$out" "$n_baselines baseline(s) at or above the floor" \
    "--check gates every committed baseline, not just the newest"
  assert_contains "$(cat "$ROOT/docs/llm-scorecard.md")" "## Model comparison" \
    "committed card carries the model comparison table"
else
  assert_contains "$out" "floor inactive" "--check reports inactive floor without a baseline"
fi

section "run.sh model-mismatch guard"
# A cache dir produced with one model must not be resumed with another:
# the guard fires before any request is built, so no key/network is needed.
GUARD="$TMP/guard"; mkdir -p "$GUARD"
jq -n '{model:"claude-test"}' > "$GUARD/manifest.json"
out="$(ANTHROPIC_API_KEY=dummy bash "$ROOT/eval/run.sh" \
  --out "$GUARD" --model claude-other 2>&1)"; rc=$?
assert_eq "$rc" "1" "run.sh exits 1 when the cache dir holds another model's run"
assert_contains "$out" "refusing to mix models" "guard names the conflict"

section "floor enforcement"
# Against the synthetic run the Tier-A F1 is 0.00 -> a 0.80 floor must fail.
# --check needs a matching card on disk; emulate by scoring in a sandbox repo? No:
# tier_a_f1 is exercised through --run/--dataset via a direct python call instead.
f1="$(cd "$ROOT" && python3 - "$RUN" "$DATASET" <<'EOF'
import sys
sys.path.insert(0, "eval")
from pathlib import Path
import score
f1, n = score.tier_a_f1(Path(sys.argv[1]), Path(sys.argv[2]))
print(f"{f1:.2f}/{n}")
EOF
)"
assert_eq "$f1" "0.00/2" "tier_a_f1 helper: F1 0.00 over 2 Tier-A cases"

exit "$fails"
