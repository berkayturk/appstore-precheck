#!/usr/bin/env bash
# Section 4 evidence boundaries: a detector lead or visible control is not proof.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PYTHONDONTWRITEBYTECODE=1 python3 - "$ROOT" <<'PY'
import importlib.util
import json
import pathlib
import plistlib
import sys
import tempfile

root = pathlib.Path(sys.argv[1])
lib = root / 'skills/appstore-precheck/scripts/lib'


def module(name, file):
    spec = importlib.util.spec_from_file_location(name, lib / file)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


source = module('section4', 'section4-review.py')
runtime = module('explore', 'dyn-explore.py')


def write_extension(base, point):
    base.mkdir(parents=True, exist_ok=True)
    path = base / 'Info.plist'
    path.write_bytes(plistlib.dumps({'NSExtension': {'NSExtensionPointIdentifier': point}}))
    return path


with tempfile.TemporaryDirectory() as temp:
    repo = pathlib.Path(temp)
    keyboard = repo / 'Keyboard'
    safari = repo / 'Safari'
    write_extension(keyboard, 'com.apple.keyboard-service')
    write_extension(safari, 'com.apple.Safari.web-extension')
    (keyboard / 'Keys.swift').write_text('func next() { advanceToNextInputMode() }\n')
    # The containing app can purchase; that does not prove its extension does.
    (repo / 'App.swift').write_text('import StoreKit\nlet ad = GADBannerView()\n')
    (safari / 'manifest.json').write_text('{"host_permissions": ["https://example.invalid/*"]}')
    extensions, app_plists = source.extension_plists(repo)
    rows = source.source_rows(repo, extensions)
    assert source.review_commerce(repo, extensions, rows)['status'] == 'SKIP'

    # A source navigation method cannot establish a reachable working control.
    key = source.review_keyboard(repo, extensions, rows)
    assert key['status'] == 'NEEDS_REVIEW'
    assert key['facets']['next_keyboard_source_hint'] is True
    (keyboard / 'Keys.swift').write_text('class Keyboard {}\n')
    no_symbol = source.review_keyboard(repo, extensions, source.source_rows(repo, extensions))
    assert no_symbol['status'] == 'NEEDS_REVIEW'
    assert no_symbol['facets']['next_keyboard_source_hint'] is False

    # Broad can be justified; narrow can still be unnecessary. Neither proves scope.
    narrow = source.review_safari(repo, extensions)
    assert narrow['status'] == 'NEEDS_REVIEW'
    assert narrow['facets']['broad_host_access'] is False
    (safari / 'manifest.json').write_text('{"host_permissions": ["<all_urls>"]}')
    broad = source.review_safari(repo, extensions)
    assert broad['status'] == 'NEEDS_REVIEW'
    assert broad['facets']['broad_host_access'] is True
    (safari / 'manifest.json').write_text('{"host_permissions": "<all_urls>"}')
    malformed = source.review_safari(repo, extensions)
    assert malformed['status'] == 'NEEDS_REVIEW'
    assert malformed['facets']['broad_host_access'] is False

    # An import is not actual extension commerce; lack of a symbol is not clearance.
    (keyboard / 'Keys.swift').write_text('import StoreKit\n')
    commerce = source.review_commerce(repo, extensions, source.source_rows(repo, extensions))
    assert commerce['status'] == 'NEEDS_REVIEW'
    assert commerce['facets'] == {'advertising': False, 'in_app_purchase': True}
    assert source.review_placeholder(repo)['status'] == 'SKIP'
    (repo / 'App.swift').write_text('let releaseNote = "Coming soon: additional themes"\n')
    assert source.review_placeholder(repo)['status'] == 'NEEDS_REVIEW'


def login_result(labels, degenerate=False):
    screen = {'degenerate': degenerate, 'labels': labels,
              'patterns': [], 'hierarchy': 'synthetic-login.json'}
    return {r['check_id']: r for r in runtime.evaluate([screen], {})}['dyn-siwa-parity']


# UI observations do not establish provider eligibility, primary-account use or parity.
for label in ['Sign in with Apple', 'Continue with Apple', 'Sign in with ExampleID',
              'Continue with EnterpriseID']:
    assert login_result([label])['status'] == 'NEEDS_REVIEW', label
assert login_result(['Sign in with Google', 'Sign in with Apple'])['status'] == 'NEEDS_REVIEW'
assert login_result(['Continue with EnterpriseID', 'Existing company account required'])['status'] == 'NEEDS_REVIEW'
assert login_result(['Continue with ExampleID', 'Connect optional sharing account'])['status'] == 'NEEDS_REVIEW'
for label in ['Sign in with email', 'Continue with password', 'Continue with passkey']:
    assert login_result([label])['status'] == 'SKIP', label
assert login_result(['Sign in with Google'], degenerate=True)['status'] == 'SKIP'
assert login_result([])['status'] == 'SKIP'

ref = root / 'skills/appstore-precheck/references'
catalog = json.loads((ref / 'obligations/4.json').read_text())['obligations']
expected = {r['id']: r for r in catalog if r['kind'] == 'obligation'}
fragment = json.loads((ref / 'verification/4.json').read_text())
assert fragment['schema_version'] == 1 and fragment['section'] == '4'
policies = {r['obligation_id']: r for r in fragment['obligations']}
assert len(policies) == len(fragment['obligations'])
assert set(policies) == set(expected)
for ident, item in expected.items():
    row = policies[ident]
    assert row['owner'] and row['document_group'] and row['applicability_evidence']
    assert row['conditions']
    assert len({c['id'] for c in row['conditions']}) == len(row['conditions'])
    for c in row['conditions']:
        assert c['description'] and c['evidence_kinds'] and c['review_requirement']
        # Current Section 4 source/runtime leads have no sufficient automated proof.
        assert c['full_positive_verifiers'] == []
        assert c['decisive_finding_verifiers'] == []
    review = ' '.join(c['review_requirement'] for c in row['conditions'])
    for exception in item['exceptions']:
        assert exception in review, (ident, exception)

# Operational response and a functioning reporting entry must remain separate duties.
report_policy = policies['atom-1cf1c65d615e4afda04bbe94b25cfa06']
assert {c['id'] for c in report_policy['conditions']} == {
    'module-report-submission', 'timely-module-report-response'}
for row in policies.values():
    if row['document_group'] == 'login-services':
        evidence = {kind for c in row['conditions'] for kind in c['evidence_kinds']}
        assert evidence != {'runtime-capture'}
        assert 'login-exception-dossier' in row['applicability_evidence']
print('section 4 verification boundaries passed')
PY
