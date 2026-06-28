#!/usr/bin/env bash
# install.sh — vendor the appstore-precheck skill into a project for any agent host.
#
# Agent Skills is an open standard (https://agentskills.io): Claude Code, Codex, Cursor, and
# Gemini CLI all read a raw SKILL.md. They differ only in WHICH directory they scan. This script
# copies the skill into the right place(s).
#
# Usage:
#   ./install.sh [target] [scope]
#     target: all (default) | claude | codex | cursor | gemini
#     scope:  project (default, ./) | user (your home dir)
#
# Examples:
#   ./install.sh                 # install for every host, into the current project
#   ./install.sh claude user     # install only for Claude Code, into ~/.claude/skills
#   ./install.sh cursor          # install only for Cursor, into ./.agents/skills

set -euo pipefail

SKILL_NAME="appstore-precheck"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/skills/$SKILL_NAME" && pwd)"
TARGET="${1:-all}"
SCOPE="${2:-project}"

if [[ "$SCOPE" == "user" ]]; then BASE="$HOME"; else BASE="$(pwd)"; fi

# Neutral dir read by Codex + Cursor + Gemini; .claude/skills read by Claude Code (+ Cursor).
declare -a DIRS
case "$TARGET" in
  all)    DIRS=(".claude/skills" ".agents/skills") ;;
  claude) DIRS=(".claude/skills") ;;
  codex|cursor|gemini) DIRS=(".agents/skills") ;;
  *) echo "Unknown target '$TARGET' (use: all|claude|codex|cursor|gemini)"; exit 1 ;;
esac

echo "Installing '$SKILL_NAME' (scope: $SCOPE) from:"
echo "  $SRC"
for d in "${DIRS[@]}"; do
  dest="$BASE/$d/$SKILL_NAME"
  mkdir -p "$(dirname "$dest")"
  rm -rf "$dest"
  cp -R "$SRC" "$dest"
  echo "  → $dest"
done
echo "Done. Run the skill before submitting; the scanner is also runnable directly:"
echo "  bash $BASE/${DIRS[0]}/$SKILL_NAME/scripts/scan.sh"
