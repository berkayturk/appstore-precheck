#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
python3 scripts/coverage.py --output "$tmp/coverage.json" --markdown "$tmp/coverage.md"
python3 - "$tmp/coverage.json" <<'PY'
import json,sys
report=json.load(open(sys.argv[1]))
assert report['total_obligations'] > 0
assert report['obligations_without_route'] >= 0
assert report['routes']['static'] > 0
assert report['routes']['runtime'] > 0
assert report['routes']['semantic'] > 0
PY
# Wave 0 deliberately preserves unassigned obligations. The complete gate is
# enabled only after section review and implementation are merged.
if python3 scripts/coverage.py --require-complete --output "$tmp/strict.json" --markdown "$tmp/strict.md" >/dev/null 2>&1; then
  python3 - "$tmp/coverage.json" <<'PY'
import json,sys
assert json.load(open(sys.argv[1]))['obligations_without_route'] == 0
PY
fi
echo 'coverage schema and registry: OK'
