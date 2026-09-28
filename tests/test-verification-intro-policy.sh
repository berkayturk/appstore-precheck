#!/usr/bin/env bash
# Intro coverage, canonical aliases, and the limits of submission evidence leads.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -B - <<'PY'
import importlib.util
import json
from pathlib import Path
import tempfile

ref = Path('skills/appstore-precheck/references')
catalog = json.loads((ref / 'obligations/intro.json').read_text())['obligations']
fragment = json.loads((ref / 'verification/intro.json').read_text())
expected = {row['id'] for row in catalog if row['kind'] == 'obligation'}
rows = {row['obligation_id']: row for row in fragment['obligations']}
assert fragment['schema_version'] == 1 and fragment['section'] == 'intro'
assert set(rows) == expected and len(rows) == len(fragment['obligations'])


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


contract = load('contract', 'skills/appstore-precheck/scripts/verification-contract.py')
for row in rows.values():
    assert row['owner'] and row['document_group'] and row['applicability_evidence']
    required = [c['id'] for c in row['conditions']]
    assert len(required) == len(set(required)) and len(required) > 1
    for c in row['conditions']:
        assert c['description'] and c['evidence_kinds'] and c['review_requirement']
        assert c['full_positive_verifiers'] == c['decisive_finding_verifiers'] == []
        assert 'generic yes answer' in c['review_requirement']
        assert 'agent-created owner approval' in c['review_requirement']
        assert 'absence of a source signal is not exclusion evidence' in c['review_requirement']
        # Even all other conditions reviewed positively cannot hide this missing one.
        partial = [other for other in required if other != c['id']]
        assert contract.reduce_status('APPLICABLE', required, partial, []) == 'UNRESOLVED'
    assert contract.reduce_status('UNKNOWN', required, required, []) == 'UNRESOLVED'
    assert contract.reduce_status('NOT_APPLICABLE', required, [], []) == 'UNRESOLVED'


def condition(ident, cid):
    return next(c for c in rows[ident]['conditions'] if c['id'] == cid)


# Informational aliases cannot reappear as duplicate obligations or extra policy rows.
items = {r['id']: r for r in catalog}
for alias, canonical in [
    ('atom-7660b11f2dad457fbefdac9a83a74d99', 'atom-aa8284569e164afb823d07720c3ca324'),
    ('atom-884097dadb564c018667d7c730d75f61', 'atom-e575151c903d4c8fb72cede56c55c136'),
    ('atom-89ba978493b44f34a8ed0f9e9d4b9bb1', 'atom-26cf6458c05541869843bb236e088a76'),
]:
    assert items[alias]['kind'] == 'informational' and alias not in rows
    assert canonical in items[alias]['related']
# Expedite/bug-fix process descriptions do not create new compliance obligations.
for ident in ['atom-a9c3f3d5e7344174860729bd57ddfa21', 'atom-fb4cb3107c0940c49cb5b9268e624813']:
    assert items[ident]['kind'] == 'informational' and ident not in rows
hardware = condition('atom-e7ac52bbed6742cea1216b232bf01b1a', 'hardware-demonstration-exception')
assert 'apple-review-correspondence' in hardware['evidence_kinds']
for phrase in ['accepting that approach for this submission', 'later reviewer requests', 'direct working access', 'Missing correspondence']:
    assert phrase in hardware['review_requirement']
notes = condition('atom-f9a98fc9b0544658a3b9a4b0152a160e', 'feature-explanation-coverage')
assert 'metadata-asc-snapshot' in notes['evidence_kinds']
assert 'nonempty notes field' in notes['review_requirement']
assert 'local fastlane draft' in notes['review_requirement']
assert 'complete feature inventory and discoverability' in notes['review_requirement']
assert 'future monitoring promise' in condition('atom-f65a3e371c2c49229e0449753fef6859', 'distributed-component-monitoring')['review_requirement']
assert 'non-Kids category' in condition('atom-c44cce19b9104b2ca5f658e0dd2a93a5', 'age-suitability')['review_requirement']
assert 'bug-fix processing allowance does not turn' in condition('atom-f7d015611dde4efda35fcf052340c2f6', 'review-and-distribution-integrity')['review_requirement']

# A source lead selects a question; neither missing signals nor present SDK/hardware
# keywords establish applicability, compliance, reviewer access, or a violation.
source = load('intro_source', 'skills/appstore-precheck/scripts/lib/section6-review.py')
with tempfile.TemporaryDirectory() as td:
    app = Path(td)
    assert source.review_external_components(app)['status'] == 'SKIP'
    assert source.review_special_hardware(app)['status'] == 'SKIP'
    (app / 'tests').mkdir()
    (app / 'tests/Seed.swift').write_text('import CoreBluetooth\n')
    (app / 'tests/package.json').write_text('{"dependencies":{"synthetic-sdk":"1"}}')
    assert source.review_special_hardware(app)['status'] == 'SKIP'
    assert source.review_external_components(app)['status'] == 'SKIP'
    (app / 'package.json').write_text('{"dependencies":{}}')
    assert source.review_external_components(app)['status'] == 'SKIP'
    (app / 'package.json').write_text('{"dependencies":{"synthetic-sdk":"1"}}')
    (app / 'App.swift').write_text('import CoreBluetooth\n')
    assert source.review_external_components(app)['status'] == 'NEEDS_REVIEW'
    assert source.review_special_hardware(app)['status'] == 'NEEDS_REVIEW'
print('Intro policies: {} obligations, {} conditions; alias and evidence boundaries passed'.format(len(rows), sum(len(r['conditions']) for r in rows.values())))
PY
