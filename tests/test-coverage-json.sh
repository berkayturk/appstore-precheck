#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cp -R "$ROOT/tests/fixtures/no-iap-app/." "$tmp/"
APPSTORE_PRECHECK_CONFIG=/nonexistent bash "$ROOT/skills/appstore-precheck/scripts/scan.sh" \
  --dir "$tmp" --format json > "$tmp/scan.json"
python3 - "$tmp/scan.json" "$ROOT/coverage.json" <<'PY'
import json, sys
scan = json.load(open(sys.argv[1]))
coverage = json.load(open(sys.argv[2]))
assert len(scan['obligations']) == coverage['total_obligations']
assert scan['coverage_summary']['routed_obligations'] == coverage['total_obligations']
assert scan['coverage_summary']['automatically_decided'] == 0
assert scan['coverage_run']['attestation']['not_run'] == coverage['total_obligations']
assert scan['coverage_run']['static']['ran'] > 0
assert all(row['status'] == 'ATTESTATION_REQUIRED' and row['question']
           for row in scan['obligations'])
assert all(row['status'] not in ('AUTO_PASS', 'SEMANTIC_PASS')
           for row in scan['obligations'])
print('coverage JSON envelope: OK')
PY
printf '{bad json\n' > "$tmp/.appstore-precheck.json"
bash "$ROOT/skills/appstore-precheck/scripts/scan.sh" --dir "$tmp" --format json > "$tmp/malformed.json"
python3 - "$tmp/malformed.json" <<'PY'
import json, sys
scan = json.load(open(sys.argv[1]))
assert scan['coverage_errors']
assert scan['findings'] and scan['obligations']
print('malformed config preserves scanner JSON: OK')
PY
