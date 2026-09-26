#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PUBLIC="$ROOT/skills/appstore-precheck/references/obligations/5.json"
REGISTRY="$ROOT/skills/appstore-precheck/references/check-registry.json"
PRIVATE="${APPSTORE_PRECHECK_PRIVATE_CATALOG:-$ROOT/.planning/opus-work/skills/appstore-precheck/references/requirement-catalog.json}"

python3 - "$PUBLIC" "$REGISTRY" "$PRIVATE" <<'PY'
import collections
import json
import pathlib
import re
import sys

records = json.loads(pathlib.Path(sys.argv[1]).read_text())['obligations']
checks = json.loads(pathlib.Path(sys.argv[2]).read_text())['checks']
assert len(records) >= 326, '5.x source or atomic records missing'
ids = [record['id'] for record in records]
assert len(set(ids)) == len(ids), 'duplicate persistent IDs'
assert all(record['apple_ref'].startswith('5.') for record in records)
assert all(record['anchor'].startswith('https://developer.apple.com/app-store/review/guidelines/#5') for record in records)
assert all(re.fullmatch('[0-9a-f]{64}', record['text_sha256']) for record in records)
assert all(record['criterion'] and 'awaiting' not in record['criterion'] and 'applicable source requirement' not in record['criterion'] for record in records)
assert all('text' not in record for record in records), 'Apple source text must stay private'
for record in records:
    assert record['kind'] in ('obligation', 'exception', 'informational', 'definition')
    assert set(record['exceptions']).issubset(ids)
    assert set(record['related']).issubset(ids)
    assert record['routes'] or record['kind'] == 'obligation', record['id']
    for route in record['routes']:
        if record['kind'] == 'obligation':
            assert route['check_id'] in checks, record['id']
            assert route['decides'] == 'partial' or (route['route'] == 'attestation' and route['decides'] == 'full'), record['id']
            assert checks[route['check_id']]['route'] == route['route'], record['id']
        elif route['check_id'] is not None:
            assert route['check_id'] in checks

private = pathlib.Path(sys.argv[3])
if private.is_file():
    source = json.loads(private.read_text())
    fragments = [item for item in source['requirements'] if item['apple_ref'].startswith('5.')]
    assert {item['id'] for item in fragments}.issubset(ids), 'source fragment omitted'
    drafted = {atom['id'] for item in fragments for atom in item.get('editorial_draft', {}).get('proposed_atomic_parts', [])}
    accepted = {item['id'] for item in source['accepted_atoms'] if item['apple_ref'].startswith('5.')}
    assert drafted | accepted <= set(ids), 'persistent atomic ID omitted'
    corpus = ' '.join(item['text'] for item in source['requirements'])
    def words(value):
        return re.findall(r'\w+', value.lower().replace('’', "'"))
    source_words = words(corpus)
    source_grams = {tuple(source_words[i:i + 8]) for i in range(len(source_words) - 7)}
    for record in records:
        material = [record['criterion']]
        if isinstance(record['applicability'], dict):
            material += [str(part) for part in record['applicability'].values()]
        for value in material:
            tokens = words(value)
            assert not any(tuple(tokens[i:i + 8]) in source_grams for i in range(len(tokens) - 7)), '8-word source overlap: ' + record['id']
    print('test-obligations-5: source and copyright checks passed')
else:
    print('test-obligations-5: private source comparison SKIP')
print('test-obligations-5: schema, identity, links, and route checks passed')
PY
