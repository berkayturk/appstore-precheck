#!/usr/bin/env bash
# tests/test-orchestration-hardening.sh — scan orchestration and reporting hardening:
# stale --out reuse, SKIP aggregation, augment-json failure containment, safe output
# writes, --check-urls DNS pinning, and verifier module wiring. Run from
# tests/test-opt-in-review.sh (and independently).
set -uo pipefail
fails=0
py() { python3 -B - "$@" || { echo "  FAIL: python block failed"; fails=$((fails + 1)); }; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS="$ROOT/skills/appstore-precheck/scripts"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo '== stale results from a reused --out directory =='
py "$SCRIPTS" <<'PY'
import contextlib, importlib.util, io, json, sys, tempfile, types
from pathlib import Path
from unittest import mock
scripts = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location('runner', scripts / 'opt-in-review.py')
runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)
fresh = {'checks': [{'check_id': 'dyn-account-deletion', 'status': 'PASS', 'reason': 'fresh'}]}
stale = {'checks': [{'check_id': 'dyn-account-deletion', 'status': 'PASS', 'reason': 'stale'},
                    {'check_id': 'dyn-first-screen', 'status': 'PASS', 'reason': 'stale'}]}
with tempfile.TemporaryDirectory() as d:
    root = Path(d); repo = root / 'source'; repo.mkdir(); app = root / 'Sample.app'; app.mkdir()
    out = root / 'report'
    def seed():
        (out / 'runtime').mkdir(parents=True, exist_ok=True)
        (out / 'runtime' / 'screen-inventory.json').write_text(json.dumps(stale))
        for name in ('summary.json', 'run-results.json', 'artifact-review.json',
                     'metadata-review.json', 'section1.json'):
            (out / name).write_text('{"stale": true}')
    def call(produce_inventory, flags=()):
        def run(argv, timeout):
            if argv[1].endswith('dynamic-run.sh'):
                if produce_inventory:
                    (out / 'runtime' / 'screen-inventory.json').write_text(json.dumps(fresh))
                return types.SimpleNamespace(returncode=0, stdout='')
            return types.SimpleNamespace(returncode=0, stdout=json.dumps({'checks': [], 'results': []}))
        argv = ['runner', '--repo', str(repo), '--out-dir', str(out), '--app', str(app)] + list(flags)
        with mock.patch.object(runner, 'run', run), mock.patch.object(sys, 'argv', argv), \
             contextlib.redirect_stdout(io.StringIO()):
            assert runner.main() == 0
        return json.loads((out / 'run-results.json').read_text())['checks']
    seed()
    checks = call(False)
    assert 'dyn-account-deletion' not in checks and 'dyn-first-screen' not in checks, checks
    assert not (out / 'metadata-review.json').exists(), 'stale metadata output survived a run without --metadata'
    assert json.loads((out / 'section1.json').read_text()) != {'stale': True}
    seed()
    checks = call(True)
    assert checks['dyn-account-deletion']['status'] == 'PASS', checks
    assert 'dyn-first-screen' not in checks, 'only this run\'s inventory may be imported'
    # A user's own unrelated file in the reused directory is never removed.
    (out / 'keep-me.txt').write_text('mine'); call(False)
    assert (out / 'keep-me.txt').read_text() == 'mine'
print('runner ignores stale inventory/outputs, keeps unrelated files: OK')
PY

cat > "$tmp/mkrepo.sh" <<'SH'
mk() {
  mkdir -p "$1/ios/Example.xcodeproj" "$1/ios/Example" "$1/fastlane/metadata/en-US"
  printf 'import SwiftUI\n@main struct ExampleApp: App { var body: some Scene { WindowGroup { Text("Hello") } } }\n' > "$1/ios/Example/ExampleApp.swift"
  printf 'Example\n' > "$1/fastlane/metadata/en-US/name.txt"
}
SH
source "$tmp/mkrepo.sh"
mk "$tmp/project"
real_python="$(command -v python3)"
mkdir -p "$tmp/shim"
cat > "$tmp/shim/python3" <<SH
#!/bin/sh
case "\$1" in *opt-in-review.py) exit 1 ;; esac
exec "$real_python" "\$@"
SH
chmod +x "$tmp/shim/python3"
mkdir -p "$tmp/reused"
printf '{"checks":{"dyn-launch":{"status":"PASS","evidence":"stale-transcript"}}}\n' > "$tmp/reused/run-results.json"
printf '{"schema_version":1,"tiers":{"runtime":"RAN"},"blocking":[],"input_errors":[],"run_results":"stale"}\n' > "$tmp/reused/summary.json"
PATH="$tmp/shim:$PATH" bash "$SCRIPTS/scan.sh" --dir "$tmp/project" --metadata --out "$tmp/reused" \
  --format json > "$tmp/stale-scan.json"
py "$tmp/stale-scan.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
assert 'opt_in' not in data, 'stale summary merged after a failed runner'
routes = [r for o in data['obligations'] for r in o['routes'] if r['check_id'] == 'dyn-launch']
assert routes and all(r['run_status'] != 'PASS' for r in routes), routes[:1]
assert not any('stale' in json.dumps(o.get('evidence', '')) for o in data['obligations'])
print('scan.sh ignores stale run-results after a failed runner: OK')
PY

exit "$fails"
