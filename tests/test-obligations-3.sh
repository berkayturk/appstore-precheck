#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
python3 - "$root" <<'PY'
import json
import os
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
section = json.loads((root / 'skills/appstore-precheck/references/obligations/3.json').read_text())['obligations']
registry = json.loads((root / 'skills/appstore-precheck/references/check-registry.json').read_text())['checks']
assert section
by_id = {entry['id']: entry for entry in section}
assert len(by_id) == len(section), 'duplicate 3.x id'

for entry in section:
    assert entry['apple_ref'].startswith('3.'), entry['id']
    assert entry['kind'] in ('obligation', 'exception', 'informational', 'definition'), entry['id']
    assert entry['criterion'] and 'source fragment awaiting' not in entry['criterion'].lower(), entry['id']
    assert 'text' not in entry, entry['id']
    assert len(entry['text_sha256']) == 64, entry['id']
    assert entry['anchor'].startswith('https://developer.apple.com/app-store/review/guidelines/#'), entry['id']
    assert entry['routes'], entry['id']
    for linked in entry['exceptions'] + entry['related']:
        assert linked in by_id, (entry['id'], linked)
    for route in entry['routes']:
        check_id = route['check_id']
        if check_id is not None:
            assert check_id in registry, (entry['id'], check_id)
            assert route['decides'] == 'partial', (entry['id'], check_id)
            assert registry[check_id]['route'] == route['route'], (entry['id'], check_id)
        elif route['route'] != 'not_app_checkable':
            assert route.get('proposed_check_id'), entry['id']
    if entry['id'].startswith('atom-'):
        assert entry['kind'] != 'informational', entry['id']
        assert entry['primary_route'] != 'not_app_checkable', entry['id']

private_path = os.environ.get('PRIVATE_CATALOG_PATH')
if not private_path:
    private_path = str(root / '.planning/opus-work/skills/appstore-precheck/references/requirement-catalog.json')
private = Path(private_path)
if private.is_file():
    catalog = json.loads(private.read_text())
    source_reqs = [r for r in catalog['requirements'] if r['apple_ref'].startswith('3.')]
    expected = {r['id'] for r in source_reqs}
    for req in source_reqs:
        expected.update(p['id'] for p in req.get('editorial_draft', {}).get('proposed_atomic_parts', []))
    assert set(by_id) == expected, '3.x source or candidate atom omitted'

    def words(text):
        return re.findall(r"[a-z0-9]+", text.casefold())

    # No public criterion may reuse eight successive source words.
    source_grams = set()
    for req in source_reqs:
        tokens = words(req['text'])
        source_grams.update(tuple(tokens[i:i + 8]) for i in range(len(tokens) - 7))
    for entry in section:
        tokens = words(entry['criterion'])
        assert not any(tuple(tokens[i:i + 8]) in source_grams for i in range(len(tokens) - 7)), entry['id']
    print('3.x source inventory and copyright overlap: PASS')
else:
    print('3.x private source comparison: SKIP (catalog unavailable)')

print('3.x obligations schema and routes: PASS')
PY
