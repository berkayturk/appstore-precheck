#!/usr/bin/env bash
# tests/test-scorecard.sh — scorecard.sh metric math (--selftest) + --check staleness
# detection + honesty caveat presence in the generated docs/scorecard.md.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/_assert.sh
source "$ROOT/tests/_assert.sh"

# metric math on a tiny known corpus
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/corpus/synthetic"
# a 2-fixture stub with a deterministic scanner stub is overkill; instead test the
# pure metric function directly via scorecard.sh's --selftest hook:
out="$(bash "$ROOT/scripts/scorecard.sh" --selftest)"
assert_contains "$out" "precision=1.00" "selftest precision computed"
assert_contains "$out" "recall=0.50" "selftest recall computed"

# --check detects a stale scorecard
cp "$ROOT/docs/scorecard.md" "$tmp/good.md"
trap 'cp "$tmp/good.md" "$ROOT/docs/scorecard.md" 2>/dev/null; rm -rf "$tmp"' EXIT
printf '\nstale-marker\n' >> "$ROOT/docs/scorecard.md"
if bash "$ROOT/scripts/scorecard.sh" --check >/dev/null 2>&1; then rc=0; else rc=1; fi
cp "$tmp/good.md" "$ROOT/docs/scorecard.md"     # restore
assert_eq "$rc" "1" "--check fails on a stale scorecard"

# honesty caveat present
assert_contains "$(cat "$ROOT/docs/scorecard.md")" "Apple's actual review decisions" "honesty caveat present"

if (( fails == 0 )); then
  echo "test-scorecard: OK"
else
  echo "test-scorecard: $fails FAILURE(S)"
  exit 1
fi
