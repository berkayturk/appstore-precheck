#!/usr/bin/env bash
# scorecard-outcomes.sh — print the "Real App Store outcomes" markdown section from the committed
# outcomes ledger. Pure bash + jq, offline, deterministic. Because it reads a LOCAL committed ledger
# (no network, unlike --real), the section is safe to bake into the generated scorecard + --check.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LEDGER="${OUTCOMES_LEDGER:-$ROOT/corpus/outcomes/ledger.json}"
OUTCOMES_FLOOR=10

n=0
if [[ -f "$LEDGER" ]]; then
  n="$(jq 'length' "$LEDGER" 2>/dev/null || echo 0)"
  [[ "$n" =~ ^[0-9]+$ ]] || n=0
fi

echo "## Real App Store outcomes (n=$n)"
echo
echo "Real Apple review outcomes, independently labelled — distinct from the synthetic and real-panel"
echo "measurements above. Neither an approval nor a rejection here proves a finding's correctness in"
echo "general. See \`corpus/outcomes/README.md\`."
echo

if [[ "$n" -eq 0 ]]; then
  echo "_No real App Store outcomes recorded yet. This section populates as outcomes are contributed"
  echo "and reviewed (see \`corpus/outcomes/README.md\`)._"
  exit 0
fi

tally() { jq -r --arg l "$1" '[.[]|select(.outcome_label==$l)]|length' "$LEDGER"; }
pf="$(tally predicted-and-flagged)"
ms="$(tally missed)"
ac="$(tally approved-clean)"
aw="$(tally approved-with-warns-unaddressed)"

echo "| outcome | count |"
echo "|---|---|"
echo "| predicted-and-flagged (rejected; tool had flagged the cited guideline) | $pf |"
echo "| missed (rejected; tool had no finding for the cited guideline) | $ms |"
echo "| approved-clean (approved; 0 FAIL at submission) | $ac |"
echo "| approved-with-warns-unaddressed (approved; >=1 WARN present) | $aw |"
echo

if [[ "$n" -lt "$OUTCOMES_FLOOR" ]]; then
  echo "**n=$n is too small to compute a meaningful rate; shown for transparency only.**"
  exit 0
fi

rej=$((pf + ms))
echo "Across $rej real rejections, the tool had already flagged the cited guideline in **$pf** of them"
echo "(directional, not a guarantee)."
echo
echo "**Survivorship-bias caveat:** apps whose FAILs were fixed before submission never produce a"
echo "rejection record, so FAIL-severity choices cannot be validated here — only WARN/PASS-level"
echo "judgment, and only in the \"approved anyway\" direction."
