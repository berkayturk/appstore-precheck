#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -B - <<'PY'
import copy
import datetime
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile

spec = importlib.util.spec_from_file_location('packet', 'skills/appstore-precheck/scripts/manual-review-packet.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
today = datetime.date.today().isoformat()
profile = {'schema_version': 1, 'reviewed_at': today, 'target': {k: None for k in m.reporter.contract.SCOPE_FIELDS}, 'facts': {}}
items = [{'id': 'one', 'kind': 'obligation', 'criterion': 'Inspect full content inventory.', 'section': '1', 'routes': [{'route': 'attestation'}], 'exceptions': []},
         {'id': 'two', 'kind': 'obligation', 'criterion': 'Verify contextual moderation.', 'section': '1', 'routes': [{'route': 'attestation'}, {'route': 'semantic'}], 'exceptions': []},
         {'id': 'context', 'kind': 'informational'}]
catalog = {'obligations': items}
condition = {'id': 'inventory', 'description': 'Inspect every offered content category.', 'review_requirement': 'Inspect locales, remote content and ongoing controls.', 'evidence_kinds': ['content-inventory', 'content-review'], 'required_positive_evidence_kinds': ['content-inventory'], 'full_positive_verifiers': [], 'decisive_finding_verifiers': []}
policies = {r['id']: {'obligation_id': r['id'], 'owner': 'content owner', 'document_group': 'content', 'applicability_evidence': ['feature-inventory'], 'conditions': [copy.deepcopy(condition)]} for r in items[:2]}
empty_evidence = {'schema_version': 1, 'evidence': []}
empty_decisions = {'schema_version': 1, 'decisions': []}
with tempfile.TemporaryDirectory() as temp:
    root = Path(temp)
    app = root / 'app'
    app.mkdir()
    sentinel = app / 'source.swift'
    sentinel.write_text('read-only source')
    def packet(ps=None, evidence=None, decisions=None, notes=None, cfg=None, target=None):
        return m.make_packet(target or profile, evidence or empty_evidence, decisions or empty_decisions, catalog, policies if ps is None else ps, root, cfg, notes)
    p, b = packet()
    assert len(p['obligations']) == 2 and p['summary']['attestation_only_obligations'] == 1
    assert not p['summary']['ready'] and p['summary']['verified_pass_percent'] == 0
    assert len(b['requests']) == 1 and set(b['requests'][0]['obligation_ids']) == {'one', 'two'}
    assert len(b['requests'][0]['requirements']) == 4
    assert len(b['shared_evidence']) == 3
    assert next(r for r in b['shared_evidence'] if r['kind'] == 'content-inventory')['mandatory_positive_for'] == [{'obligation_id': i, 'condition_id': 'inventory'} for i in ('one', 'two')]
    assert p['obligations'][0]['conditions'][0]['required_positive_evidence_kinds'] == ['content-inventory']
    assert all(len(r['requirements']) == 2 for r in b['shared_evidence'])
    assert b['requests'][0]['reviewer'] is None
    assert 'Required for PASS: content-inventory' in m.markdown(p, b)
    assert condition['review_requirement'] in m.markdown(p, b)
    assert all(c['result']['status'] == 'UNKNOWN' for r in p['obligations'] for c in r['conditions'])
    cfg = {'attestations': {'one': {'answer': 'yes', 'evidence': 'owner says yes', 'answered_on': today}}}
    p, b = packet(cfg=cfg)
    assert p['obligations'][0]['attestation'] == 'ATTESTED_YES' and not p['summary']['ready']
    p, b = packet(ps={})
    assert p['summary']['policy_gap_count'] == 2 and p['obligations'][0]['conditions'][0]['condition_id'] == 'criterion'
    assert all(r['status'] == 'UNRESOLVED' for r in p['obligations'])
    # Declared local observations survive incomplete target scope, without closure.
    observation_file = root / 'inventory.json'
    observation_file.write_text('{"sample":"one screen"}')
    ev = {'id': 'capture', 'kind': 'content-inventory', 'path': str(observation_file), 'sha256': hashlib.sha256(observation_file.read_bytes()).hexdigest(), 'scope': profile['target'], 'collected_at': today, 'collector': 'analyst', 'limitations': ['one screen only']}
    manifest = {'schema_version': 1, 'evidence': [ev]}
    observation = {'obligation_id': 'one', 'condition_id': 'inventory', 'basis': 'observed', 'summary': 'One sample read.', 'location': 'sample', 'evidence_ids': ['capture'], 'limitations': ['not complete content coverage']}
    p, b = packet(evidence=manifest, notes={'schema_version': 1, 'observations': [None, observation]})
    assert len(p['obligations'][0]['observations']) == 1 and not p['evidence']
    assert p['observation_evidence_candidates'][0]['path'] == str(observation_file)
    assert 'unknown or mismatched scope' in p['observation_evidence_candidates'][0]['validation_errors']
    assert 'incomplete' in p['obligations'][0]['observations'][0]['evidence_binding']
    assert not p['summary']['ready']
    for mutation in ({'basis': 'verified'}, {'evidence_ids': ['invented']}, {'condition_id': 'invented'}, {'condition_id': []}):
        changed = dict(observation, **mutation)
        p, _ = packet(evidence=manifest, notes={'schema_version': 1, 'observations': [changed, observation]})
        assert len(p['obligations'][0]['observations']) == 1 and p['input_errors']
    # Forged caller decisions cannot produce reviewed closure or hide requests.
    claims = {'schema_version': 1, 'decisions': [{'obligation_id': 'one', 'applicability': {'status': 'APPLICABLE'}, 'conditions': [{'condition_id': 'inventory', 'status': 'PASS', 'mode': 'reviewed', 'reviewer': 'robot', 'rationale': 'looks fine', 'evidence_ids': ['capture']}]}]}
    p, b = packet(evidence=manifest, decisions=claims)
    assert p['obligations'][0]['status'] == 'UNRESOLVED' and len(b['requests']) == 1
    # Real reviewed closure remains visible and removes only proven requirements.
    target = {k: 'synthetic' for k in m.reporter.contract.SCOPE_FIELDS}
    target.update(bundle_id='test.packet', devices=['phone'], storefronts=['US'], artifact_sha256='a'*64, source_sha256='b'*64, distribution='simulator')
    known_profile = dict(profile, target=target)
    valid_evidence = []
    def add(ident, kind, payload):
        path = root / (ident + '.json')
        path.write_text(json.dumps(payload))
        valid_evidence.append({'id': ident, 'kind': kind, 'path': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'scope': target, 'collected_at': today, 'collector': 'fixture', 'limitations': []})
    add('features', 'feature-inventory', {'inventory': 'fixture scope'})
    add('contents', 'content-inventory', {'inventory': 'fixture complete content'})
    add('authority', 'reviewer-authority', {'schema_version': 1, 'reviewer': 'fixture human', 'authorized_by': 'fixture owner', 'role': 'content reviewer', 'actor_type': 'human', 'obligation_ids': ['one'], 'identity_check': 'owner-confirmed', 'basis': 'synthetic test authority'})
    for condition_id, outcome, source_id in [('applicability', 'APPLICABLE', 'features'), ('inventory', 'PASS', 'contents')]:
        add('review-' + condition_id, 'review-record', {'schema_version': 1, 'obligation_id': 'one', 'condition_id': condition_id, 'outcome': outcome, 'reviewer': 'fixture human', 'rationale': 'complete synthetic review', 'scope': target, 'reviewed_at': today, 'evidence_ids': [source_id], 'observations': [{'evidence_id': source_id, 'location': 'inventory', 'observation': 'complete synthetic condition scope inspected'}], 'authority': {'status': 'verified', 'evidence_ids': ['authority']}, 'source_ids': ['one'], 'applicability_reason': 'fixture applies'})
    p, b = packet(target=known_profile, evidence={'schema_version': 1, 'evidence': valid_evidence})
    assert p['obligations'][0]['status'] == 'VERIFIED_PASS'
    assert p['obligations'][1]['status'] == 'UNRESOLVED'
    assert b['requests'][0]['obligation_ids'] == ['two']
    assert len(p['obligations'][0]['conditions']) == 1
    assert b['remediation_findings'] == []
    # Completed review of a violation still creates an actionable finding,
    # independently of missing-input requests for the other obligation.
    finding_manifest = copy.deepcopy(valid_evidence)
    review_path = root / 'review-inventory.json'
    finding_record = json.loads(review_path.read_text())
    finding_record['outcome'] = 'FINDING'
    finding_record['rationale'] = 'Synthetic complete inventory contains a prohibited entry.'
    review_path.write_text(json.dumps(finding_record))
    next(e for e in finding_manifest if e['id'] == 'review-inventory')['sha256'] = hashlib.sha256(review_path.read_bytes()).hexdigest()
    p, b = packet(target=known_profile, evidence={'schema_version': 1, 'evidence': finding_manifest})
    assert p['obligations'][0]['status'] == 'VERIFIED_FINDING'
    assert not p['summary']['ready'] and p['summary']['verified_pass_percent'] == 0
    assert b['requests'][0]['obligation_ids'] == ['two']
    assert len(b['remediation_findings']) == 1
    finding = b['remediation_findings'][0]
    assert (finding['obligation_id'], finding['condition_id'], finding['owner']) == ('one', 'inventory', 'content owner')
    assert 'review-inventory' in finding['evidence_ids'] and finding['description'] == condition['description']
    assert finding_record['rationale'] in finding['reasons']
    assert 'Risk acceptance does not establish PASS' in finding['next_action']
    assert 'VERIFIED_FINDING' in m.markdown(p, b)

    # Credential text is redacted, including in narrative observations and paths.
    os.environ['PRECHECK_DEMO_PASSWORD'] = 'synthetic-secret-value'
    changed = dict(observation, summary='synthetic-secret-value https://user:pass@example.test/?token=hidden')
    p, b = packet(evidence=manifest, notes={'schema_version': 1, 'observations': [changed]})
    assert 'synthetic-secret-value' not in json.dumps(p) and 'user:pass' not in json.dumps(p) and 'token=hidden' not in json.dumps(p)
    p, b = packet()
    m.write_packet(root / 'output', app, p, b)
    assert stat.S_IMODE((root / 'output').stat().st_mode) == 0o700
    for file in (root / 'output').iterdir():
        assert stat.S_IMODE(file.stat().st_mode) == 0o600
    for output in (app / 'forbidden', root / 'output'):
        try:
            m.write_packet(output, app, p, b)
        except (ValueError, FileExistsError):
            pass
        else:
            raise AssertionError('unsafe or overwrite output accepted')
    (root / 'link').symlink_to(app, target_is_directory=True)
    try:
        m.write_packet(root / 'link' / 'forbidden', app, p, b)
    except ValueError:
        pass
    else:
        raise AssertionError('symlink into source accepted')
    assert sentinel.read_text() == 'read-only source' and sorted(x.name for x in app.iterdir()) == ['source.swift']
    # Installed runtime policies and catalog are used; all current obligations
    # and every attestation-only criterion appear, without fixed catalog counts.
    real_catalog = m.reporter.object_file(m.reporter.REF / 'guideline-obligations.json')
    real_policies = m.reporter.trusted_policies()
    p, b = m.make_packet(profile, empty_evidence, empty_decisions, real_catalog, real_policies, root)
    expected = {r['id'] for r in real_catalog['obligations'] if r['kind'] == 'obligation'}
    assert {r['obligation_id'] for r in p['obligations']} == expected
    assert {i for r in b['requests'] for i in r['obligation_ids']} == expected
    assert {r['obligation_id'] for r in p['obligations'] if r['attestation_only']} == {r['id'] for r in real_catalog['obligations'] if r['kind'] == 'obligation' and {x['route'] for x in r['routes']} == {'attestation'}}
    for item in p['obligations']:
        expected_conditions = real_policies.get(item['obligation_id'], {}).get('conditions', [{'id': 'criterion'}])
        assert {c['condition_id'] for c in item['conditions']} == {c['id'] for c in expected_conditions}
    (root / 'profile.json').write_text(json.dumps(profile))
    proc = subprocess.run(['python3', '-B', str(m.HERE / 'manual-review-packet.py'), '--profile', str(root / 'profile.json'), '--source-root', str(app), '--out', str(root / 'cli-output')], capture_output=True, text=True)
    assert proc.returncode == 0, proc.stderr
    assert json.loads(proc.stdout)['ready'] is False
print('manual review packet tests passed')
PY
