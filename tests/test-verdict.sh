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

# PRO line: printed last, only on RED/YELLOW, and only when none of the three opt-out
# channels is set. Every case clears CI explicitly — GitHub Actions exports CI=true,
# which is itself one of the opt-outs.
PROMO="PRO: Rejected after all? Paste Apple's message into https://precheck.blitzcortex.com for a resubmission check."

section "promo — RED prints the PRO line as the last stdout line"
out="$(gen 1 0 5 | env -u CI bash "$VERDICT")"
assert_eq "$(printf '%s\n' "$out" | tail -n1)" "$PROMO" "RED prints promo last"

section "promo — YELLOW prints the PRO line"
out="$(gen 0 5 5 | env -u CI bash "$VERDICT")"
assert_contains "$out" "$PROMO" "YELLOW prints promo"

section "promo — GREEN never prints it"
out="$(gen 0 4 5 | env -u CI bash "$VERDICT")"
assert_absent "$out" "PRO:" "GREEN has no promo"

section "promo — --no-promo suppresses"
out="$(gen 1 0 5 | env -u CI bash "$VERDICT" --no-promo)"
assert_absent "$out" "PRO:" "--no-promo suppresses"

section "promo — PRECHECK_NO_PROMO=1 / true suppress, 0 keeps"
out="$(gen 1 0 5 | env -u CI PRECHECK_NO_PROMO=1 bash "$VERDICT")"
assert_absent "$out" "PRO:" "env 1 suppresses"
out="$(gen 1 0 5 | env -u CI PRECHECK_NO_PROMO=true bash "$VERDICT")"
assert_absent "$out" "PRO:" "env true suppresses"
out="$(gen 1 0 5 | env -u CI PRECHECK_NO_PROMO=0 bash "$VERDICT")"
assert_contains "$out" "PRO:" "env 0 keeps promo"

section "promo — CI set (even empty) suppresses"
out="$(gen 1 0 5 | env CI= bash "$VERDICT")"
assert_absent "$out" "PRO:" "empty CI suppresses"
out="$(gen 1 0 5 | env CI=true bash "$VERDICT")"
assert_absent "$out" "PRO:" "CI=true suppresses"

section "promo — file argument path prints it too"
TMP="$(mktemp)"; gen 1 0 5 > "$TMP"
out="$(env -u CI bash "$VERDICT" "$TMP")"
assert_contains "$out" "$PROMO" "file arg prints promo"
rm -f "$TMP"

section "promo — counts and exit code unchanged"
out="$(gen 1 0 5 | env -u CI bash "$VERDICT")"; code=$?
assert_contains "$out" "COUNTS: fail=1 warn=0 pass=5" "counts unchanged"
assert_eq "$code" "1" "RED exit 1 unchanged"

echo
if (( fails == 0 )); then echo "test-verdict: ALL PASSED"; else echo "test-verdict: $fails FAILED"; fi
exit "$fails"
