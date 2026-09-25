#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$ROOT" <<'PY'
import json
import os
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
section = json.loads((root / 'skills/appstore-precheck/references/obligations/1.json').read_text())
registry = json.loads((root / 'skills/appstore-precheck/references/check-registry.json').read_text())['checks']
rows = section['obligations']
assert section['schema_version'] == 1 and section['section'] == '1'
assert len(rows) == len({row['id'] for row in rows})
assert all(row['apple_ref'].startswith('1.') for row in rows)
assert all('text' not in row and len(row['criterion'].split()) <= 55 for row in rows)
assert all(row['text_sha256'] and row['anchor'].startswith('https://developer.apple.com/') for row in rows)
assert all(row['criterion'] not in ('Determine whether the applicable source requirement is satisfied.', 'Source fragment awaiting independent section review.') for row in rows)
assert all(route['check_id'] in registry and (route['decides'] == 'partial' or (route['route'] == 'attestation' and route['decides'] == 'full'))
           for row in rows for route in row['routes'] if route['route'] != 'not_app_checkable')
assert all(row['kind'] != 'obligation' for row in rows for route in row['routes'] if route['route'] == 'not_app_checkable')
assert all(any(route['route'] == 'attestation' for route in row['routes']) for row in rows if row['kind'] == 'obligation')
assert any(row['retired_from'] for row in rows)

# The source catalogue is intentionally private. Compare against it only if installed.
private = Path(os.environ.get('APPSTORE_PRECHECK_PRIVATE_CATALOG', str(root / '.planning/opus-work/skills/appstore-precheck/references/requirement-catalog.json')))
if private.is_file():
    source = json.loads(private.read_text())
    fragments = [r for r in source['requirements'] if r['apple_ref'].startswith('1.')]
    expected = {r['id'] for r in fragments}
    expected.update(a['id'] for r in fragments for a in r.get('editorial_draft', {}).get('proposed_atomic_parts', []))
    actual = {row['id'] for row in rows}
    assert expected <= actual, sorted(expected - actual)
    words = lambda value: re.findall(r"[\w]+(?:['’][\w]+)?", value.casefold())
    grams = set()
    for fragment in fragments:
        w = words(fragment['text'])
        grams.update(tuple(w[i:i + 8]) for i in range(len(w) - 7))
    for row in rows:
        for field in ('criterion',):
            w = words(row[field])
            assert not any(tuple(w[i:i + 8]) in grams for i in range(len(w) - 7)), (row['id'], field)
    print('section 1: source IDs and 8-word copyright boundary verified')
else:
    print('section 1: private source comparison SKIP')
print('section 1: schema, links, classifications verified')
PY
