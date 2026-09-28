#!/usr/bin/env python3
"""Validate obligation routes and derive public coverage reports (stdlib only)."""
import argparse
import importlib.util
import json
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REF = ROOT / 'skills/appstore-precheck/references'
ROUTES = {'static', 'artifact', 'runtime', 'metadata', 'semantic', 'attestation', 'not_app_checkable'}
AUTO = {'static', 'artifact', 'runtime', 'metadata'}


def fail(message):
    raise ValueError(message)


def load(path):
    return json.loads(path.read_text())


def merge_fragments(catalog, registry):
    """Merge reviewed section and route files by persistent ID/check ID."""
    items = {item['id']: item for item in catalog['obligations']}
    for path in sorted((REF / 'obligations').glob('*.json')):
        section = load(path)
        for item in section.get('obligations', []):
            items[item['id']] = item
    catalog['obligations'] = list(items.values())
    for path in sorted((REF / 'registry').glob('*.json')):
        registry['checks'].update(load(path).get('checks', {}))
    return catalog, registry


def validate(catalog, registry):
    if catalog.get('schema_version') != 1 or registry.get('schema_version') != 1:
        fail('unsupported schema version')
    checks = registry['checks']
    if not isinstance(checks, dict):
        fail('registry checks must be an object')
    for check_id, check in checks.items():
        if check['route'] not in ROUTES - {'not_app_checkable'}:
            fail('invalid registry route: ' + check_id)
        implementation = ROOT / check['implementation']
        if not implementation.is_file() or check['symbol'] not in implementation.read_text(errors='replace'):
            fail('missing implementation/symbol: ' + check_id)
        if not check.get('tests') or any(not (ROOT / test).is_file() for test in check['tests']):
            fail('missing test: ' + check_id)
        if not check.get('line_prefix') or not check.get('evidence_class'):
            fail('incomplete registry entry: ' + check_id)
    ids = set()
    kinds = {item['id']: item['kind'] for item in catalog['obligations']}
    for item in catalog['obligations']:
        ident = item['id']
        if ident in ids:
            fail('duplicate obligation id: ' + ident)
        ids.add(ident)
        for linked in item['exceptions']:
            if kinds.get(linked) != 'exception':
                fail('exceptions[] must reference exception-kind records: ' + ident + ' -> ' + str(linked))
        if not item['routes'] and item['kind'] != 'obligation':
            fail('non-obligation record without a justified route: ' + ident)
        if item['kind'] not in {'obligation', 'exception', 'informational', 'definition'}:
            fail('invalid kind: ' + ident)
        if any(key not in item for key in ('apple_ref', 'anchor', 'text_sha256', 'criterion',
                                          'platforms', 'applicability', 'routes', 'primary_route',
                                          'exceptions', 'related', 'retired_from')):
            fail('incomplete obligation: ' + ident)
        if 'text' in item or len(item['criterion'].split()) > 55:
            fail('source text or long criterion in public catalog: ' + ident)
        for route in item['routes']:
            if route['route'] not in ROUTES:
                fail('unknown route: ' + ident)
            check_id = route.get('check_id')
            if route['route'] == 'not_app_checkable':
                if not route.get('reason') or item['kind'] == 'obligation':
                    fail('unjustified non-app route: ' + ident)
            elif check_id not in checks or checks[check_id]['route'] != route['route']:
                fail('unknown or mismatched check: ' + ident + ' ' + str(check_id))
            if route.get('decides') not in {'full', 'partial'}:
                fail('invalid decision scope: ' + ident)
        if item['primary_route'] is not None and item['primary_route'] not in [r['route'] for r in item['routes']]:
            fail('primary route missing: ' + ident)
    return checks


def full_positive_capability(catalog):
    """Count obligations whose every condition has an implemented positive verifier.

    Derived by the condition-policy tool (scripts/verification-policy.py) so the
    coverage headline can sit next to real automatic decision capability. Returns
    None only when that tool is not present; invalid policies raise ValueError.
    """
    path = ROOT / 'scripts/verification-policy.py'
    if not path.is_file():
        return None
    spec = importlib.util.spec_from_file_location('verification_policy', path)
    policy = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(policy)
    capabilities = policy.verifier_capabilities()
    policies = policy.load_policies(REF / 'verification', catalog, capabilities)
    return policy.report(catalog, policies, capabilities)['summary']['full_positive_capability']


def report(catalog, checks):
    obligations = [x for x in catalog['obligations'] if x['kind'] == 'obligation']
    route_counts = Counter()
    automatic = semantic = attestation_only = non_attestation = automated = 0
    gaps = []
    for item in obligations:
        routes = {r['route'] for r in item['routes']}
        route_counts.update(routes)
        if not routes:
            gaps.append(item['id'])
        if any(r['route'] in AUTO and r['decides'] == 'full' for r in item['routes']):
            automatic += 1
        if routes - {'attestation'}:
            non_attestation += 1
        if routes & AUTO:
            automated += 1
        if 'semantic' in routes:
            semantic += 1
        if routes == {'attestation'}:
            attestation_only += 1
    routed_checks = {r.get('check_id') for item in catalog['obligations'] for r in item['routes'] if r.get('check_id')}
    unrouted_checks = sorted(check for check in checks if check not in routed_checks)
    return {
        'schema_version': 1, 'source': catalog['source'],
        'unrouted_checks': unrouted_checks,
        'total_obligations': len(obligations), 'routed_obligations': len(obligations) - len(gaps),
        'obligations_without_route': len(gaps), 'unrouted_ids': gaps,
        'routes': {route: route_counts[route] for route in sorted(ROUTES)},
        'automatic_possible': automatic, 'semantic_possible': semantic,
        'attestation_only': attestation_only, 'registered_checks': len(checks),
        'non_attestation_route': non_attestation, 'automated_route': automated,
    }


def share(count, total):
    """Percentage with one decimal, or two when a nonzero share would round to 0.x."""
    value = (100 * count / total) if total else 0
    return '{:.2f}%'.format(value) if 0 < value < 1 else '{:.1f}%'.format(value)


def markdown(summary):
    total = summary['total_obligations']
    row = lambda label, count: '| {} | {} | {} |'.format(label, count, share(count, total))
    rows = ['# Guideline obligation coverage', '',
            'This counts available routes, not checks that ran for an app. Routes can overlap.', '',
            'Every obligation carries the generic developer-attestation route, so the routed share is complete by construction. '
            'It shows that each obligation has a documented way to be answered, not that the tool can decide it automatically. '
            'This report does not certify App Store compliance.', '',
            'Condition-based executable capability is reported separately in [verification-capability.md](verification-capability.md). Legacy full-route labels do not establish evidence-bound readiness.', '',
            '| Measure | Count | Share |', '|---|---:|---:|',
            '| Obligations | {} | 100% |'.format(total),
            row('Routed (including developer attestation)', summary['routed_obligations']),
            row('Without route', summary['obligations_without_route']),
            row('With a route other than attestation', summary['non_attestation_route']),
            row('With an automated route (static, artifact, runtime or metadata)', summary['automated_route'])]
    if summary.get('full_positive_automatic') is not None:
        rows.append(row('Full positive automatic decision capability', summary['full_positive_automatic']))
    rows += [row('Legacy full-route declarations', summary['automatic_possible']),
             row('Semantic route', summary['semantic_possible']),
             row('Attestation only (developer attestation or evidence)', summary['attestation_only']),
             '', 'Automated and semantic routes are partial signals unless the capability row says otherwise.',
             '', '## Route counts', '', '| Route | Obligations |', '|---|---:|']
    rows += ['| {} | {} |'.format(k, v) for k, v in summary['routes'].items()]
    rows += ['', 'Section classifications and atomic splits received an independent review; the route count is not an App Store approval guarantee.', '']
    return '\n'.join(rows)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--catalog', type=Path, default=REF / 'guideline-obligations.json')
    parser.add_argument('--registry', type=Path, default=REF / 'check-registry.json')
    parser.add_argument('--output', type=Path, default=ROOT / 'coverage.json')
    parser.add_argument('--markdown', type=Path, default=ROOT / 'docs/guideline-coverage.md')
    parser.add_argument('--require-complete', action='store_true')
    parser.add_argument('--merge', action='store_true', help='merge reviewed section and route fragments')
    parser.add_argument('--changed-ref', help='print IDs affected by a changed Apple section')
    args = parser.parse_args()
    try:
        catalog, registry = load(args.catalog), load(args.registry)
        if args.changed_ref:
            ref = args.changed_ref
            for item in catalog['obligations']:
                if item['apple_ref'] == ref or item['apple_ref'].startswith(ref + '(') or item['apple_ref'].startswith(ref + '.'):
                    print(item['id'])
            return 0
        if args.merge:
            catalog, registry = merge_fragments(catalog, registry)
            args.catalog.write_text(json.dumps(catalog, indent=2, ensure_ascii=False, sort_keys=True) + '\n')
            args.registry.write_text(json.dumps(registry, indent=2, ensure_ascii=False, sort_keys=True) + '\n')
        checks = validate(catalog, registry)
        summary = dict(report(catalog, checks), full_positive_automatic=full_positive_capability(catalog))
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print('coverage: ' + str(exc), file=sys.stderr)
        return 2
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.markdown.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(summary, indent=2, sort_keys=True) + '\n')
    args.markdown.write_text(markdown(summary))
    print('coverage: {}/{} routed; {} gaps'.format(summary['routed_obligations'], summary['total_obligations'], summary['obligations_without_route']))
    incomplete = summary['obligations_without_route'] or summary['unrouted_checks']
    if args.require_complete and summary['unrouted_checks']:
        print('coverage: registered checks without an obligation route: ' + ', '.join(summary['unrouted_checks']), file=sys.stderr)
    return 1 if args.require_complete and incomplete else 0


if __name__ == '__main__':
    sys.exit(main())
