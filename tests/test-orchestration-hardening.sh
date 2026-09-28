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

echo '== SKIP is never masked by a sibling PASS =='
py "$SCRIPTS" <<'PY'
import importlib.util, json, sys
from pathlib import Path
scripts = Path(sys.argv[1])
def load(name, file):
    spec = importlib.util.spec_from_file_location(name, scripts / file)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module); return module
runner, engine, augment = load('runner', 'opt-in-review.py'), load('engine', 'attestation-report.py'), load('augment', 'augment-json.py')
registry = json.loads((scripts.parent / 'references/check-registry.json').read_text())
SKIP = 'DYNAMIC-SKIP: 5.1.1 [dyn-permission-prompt:NSCameraUsageDescription] — camera prompt could not be triggered'
PASS = 'DYNAMIC-PASS: 5.1.1 [dyn-permission-prompt:NSLocationWhenInUseUsageDescription] — location prompt shown'
FIND = 'DYNAMIC-FINDING: 5.1.1 [dyn-permission-prompt:NSMicrophoneUsageDescription] — purpose string empty (quorum 3/3)'
def dyn(*lines):
    checks = {}; runner.import_dynamic(checks, '\n'.join(lines), 'transcript.txt'); return checks
for order in ((SKIP, PASS), (PASS, SKIP)):
    result = dyn(*order)['dyn-permission-prompt']
    assert result['status'] not in {'PASS'}, (order, result)
    assert result['status'] in {'REVIEW_REQUIRED', 'SKIP'} and result.get('reason'), result
    engine.validate_run_results({'checks': {'dyn-permission-prompt': result}}, registry)
for order in ((SKIP, PASS, FIND), (FIND, PASS, SKIP), (PASS, FIND, SKIP)):
    assert dyn(*order)['dyn-permission-prompt']['status'] == 'FINDING', order
assert dyn(PASS, PASS.replace('Location', 'Camera'))['dyn-permission-prompt']['status'] == 'PASS'
assert dyn(SKIP, SKIP.replace('Camera', 'Photo'))['dyn-permission-prompt']['status'] == 'SKIP'

def records(*rows):
    checks = {}; runner.import_records(checks, list(rows), 'inv.json'); return checks
rows = ({'check_id': 'dyn-first-screen', 'status': 'PASS'}, {'check_id': 'dyn-first-screen', 'status': 'SKIP', 'reason': 'no screen'})
for order in (rows, rows[::-1]):
    result = records(*order)['dyn-first-screen']
    assert result['status'] == 'REVIEW_REQUIRED' and result['reason'], result
    engine.validate_run_results({'checks': {'dyn-first-screen': result}}, registry)
assert records(*rows, {'check_id': 'dyn-first-screen', 'status': 'FINDING'})['dyn-first-screen']['status'] == 'FINDING'
assert records(rows[0], rows[0])['dyn-first-screen']['status'] == 'PASS'

def static(*severities):
    findings = [{'rule_id': 'ats', 'severity': s, 'id': 'f%d' % i, 'suppressed': False} for i, s in enumerate(severities)]
    return augment.normalize_static(findings, {'checks': {'ats': {'route': 'static'}}})['ats']
for order in (('PASS', 'SKIP'), ('SKIP', 'PASS')):
    result = static(*order)
    assert result['status'] == 'REVIEW_REQUIRED' and result['reason'], result
assert static('PASS', 'SKIP', 'WARN')['status'] == 'WARN' and static('SKIP', 'PASS', 'FAIL')['status'] == 'FINDING'
assert static('PASS', 'PASS')['status'] == 'PASS' and static('SKIP', 'SKIP')['status'] == 'SKIP'
print('aggregation: PASS only when every sibling passed, defects dominate: OK')
PY

echo '== augment-json never loses the scanner JSON =='
py "$SCRIPTS" "$tmp" <<'PY'
import json, subprocess, sys
from pathlib import Path
scripts, tmp = Path(sys.argv[1]), Path(sys.argv[2])
def augment(stdin, *args):
    return subprocess.run([sys.executable, '-B', str(scripts / 'augment-json.py'), *args], input=stdin,
                          capture_output=True, text=True)
envelope = {'tool': 'appstore-precheck', 'version': 'x', 'verdict': 'GREEN', 'summary': {}, 'findings': 5}
result = augment(json.dumps(envelope))
assert result.returncode == 0, result.stderr
out = json.loads(result.stdout)
assert {k: v for k, v in out.items() if k != 'coverage_errors'} == envelope, out
assert isinstance(out['coverage_errors'], list) and out['coverage_errors'], out
envelope['findings'] = []
(tmp / 'bad-summary.json').write_text('{not json')
result = augment(json.dumps(envelope), '--opt-summary', str(tmp / 'bad-summary.json'))
assert result.returncode == 0, result.stderr
out = json.loads(result.stdout)
assert out['tool'] == 'appstore-precheck' and out['coverage_errors'], out
for raw in ('not json at all {', '[1, 2]', '', '"text"'):
    result = augment(raw)
    assert result.returncode == 0 and result.stdout == raw, (raw, result.returncode, result.stdout)
result = augment(json.dumps(envelope))
assert result.returncode == 0 and 'coverage_errors' not in json.loads(result.stdout)
print('augment-json failure containment: OK')
PY
py "$SCRIPTS" <<'PY'
import importlib.util, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location('augment', Path(sys.argv[1]) / 'augment-json.py')
augment = importlib.util.module_from_spec(spec); spec.loader.exec_module(augment)
silent = augment.mark_silent_static({}, {'checks': {'ipv4-literal': {'route': 'static'}}})
reasons = {v['reason'] for v in silent.values()}
assert reasons, 'expected at least one silent static rule'
for reason in reasons:
    assert 'ran in this scan' not in reason and 'no applicable signal' in reason, reason
print('silent static reason is not self-contradictory: OK')
PY

exit "$fails"
