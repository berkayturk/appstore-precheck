#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -B - <<'PY'
import importlib.util
import json
from pathlib import Path

ref = Path('skills/appstore-precheck/references')
catalog = json.loads((ref / 'obligations/5.json').read_text())['obligations']
obligations = {x['id']: x for x in catalog if x['kind'] == 'obligation'}
fragment = json.loads((ref / 'verification/5.json').read_text())
assert fragment['schema_version'] == 1 and fragment['section'] == '5'
policies = {x['obligation_id']: x for x in fragment['obligations']}
assert len(policies) == len(fragment['obligations']), 'duplicate legal policy'
assert set(policies) == set(obligations), 'missing obligation or non-obligation promoted'
for ident, policy in policies.items():
    assert policy['owner'] and policy['document_group'] and policy['applicability_evidence']
    assert all(isinstance(x, str) and x for x in policy['applicability_evidence'])
    conditions = policy['conditions']
    assert conditions and len({c['id'] for c in conditions}) == len(conditions)
    for c in conditions:
        assert c['description'] and c['evidence_kinds'] and c['review_requirement']
        # Legal source leads must not acquire either automatic decision direction.
        assert c['full_positive_verifiers'] == []
        assert c['decisive_finding_verifiers'] == []
        assert 'missing source signals do not establish non-applicability' in c['review_requirement']
        assert 'unverified owner answer is not sufficient' in c['review_requirement']
    review = ' '.join(c['review_requirement'] for c in conditions)
    for exception in obligations[ident]['exceptions']:
        assert exception in review, (ident, 'exception lineage lost')

def row(prefix):
    matches = [p for ident, p in policies.items() if ident.startswith('atom-' + prefix)]
    assert len(matches) == 1
    return matches[0]

def needs(prefix, *terms):
    review = ' '.join(c['review_requirement'] for c in row(prefix)['conditions']).lower()
    assert all(term.lower() in review for term in terms), (prefix, terms)

# Counterexamples that used to disappear behind broad yes/feature-absent answers.
needs('e3c31431', 'first-collection', 'denial', 'withdrawal', 'every applicable condition')
needs('00204211', 'backend', 'denied', 'restricted', 'undetermined', 'revoked', 'definition')
needs('79c28004', 'AI providers', 'before the first transfer', 'refusal', 'backend')
needs('b4005c96', 'authorized disposable test account', 'backend confirmation', 'logout alone')
needs('7cb28983', 'public', 'indirect source', 'explicit direct-source consent')
needs('17970632', 'intended audience', '1.3', 'identifiers', 'location', 'child-identifying')
needs('0f276337', '1.3', 'contextual-only', 'human review', 'before display')
needs('925e6d26', 'sharing capability', 'parental gate is not statutory consent')
needs('5345fc39', 'parent/guardian authority', 'before-enrollment')
needs('45f00d84', 'independent', 'protocol version', 'before recruitment', 'authenticity')
needs('7b04cb06', 'CloudKit', 'backups', 'indirect storage')
needs('f6d77897', 'weight/use specifications', 'small-device exception')
needs('41c5d255', 'signatory authority', 'cannot sign on behalf')
needs('12c2449b', 'explicit source authorization', 'conversion', 'territory')
needs('9b377905', 'backend', 'border cases', 'location-denied', 'Storefront selection alone')
needs('5dbfbb56', 'licensee', 'App Review Notes', 'selected release')
needs('d341dea3', 'non-VPN', 'Apple provider approval')
needs('d0d72849', 'performance', 'exclude user data, device data', 'other installed apps')
needs('21008b99', 'membership', 'App Review', 'EU trader applicability', 'current legal registration')
for ident, item in obligations.items():
    if item['apple_ref'] == '5.5':
        needs(ident[5:13], 'configuration-profile offerings even when no MDM service is marketed')

# Shared documents can support distinct criteria; no requirement is collapsed.
assert row('cf99fa88')['document_group'] == row('e472c4ce')['document_group']
assert row('cf99fa88')['conditions'] != row('e472c4ce')['conditions']
assert row('45f00d84')['document_group'] == row('aff1d3b8')['document_group']
assert row('45f00d84')['conditions'] != row('aff1d3b8')['conditions']

spec = importlib.util.spec_from_file_location('contract',
    'skills/appstore-precheck/scripts/verification-contract.py')
contract = importlib.util.module_from_spec(spec)
spec.loader.exec_module(contract)
for policy in policies.values():
    required = [c['id'] for c in policy['conditions']]
    assert contract.reduce_status('UNKNOWN', required, [], []) == 'UNRESOLVED'
    assert contract.reduce_status('NOT_APPLICABLE', required, [], []) == 'UNRESOLVED'
    # Source findings or attestations do not supply proven condition IDs.
    assert contract.reduce_status('APPLICABLE', required, [], []) == 'UNRESOLVED'
    assert contract.reduce_status('APPLICABLE', required, required, [required[0]]) == 'VERIFIED_FINDING'

# Exercise actual legal signal functions against a risky and an absent-feature fixture.
spec = importlib.util.spec_from_file_location('legal_signals',
    'skills/appstore-precheck/scripts/lib/section5-review.py')
signals = importlib.util.module_from_spec(spec)
spec.loader.exec_module(signals)
source_rows = [('Flow.swift', 1, 'let picker = CNContactPickerViewController()'),
               ('Flow.swift', 2, 'Button("Select All") {}'),
               ('Flow.swift', 3, 'let selectedContacts = allContacts'),
               ('Flow.swift', 4, 'let safariVC = SFSafariViewController(url: page)'),
               ('Flow.swift', 5, 'safariVC.view.addSubview(cover)'),
               ('Flow.swift', 6, 'Link("Privacy Policy", destination: page)')]
for detector in (signals.review_contact_select_all, signals.review_contact_preselect,
                 signals.review_safari_obscure, signals.review_privacy_entry):
    assert detector(source_rows)['status'] == 'NEEDS_REVIEW'
    assert detector([])['status'] == 'SKIP'
    check_id = detector(source_rows)['check_id']
    linked = [x for x in obligations.values() if any(r.get('check_id') == check_id for r in x['routes'])]
    assert len(linked) == 1
    assert all(not c['full_positive_verifiers'] and not c['decisive_finding_verifiers']
               for c in policies[linked[0]['id']]['conditions'])
print('legal verification policy: complete coverage, scoped exceptions and unresolved source leads passed')
PY
