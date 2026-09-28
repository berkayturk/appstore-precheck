#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out="$(mktemp)"
json_out="$(mktemp)"
trap 'rm -f "$out" "$json_out"' EXIT
APPSTORE_PRECHECK_CONFIG=/nonexistent \
  bash skills/appstore-precheck/scripts/scan.sh --dir tests/fixtures/no-iap-app > "$out"
diff -u tests/golden/no-iap-app.txt "$out"
echo 'default scan output: byte-identical to main baseline'

# JSON: every key main emitted keeps its exact value; the coverage additions are the
# only new keys, and neither opt_in nor coverage_errors appears on a default scan.
APPSTORE_PRECHECK_CONFIG=/nonexistent \
  bash skills/appstore-precheck/scripts/scan.sh --dir tests/fixtures/no-iap-app --format json > "$json_out"
python3 - tests/golden/no-iap-app.json "$json_out" skills/appstore-precheck/SKILL.md <<'PY'
import json, re, sys
expected = json.load(open(sys.argv[1]))
actual = json.load(open(sys.argv[2]))
skill_version = re.search(r'(?m)^\s*version:\s*(\S+)', open(sys.argv[3]).read()).group(1)
assert actual['version'] == skill_version, (actual['version'], skill_version)
added = set(actual) - set(expected)
assert added == {'coverage_run', 'coverage_summary', 'obligations'}, added
for key, value in expected.items():
    if key == 'version':
        continue
    assert actual[key] == value, 'default JSON key changed: ' + key
assert list(actual)[:len(expected)] == list(expected), 'key order of main baseline changed'
assert len(actual['obligations']) == actual['coverage_summary']['total_obligations']
PY
echo 'default JSON output: every baseline key unchanged'
