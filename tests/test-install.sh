#!/usr/bin/env bash
# tests/test-install.sh — smoke tests for install.sh. Verifies the skill lands in the
# right per-host directories of a throwaway project, that single-host installs are
# scoped, and that an unknown target fails loudly.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/_assert.sh
source "$DIR/_assert.sh"
INSTALL="$DIR/../install.sh"
SKILL="appstore-precheck"

# present <base> <reldir> — "yes" if the skill (with its scanner) installed under reldir.
present() {
  if [[ -f "$1/$2/$SKILL/SKILL.md" && -f "$1/$2/$SKILL/scripts/scan.sh" ]]; then
    echo yes
  else
    echo no
  fi
}

section "install all -> both .claude/skills and .agents/skills"
P="$(mktemp -d)"
( cd "$P" && bash "$INSTALL" all project >/dev/null )
assert_eq "$(present "$P" ".claude/skills")" "yes" "Claude Code dir populated"
assert_eq "$(present "$P" ".agents/skills")" "yes" "neutral .agents/skills dir populated"
rm -rf "$P"

section "install claude -> only .claude/skills"
P="$(mktemp -d)"
( cd "$P" && bash "$INSTALL" claude project >/dev/null )
assert_eq "$(present "$P" ".claude/skills")" "yes" "Claude Code dir populated"
assert_eq "$(present "$P" ".agents/skills")" "no"  ".agents/skills left untouched"
rm -rf "$P"

section "install codex -> only .agents/skills"
P="$(mktemp -d)"
( cd "$P" && bash "$INSTALL" codex project >/dev/null )
assert_eq "$(present "$P" ".agents/skills")" "yes" "neutral dir populated"
assert_eq "$(present "$P" ".claude/skills")" "no"  ".claude/skills left untouched"
rm -rf "$P"

section "installed scanner actually runs"
P="$(mktemp -d)"
( cd "$P" && bash "$INSTALL" all project >/dev/null )
out="$( cd "$P" && APPSTORE_PRECHECK_CONFIG=/nonexistent bash ".claude/skills/$SKILL/scripts/scan.sh" 2>&1 )"
assert_contains "$out" "---END-OF-SCAN---" "installed scan.sh runs to completion"
rm -rf "$P"

section "unknown target fails loudly"
P="$(mktemp -d)"
rc=0
( cd "$P" && bash "$INSTALL" bogus project >/dev/null 2>&1 ) || rc=$?
assert_eq "$( (( rc != 0 )) && echo nonzero || echo zero )" "nonzero" "unknown target exits non-zero"
rm -rf "$P"

echo
if (( fails == 0 )); then echo "test-install: ALL PASSED"; else echo "test-install: $fails FAILED"; fi
exit "$fails"
