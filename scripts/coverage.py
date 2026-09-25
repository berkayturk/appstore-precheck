#!/usr/bin/env python3
"""Validate obligation routes and derive public coverage reports (stdlib only)."""
import argparse
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
    for item in catalog['obligations']:
        ident = item['id']
        if ident in ids:
            fail('duplicate obligation id: ' + ident)
        ids.add(ident)
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


def report(catalog, checks):
    obligations = [x for x in catalog['obligations'] if x['kind'] == 'obligation']
    route_counts = Counter()
    automatic = semantic = attestation_only = 0
    gaps = []
    for item in obligations:
        routes = {r['route'] for r in item['routes']}
        route_counts.update(routes)
        if not routes:
            gaps.append(item['id'])
        if any(r['route'] in AUTO and r['decides'] == 'full' for r in item['routes']):
            automatic += 1
        if 'semantic' in routes:
            semantic += 1
        if routes == {'attestation'}:
            attestation_only += 1
    return {
        'schema_version': 1, 'source': catalog['source'],
        'total_obligations': len(obligations), 'routed_obligations': len(obligations) - len(gaps),
        'obligations_without_route': len(gaps), 'unrouted_ids': gaps,
        'routes': {route: route_counts[route] for route in sorted(ROUTES)},
        'automatic_possible': automatic, 'semantic_possible': semantic,
        'attestation_only': attestation_only, 'registered_checks': len(checks),
    }


def markdown(summary):
    total = summary['total_obligations']
    percent = lambda n: (100 * n / total) if total else 0
    rows = ['# Guideline obligation coverage', '',
            'This counts available routes, not checks that ran for an app. Routes can overlap.', '',
            '| Measure | Count | Share |', '|---|---:|---:|',
            '| Obligations | {} | 100% |'.format(total),
            '| Routed | {} | {:.1f}% |'.format(summary['routed_obligations'], percent(summary['routed_obligations'])),
            '| Without route | {} | {:.1f}% |'.format(summary['obligations_without_route'], percent(summary['obligations_without_route'])),
            '| Potential automatic decision | {} | {:.1f}% |'.format(summary['automatic_possible'], percent(summary['automatic_possible'])),
            '| Semantic route | {} | {:.1f}% |'.format(summary['semantic_possible'], percent(summary['semantic_possible'])),
            '| Attestation only | {} | {:.1f}% |'.format(summary['attestation_only'], percent(summary['attestation_only'])),
            '', '## Route counts', '', '| Route | Obligations |', '|---|---:|']
    rows += ['| {} | {} |'.format(k, v) for k, v in summary['routes'].items()]
    rows += ['', 'The source classification and atomic split remain subject to independent section review.', '']
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
        summary = report(catalog, checks)
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print('coverage: ' + str(exc), file=sys.stderr)
        return 2
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.markdown.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(summary, indent=2, sort_keys=True) + '\n')
    args.markdown.write_text(markdown(summary))
    print('coverage: {}/{} routed; {} gaps'.format(summary['routed_obligations'], summary['total_obligations'], summary['obligations_without_route']))
    return 1 if args.require_complete and summary['obligations_without_route'] else 0


if __name__ == '__main__':
    sys.exit(main())
