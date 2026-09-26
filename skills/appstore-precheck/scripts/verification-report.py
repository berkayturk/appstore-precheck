#!/usr/bin/env python3
"""Offline evidence-bound readiness report, independent of the legacy verdict."""
import argparse
import hashlib
import importlib.util
import json
import os
import re
import sys
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
REF = HERE.parent / 'references'
sys.dont_write_bytecode = True


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded


contract = module('verification_contract', HERE / 'verification-contract.py')
verifiers = module('verification_verifiers', HERE / 'lib/verification-verifiers.py')


def redact(value):
    """Keep credentials out of reports, including known env-supplied demo secrets."""
    sensitive = re.compile(r'(password|credential|secret|token|private.?key)', re.I)
    secrets = [os.environ.get(key, '') for key in
               ('PRECHECK_DEMO_USERNAME', 'PRECHECK_DEMO_PASSWORD', 'ASC_ISSUER_ID', 'ASC_KEY_ID')]
    def clean(item):
        if isinstance(item, dict):
            return {k: '[REDACTED]' if sensitive.search(k) else clean(v) for k, v in item.items()}
        if isinstance(item, list):
            return [clean(v) for v in item]
        if isinstance(item, str):
            item = re.sub(r'(https?://)[^/@\s]+:[^/@\s]+@', r'\1[REDACTED]@', item)
            item = re.sub(r'([?&](?:token|key|password|secret|access_token)=)[^&\s]+', r'\1[REDACTED]', item, flags=re.I)
            for secret in secrets:
                if len(secret) >= 4:
                    item = item.replace(secret, '[REDACTED]')
        return item
    return clean(value)


def object_file(path):
    value = json.loads(Path(path).read_text(encoding='utf-8'))
    if not isinstance(value, dict):
        raise ValueError('expected JSON object')
    return value


def collection(value, key):
    if not isinstance(value, dict) or value.get('schema_version') != 1:
        raise ValueError('unsupported ' + key + ' version')
    rows = value.get(key)
    if not isinstance(rows, list):
        raise ValueError(key + ' must be a list')
    return rows


def strings(value):
    return isinstance(value, list) and bool(value) and all(isinstance(x, str) and x for x in value)


def nonempty(value):
    return isinstance(value, str) and bool(value.strip())


def trusted_policies():
    result = {}
    for path in sorted((REF / 'verification').glob('*.json')):
        for row in collection(object_file(path), 'obligations'):
            if not isinstance(row, dict) or not nonempty(row.get('obligation_id')):
                raise ValueError('invalid trusted policy row')
            if row['obligation_id'] in result:
                raise ValueError('duplicate trusted policy')
            result[row['obligation_id']] = row
    return result


def evidence_index(manifest, profile, base):
    rows = collection(manifest, 'evidence')
    result, errors = {}, []
    ids = Counter(row.get('id') for row in rows if isinstance(row, dict) and isinstance(row.get('id'), str))
    for number, row in enumerate(rows):
        issues = contract.evidence_errors(row, profile, base)
        if isinstance(row, dict) and isinstance(row.get('id'), str) and ids[row['id']] > 1:
            issues.append('duplicate evidence identity')
        if issues:
            errors.append({'record': number, 'type': 'evidence', 'errors': issues})
            continue
        path = Path(row['path'])
        path = path if path.is_absolute() else Path(base) / path
        # Read the same bytes for hashing and evaluation, closing the validation/read race.
        try:
            content = path.read_bytes()
            if hashlib.sha256(content).hexdigest() != row['sha256']:
                raise ValueError('evidence changed while reading')
            try:
                data = json.loads(content)
            except (UnicodeDecodeError, ValueError):
                data = None
            result[row['id']] = dict(row, path=str(path.resolve()), data=data, content=content)
        except (OSError, ValueError):
            errors.append({'record': number, 'type': 'evidence', 'errors': ['unreadable or changed evidence']})
    return result, errors


def fallback(item):
    return {'obligation_id': item['id'], 'owner': 'developer/reviewer',
            'document_group': 'criterion-specific review', 'applicability_evidence': ['document'],
            'conditions': [{'id': 'criterion', 'description': item['criterion'],
                            'evidence_kinds': [], 'full_positive_verifiers': [],
                            'decisive_finding_verifiers': [],
                            'review_requirement': 'Independent criterion-specific evidence review'}]}


def review_proof(ids, index, profile, obligation, condition, outcome, reviewer, source_ids=None, allowed_kinds=None):
    """Review is explicit provenance, never inferred from a yes answer or file presence.

    Human authority documents remain supplied evidence, not cryptographic proof of
    authenticity. This limitation accompanies every reviewed closure.
    """
    if not strings(ids) or not nonempty(reviewer) or any(i not in index for i in ids):
        return None
    for ident in ids:
        evidence = index[ident]
        record = evidence.get('data')
        if evidence['kind'] != 'review-record' or not isinstance(record, dict):
            continue
        if (record.get('schema_version') != 1 or record.get('obligation_id') != obligation or
                record.get('condition_id') != condition or record.get('outcome') != outcome or
                record.get('reviewer') != reviewer or not nonempty(record.get('rationale')) or
                not contract.scope_matches(profile['target'], record.get('scope', {})) or
                record.get('reviewed_at') != profile['reviewed_at']):
            continue
        substantive = record.get('evidence_ids')
        observations = record.get('observations')
        if (not strings(substantive) or ident in substantive or
                any(i not in index or index[i]['kind'] in ('review-record', 'attestation') for i in substantive) or
                not isinstance(observations, list) or not observations):
            continue
        if allowed_kinds and not any(index[i]['kind'] in allowed_kinds for i in substantive):
            continue
        observed = set()
        for observation in observations:
            if (isinstance(observation, dict) and observation.get('evidence_id') in substantive and
                    nonempty(observation.get('location')) and nonempty(observation.get('observation'))):
                observed.add(observation['evidence_id'])
        if not set(substantive) <= observed:
            continue
        authority = record.get('authority')
        if not isinstance(authority, dict) or authority.get('status') != 'verified' or not strings(authority.get('evidence_ids')):
            continue
        authority_ok = False
        for auth_id in authority['evidence_ids']:
            auth = index.get(auth_id, {})
            doc = auth.get('data')
            if (auth.get('kind') == 'reviewer-authority' and isinstance(doc, dict) and
                    doc.get('schema_version') == 1 and doc.get('reviewer') == reviewer and
                    nonempty(doc.get('authorized_by')) and nonempty(doc.get('role')) and
                    doc.get('actor_type') == 'human' and
                    strings(doc.get('obligation_ids')) and obligation in doc['obligation_ids'] and
                    doc.get('identity_check') == 'owner-confirmed' and
                    nonempty(doc.get('basis'))):
                authority_ok = True
        if not authority_ok:
            continue
        if source_ids is not None and (record.get('source_ids') != source_ids or
                                      not nonempty(record.get('applicability_reason'))):
            continue
        return {'record_id': ident, 'evidence_ids': list(dict.fromkeys(ids + substantive + authority['evidence_ids'])),
                'reviewer': reviewer,
                'limitation': 'Review relies on supplied owner-confirmed authority; hashes establish integrity, not document authenticity or institutional approval.'}
    return None


def evaluate_condition(condition, claims, index, profile, item, errors):
    result = {'condition_id': condition['id'], 'description': condition['description'],
              'status': 'UNKNOWN', 'mode': None, 'evidence_ids': [], 'reasons': [],
              'limitations': [], 'review_requirement': condition.get('review_requirement')}
    outcomes = []
    claims = list(claims)
    # Evidence cannot be concealed by omitting its decision row or claiming PASS.
    # Only trusted condition verifiers are run; raw payload status is never proof.
    allowed_kinds = set(condition.get('evidence_kinds', []))
    eligible = [i for i, e in index.items() if e['kind'] in allowed_kinds]
    for verifier in set(condition.get('full_positive_verifiers', []) + condition.get('decisive_finding_verifiers', [])):
        if eligible:
            claims.append({'status': 'UNKNOWN', 'mode': 'automatic', 'verifier': verifier, 'evidence_ids': eligible})
    for ident, evidence in index.items():
        record = evidence.get('data')
        if (evidence['kind'] == 'review-record' and isinstance(record, dict) and
                record.get('obligation_id') == item['id'] and record.get('condition_id') == condition['id']):
            claims.append({'status': record.get('outcome'), 'mode': 'reviewed',
                           'evidence_ids': [ident], 'reviewer': record.get('reviewer'),
                           'rationale': record.get('rationale')})
    capabilities = verifiers.capabilities()
    for claim in claims:
        if claim.get('status') not in ('PASS', 'FINDING', 'UNKNOWN') or claim.get('mode') not in ('automatic', 'reviewed'):
            errors.append({'type': 'condition', 'errors': ['invalid condition status or mode']})
            continue
        ids = claim.get('evidence_ids')
        if not strings(ids) or any(i not in index for i in ids):
            result['reasons'].append('Missing, invalid or unbound evidence')
            continue
        if claim['mode'] == 'reviewed':
            proof = review_proof(ids, index, profile, item['id'], condition['id'], claim['status'], claim.get('reviewer'),
                                 allowed_kinds=condition.get('evidence_kinds'))
            if proof and nonempty(claim.get('rationale')):
                outcomes.append((claim['status'], 'reviewed', proof['evidence_ids']))
                result['limitations'].append(proof['limitation'])
                result['reviewer'] = proof['reviewer']
            else:
                result['reasons'].append('Independent substantive review and owner-confirmed reviewer authority required')
            continue
        verifier = claim.get('verifier')
        if not isinstance(verifier, str) or verifier not in capabilities:
            errors.append({'type': 'condition', 'errors': ['unknown or unavailable verifier']})
            result['reasons'].append('Unknown or unavailable verifier')
            continue
        allowed = set(condition.get('evidence_kinds', []))
        payloads = [index[i] for i in ids if index[i]['kind'] in allowed]
        try:
            evaluated = verifiers.evaluate(verifier, payloads, {'profile': profile, 'obligation': item, 'condition': condition})
        except (ValueError, TypeError, KeyError, OSError):
            result['reasons'].append('Verifier could not evaluate malformed payload')
            continue
        actual = evaluated.get('status')
        direction = 'positive' if actual == 'PASS' else 'finding'
        policy_key = 'full_positive_verifiers' if actual == 'PASS' else 'decisive_finding_verifiers'
        supported = evaluated.get('evidence_ids', [])
        if (actual in ('PASS', 'FINDING') and capabilities[verifier].get(direction) is True and
                verifier in condition.get(policy_key, []) and strings(supported) and set(supported) <= set(ids)):
            outcomes.append((actual, 'automatic', supported))
            result['verifier'] = verifier
        result['reasons'].append(evaluated.get('reason', 'No sufficient condition proof'))
    findings = [o for o in outcomes if o[0] == 'FINDING']
    passes = [o for o in outcomes if o[0] == 'PASS']
    selected = findings or passes
    if selected:
        result['status'] = selected[0][0]
        result['mode'] = 'reviewed' if any(o[1] == 'reviewed' for o in selected) else 'automatic'
        result['evidence_ids'] = sorted(set(i for o in selected for i in o[2]))
        result['limitations'].extend(str(note) for i in result['evidence_ids'] for note in index[i]['limitations'])
    result['conflict'] = bool(findings and passes)
    if not selected:
        result['reasons'].append('Required condition is not sufficiently verified')
    return result


def build_report(profile, manifest, decisions, catalog, policies, base, config=None):
    contract.validate_profile(profile)
    raw = collection(decisions, 'decisions')
    if not isinstance(config or {}, dict) or not isinstance((config or {}).get('attestations', {}), dict):
        raise ValueError('legacy attestations must be an object')
    index, errors = evidence_index(manifest, profile, base)
    obligations = [row for row in catalog['obligations'] if row['kind'] == 'obligation']
    by_id = {row['id']: row for row in obligations}
    valid_sources = {row['id'] for row in catalog['obligations']}
    grouped = {}
    for number, row in enumerate(raw):
        if not isinstance(row, dict) or not isinstance(row.get('obligation_id'), str) or row['obligation_id'] not in by_id:
            errors.append({'type': 'decision', 'record': number, 'errors': ['unknown obligation or malformed decision']})
            continue
        grouped.setdefault(row['obligation_id'], []).append(row)
    rows = []
    for item in obligations:
        ident = item['id']
        policy = policies.get(ident, fallback(item))
        conditions = policy['conditions']
        required = {c['id'] for c in conditions}
        claims, applicability, gaps = {}, [], []
        for decision in grouped.get(ident, []):
            app = decision.get('applicability', {'status': 'UNKNOWN'})
            if not isinstance(app, dict) or app.get('status') not in ('APPLICABLE', 'NOT_APPLICABLE', 'UNKNOWN'):
                errors.append({'type': 'applicability', 'errors': ['invalid applicability status']})
                app = {'status': 'UNKNOWN'}
            applicability.append(app)
            values = decision.get('conditions', [])
            if not isinstance(values, list):
                errors.append({'type': 'condition', 'errors': ['conditions must be a list']})
                continue
            for claim in values:
                if not isinstance(claim, dict) or not isinstance(claim.get('condition_id'), str) or claim['condition_id'] not in required:
                    errors.append({'type': 'condition', 'errors': ['unknown condition or malformed claim']})
                    continue
                claims.setdefault(claim['condition_id'], []).append(claim)
        evaluated = [evaluate_condition(c, claims.get(c['id'], []), index, profile, item, errors) for c in conditions]
        states = {a['status'] for a in applicability}
        app_status = next(iter(states)) if len(states) == 1 else 'UNKNOWN'
        na, na_proof = False, None
        for app in applicability:
            sources = app.get('source_ids')
            applicable_sources = {ident} | set(item.get('exceptions', []))
            if (app['status'] == 'NOT_APPLICABLE' and nonempty(app.get('rationale')) and strings(sources) and
                    set(sources) <= valid_sources and set(sources) <= applicable_sources):
                na_proof = review_proof(app.get('evidence_ids'), index, profile, ident, 'applicability',
                                        'NOT_APPLICABLE', app.get('reviewer'), sources,
                                        allowed_kinds=policy.get('applicability_evidence'))
                na = na or bool(na_proof)
        satisfied = [c['condition_id'] for c in evaluated if c['status'] == 'PASS']
        violated = [c['condition_id'] for c in evaluated if c['status'] == 'FINDING']
        conflict = len(states) > 1 or any(c['conflict'] for c in evaluated) or (na and bool(violated))
        status = contract.reduce_status(app_status, required, satisfied, violated, na, conflict)
        if app_status == 'UNKNOWN':
            gaps.append('Applicability evidence or scoped decision required')
        if app_status == 'NOT_APPLICABLE' and not na:
            gaps.append('Criterion/exception-specific substantive applicability review required')
        legacy = (config or {}).get('attestations', {}).get(ident, {})
        row = {'obligation_id': ident, 'criterion': item['criterion'], 'section': item.get('section'),
               'applicability': app_status, 'status': status, 'conditions': evaluated,
               'owner': policy.get('owner', 'developer/reviewer'), 'document_group': policy.get('document_group'),
               'scope': profile['target'], 'reviewed_at': profile['reviewed_at'], 'conflict': conflict,
               'missing_requirements': [] if status == 'NOT_APPLICABLE_VERIFIED' else gaps + [c['description'] for c in evaluated if c['status'] == 'UNKNOWN'],
               'attestation': 'ATTESTED_YES' if isinstance(legacy, dict) and legacy.get('answer') == 'yes' else None,
               'limitations': sorted(set(x for c in evaluated for x in c['limitations'])),
               'evidence_ids': sorted(set(i for c in evaluated for i in c['evidence_ids']))}
        if na_proof:
            row['applicability_review'] = na_proof
            row['evidence_ids'] = sorted(set(row['evidence_ids'] + na_proof['evidence_ids']))
            row['limitations'].append(na_proof['limitation'])
        rows.append(row)
    summary = contract.summarize(rows)
    summary['ready'] = summary['ready'] and not errors and not any(r['conflict'] for r in rows)
    summary['automatic_decisions'] = sum(r['status'] in contract.CLOSED and r['status'] != 'NOT_APPLICABLE_VERIFIED' and all(c['mode'] != 'reviewed' for c in r['conditions']) for r in rows)
    summary['reviewed_decisions'] = sum(r['status'] in contract.CLOSED for r in rows) - summary['automatic_decisions']
    return redact({'schema_version': 1, 'profile': profile, 'summary': summary, 'input_errors': errors,
            'policy_sha256': hashlib.sha256(json.dumps(policies, sort_keys=True).encode()).hexdigest(),
            'catalog_sha256': hashlib.sha256(json.dumps(catalog, sort_keys=True).encode()).hexdigest(),
            'evidence': [{k: v for k, v in e.items() if k not in ('data', 'content')} for e in index.values()],
            'obligations': rows, 'limitations': ['Evidence integrity does not establish authenticity. Results apply only to this scope and review date.']})


def markdown(report):
    summary = report['summary']
    lines = ['# Evidence-bound verification', '', 'Ready: ' + str(summary['ready']).lower(),
             'Verified pass: ' + str(summary['verified_pass_percent']) + '%',
             'Decided: ' + str(summary['decided_percent']) + '%', '',
             '| Obligation | Applicability | Result | Owner |', '|---|---|---|---|']
    for row in report['obligations']:
        lines.append('| ' + ' | '.join(str(row[k]).replace('|', '\\|').replace('\n', ' ') for k in
                                       ('obligation_id', 'applicability', 'status', 'owner')) + ' |')
    lines += ['', 'Evidence integrity is not document authenticity. See JSON for conditions, scope, gaps and limitations.']
    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', type=Path, required=True)
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--decisions', type=Path, required=True)
    parser.add_argument('--config', type=Path)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--markdown', type=Path)
    args = parser.parse_args()
    try:
        report = build_report(object_file(args.profile), object_file(args.evidence), object_file(args.decisions),
                              object_file(REF / 'guideline-obligations.json'), trusted_policies(),
                              args.evidence.parent, object_file(args.config) if args.config else {})
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps(report, indent=2, sort_keys=True) + '\n', encoding='utf-8')
        if args.markdown:
            args.markdown.parent.mkdir(parents=True, exist_ok=True)
            args.markdown.write_text(markdown(report), encoding='utf-8')
    except (ValueError, TypeError, KeyError, OSError):
        print('Verification input or output error: invalid top-level schema, policy or unreadable file', file=sys.stderr)
        return 2
    return 0 if report['summary']['ready'] else 1


if __name__ == '__main__':
    sys.exit(main())
