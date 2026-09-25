#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
python3 - "$ROOT" <<'PY'
import json
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
part = json.loads((root / 'skills/appstore-precheck/references/obligations/4.json').read_text())['obligations']
base = json.loads((root / 'skills/appstore-precheck/references/guideline-obligations.json').read_text())['obligations']
checks = json.loads((root / 'skills/appstore-precheck/references/check-registry.json').read_text())['checks']
original = {x['id']: x for x in base if x.get('section') == '4'}
assert len(part) == len(original), (len(part), len(original))
assert set(x['id'] for x in part) == set(original)
assert len({x['id'] for x in part}) == len(part)
by_id = {x['id']: x for x in part}
all_ids = {x['id'] for x in json.loads((root / 'skills/appstore-precheck/references/guideline-obligations.json').read_text())['obligations']}
for item in part:
    prior = original[item['id']]
    assert item['apple_ref'] == prior['apple_ref']
    assert item['anchor'] == prior['anchor']
    assert item['text_sha256'] == prior['text_sha256']
    assert item['criterion'] and 'awaiting' not in item['criterion'].lower()
    assert 'text' not in item
    assert item['applicability'].get('condition')
    for linked in item['exceptions'] + item['related'] + item['retired_from']:
        assert linked in all_ids, (item['id'], linked)
    if item['kind'] == 'obligation':
        assert all(r['decides'] == 'partial' or (r['route'] == 'attestation' and r['decides'] == 'full') for r in item['routes'])
        assert all(r['check_id'] in checks for r in item['routes'])
        assert all(r['route'] == checks[r['check_id']]['route'] for r in item['routes'])
        assert item['primary_route'] == (item['routes'][0]['route'] if item['routes'] else None)
    else:
        assert all(r['route'] == 'not_app_checkable' for r in item['routes'])

private = Path('/Users/bt/claude/appstore-precheck/.planning/opus-work/skills/appstore-precheck/references/requirement-catalog.json')
if private.is_file():
    catalog = json.loads(private.read_text())
    fragments = [x for x in catalog['requirements'] if x['apple_ref'].startswith('4.')]
    expected = {x['id'] for x in fragments}
    expected.update(a['id'] for x in fragments for a in x.get('editorial_draft', {}).get('proposed_atomic_parts', []))
    assert set(by_id) == expected
    source_text = [x['text'] for x in fragments]
    source_text += [x['text'] for x in catalog['records'] if x['ref'].startswith('4.')]
    def tokens(value):
        return re.findall(r"[a-z0-9]+(?:['’][a-z0-9]+)?", value.lower())
    source_grams = set()
    for passage in source_text:
        words = tokens(passage)
        source_grams.update(tuple(words[i:i + 8]) for i in range(len(words) - 7))
    for item in part:
        # Compare every human-readable field, including explanatory route reasons.
        for value in (item['criterion'], item['applicability']['condition'], *(r.get('reason', '') for r in item['routes'])):
            words = tokens(value)
            for i in range(len(words) - 7):
                assert tuple(words[i:i + 8]) not in source_grams, (item['id'], 'Apple text overlap')
else:
    print('SKIP: private source catalog unavailable for eight-word comparison')
print('PASS: 4.x stable IDs, lineage, route honesty, and public-text safety')
PY
