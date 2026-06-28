#!/usr/bin/env bash
# Optional Claude Code PreToolUse hook.
# Blocks `fastlane deliver/pilot/release` unless a fresh `.precheck-pass` token exists.
# stdin = tool-use JSON. exit 0 = allow, exit 2 = block (stderr is shown to the model).

set -u
CMD=$(jq -r '.tool_input.command // empty' 2>/dev/null)
[[ -z "$CMD" ]] && exit 0

# Only trigger on fastlane submit/upload commands.
echo "$CMD" | grep -qE 'fastlane[[:space:]]+(deliver|pilot|release|upload_to_app_store|upload_to_testflight)' || exit 0

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
TOKEN="$ROOT/.precheck-pass"

if [[ -f "$TOKEN" ]] && [[ -n $(find "$TOKEN" -mmin -60 2>/dev/null) ]]; then
  exit 0
fi

cat >&2 <<EOF
BLOCKED: a fastlane submit command was attempted but no fresh .precheck-pass token exists (or it is >60 min old).

Non. Pierre has not cleared this build.

First run the appstore-precheck skill.

If it comes back GREEN, .precheck-pass is written automatically and this guard passes.
To bypass (not recommended — raises rejection risk): touch $TOKEN
EOF
exit 2
