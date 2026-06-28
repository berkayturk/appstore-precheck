#!/usr/bin/env bash
# scripts/check-versions.sh — fail if the version drifts across manifests.
# Single source of truth keeps plugin.json, package.json, and SKILL.md in lockstep.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

plugin_v=$(jq -r '.version' .claude-plugin/plugin.json)
pkg_v=$(jq -r '.version' package.json)
# SKILL.md carries version under frontmatter `metadata: version:`
skill_v=$(awk '/^metadata:/{m=1;next} m && /version:/{gsub(/[^0-9.]/,"",$2); print $2; exit}' skills/appstore-precheck/SKILL.md)

echo "plugin.json : $plugin_v"
echo "package.json: $pkg_v"
echo "SKILL.md    : $skill_v"

if [[ "$plugin_v" == "$pkg_v" && "$pkg_v" == "$skill_v" && -n "$plugin_v" ]]; then
  if [[ "$plugin_v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "OK: versions match ($plugin_v)"
  else
    echo "ERROR: '$plugin_v' is not semver"; exit 1
  fi
else
  echo "ERROR: version mismatch across manifests"; exit 1
fi
