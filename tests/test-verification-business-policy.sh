#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -B - <<'PY'
"""Business review policy boundaries and conservative source-signal fixtures."""
import importlib.util
import json
from pathlib import Path


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


ref = Path('skills/appstore-precheck/references')
catalog = json.loads((ref / 'obligations/3.json').read_text())['obligations']
fragment = json.loads((ref / 'verification/3.json').read_text())
expected = {r['id']: r for r in catalog if r['kind'] == 'obligation'}
rows = {r['obligation_id']: r for r in fragment['obligations']}
assert fragment['schema_version'] == 1 and fragment['section'] == '3'
assert set(rows) == set(expected)
assert len(rows) == len(fragment['obligations'])
for ident, row in rows.items():
    assert row['owner'] and row['document_group'] and row['applicability_evidence']
    conditions = row['conditions']
    assert conditions and len({c['id'] for c in conditions}) == len(conditions)
    review = ' '.join(c['review_requirement'] for c in conditions)
    for exception in expected[ident]['exceptions']:
        assert exception in review, (ident, exception)
    for condition in conditions:
        assert condition['description'] and condition['evidence_kinds']
        assert condition['review_requirement']
        # These are required reviewed evidence, not implemented automatic proofs.
        assert condition['full_positive_verifiers'] == []
        assert condition['decisive_finding_verifiers'] == []


def requirements(ident):
    return ' '.join(c['review_requirement'] for c in rows[ident]['conditions'])


# Exception counterexamples are explicit review requirements, not keyword-derived
# applicability decisions. US links, Mac plug-ins, physical gifts and ordinary
# rewards must not become unconditional digital-payment or access violations.
cases = {
    'atom-997058a40b3344e99d8bdee763e77f8b': ['reader', 'cross-platform', 'organization-only', 'one-to-one', 'US buying-link allowance'],
    'atom-ec57f6028fbc49c8a9134643ee424b25': ['Mac App Store', 'req-95650ef4819840ca891f87b367c802cc'],
    'atom-f1e506715b5a4150b03360f62e4f9108': ['actually mailed', 'req-d69f1d9a20a4482f95e4326bec407abf'],
    'atom-a017a6446edb434fb697a7a183abec0a': ['absent entitlement cannot prove a violation in the US', 'global eligibility'],
    'atom-14a13b1656a44dcc95d27e7a5f3bb1d2': ['Outside the US', 'ownership/responsibility', 'req-a062d314b6e748c290a0f189f3a0bd44'],
    'atom-54c9e12357d247e6a0e41c048bd5d3dc': ['consumable', 'equivalent purchasable IAP', 'unrelated IAP'],
    'atom-25dc6b52a96643889de2ae590fcbd474': ['ordinary subscriptions', 'carrier restriction'],
    'atom-6c351a87ea6a49f89a18320c5ddd0f69': ['receipt', 'restored entitlement', 'simulator tap is not restored access'],
    'atom-d697d85363f54565ae5c0054ad8d7205': ['Introductory free-trial duration', 'local StoreKit test period'],
    'atom-71995e2b64614ab186c0916f6eee5090': ['at any time', 'IAP'],
    'atom-d9a7820c78114031b7ce582158d99737': ['rental exception', 'approved rental media', 'non-rental'],
    'atom-f8ddbab62bc44016b958734f103b7f75': ['legitimate service, legal or technical basis', 'licensed-territory'],
    'atom-4599cc6b6a6b402e874a4504d940acae': ['declining', 'optional ordinary in-app rewards', 'atom-c6a14f55a49a42059c77a7fdf76f30a6'],
    'atom-c6786ba2029b4e07b99267033b098c34': ['more than 60 days', 'voluntary early repayment'],
    'atom-a65bca1597d64179bf7c1f57349cdd83': ['costs and fees', '36 percent', 'actual contracts'],
}
for ident, terms in cases.items():
    for term in terms:
        assert term in requirements(ident), (ident, term)

# Shared dossier avoids repeatedly requesting the same approvals and offer data.
for identifiers in [
    ['atom-792af3fdfba646389746446c7b18b3e7', 'atom-3c81315eba0047768ffbd71871a855a8'],
    ['atom-25cdf7a8964c4cbbabcd91ec67a51c30', 'atom-6f16c5183f3d41f49c43bfc5e9c7c210', 'atom-a65bca1597d64179bf7c1f57349cdd83', 'atom-c6786ba2029b4e07b99267033b098c34'],
]:
    assert len({rows[i]['document_group'] for i in identifiers}) == 1

contract = module('contract', 'skills/appstore-precheck/scripts/verification-contract.py')
companion = rows['atom-2ddcf75d3e544bb6828e52f95a702bb4']['conditions']
condition_ids = [c['id'] for c in companion]
assert len(condition_ids) == 3
assert contract.reduce_status('APPLICABLE', condition_ids, condition_ids[:1], []) == 'UNRESOLVED'
assert contract.reduce_status('UNKNOWN', condition_ids, condition_ids, []) == 'UNRESOLVED'
assert contract.reduce_status('NOT_APPLICABLE', condition_ids, [], []) == 'UNRESOLVED'
assert not contract.scope_matches({'storefronts': ['US']}, {'storefronts': ['TR']})

source = module('business_source', 'skills/appstore-precheck/scripts/lib/section3-review.py')
# Same source supports multiple legal contexts. Neither a US link, legitimate
# physical checkout, reader account link nor unknown scope yields a verdict.
for scenario, text in [
    ('us_digital_link', 'func openExternalCheckout() {}'),
    ('physical_goods', 'import Stripe'),
    ('reader_account', 'let externalPurchaseLink = accountURL'),
    ('unknown_scope', 'let checkoutURL = remoteURL'),
]:
    check = source.review_payment([('Commerce.swift', 1, text)])
    assert check['status'] in ('SKIP', 'NEEDS_REVIEW'), (scenario, check)
    assert source.review_entitlement([('Commerce.swift', 1, text)], [])['status'] in ('SKIP', 'NEEDS_REVIEW')
assert source.review_payment([])['status'] == 'SKIP'  # Missing signal is not N/A.
entitlements = [('App.entitlements', {'com.apple.developer.storekit.external-purchase-link': True})]
assert source.review_entitlement([], entitlements)['status'] == 'NEEDS_REVIEW'
# A short local test period cannot prove a production subscription violation;
# a compliant local test period cannot prove the live offering is compliant.
for period in ['P3D', 'P7D', 'P1M']:
    check = source.review_catalog([('Products.storekit', {'products': [
        {'type': 'RecurringSubscription', 'recurringSubscriptionPeriod': period}]})])
    assert check['status'] == 'NEEDS_REVIEW'
assert source.review_catalog([])['status'] == 'SKIP'
print('Business policy: {} obligations, {} conditions; exception boundaries and source-proof limits passed'.format(
    len(rows), sum(len(r['conditions']) for r in rows.values())))
PY
