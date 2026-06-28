#!/usr/bin/env bash
# tests/test-guard.sh — unit tests for hooks/fastlane-guard.sh.
# The guard reads tool-use JSON on stdin, and blocks (exit 2) a fastlane submit
# command unless a fresh (<60 min) .precheck-pass token exists at the git root.
# Each case runs inside a throwaway git repo so the token state is controlled.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/_assert.sh
source "$DIR/_assert.sh"
GUARD="$DIR/../hooks/fastlane-guard.sh"

# A throwaway git repo is the guard's "repo root" (it uses git rev-parse).
REPO="$(mktemp -d)"
( cd "$REPO" && git init -q && git config user.email t@t.t && git config user.name t )
TOKEN="$REPO/.precheck-pass"

# guard_exit <json> — feed JSON on stdin from inside the repo, echo the exit code.
guard_exit() {
  local rc
  ( cd "$REPO" && printf '%s' "$1" | bash "$GUARD" >/dev/null 2>&1 )
  rc=$?
  echo "$rc"
}

DELIVER='{"tool_input":{"command":"bundle exec fastlane deliver --submit"}}'
PILOT='{"tool_input":{"command":"fastlane pilot upload"}}'
HARMLESS='{"tool_input":{"command":"ls -la && git status"}}'
NOCMD='{"tool_input":{}}'

section "non-fastlane command is ignored (allow)"
rm -f "$TOKEN"
assert_eq "$(guard_exit "$HARMLESS")" "0" "harmless command -> allow (exit 0)"

section "missing command field is ignored (allow)"
assert_eq "$(guard_exit "$NOCMD")" "0" "no command -> allow (exit 0)"

section "fastlane submit with NO token is blocked"
rm -f "$TOKEN"
assert_eq "$(guard_exit "$DELIVER")" "2" "deliver, no token -> block (exit 2)"

section "fastlane submit with a FRESH token is allowed"
touch "$TOKEN"   # mtime = now
assert_eq "$(guard_exit "$DELIVER")" "0" "deliver, fresh token -> allow (exit 0)"
assert_eq "$(guard_exit "$PILOT")"   "0" "pilot, fresh token -> allow (exit 0)"

section "fastlane submit with a STALE token (>60 min) is blocked"
touch -t 202001010000 "$TOKEN"   # Jan 1 2020 — far older than 60 min, GNU+BSD touch
assert_eq "$(guard_exit "$DELIVER")" "2" "deliver, stale token -> block (exit 2)"

section "guard message names Pierre on block"
rm -f "$TOKEN"
msg="$( ( cd "$REPO" && printf '%s' "$DELIVER" | bash "$GUARD" 2>&1 >/dev/null ) )"
assert_contains "$msg" "BLOCKED" "block message present"
assert_contains "$msg" "Non" "Pierre voice in block message"

rm -rf "$REPO"
echo
if (( fails == 0 )); then echo "test-guard: ALL PASSED"; else echo "test-guard: $fails FAILED"; fi
exit "$fails"
