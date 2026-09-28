#!/usr/bin/env python3
"""Validate condition policies and derive capability separately from run results."""
import argparse
import importlib.util
import json
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REF = ROOT / 'skills/appstore-precheck/references'


def verifier_capabilities():
    path = REF.parent / 'scripts/lib/verification-verifiers.py'
    if not path.exists():
        return {}
    spec = importlib.util.spec_from_file_location('verification_verifiers', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.capabilities() if hasattr(module, 'capabilities') else getattr(module, 'VERIFIERS', {})


def load_policies(directory, catalog, capabilities):
    obligations = {x['id']: x for x in catalog['obligations'] if x['kind'] == 'obligation'}
    policies = {}
    for path in sorted(Path(directory).glob('*.json')):
        fragment = json.loads(path.read_text())
        if fragment.get('schema_version') != 1 or not isinstance(fragment.get('obligations'), list):
            raise ValueError('invalid policy fragment: ' + path.name)
        for row in fragment['obligations']:
            ident = row.get('obligation_id')
            if ident not in obligations or ident in policies:
                raise ValueError('unknown or duplicate policy obligation: ' + str(ident))
            if fragment.get('section') != obligations[ident]['section']:
                raise ValueError('policy section mismatch: ' + ident)
            if not row.get('owner') or not row.get('document_group') or not row.get('applicability_evidence'):
                raise ValueError('policy needs owner, document group and applicability evidence: ' + ident)
            for name in row.get('applicability_verifiers', []):
                if name not in capabilities or not capabilities[name].get('applicability'):
                    raise ValueError('unsupported applicability verifier: ' + str(name))
            conditions = row.get('conditions')
            if not isinstance(conditions, list) or not conditions:
                raise ValueError('policy needs required conditions: ' + ident)
            seen = set()
            for condition in conditions:
                cid = condition.get('id')
                if not isinstance(cid, str) or not cid or cid in seen:
                    raise ValueError('invalid condition ID: ' + ident)
                seen.add(cid)
                if not condition.get('description') or not condition.get('evidence_kinds') or not condition.get('review_requirement'):
                    raise ValueError('condition needs description, evidence kinds and review requirements: ' + ident)
                kinds = condition['evidence_kinds']
                mandatory = condition.get('required_positive_evidence_kinds', [])
                groups = condition.get('required_positive_evidence_groups', [])
                if (not isinstance(kinds, list) or any(not isinstance(k, str) or not k for k in kinds) or
                        not isinstance(mandatory, list) or any(not isinstance(k, str) or not k for k in mandatory) or
                        len(mandatory) != len(set(mandatory)) or not set(mandatory) <= set(kinds)):
                    raise ValueError('required evidence kinds must be a subset of accepted kinds: ' + ident)
                if (not isinstance(groups, list) or any(
                        not isinstance(group, list) or not group or
                        any(not isinstance(k, str) or not k for k in group) or
                        len(group) != len(set(group)) or not set(group) <= set(kinds)
                        for group in groups)):
                    raise ValueError('positive evidence alternatives must be nonempty subsets of accepted kinds: ' + ident)
                for field, direction in [('full_positive_verifiers', 'positive'), ('decisive_finding_verifiers', 'finding')]:
                    names = condition.get(field)
                    if not isinstance(names, list) or any(not isinstance(n, str) for n in names):
                        raise ValueError('condition verifier names must be a list: ' + ident)
                    for name in names:
                        if name not in capabilities or not capabilities[name].get(direction):
                            raise ValueError('unimplemented or unsupported verifier direction: ' + name)
            policies[ident] = row
    return policies


def report(catalog, policies, capabilities):
    rows = []
    for item in catalog['obligations']:
        if item['kind'] != 'obligation':
            continue
        policy = policies.get(item['id'])
        conditions = policy['conditions'] if policy else []
        positive = bool(conditions) and all(c['full_positive_verifiers'] for c in conditions)
        finding = any(c['decisive_finding_verifiers'] for c in conditions)
        routes = {r['route'] for r in item['routes']}
        auto_leads = bool(routes & {'static', 'artifact', 'runtime', 'metadata'})
        category = ('machine-verifiable' if positive else 'mixed' if auto_leads or finding
                    else 'human-review' if 'semantic' in routes else 'developer-evidence')
        rows.append({'obligation_id': item['id'], 'apple_ref': item['apple_ref'],
                     'section': item['section'], 'criterion': item['criterion'],
                     'routes': item['routes'], 'exceptions': item['exceptions'],
                     'applicability_conditions': item['applicability'],
                     'profile_applicability': 'UNKNOWN', 'classification': category,
                     'full_positive': positive, 'decisive_finding': finding,
                     'policy_defined': policy is not None,
                     'owner': policy['owner'] if policy else 'developer / qualified reviewer',
                     'document_group': policy['document_group'] if policy else 'unclassified',
                     'applicability_evidence': policy['applicability_evidence'] if policy else ['Scoped feature and exception review required'],
                     'conditions': conditions})
    total = len(rows)
    count = lambda name: sum(bool(x[name]) for x in rows)
    positive, finding = count('full_positive'), count('decisive_finding')
    return {'schema_version': 1, 'source': catalog['source'],
            'summary': {'total_obligations': total, 'policy_defined': count('policy_defined'),
                        'full_positive_capability': positive, 'decisive_finding_capability': finding,
                        'full_positive_percent': round(100 * positive / total, 2) if total else 0,
                        'decisive_finding_percent': round(100 * finding / total, 2) if total else 0,
                        'unknown_applicability': total,
                        'classes': dict(sorted(Counter(x['classification'] for x in rows).items()))},
            'verifiers': capabilities, 'obligations': rows}


def markdown(data):
    s = data['summary']
    lines = ['# Verification capability', '',
             'Generated from condition policies and implemented verifier directions. This is tool capability, not a run result or compliance percentage.', '',
             '| Measure | Count |', '|---|---:|',
             '| Obligations | {} |'.format(s['total_obligations']),
             '| Explicit condition policies | {} |'.format(s['policy_defined']),
             '| Full positive automatic capability | {} |'.format(s['full_positive_capability']),
             '| Decisive negative automatic capability | {} |'.format(s['decisive_finding_capability']),
             '| Unknown applicability without an app profile | {} |'.format(s['unknown_applicability']), '',
             'A positive verifier must cover every required condition. One decisive violation may establish a finding. Other static or runtime signals remain partial. Human evidence requirements are not counted as automatic capability.', '']
    return '\n'.join(lines)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--policies', type=Path, default=REF / 'verification')
    p.add_argument('--out', type=Path, default=ROOT / 'verification-capability.json')
    p.add_argument('--markdown', type=Path, default=ROOT / 'docs/verification-capability.md')
    p.add_argument('--require-complete', action='store_true')
    p.add_argument('--inventory', type=Path, help='Optional complete derived backlog (keep application copies private)')
    a = p.parse_args()
    try:
        catalog = json.loads((REF / 'guideline-obligations.json').read_text())
        capabilities = verifier_capabilities()
        result = report(catalog, load_policies(a.policies, catalog, capabilities), capabilities)
        if a.require_complete and result['summary']['policy_defined'] != result['summary']['total_obligations']:
            raise ValueError('condition policy coverage is incomplete')
        public = {k: v for k, v in result.items() if k != 'obligations'}
        public['full_positive_obligation_ids'] = [r['obligation_id'] for r in result['obligations'] if r['full_positive']]
        public['decisive_finding_obligation_ids'] = [r['obligation_id'] for r in result['obligations'] if r['decisive_finding']]
        public['policy_gap_ids'] = [r['obligation_id'] for r in result['obligations'] if not r['policy_defined']]
        a.out.write_text(json.dumps(public, indent=2, sort_keys=True)+'\n')
        if a.inventory:
            a.inventory.write_text(json.dumps(result, indent=2, sort_keys=True)+'\n')
        a.markdown.write_text(markdown(result))
        print(json.dumps(result['summary'], sort_keys=True))
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print('verification-policy: ' + str(exc), file=sys.stderr)
        return 2
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
