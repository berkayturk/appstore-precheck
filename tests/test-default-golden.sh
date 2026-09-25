#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out="$(mktemp)"
trap 'rm -f "$out"' EXIT
APPSTORE_PRECHECK_CONFIG=/nonexistent \
  bash skills/appstore-precheck/scripts/scan.sh --dir tests/fixtures/no-iap-app > "$out"
diff -u tests/golden/no-iap-app.txt "$out"
echo 'default scan output: byte-identical to main baseline'
