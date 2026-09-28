#!/usr/bin/env bash
# Section 2 policy completeness, scoped exceptions, and source-lead boundaries.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$ROOT" <<'PY'
import importlib.util
import json
from pathlib import Path
import tempfile
import sys
root = Path(sys.argv[1])
ref = root / 'skills/appstore-precheck/references'
catalog = json.loads((ref / 'obligations/2.json').read_text())['obligations']
fragment = json.loads((ref / 'verification/2.json').read_text())
assert fragment['schema_version'] == 1 and fragment['section'] == '2'
items = {row['id']: row for row in catalog if row['kind'] == 'obligation'}
policies = {row['obligation_id']: row for row in fragment['obligations']}
assert set(items) == set(policies)
assert len(policies) == len(fragment['obligations'])
for ident, policy in policies.items():
    assert policy['owner'] and policy['document_group'] and policy['applicability_evidence']
    conditions = policy['conditions']
    assert conditions and len({c['id'] for c in conditions}) == len(conditions)
    assert all(c['description'] and c['review_requirement'] and c['evidence_kinds'] for c in conditions)
    for exception in items[ident]['exceptions']:
        assert any(exception in c['review_requirement'] for c in conditions), (ident, exception)
    assert all('absence of a source signal is not exclusion evidence' in c['review_requirement'] for c in conditions)
# Length is separate from uniqueness, accurate claims and discovery manipulation.
name_id = 'atom-9518097ae09743e8a5d0e3a752b262aa'
auto = [ident for ident,p in policies.items() if any(c['full_positive_verifiers'] or c['decisive_finding_verifiers'] for c in p['conditions'])]
assert auto == [name_id]
name = policies[name_id]['conditions'][0]
assert name['id'] == 'app-name-limit'
assert name['evidence_kinds'] == ['metadata-asc-snapshot']
assert name['full_positive_verifiers'] == name['decisive_finding_verifiers'] == ['metadata.app-name-length.v1']
assert 'primary locale' in name['review_requirement'] and 'Local fastlane' in name['review_requirement']
# A partial physical test or complete install cannot close the distinct condition.
hardware = policies['atom-3c95a205dfc5469d86927977e0e7c636']['conditions']
assert {c['id'] for c in hardware} == {'real-hardware-test', 'stability-defects'}
assert all('Mac' in c['review_requirement'] and 'formal defect log' in c['review_requirement'] for c in hardware)
package = policies['req-2f2096c499274b42bfe329048e038a33']['conditions']
assert {c['id'] for c in package} == {'complete-package', 'stable-operation'}
access = policies['atom-e575151c903d4c8fb72cede56c55c136']['conditions']
assert {c['id'] for c in access} == {'review-access','review-period-access','demo-exception'}
assert all('prior approval' in c['review_requirement'] for c in access)
# Source words, missing source and excluded fixtures cannot produce a verified result.
path = root / 'skills/appstore-precheck/scripts/lib/section2-review.py'
spec = importlib.util.spec_from_file_location('section2_review', path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
with tempfile.TemporaryDirectory() as directory:
    app = Path(directory)
    (app / 'tests').mkdir()
    (app / 'tests/Seed.swift').write_text('Text("Lorem ipsum")\nfatalError("TODO")\n')
    (app / 'App.swift').write_text('// Text("Lorem ipsum")\nlet title = "Welcome"\n')
    rows = list(module.source_rows(app))
    assert module.review_completeness(rows)['status'] == 'SKIP'
    assert module.review_access(rows)['status'] == 'SKIP'
    (app / 'Localizable.strings').write_text('"welcome" = "Lorem ipsum";\n')
    (app / 'App.swift').write_text('func login() { authenticateUser() }\nfunc load() { URLSession.shared.dataTask(with: endpoint) }\n')
    rows = list(module.source_rows(app))
    placeholder = module.review_completeness(rows)
    access = module.review_access(rows)
    assert placeholder['status'] == access['status'] == 'NEEDS_REVIEW'
    assert placeholder['facets']['placeholder'] is True
    assert access['facets'] == {'login': True, 'network': True}
    assert all('/tests/' not in e['file'] and not e['file'].startswith('tests/') for e in placeholder['evidence'])
print('Section 2 verification policies and source-lead boundary fixtures passed')
PY
