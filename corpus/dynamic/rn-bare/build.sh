#!/usr/bin/env bash
# Bootstrap the official bare RN template in a disposable directory, then use
# build-run.sh for the isolated simulator build. Network/tooling gaps are SKIP.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
VARIANT="${1:-}"
[[ "$VARIANT" == clean || "$VARIANT" == broken ]] || { echo "usage: $0 clean|broken [build-run options]" >&2; exit 64; }
shift
command -v npx >/dev/null 2>&1 || { echo "SKIP: RN bootstrap needs Node.js and npx"; exit 3; }
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/precheck-rn-corpus.XXXXXX")" || exit 3
trap 'rm -rf "$STAGE"' EXIT
source "$HERE/../bootstrap.sh"
export npm_config_fetch_retries=0 npm_config_fetch_timeout=15000 npm_config_cache="$STAGE/npm-cache"
if ! corpus_bootstrap rn-template "$STAGE" npx --yes @react-native-community/cli@latest init PrecheckRN --directory project --skip-install --install-pods false --pm npm --skip-git-init true; then
  echo "SKIP: RN template unavailable; install Node.js and allow npm registry access"
  exit 3
fi
cp "$HERE/$VARIANT/App.js" "$STAGE/project/App.js"
rm -f "$STAGE/project/App.tsx"
if ! corpus_bootstrap dependency-lock "$STAGE/project" npm install --package-lock-only --ignore-scripts --no-audit --no-fund; then
  echo "SKIP: RN dependency lock could not be resolved from npm"
  exit 3
fi
bash "$ROOT/skills/appstore-precheck/scripts/build-run.sh" --repo "$STAGE/project" --framework rn "$@"
