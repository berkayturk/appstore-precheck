#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
repo="$tmp/project"
out="$tmp/report"
mkdir -p "$repo/ios/Example.xcodeproj" "$repo/ios/Example" "$repo/fastlane/metadata/en-US"
printf 'import SwiftUI\n@main struct ExampleApp: App { var body: some Scene { WindowGroup { Text("Hello") } } }\n' > "$repo/ios/Example/ExampleApp.swift"
printf 'Example\n' > "$repo/fastlane/metadata/en-US/name.txt"
before="$(find "$repo" -type f -print0 | sort -z | xargs -0 shasum -a 256 | shasum -a 256)"
bash "$ROOT/skills/appstore-precheck/scripts/scan.sh" --dir "$repo" --build --dry-run \
  --metadata --out "$out" --format json > "$tmp/scan.json"
after="$(find "$repo" -type f -print0 | sort -z | xargs -0 shasum -a 256 | shasum -a 256)"
[[ "$before" == "$after" ]] || { echo 'opt-in dry run changed source'; exit 1; }
python3 - "$tmp/scan.json" "$out/run-results.json" <<'PY'
import json,sys
scan=json.load(open(sys.argv[1])); results=json.load(open(sys.argv[2]))['checks']
assert scan['opt_in']['tiers']['build']=='PLAN'
assert scan['opt_in']['tiers']['runtime']=='NOT_RUN'
assert scan['opt_in']['tiers']['metadata']=='RAN'
assert results['artifact-private-api']['status']=='NOT_RUN'
assert 'meta-review-notes' in results
assert len(scan['obligations'])==scan['coverage_summary']['total_obligations']
print('opt-in dry run and metadata report: OK')
PY
node "$ROOT/bin/cli.js" dynamic --build --dry-run --metadata --dir "$repo" \
  --out "$tmp/cli-report" --format json > "$tmp/cli.json"
python3 - "$tmp/cli.json" <<'PY'
import json,sys
data=json.load(open(sys.argv[1]));assert data['opt_in']['tiers']['build']=='PLAN'
print('dynamic CLI build flag: OK')
PY
if python3 "$ROOT/skills/appstore-precheck/scripts/opt-in-review.py" --repo "$repo" \
  --out-dir "$repo/output" --metadata >/dev/null 2>&1; then
  echo 'opt-in wrote inside source'; exit 1
fi
[[ ! -e "$repo/output" ]] || { echo 'opt-in created source output'; exit 1; }
echo 'out-dir source boundary: OK'
bash "$ROOT/skills/appstore-precheck/scripts/scan.sh" --dir "$repo" --build --dry-run \
  --format json > "$tmp/auto-out.json"
auto_out="$(python3 - "$tmp/auto-out.json" <<'PY'
import json,sys
print(json.load(open(sys.argv[1]))['opt_in']['report_dir'])
PY
)"
[[ -f "$auto_out/run-results.json" ]] || { echo 'automatic report path disappeared'; exit 1; }
rm -rf "$auto_out"
echo 'automatic opt-in evidence retained: OK'
printf '{"dynamic":{"build":true}}\n' > "$repo/.appstore-precheck.json"
scan="$ROOT/skills/appstore-precheck/scripts/scan.sh"
# The config lives in the scanned repo, so it must never start a build by itself.
env -u APPSTORE_PRECHECK_TRUST_CONFIG bash "$scan" --dir "$repo" \
  --dry-run --out "$tmp/config-report" --format json > "$tmp/config.json" 2> "$tmp/config.err"
python3 - "$tmp/config.json" <<'PY'
import json,sys
assert 'opt_in' not in json.load(open(sys.argv[1])), 'untrusted config entered the build tier'
PY
grep -qF 'appstore-precheck: config requests dynamic.build; ignored (pass --build or set APPSTORE_PRECHECK_TRUST_CONFIG=1)' "$tmp/config.err" \
  || { echo 'missing ignored-config notice'; cat "$tmp/config.err"; exit 1; }
[[ ! -e "$tmp/config-report" ]] || { echo 'untrusted config ran the opt-in runner'; exit 1; }
if env -u APPSTORE_PRECHECK_TRUST_CONFIG bash "$scan" --dir "$repo" \
  --dry-run --dynamic-blocking >/dev/null 2>&1; then
  echo 'untrusted config permitted --dynamic-blocking without a build'; exit 1
fi
echo 'untrusted config build is ignored with a notice: OK'
APPSTORE_PRECHECK_TRUST_CONFIG=1 bash "$scan" --dir "$repo" --dry-run \
  --dynamic-blocking --out "$tmp/trusted-report" --format json > "$tmp/trusted.json" 2> "$tmp/trusted.err"
python3 - "$tmp/trusted.json" <<'PY'
import json,sys
assert json.load(open(sys.argv[1]))['opt_in']['tiers']['build'] == 'PLAN'
PY
! grep -q 'ignored' "$tmp/trusted.err" || { echo 'trusted config printed the ignored notice'; exit 1; }
echo 'trusted config build opt-in permits dynamic blocking: OK'
# dynamic.demoLogin is only a default for an already-active build or app.
printf '{"dynamic":{"demoLogin":true}}\n' > "$repo/.appstore-precheck.json"
env -u APPSTORE_PRECHECK_TRUST_CONFIG bash "$scan" --dir "$repo" > "$tmp/demo-plain.txt" 2> "$tmp/demo-plain.err" \
  || { echo 'config demoLogin broke a plain scan'; cat "$tmp/demo-plain.err"; exit 1; }
env -u APPSTORE_PRECHECK_TRUST_CONFIG bash "$scan" --dir "$repo" --no-runtime > /dev/null 2>&1 \
  || { echo 'config demoLogin broke --no-runtime'; exit 1; }
env -u APPSTORE_PRECHECK_TRUST_CONFIG bash "$scan" --dir "$repo" --build --dry-run --no-runtime \
  --out "$tmp/demo-nr" --format json > "$tmp/demo-nr.json" \
  || { echo 'config demoLogin conflicted with an explicit --no-runtime'; exit 1; }
env -u APPSTORE_PRECHECK_TRUST_CONFIG bash "$scan" --dir "$repo" --build --dry-run \
  --out "$tmp/demo-build" --format json > "$tmp/demo-build.json" \
  || { echo 'config demoLogin broke an explicit build'; exit 1; }
python3 - "$tmp/demo-nr.json" "$tmp/demo-build.json" <<'PY'
import json,sys
for path in sys.argv[1:]: assert json.load(open(path))['opt_in']['tiers']['build'] == 'PLAN'
PY
rm -f "$repo/.appstore-precheck.json"
echo 'config demoLogin never fails a scan by itself: OK'

python3 - "$ROOT" <<'PY'
import importlib.util, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
scripts = root/'skills/appstore-precheck/scripts'
def module(name):
    spec = importlib.util.spec_from_file_location(name, scripts/(name+'.py'))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result
runner = module('opt-in-review')
engine = module('attestation-report')
registry = json.loads((scripts.parent/'references/check-registry.json').read_text())
checks = {}
runner.import_dynamic(checks, '''DYNAMIC-FINDING: 5.1.1 [dyn-shipped-bundle:NSLocationWhenInUseUsageDescription] — purpose string is empty
DYNAMIC-PASS: 5.1.1 [dyn-shipped-bundle] — installed bundle has 12 keys
DYNAMIC-FINDING: 2.1 [dyn-launch] — quorum 1/3: not unanimous
''', '/tmp/recorded-transcript.txt')
assert checks['dyn-shipped-bundle']['status'] == 'WARN'
assert checks['dyn-shipped-bundle']['evidence'].endswith('#dyn-shipped-bundle:NSLocationWhenInUseUsageDescription')
assert checks['dyn-launch']['status'] == 'WARN'
assert engine.validate_run_results({'checks':checks}, registry) == checks
checks = {}
runner.import_dynamic(checks, 'DYNAMIC-PASS: 5.1.1 [dyn-shipped-bundle:NSCameraUsageDescription] — purpose string present', '/tmp/clean-transcript.txt')
assert checks['dyn-shipped-bundle']['status'] == 'PASS'
engine.validate_run_results({'checks':checks}, registry)
checks = {}
runner.record(checks, 'dyn-launch', 'SKIP', reason='x' * 900 + '\nsecond line ' + 'y' * 200)
assert len(checks['dyn-launch']['reason']) <= 500 and '\n' not in checks['dyn-launch']['reason']
engine.validate_run_results({'checks': checks}, registry)
checks = {}
runner.import_records(checks, [{'check_id': 'dyn-account-deletion', 'status': 'NEEDS_REVIEW', 'reason': 'r'}], 'inv.json')
assert checks['dyn-account-deletion']['status'] == 'REVIEW_REQUIRED'
assert engine.validate_run_results({'checks': {'dyn-launch': {'status': 'NEEDS_REVIEW', 'reason': 'alias'}}}, registry)['dyn-launch']['status'] == 'REVIEW_REQUIRED'
print('dynamic subcheck aggregation and registry validation: OK')
PY
bash "$ROOT/tests/test-orchestration-hardening.sh"
