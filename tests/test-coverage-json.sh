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
silent = [r for row in scan['obligations'] for r in row['routes'] if r.get('check_id') == 'demo-account']
assert silent and all(r['run_status'] == 'NOT_RUN' and 'no applicable signal' in r['reason'] for r in silent), silent[:1]
print('coverage JSON envelope: OK')
PY
printf '{"checks":{"dyn-launch":{"status":"NEEDS_REVIEW","reason":"alias token"},"dyn-first-screen":{"status":"BOGUS"},"artifact-ats":{"status":"PASS","evidence":"artifact:ats"}}}\n' > "$tmp/run-results.json"
printf '{"tiers":{"metadata":"RAN"},"input_errors":["Malformed optional result ignored"]}\n' > "$tmp/opt-summary.json"
python3 "$ROOT/skills/appstore-precheck/scripts/augment-json.py" --opt-summary "$tmp/opt-summary.json" --run-results "$tmp/run-results.json" < "$tmp/scan.json" > "$tmp/partial.json"
python3 - "$tmp/partial.json" <<'PY'
import json, sys
scan = json.load(open(sys.argv[1]))
routes = {r['check_id']: r for row in scan['obligations'] for r in row['routes'] if r.get('check_id')}
assert routes['dyn-launch']['run_status'] == 'REVIEW_REQUIRED', routes['dyn-launch']
assert routes['artifact-ats']['run_status'] == 'PASS', routes['artifact-ats']
assert scan['opt_in']['input_errors'] == ['Malformed optional result ignored']
assert routes['dyn-first-screen']['run_status'] == 'NOT_RUN'
assert any('dyn-first-screen' in e for e in scan['coverage_errors']), scan['coverage_errors']
print('one invalid run record is dropped without discarding the tier: OK')
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
