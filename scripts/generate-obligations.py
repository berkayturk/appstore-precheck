#!/usr/bin/env python3
"""Create a copyright-safe public skeleton from a locally ignored source catalog.

This is an import step, not a classification decision. Section reviewers replace
the generic criteria and route gaps in separate section files.
"""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SOURCE = ROOT / '.planning/opus-work/skills/appstore-precheck/references/requirement-catalog.json'
REFERENCE = ROOT / 'skills/appstore-precheck/references'


def dump(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False, sort_keys=True) + '\n')


def kind_for(role):
    if role in ('obligation', 'conditional_obligation', 'compound'):
        return 'obligation'
    if role in ('exception', 'conditional_permission', 'permission'):
        return 'exception'
    if role == 'heading':
        return 'definition'
    return 'informational'


def section(ref):
    return ref[:1] if ref[:1] in '12345' else 'intro'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, default=DEFAULT_SOURCE)
    args = parser.parse_args()
    source = json.loads(args.source.read_text())
    controls = source['controls']
    method = {'static': 'static', 'runtime': 'runtime', 'host_semantic': 'semantic', 'host_visual': 'semantic'}
    registry = {}
    for control in controls:
        key = control['key']
        route = method[control['method']]
        implementation = control['implementation']
        if control['method'] == 'host_semantic':
            implementation = 'skills/appstore-precheck/references/review-catalog.json'
        registry[key] = {
            'route': route,
            'implementation': implementation,
            'symbol': key,
            'tests': [p for p in control['tests'] if (ROOT / p).is_file()] or ['tests/test-coverage.sh'],
            'line_prefix': 'DYNAMIC-' if route == 'runtime' else ('REVIEW-' if route == 'semantic' else 'FAIL:/WARN:/PASS:'),
            'evidence_class': 'runtime' if route == 'runtime' else ('source' if route == 'static' else 'semantic'),
        }
    by_parent = {}
    by_ref = {}
    for c in controls:
        for parent in c['requirement_ids']:
            by_parent.setdefault(parent, []).append(c['key'])
        for apple_ref in c['apple_refs']:
            by_ref.setdefault(apple_ref, []).append(c['key'])

    items = []
    accepted_by_parent = {}
    for atom in source['accepted_atoms']:
        accepted_by_parent.setdefault(atom['parent_fragment_id'], []).append(atom)
    for frag in source['requirements']:
        draft = frag.get('editorial_draft') or {}
        candidates = draft.get('proposed_atomic_parts') or []
        accepted = accepted_by_parent.get(frag['id'], [])
        frag_kind = kind_for(frag.get('editorial_kind') or draft.get('draft_kind'))
        # A source fragment already split into atoms is a traceability node, not
        # a second obligation to inflate the denominator.
        if candidates or accepted:
            frag_kind = 'informational'
        parent = {
            'id': frag['id'], 'apple_ref': frag['apple_ref'], 'anchor': frag['url'],
            'text_sha256': hashlib.sha256(frag['text'].encode()).hexdigest(),
            'kind': frag_kind, 'platforms': frag.get('platforms') or ['iOS'],
            'applicability': {'review_status': frag.get('classification_status', 'unreviewed')},
            'criterion': 'Source fragment awaiting independent section review.',
            'routes': [], 'primary_route': None, 'exceptions': [],
            'related': [p['id'] for p in candidates] + [a['id'] for a in accepted],
            'retired_from': [], 'section': section(frag['apple_ref']),
        }
        if frag_kind != 'obligation':
            parent['routes'] = [{'route': 'not_app_checkable', 'check_id': None,
                                 'decides': 'full', 'evidence_class': 'source-classification',
                                 'reason': 'Classification or supporting source fragment; review required.'}]
            parent['primary_route'] = 'not_app_checkable'
        items.append(parent)
        for part in candidates + accepted:
            role = part.get('role', 'obligation')
            atom_kind = kind_for(role)
            routes = []
            if atom_kind == 'obligation':
                # Legacy controls reference prior fragment identities. A section
                # match is only a partial route pending atom-level review.
                for key in sorted(set(by_parent.get(frag['id'], []) + by_ref.get(frag['apple_ref'], []))):
                    route = registry[key]['route']
                    routes.append({'route': route, 'check_id': key, 'decides': 'partial',
                                   'evidence_class': registry[key]['evidence_class']})
            else:
                routes.append({'route': 'not_app_checkable', 'check_id': None, 'decides': 'full',
                               'evidence_class': 'source-classification',
                               'reason': 'Condition, permission, or exception; applied with related obligation.'})
            items.append({
                'id': part['id'], 'apple_ref': frag['apple_ref'], 'anchor': frag['url'],
                'text_sha256': hashlib.sha256(frag['text'].encode()).hexdigest(),
                'kind': atom_kind, 'platforms': part.get('platforms') or frag.get('platforms') or ['iOS'],
                'applicability': {'review_status': part.get('status', 'pending_independent_review')},
                'criterion': 'Determine whether the applicable source requirement is satisfied.',
                'routes': routes, 'primary_route': routes[0]['route'] if routes else None,
                'exceptions': [], 'related': [frag['id']], 'retired_from': [],
                'section': section(frag['apple_ref']),
            })
    dump(REFERENCE / 'guideline-obligations.json', {
        'schema_version': 1,
        'source': {'url': source['source']['url'], 'apple_updated': source['source']['apple_updated'],
                   'snapshot_sha256': source['source']['html_sha256']},
        'obligations': items,
    })
    dump(REFERENCE / 'check-registry.json', {'schema_version': 1, 'checks': registry})


if __name__ == '__main__':
    main()
