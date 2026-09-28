#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - <<'PY'
"""Guard safety evidence boundaries; no synthetic app verdicts or owner signatures."""
import json
from pathlib import Path

ref = Path('skills/appstore-precheck/references')
catalog = json.loads((ref / 'obligations/1.json').read_text())['obligations']
fragment = json.loads((ref / 'verification/1.json').read_text())
expected = {r['id'] for r in catalog if r['kind'] == 'obligation'}
rows = {r['obligation_id']: r for r in fragment['obligations']}
assert set(rows) == expected
assert len(rows) == len(fragment['obligations'])
assert fragment['schema_version'] == 1 and fragment['section'] == '1'
for row in rows.values():
    assert row['owner'] and row['document_group'] and row['applicability_evidence']
    conditions = row['conditions']
    assert conditions and len({c['id'] for c in conditions}) == len(conditions)
    for condition in conditions:
        assert condition['evidence_kinds'] and condition['review_requirement']
        # These policies require evidence review; none may claim an unimplemented
        # automatic determination from a keyword or a caller-supplied verdict.
        assert condition['full_positive_verifiers'] == []
        assert condition['decisive_finding_verifiers'] == []


def review(ident):
    return ' '.join(c['review_requirement'] for c in rows[ident]['conditions'])

# The content allowance is conjunctive and cannot legalize the primary use.
ugc = review('atom-e90ce97c6e7d4632b40f9f6fefe9c4d0')
for required in ['incidental', 'hidden', 'default', 'website', 'primarily prohibited']:
    assert required in ugc
# Reporting and blocking demand delivered/enforced state, beyond visible controls.
assert 'backend moderation case' in review('atom-b159c69f4a294eb68d1bc7aa7ebb98a8')
assert 'persisted backend state' in review('atom-8a14301460114ce3bca499a40882c0d6')
assert 'before another account can view' in review('atom-a9b4a1952d944e24a795730819986b70')
# Current category alone cannot erase protections promised in prior releases.
assert 'prior versions' in review('atom-9c53e07611ad4df3b1fda0d14b0ab465')
# All five analytics data restrictions survive simplification of review text.
analytics = review('atom-46e109a06fef4a9999003e29a29d7c4a')
for required in ['IDFA', 'child-identifying', 'child location', 'device-identifying', 'device/network', 'collection and transmission']:
    assert required in analytics
for ident in ['atom-6186554d692347f783bbb47b9052e065', 'atom-3e0f0c34543d434ba957cd1d634af137']:
    assert 'unresolved' in review(ident) and 'authoritative interpretation' in review(ident)
# A medically persuasive claim cannot replace actual method/accuracy validation.
assert 'reproducible validation protocol' in review('atom-726881973a096ad43aa49a76b2f997b1')
assert 'implementation/version' in review('atom-c969c9f28aa1f547adc9c2c637bb10fb')
# Cryptographic integrity does not establish the signer owns the pass brand.
wallet = rows['atom-564c86e5c2b44721aacf6d633eec6024']['conditions']
assert {c['id'] for c in wallet} == {'pass-signature', 'brand-certificate-assignment'}
# Sales exceptions retain territory, merchant authority and tobacco exclusion.
sale = review('atom-1120cf24fc3e431b87ba3e7bf5583dd5')
for required in ['license', 'territory', 'tobacco is outside']:
    assert required in sale
# Related contact duties intentionally reuse one evidence group.
for ident in ['atom-dc2caed931c44f58abc0fc8807b00cfc', 'atom-d188d94683794eb6a1e3977400195292', 'atom-cb980266eda4426cb44c7d30b2a00ca1', 'atom-aee38865f5f34a8e8d3d9b67bba99c53']:
    assert rows[ident]['document_group'] == 'developer-contact'
print('Safety policy: {} obligations and {} evidence conditions validated'.format(len(rows), sum(len(r['conditions']) for r in rows.values())))
PY
