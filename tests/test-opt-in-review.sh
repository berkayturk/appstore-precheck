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
bash "$ROOT/skills/appstore-precheck/scripts/scan.sh" --dir "$repo" --dry-run \
  --dynamic-blocking --out "$tmp/config-report" --format json > "$tmp/config.json"
python3 - "$tmp/config.json" <<'PY'
import json,sys
assert json.load(open(sys.argv[1]))['opt_in']['tiers']['build'] == 'PLAN'
PY
echo 'config build opt-in permits dynamic blocking: OK'

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
print('dynamic subcheck aggregation and registry validation: OK')
PY
