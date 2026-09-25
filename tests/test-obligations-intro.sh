#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
python3 - "$ROOT" <<'PY'
import json
import hashlib
import os
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
path = root / 'skills/appstore-precheck/references/obligations/intro.json'
data = json.loads(path.read_text())
rows = data['obligations']
assert len(rows) == len({row['id'] for row in rows})
assert {row['apple_ref'] for row in rows} == {'introduction', 'before-you-submit', 'after-you-submit'}
for row in rows:
    assert row['id'].startswith(('req-', 'atom-'))
    assert re.fullmatch(r'[0-9a-f]{64}', row['text_sha256'])
    assert row['anchor'].startswith('https://developer.apple.com/app-store/review/guidelines/#')
    assert row['kind'] in {'obligation', 'exception', 'informational', 'definition'}
    assert row['criterion'] and 'source requirement is satisfied' not in row['criterion']
    assert 'text' not in row and 'source_context' not in row
    assert all(route.get('check_id', 'absent') is not None for route in row['routes'])
    if row['kind'] == 'obligation':
        assert not row['routes'], f"Unimplemented route written into {row['id']}"
    else:
        assert row['primary_route'] == 'not_app_checkable'
        assert row['routes'][0]['reason']

private = Path(os.environ.get('APPSTORE_PRECHECK_PRIVATE_CATALOG', str(root / '.planning/opus-work/skills/appstore-precheck/references/requirement-catalog.json')))
if not private.exists():
    print('intro obligations: structure PASS; source overlap SKIP (private catalog unavailable)')
    raise SystemExit(0)

source = json.loads(private.read_text())
source_rows = [row for row in source['requirements'] if row['source_ref'].split('/')[0] in {'introduction', 'before-you-submit', 'after-you-submit'}]
assert {row['id'] for row in source_rows}.issubset({row['id'] for row in rows})
source_hashes = {row['id']: hashlib.sha256(row['text'].encode()).hexdigest() for row in source_rows}
for row in rows:
    if row['id'] in source_hashes:
        assert row['text_sha256'] == source_hashes[row['id']], row['id']
accepted_hashes = {row['id']: row['source_sha256'] for row in source['accepted_atoms']}
for row in rows:
    if row['id'] in accepted_hashes:
        assert row['text_sha256'] == accepted_hashes[row['id']], row['id']

def words(value):
    return re.findall(r"\w+(?:['’]\w+)?", value.lower(), flags=re.UNICODE)

source_grams = set()
for source_row in source['requirements']:
    tokens = words(source_row['text'])
    source_grams.update(tuple(tokens[i:i+8]) for i in range(len(tokens)-7))
for row in rows:
    # Check all authored prose that will be published, not machine IDs and URLs.
    authored = [row['criterion']]
    authored += [str(value) for value in row.get('applicability', {}).values()]
    authored += [route.get('reason', '') for route in row.get('routes', [])]
    for field in authored:
        tokens = words(field)
        for i in range(len(tokens)-7):
            assert tuple(tokens[i:i+8]) not in source_grams, (row['id'], field)
print('intro obligations: structure and source overlap PASS')
PY
