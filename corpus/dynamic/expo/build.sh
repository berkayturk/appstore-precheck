#!/usr/bin/env bash
# Expo source is checked in; npm lock/prebuild happen only in a temp stage.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
VARIANT="${1:-}"
[[ "$VARIANT" == clean || "$VARIANT" == broken ]] || { echo "usage: $0 clean|broken [build-run options]" >&2; exit 64; }
shift
if ! command -v npm >/dev/null 2>&1 || ! command -v npx >/dev/null 2>&1; then
  echo "SKIP: Expo bootstrap needs Node.js, npm, and npx"
  exit 3
fi
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/precheck-expo-corpus.XXXXXX")" || exit 3
trap 'rm -rf "$STAGE"' EXIT
export npm_config_fetch_retries=0 npm_config_fetch_timeout=15000 npm_config_cache="$STAGE/npm-cache"
if ! (cd "$STAGE" && npx --yes create-expo-app@latest project --template blank --no-install --no-agents-md >/dev/null 2>&1); then
  echo "SKIP: Expo blank template unavailable; install Node.js and allow npm registry access"
  exit 3
fi
cp "$HERE/$VARIANT/App.js" "$HERE/$VARIANT/app.json" "$STAGE/project/"
if [[ -d "$HERE/$VARIANT/plugins" ]]; then
  cp -R "$HERE/$VARIANT/plugins" "$STAGE/project/"
fi
if ! (cd "$STAGE/project" && npm pkg set 'dependencies.expo-camera=*' >/dev/null 2>&1); then
  echo "SKIP: Expo package metadata could not be prepared"
  exit 3
fi
if ! (cd "$STAGE/project" && npm install --package-lock-only --ignore-scripts --no-audit --no-fund >/dev/null 2>&1); then
  echo "SKIP: Expo dependency lock could not be resolved from npm"
  exit 3
fi
bash "$ROOT/skills/appstore-precheck/scripts/build-run.sh" --repo "$STAGE/project" --framework rn "$@"
