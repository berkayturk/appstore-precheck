#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

python3 - "$tmp" <<'PY'
import datetime as dt
import importlib.util
import json
import subprocess
import sys
from pathlib import Path

root = Path.cwd()
tmp = Path(sys.argv[1])
script = root / 'skills/appstore-precheck/scripts/attestation-report.py'
spec = importlib.util.spec_from_file_location('attestation_report', script)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

def obligation(number, routes):
    return {'id': f'atom-fixture-{number}', 'kind': 'obligation', 'apple_ref': f'1.{number}',
            'anchor': f'https://developer.apple.com/app-store/review/guidelines/#1.{number}',
            'section': '1', 'criterion': f'Fixture criterion {number}.', 'routes': routes}

attest = {'route': 'attestation', 'check_id': 'attestation-generic', 'decides': 'full'}
full = {'route': 'static', 'check_id': 'fixture-static', 'decides': 'full'}
partial = {'route': 'static', 'check_id': 'fixture-static', 'decides': 'partial'}
catalog = {'schema_version': 1, 'obligations': [
    obligation(1, [attest]), obligation(2, [attest]), obligation(3, [attest]),
    obligation(4, [attest]), obligation(5, [partial, attest]),
    obligation(6, [full, attest]), obligation(7, [full, attest]),
    obligation(8, [full]), obligation(9, [attest])
]}
registry = {'schema_version': 1, 'checks': {
    'attestation-generic': {'route': 'attestation'},
    'fixture-static': {'route': 'static'}}}
today = dt.date.today().isoformat()
config = {'attestations': {
    'atom-fixture-1': {'answer': 'yes', 'evidence': 'docs/review.md#1', 'answered_on': today},
    'atom-fixture-2': {'answer': 'no', 'evidence': 'tests/fail.json#2', 'answered_on': today},
    'atom-fixture-3': {'answer': 'unknown', 'evidence': 'review/unknown#3', 'answered_on': today},
    'atom-fixture-4': {'answer': 'yes', 'evidence': '', 'answered_on': today},
    'atom-fixture-9': {'answer': 'yes', 'evidence': 'docs/review.md#9', 'answered_on': '2099-01-01'},
}}
runs = {'checks': {'fixture-static': {'status': 'PASS', 'evidence': 'tests/static.json#pass'}}}
report = module.build_report(catalog, registry, config, runs)
rows = {row['id']: row for row in report['obligations']}
expect = {1: 'ATTESTED_YES', 2: 'ATTESTED_NO', 3: 'ATTESTATION_UNKNOWN',
          4: 'ATTESTATION_REQUIRED', 5: 'ATTESTATION_REQUIRED',
          6: 'AUTO_PASS', 7: 'AUTO_PASS', 8: 'AUTO_PASS',
          9: 'ATTESTATION_REQUIRED'}
for number, status in expect.items():
    assert rows[f'atom-fixture-{number}']['status'] == status, (number, rows[f'atom-fixture-{number}'])
assert rows['atom-fixture-5']['routes'][0]['decides'] == 'partial'
assert rows['atom-fixture-5']['question'].startswith('Does the submitted app satisfy')
assert report['summary']['automatically_decided'] == 3
assert report['summary']['semantically_decided'] == 0
assert report['summary']['self_reported'] == 2
assert report['summary']['attestation_required'] == 3
assert report['summary']['attestation_unknown'] == 1
assert report['summary']['route_counts'] == {'attestation': 8, 'static': 4}
assert report['summary']['routes_run'] == {'attestation': 3, 'static': 4}
assert report['sections']['1']['total'] == 9

# A possible full automatic route does not imply a decision when it did not run.
not_run = module.build_report(catalog, registry, {}, {})
assert not_run['summary']['automatically_decided'] == 0
assert not_run['summary']['attestation_required'] == 8
assert not_run['obligations'][7]['status'] == 'NOT_RUN'
assert not_run['summary']['not_run_reasons']['Check not invoked'] == 4
assert not_run['summary']['routes_run'] == {}

found = module.build_report(catalog, registry, config,
    {'checks': {'fixture-static': {'status': 'FINDING', 'evidence': 'tests/static.json#finding'}}})
assert found['obligations'][5]['status'] == 'AUTO_FINDING'
assert found['obligations'][4]['status'] == 'ATTESTATION_REQUIRED' # partial finding is not a full decision

semantic = {'schema_version': 1, 'obligations': [obligation(10, [
    {'route': 'semantic', 'check_id': 'fixture-semantic', 'decides': 'full'}, attest])]}
semantic_registry = {'schema_version': 1, 'checks': dict(registry['checks'], **{
    'fixture-semantic': {'route': 'semantic'}})}
semantic_report = module.build_report(semantic, semantic_registry, {}, {'checks': {
    'fixture-semantic': {'status': 'PASS', 'evidence': 'review/case-10.json'}}})
assert semantic_report['obligations'][0]['status'] == 'SEMANTIC_PASS'
assert semantic_report['summary']['automatically_decided'] == 0
assert semantic_report['summary']['semantically_decided'] == 1

malformed = {'attestations': {'atom-fixture-1': {'answer': [], 'evidence': 'docs/x', 'answered_on': today}}}
assert module.build_report(catalog, registry, malformed, {})['obligations'][0]['status'] == 'ATTESTATION_REQUIRED'

for invalid in ({'checks': {'missing': {'status': 'PASS', 'evidence': 'x'}}},
                {'checks': {'fixture-static': {'status': 'PASS'}}},
                {'checks': {'fixture-static': {'status': 'SKIP'}}}):
    try:
        module.build_report(catalog, registry, {}, invalid)
    except ValueError:
        pass
    else:
        raise AssertionError('invalid run result accepted')

for name, data in [('catalog', catalog), ('registry', registry), ('config', config), ('run', runs)]:
    (tmp / f'{name}.json').write_text(json.dumps(data))
command = [sys.executable, str(script), '--catalog', str(tmp/'catalog.json'), '--registry',
           str(tmp/'registry.json'), '--config', str(tmp/'config.json'),
           '--run-results', str(tmp/'run.json'), '--out', str(tmp/'report.json'),
           '--markdown', str(tmp/'report.md')]
completed = subprocess.run(command, capture_output=True, text=True)
assert completed.returncode == 0, completed.stderr
assert completed.stdout == ''
assert json.loads((tmp/'report.json').read_text())['summary']['automatically_decided'] == 3
md = (tmp/'report.md').read_text()
assert 'ATTESTATION_REQUIRED' in md and 'Question:' in md and 'Section' in md

# Registry fragment is compatible with the public catalog validator after merge.
cov_spec = importlib.util.spec_from_file_location('coverage_tool', root/'scripts/coverage.py')
cov = importlib.util.module_from_spec(cov_spec)
cov_spec.loader.exec_module(cov)
public = json.loads((root/'skills/appstore-precheck/references/guideline-obligations.json').read_text())
registered = json.loads((root/'skills/appstore-precheck/references/check-registry.json').read_text())
fragment = json.loads((root/'skills/appstore-precheck/references/registry/attestation.json').read_text())
registered['checks'].update(fragment['checks'])
cov.validate(public, registered)
print('attestation report: OK')
PY
