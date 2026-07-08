#!/usr/bin/env bash
# appstore-precheck/scripts/verdict.sh
# Deterministic verdict from scan.sh output. Reads scan output on stdin (or a file
# arg), counts top-level FAIL:/WARN:/PASS: lines, and decides GREEN/YELLOW/RED plus
# the .precheck-pass token action — so the verdict is machine-testable, not just an
# agent judgement.
#
#   GREEN   0 FAIL and <=4 WARN   -> token: write
#   YELLOW  0 FAIL and >=5 WARN   -> token: hold  (needs explicit human confirmation)
#   RED     >=1 FAIL              -> token: remove
#
# Usage:
#   bash scan.sh | bash verdict.sh            # compute only, print summary
#   bash verdict.sh scan-output.txt           # read from a file instead of stdin
#   bash scan.sh | bash verdict.sh --apply    # also write/remove the token
#
# Output (stdout), stable and grep-friendly:
#   VERDICT: GREEN|YELLOW|RED
#   COUNTS: fail=<n> warn=<n> pass=<n>
#   TOKEN: write|hold|remove
# Exit code: 0 GREEN, 1 RED, 2 YELLOW (so callers can branch without parsing).

set -u

APPLY="false"
SRC=""
for arg in "$@"; do
  case "$arg" in
    --apply) APPLY="true" ;;
    -*) echo "verdict.sh: unknown option '$arg'" >&2; exit 64 ;;
    *)  SRC="$arg" ;;
  esac
done

# Read the scan output from the file arg if given, else from stdin.
if [[ -n "$SRC" ]]; then
  [[ -f "$SRC" ]] || { echo "verdict.sh: no such file '$SRC'" >&2; exit 66; }
  input="$(cat "$SRC")"
else
  input="$(cat)"
fi

# Count only TOP-LEVEL verdict lines (anchored at column 0). scan.sh indents the
# evidence under a FAIL: header, so anchoring avoids double-counting those.
count() { printf '%s\n' "$input" | grep -cE "$1"; }
fails=$(count '^FAIL:')
warns=$(count '^WARN:')
passes=$(count '^PASS:')

# Thresholds live in thresholds.sh (shared with findings.sh's JSON renderer).
# shellcheck source=thresholds.sh
. "$(dirname "${BASH_SOURCE[0]}")/thresholds.sh"

if (( fails >= RED_FAIL_MIN )); then
  verdict="RED";    token="remove"; code=1
elif (( warns >= YELLOW_WARN_MIN )); then
  verdict="YELLOW"; token="hold";   code=2
else
  verdict="GREEN";  token="write";  code=0
fi

echo "VERDICT: $verdict"
echo "COUNTS: fail=$fails warn=$warns pass=$passes"
echo "TOKEN: $token"

# Side effects only with --apply. The token lives at the repo root; the guard hook
# tests it with an mmin -60 filter. YELLOW deliberately leaves the token untouched —
# writing it is a human-confirmation step the agent performs, not this script.
if [[ "$APPLY" == "true" ]]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || ROOT="$(pwd)"
  TOKEN_FILE="$ROOT/.precheck-pass"
  case "$token" in
    write)  date +%s > "$TOKEN_FILE" && echo "APPLIED: token written ($TOKEN_FILE)" ;;
    remove) rm -f "$TOKEN_FILE"       && echo "APPLIED: token removed" ;;
    hold)   echo "APPLIED: token held (YELLOW needs explicit confirmation)" ;;
  esac
fi

exit "$code"
