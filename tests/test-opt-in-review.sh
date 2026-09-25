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
