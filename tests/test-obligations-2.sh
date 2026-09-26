#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - <<'PY'
import hashlib
import json
import os
import re
from pathlib import Path
import importlib.util

root = Path.cwd()
section = json.loads((root / 'skills/appstore-precheck/references/obligations/2.json').read_text())
base = json.loads((root / 'skills/appstore-precheck/references/guideline-obligations.json').read_text())
registry = json.loads((root / 'skills/appstore-precheck/references/check-registry.json').read_text())['checks']
items = section['obligations']
original = {x['id']: x for x in base['obligations'] if x['apple_ref'].startswith('2')}
assert section['section'] == '2'
assert {x['id'] for x in items} == set(original), 'section IDs differ from the public skeleton'
assert len(items) == len(original), 'duplicate section ID'
by_id = {x['id']: x for x in items}
for item in items:
    before = original[item['id']]
    for key in ('id', 'apple_ref', 'anchor', 'text_sha256', 'section'):
        assert item[key] == before[key], (item['id'], key)
    assert item['kind'] in ('obligation', 'exception', 'informational', 'definition')
    assert item['criterion'] and 'Determine whether' not in item['criterion']
    assert 'awaiting independent' not in item['criterion']
    assert len(item['criterion'].split()) <= 55
    assert item['applicability'].get('feature_condition')
    assert item['applicability'].get('unknown') == 'NEEDS_REVIEW'
    assert not any(k in item for k in ('text', 'source_text', 'full_text'))
    if item['kind'] == 'obligation':
        assert all(r['route'] != 'not_app_checkable' for r in item['routes'])
    for route in item['routes']:
        assert route['decides'] in ('partial', 'full')
        if route['route'] == 'not_app_checkable':
            assert item['kind'] != 'obligation' and route.get('reason')
        else:
            check = registry[route['check_id']]
            assert check['route'] == route['route']
            assert route['decides'] == 'partial' or (route['route'] == 'attestation' and route['decides'] == 'full'), 'only attestation may add a full section route'
    if item['routes']:
        assert item['primary_route'] in {r['route'] for r in item['routes']}
    else:
        assert item['primary_route'] is None
    assert set(item['exceptions'] + item['related']) <= set(by_id)

spec = importlib.util.spec_from_file_location('coverage', root / 'scripts/coverage.py')
coverage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(coverage)
merged = dict(base)
merged['obligations'] = [by_id.get(x['id'], x) for x in base['obligations']]
coverage.validate(merged, {'schema_version': 1, 'checks': registry})

# Optional local provenance and copyright checks; CI omits the private source catalog.
private = Path(os.environ.get('APPSTORE_PRECHECK_PRIVATE_CATALOG') or str(root / '.planning/opus-work/skills/appstore-precheck/references/requirement-catalog.json'))
if private.is_file():
    catalog = json.loads(private.read_text())
    source = {x['id']: x for x in catalog['requirements'] if x['apple_ref'].startswith('2')}
    for item in items:
        if item['id'] in source:
            expected = hashlib.sha256(source[item['id']]['text'].encode()).hexdigest()
            assert item['text_sha256'] == expected, item['id']
    def words(value):
        return re.findall(r'[a-z0-9]+', value.lower())
    windows = set()
    for fragment in catalog['requirements']:
        tokens = words(fragment['text'])
        windows.update(tuple(tokens[i:i+8]) for i in range(len(tokens)-7))
    for item in items:
        tokens = words(item['criterion'])
        assert not any(tuple(tokens[i:i+8]) in windows for i in range(len(tokens)-7)), item['id']
    print('section 2 source provenance and copyright: OK')
else:
    print('section 2 private-source checks: SKIP')
print('section 2 obligations: OK')
PY
