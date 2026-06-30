#!/usr/bin/env bash
# tests/test-verdict.sh — verdict.sh threshold + token-action + exit-code assertions.
# Feeds synthetic scan output (no fixtures needed) so the GREEN/YELLOW/RED boundaries
# are pinned deterministically.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/_assert.sh
source "$DIR/_assert.sh"
VERDICT="$DIR/../skills/appstore-precheck/scripts/verdict.sh"

# gen <n_fail> <n_warn> <n_pass> — emit that many top-level FAIL/WARN/PASS lines,
# interleaved with indented evidence lines that must NOT be counted.
gen() {
  local nf="$1" nw="$2" np="$3" i
  for ((i = 0; i < nf; i++)); do echo "FAIL: synthetic fault $i"; echo "      indented evidence (must not count)"; done
  for ((i = 0; i < nw; i++)); do echo "WARN: synthetic warning $i"; done
  for ((i = 0; i < np; i++)); do echo "PASS: synthetic pass $i"; done
  echo "---END-OF-SCAN---"
}

# run_case <nf> <nw> <np> — capture verdict.sh stdout + exit code for a synthetic scan.
out=""; code=0
run_case() { out="$(gen "$1" "$2" "$3" | bash "$VERDICT")"; code=$?; }

section "GREEN — 0 FAIL, 0 WARN"
run_case 0 0 12
assert_contains "$out" "VERDICT: GREEN" "0F/0W is GREEN"
assert_contains "$out" "TOKEN: write"   "GREEN writes token"
assert_eq "$code" "0" "GREEN exit code 0"

section "GREEN — 0 FAIL, 4 WARN (upper boundary)"
run_case 0 4 5
assert_contains "$out" "VERDICT: GREEN" "0F/4W still GREEN"
assert_contains "$out" "COUNTS: fail=0 warn=4 pass=5" "counts correct"
assert_eq "$code" "0" "exit 0"

section "YELLOW — 0 FAIL, 5 WARN (lower boundary)"
run_case 0 5 5
assert_contains "$out" "VERDICT: YELLOW" "0F/5W tips to YELLOW"
assert_contains "$out" "TOKEN: hold"     "YELLOW holds token"
assert_eq "$code" "2" "YELLOW exit code 2"

section "RED — 1 FAIL overrides any WARN count"
run_case 1 0 5
assert_contains "$out" "VERDICT: RED"   "1F is RED"
assert_contains "$out" "TOKEN: remove"  "RED removes token"
assert_eq "$code" "1" "RED exit code 1"

section "RED — FAIL dominates even with many WARN"
run_case 2 9 1
assert_contains "$out" "VERDICT: RED" "FAIL beats WARN"
assert_contains "$out" "COUNTS: fail=2 warn=9 pass=1" "indented evidence not counted as FAIL"

section "--apply writes token on GREEN and removes on RED"
TMP="$(mktemp -d)"
( cd "$TMP" && gen 0 0 3 | bash "$VERDICT" --apply >/dev/null )
assert_eq "$([[ -f "$TMP/.precheck-pass" ]] && echo yes || echo no)" "yes" "GREEN --apply writes .precheck-pass"
( cd "$TMP" && gen 1 0 3 | bash "$VERDICT" --apply >/dev/null )
assert_eq "$([[ -f "$TMP/.precheck-pass" ]] && echo yes || echo no)" "no" "RED --apply removes .precheck-pass"
# YELLOW must NOT create a token
( cd "$TMP" && gen 0 5 3 | bash "$VERDICT" --apply >/dev/null )
assert_eq "$([[ -f "$TMP/.precheck-pass" ]] && echo yes || echo no)" "no" "YELLOW --apply holds (no token)"
rm -rf "$TMP"

section "reads from a file argument"
TMP="$(mktemp)"; gen 0 1 4 > "$TMP"
out="$(bash "$VERDICT" "$TMP")"
assert_contains "$out" "VERDICT: GREEN" "file-arg input parsed"
rm -f "$TMP"

echo
if (( fails == 0 )); then echo "test-verdict: ALL PASSED"; else echo "test-verdict: $fails FAILED"; fi
exit "$fails"
