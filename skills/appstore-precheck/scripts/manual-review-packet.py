#!/usr/bin/env python3
"""Create an offline, private criterion-specific review packet; never grant approval."""
import argparse
import hashlib
import importlib.util
import json
import os
import sys
from pathlib import Path

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('verification_report', HERE / 'verification-report.py')
reporter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reporter)


def stable_id(prefix, value):
    return prefix + hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()[:16]


def annotation_index(value, catalog, policies, evidence, validated_ids):
    """Annotations are analyst notes, never verifier or reviewer proof."""
    rows = reporter.collection(value, 'observations')
    known = {r['id']: r for r in catalog['obligations'] if r['kind'] == 'obligation'}
    available = {r['id'] for r in evidence}
    index, errors = {}, []
    for number, row in enumerate(rows):
        if not isinstance(row, dict):
            errors.append({'record': number, 'type': 'observation', 'errors': ['expected observation object']})
            continue
        ident = row.get('obligation_id')
        item = known.get(ident) if isinstance(ident, str) else None
        policy = policies.get(ident, reporter.fallback(item)) if item else {}
        condition_ids = {'applicability'} | {c['id'] for c in policy.get('conditions', [])}
        if (not item or not isinstance(row.get('condition_id'), str) or row['condition_id'] not in condition_ids or
                row.get('basis') not in ('observed', 'inferred', 'attested') or
                not reporter.nonempty(row.get('summary')) or
                not reporter.nonempty(row.get('location')) or
                not reporter.strings(row.get('evidence_ids')) or
                not set(row['evidence_ids']) <= available or
                not isinstance(row.get('limitations'), list)):
            errors.append({'record': number, 'type': 'observation', 'errors': ['invalid annotation, condition, basis or bound evidence reference']})
            continue
        safe = {k: row[k] for k in ('condition_id', 'basis', 'summary', 'location', 'evidence_ids', 'limitations')}
        safe['evidence_binding'] = 'validated' if set(row['evidence_ids']) <= validated_ids else 'incomplete or invalid; observation cannot establish scoped closure'
        safe['decision_effect'] = 'none; only evaluator-validated proof can close a condition'
        index.setdefault(ident, []).append(safe)
    return index, errors


def make_packet(profile, manifest, decisions, catalog, policies, base, config=None, observations=None):
    # Recompute closure from trusted policies and substantive inputs. A supplied
    # report or annotation labelled VERIFIED is not an input to this workflow.
    report = reporter.build_report(profile, manifest, decisions, catalog, policies, base, config)
    candidates = []
    for number, evidence in enumerate(reporter.collection(manifest, 'evidence')):
        if not isinstance(evidence, dict) or not reporter.nonempty(evidence.get('id')):
            continue
        candidate = {k: evidence.get(k) for k in ('id', 'kind', 'path', 'sha256', 'collected_at', 'scope', 'collector', 'limitations')}
        candidate['validation_errors'] = reporter.contract.evidence_errors(evidence, profile, base)
        candidate['record'] = number
        candidates.append(candidate)
    notes, annotation_errors = annotation_index(observations or {'schema_version': 1, 'observations': []},
                                               catalog, policies, candidates, {e['id'] for e in report['evidence']})
    indexed = {r['obligation_id']: r for r in report['obligations']}
    reviewed_rationales = {}
    for evidence in report['evidence']:
        if evidence['kind'] != 'review-record':
            continue
        try:
            content = Path(evidence['path']).read_bytes()
            record = json.loads(content)
            if (hashlib.sha256(content).hexdigest() == evidence['sha256'] and
                    isinstance(record, dict) and reporter.nonempty(record.get('rationale'))):
                reviewed_rationales[evidence['id']] = record['rationale']
        except (OSError, ValueError):
            pass
    rows, requests, shared, findings = [], {}, {}, []
    for item in catalog['obligations']:
        if item['kind'] != 'obligation':
            continue
        ident = item['id']
        policy = policies.get(ident, reporter.fallback(item))
        result = indexed[ident]
        route_names = {r['route'] for r in item.get('routes', [])}
        row = {'obligation_id': ident, 'apple_ref': item.get('apple_ref'),
               'criterion': item['criterion'], 'anchor': item.get('anchor'),
               'owner': policy['owner'], 'document_group': policy['document_group'],
               'policy_defined': ident in policies, 'attestation_only': route_names == {'attestation'},
               'applicability_conditions': item.get('applicability', {}),
               'exceptions': item.get('exceptions', []),
               'applicability': result['applicability'], 'status': result['status'],
               'attestation': result.get('attestation'), 'observations': notes.get(ident, []),
               'evidence_ids': result['evidence_ids'], 'limitations': result['limitations'],
               'conditions': []}
        unresolved_app = result['applicability'] == 'UNKNOWN' or result.get('conflict', False)
        requirements = [{'condition_id': 'applicability',
                         'description': 'Establish criterion and exception applicability for this exact scope.',
                         'review_requirement': 'Provide scoped feature, territory and exception evidence; cite the criterion or an explicit related exception. Absence of source keywords is not absence of a feature.',
                         'evidence_kinds': policy['applicability_evidence'],
                         'required_positive_evidence_kinds': [],
                         'needed': unresolved_app}]
        for condition, evaluated in zip(policy['conditions'], result['conditions']):
            needed = (result['status'] != 'NOT_APPLICABLE_VERIFIED' and
                      (evaluated['status'] == 'UNKNOWN' or evaluated.get('conflict', False)))
            detail = {'condition_id': condition['id'], 'description': condition['description'],
                      'review_requirement': condition.get('review_requirement'),
                      'evidence_kinds': condition['evidence_kinds'],
                      'required_positive_evidence_kinds': condition.get('required_positive_evidence_kinds', []),
                      'full_positive_verifiers': condition['full_positive_verifiers'],
                      'decisive_finding_verifiers': condition['decisive_finding_verifiers'],
                      'result': evaluated, 'needed': needed}
            row['conditions'].append(detail)
            requirements.append(detail)
            if evaluated['status'] == 'FINDING':
                findings.append({'obligation_id': ident, 'condition_id': condition['id'],
                    'owner': policy['owner'], 'description': condition['description'],
                    'obligation_status': result['status'], 'applicability': result['applicability'],
                    'evidence_ids': evaluated['evidence_ids'], 'mode': evaluated.get('mode'),
                    'reviewer': evaluated.get('reviewer'),
                    'reasons': evaluated['reasons'] + [reviewed_rationales[i] for i in evaluated['evidence_ids'] if i in reviewed_rationales],
                    'limitations': evaluated['limitations'],
                    'next_action': 'Resolve or investigate the evidenced condition violation within authorized scope, then collect fresh proof and re-run verification. Risk acceptance does not establish PASS.'})
        row['applicability_review'] = requirements[0]
        rows.append(row)
        pending = [r for r in requirements if r['needed']]
        if not pending:
            continue
        group_key = (policy['owner'], policy['document_group'])
        request_id = stable_id('request-', group_key)
        request = requests.setdefault(request_id, {'id': request_id, 'owner': policy['owner'],
                  'document_group': policy['document_group'], 'obligation_ids': [], 'requirements': [],
                  'instruction': 'Supply one scoped evidence package for this group, with a location for each mapped condition. Accepted evidence kinds are alternatives subject to the full review requirement; mere document presence is insufficient.',
                  'reviewer': None, 'authority_status': 'NOT_SUPPLIED_BY_GENERATOR'})
        request['obligation_ids'].append(ident)
        for requirement in pending:
            ref = {'obligation_id': ident, 'condition_id': requirement['condition_id']}
            request['requirements'].append(dict(ref, description=requirement['description'],
                        required_review=requirement.get('review_requirement'),
                        accepted_evidence_kinds=requirement['evidence_kinds'],
                        required_positive_evidence_kinds=requirement.get('required_positive_evidence_kinds', [])))
            for kind in sorted(set(requirement['evidence_kinds'])):
                common = shared.setdefault(kind, {'kind': kind, 'owners': set(), 'request_ids': set(), 'requirements': [], 'mandatory_positive_for': []})
                if kind in requirement.get('required_positive_evidence_kinds', []):
                    common['mandatory_positive_for'].append(ref)
                common['owners'].add(policy['owner'])
                common['request_ids'].add(request_id)
                common['requirements'].append(ref)
    shared_rows = []
    for kind in sorted(shared):
        value = shared[kind]
        shared_rows.append(dict(value, owners=sorted(value['owners']), request_ids=sorted(value['request_ids'])))
    backlog = {'schema_version': 1, 'scope': profile['target'], 'reviewed_at': profile['reviewed_at'],
               'requests': sorted(requests.values(), key=lambda r: (r['owner'], r['document_group'])),
               'remediation_findings': findings,
               'shared_evidence': shared_rows,
               'review_authority_request': {'owner': 'product owner / responsible organization',
                    'required': bool(requests), 'obligation_ids': sorted({r for v in requests.values() for r in v['obligation_ids']}),
                    'content': 'Identify a human reviewer, their role and exact authorized obligation IDs, the authorizing owner and basis, and owner-confirmed identity. Supply substantive condition-specific observations separately. The generator supplies no identity, signature, approval or claim of verified authority.'}}
    packet = {'schema_version': 1, 'packet_type': 'manual-evidence-review', 'profile': report['profile'],
              'catalog_sha256': report['catalog_sha256'], 'policy_sha256': report['policy_sha256'],
              'summary': dict(report['summary'], attestation_only_obligations=sum(r['attestation_only'] for r in rows),
                              policy_gap_count=sum(not r['policy_defined'] for r in rows),
                              request_groups=len(requests), shared_evidence_kinds=len(shared_rows),
                              remediation_findings=len(findings)),
              'evidence': report['evidence'], 'observation_evidence_candidates': candidates, 'input_errors': report['input_errors'] + annotation_errors,
              'basis_definitions': {
                  'observed': 'A cited local observation; limited to the evidence scope and sampled content. It is not a compliance result.',
                  'inferred': 'An analyst interpretation that needs confirmation, not a fact or finding.',
                  'attested': 'A supplied answer or owner assertion; even yes does not establish verified compliance.',
                  'verified': 'Only a result re-evaluated by the trusted verification engine from sufficient scoped evidence and required review provenance.'},
              'limitations': report['limitations'] + [
                  'AI analysis cannot create human review authority, document authenticity, institutional approval or an owner signature.',
                  'A screenshot, small clean sample, source keyword or document presence does not establish complete content, operational or legal coverage.',
                  'Remote content and backend operations require ongoing controls; a snapshot cannot guarantee future conduct.',
                  'Evidence kinds in the shared index are reusable collection candidates, not a demand to provide every alternative or a guarantee of sufficiency.',
                  'Missing policy is an explicit gap; criterion fallback does not supply a complete review policy.'],
              'obligations': rows}
    return reporter.redact(packet), reporter.redact(backlog)


def markdown(packet, backlog):
    lines = ['# Manual evidence review packet', '',
             'This packet requests evidence and records observations; it grants no approval.',
             'Ready according to the verification engine: ' + str(packet['summary']['ready']).lower(),
             'Obligations: {}. Attestation-only: {}. Policy gaps: {}.'.format(
                 len(packet['obligations']), packet['summary']['attestation_only_obligations'], packet['summary']['policy_gap_count']), '',
             'Observed = cited observation; inferred = interpretation; attested = supplied assertion; verified = evaluator-proven result.', '',
             '## Grouped developer inputs', '']
    for request in backlog['requests']:
        lines += ['### ' + request['document_group'], '', 'Owner: ' + request['owner'], '', request['instruction'], '']
        for requirement in request['requirements']:
            lines += ['- `{}` / `{}`: {} Accepted evidence: {}. Required for PASS: {}. Review: {}'.format(
                requirement['obligation_id'], requirement['condition_id'], requirement['description'],
                ', '.join(requirement['accepted_evidence_kinds']) or 'policy gap', ', '.join(requirement['required_positive_evidence_kinds']) or 'see criterion review scope', requirement['required_review'])]
        lines.append('')
    lines += ['## Evidenced findings requiring action', '']
    if not backlog['remediation_findings']:
        lines += ['No evaluated condition findings recorded; this does not establish compliance.', '']
    for finding in backlog['remediation_findings']:
        lines += ['- `{}` / `{}` — owner: {}; obligation result: {}; applicability: {}. {} Evidence: {}. Reasons: {}. {}'.format(
            finding['obligation_id'], finding['condition_id'], finding['owner'],
            finding['obligation_status'], finding['applicability'], finding['description'],
            ', '.join(finding['evidence_ids']), '; '.join(finding['reasons']) or 'See cited condition proof', finding['next_action']), '']
    lines += ['## Review provenance', '', backlog['review_authority_request']['content'], '',
              'The JSON packet includes every obligation and all required conditions, evidence IDs, verified results, annotations and gaps. The JSON backlog deduplicates reusable evidence kinds without merging criterion-specific judgments.', '']
    return '\n'.join(lines)


def write_packet(directory, source_root, packet, backlog):
    """Never write into the supplied app, follow output symlinks or overwrite data."""
    source = source_root.resolve(strict=True)
    output = directory.resolve()
    if not source.is_dir() or output == source or source in output.parents:
        raise ValueError('output must be outside source')
    # A fresh directory avoids clobbering private work and symlinked leaf files.
    output.mkdir(mode=0o700, parents=True, exist_ok=False)
    os.chmod(str(output), 0o700)
    files = {'manual-review-packet.json': json.dumps(packet, indent=2, sort_keys=True) + '\n',
             'developer-input-backlog.json': json.dumps(backlog, indent=2, sort_keys=True) + '\n',
             'manual-review-packet.md': markdown(packet, backlog)}
    for name, content in files.items():
        fd = os.open(str(output / name), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, 'w', encoding='utf-8') as handle:
            handle.write(content)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', type=Path, required=True)
    parser.add_argument('--evidence', type=Path, help='External versioned manifest; omitted means no supplied evidence')
    parser.add_argument('--decisions', type=Path, help='External decisions; omitted means no supplied claims')
    parser.add_argument('--config', type=Path, help='Optional external legacy attestations')
    parser.add_argument('--observations', type=Path, help='Optional analyst annotations; never review authority')
    parser.add_argument('--source-root', type=Path, required=True, help='Read-only application root, used to prohibit output inside it')
    parser.add_argument('--out', type=Path, required=True, help='New private output directory outside the application')
    args = parser.parse_args()
    try:
        packet, backlog = make_packet(reporter.object_file(args.profile),
            reporter.object_file(args.evidence) if args.evidence else {'schema_version': 1, 'evidence': []},
            reporter.object_file(args.decisions) if args.decisions else {'schema_version': 1, 'decisions': []},
            reporter.object_file(reporter.REF / 'guideline-obligations.json'), reporter.trusted_policies(),
            args.evidence.parent if args.evidence else args.profile.parent,
            reporter.object_file(args.config) if args.config else {},
            reporter.object_file(args.observations) if args.observations else None)
        write_packet(args.out, args.source_root, packet, backlog)
    except (ValueError, TypeError, KeyError, OSError):
        print('Manual review packet error: invalid input, policy or external output directory', file=sys.stderr)
        return 2
    print(json.dumps({'obligations': len(packet['obligations']), 'requests': len(backlog['requests']),
                      'input_errors': len(packet['input_errors']), 'ready': packet['summary']['ready']}))
    # Successful packet generation is not a readiness exit code. Verification's
    # separate 0/1 readiness contract is intentionally unchanged.
    return 0


if __name__ == '__main__':
    sys.exit(main())
