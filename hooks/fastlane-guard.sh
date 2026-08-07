#!/usr/bin/env bash
# Optional PreToolUse hook (Claude Code + Cursor + Grok Build plugin installs).
# Blocks `fastlane deliver/pilot/release` unless a fresh `.precheck-pass` token exists.
# stdin = tool-use JSON. exit 0 = allow, exit 2 = block.
#
# Hosts disagree on the envelope, and reading only one shape fails OPEN on the others:
#   Claude Code  .tool_input.command   (snake_case)
#   Grok Build   .toolInput.command    (camelCase throughout)
#   Cursor       .command              (top level, beforeShellExecution)
# On a block, stderr carries Pierre's message (Claude Code shows stderr to the model on
# exit 2) and stdout carries the same reason as JSON, because Grok documents stderr
# feedback only for Stop/SubagentStop and honours a stdout `deny` for PreToolUse.

set -u
CMD=$(jq -r '.tool_input.command // .toolInput.command // .command // empty' 2>/dev/null)
[[ -z "$CMD" ]] && exit 0

# Only trigger on fastlane submit/upload commands.
echo "$CMD" | grep -qE 'fastlane[[:space:]]+(deliver|pilot|release|upload_to_app_store|upload_to_testflight)' || exit 0

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
TOKEN="$ROOT/.precheck-pass"

if [[ -f "$TOKEN" ]] && [[ -n $(find "$TOKEN" -mmin -60 2>/dev/null) ]]; then
  exit 0
fi

REASON="Non. Pierre has not cleared this build: no fresh .precheck-pass token exists (or it is >60 min old). Run the appstore-precheck skill first; a GREEN verdict writes the token automatically."

cat >&2 <<EOF
BLOCKED: a fastlane submit command was attempted but no fresh .precheck-pass token exists (or it is >60 min old).

Non. Pierre has not cleared this build.

First run the appstore-precheck skill.

If it comes back GREEN, .precheck-pass is written automatically and this guard passes.
To bypass (not recommended — raises rejection risk): touch $TOKEN
EOF

# Machine-readable deny for hosts that read stdout: `.decision` (Grok, legacy Claude)
# and `.hookSpecificOutput` (current Claude Code PreToolUse schema).
jq -nc --arg r "$REASON" '{
  decision: "deny",
  reason: $r,
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $r
  }
}' 2>/dev/null || true

exit 2
