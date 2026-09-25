#!/usr/bin/env python3
"""Render an obligation-level run report without treating self-report as verification.

The catalog and registry describe *possible* routes. --run-results describes routes
that actually ran. Its shape is {"checks": {check_id: {"status": ...,
"evidence": "pointer", "reason": "..."}}}. A missing check is NOT_RUN.
"""

import argparse
import datetime as dt
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path

HERE = Path(__file__).resolve()
REF = HERE.parent.parent / 'references'
AUTO_ROUTES = {'static', 'artifact', 'runtime', 'metadata'}
DECISIVE = {'PASS', 'FINDING'}
RUN_STATUSES = DECISIVE | {'WARN', 'SKIP', 'NOT_RUN', 'REVIEW_REQUIRED'}
ANSWERS = {'yes', 'no', 'unknown'}


def read_object(path, default=None):
    if path is None:
        return {} if default is None else default
    value = json.loads(path.read_text(encoding='utf-8'))
    if not isinstance(value, dict):
        raise ValueError(f'{path}: expected JSON object')
    return value


def pointer(value, field):
    if not isinstance(value, str) or not value.strip() or len(value) > 500 or '\n' in value:
        raise ValueError(f'{field}: expected a nonempty, single-line evidence pointer (max 500 characters)')
    return value.strip()


def validate_run_results(run_results, registry):
    checks = run_results.get('checks', {})
    if not isinstance(checks, dict):
        raise ValueError('run results checks must be an object')
    unknown = set(checks) - set(registry.get('checks', {}))
    if unknown:
        raise ValueError('run results contain unregistered check: ' + sorted(unknown)[0])
    for check_id, result in checks.items():
        if not isinstance(result, dict) or result.get('status') not in RUN_STATUSES:
            raise ValueError(f'{check_id}: invalid run status')
        if result['status'] in DECISIVE:
            pointer(result.get('evidence'), f'{check_id} evidence')
        elif result.get('evidence') is not None:
            pointer(result['evidence'], f'{check_id} evidence')
        if result['status'] in {'SKIP', 'NOT_RUN', 'REVIEW_REQUIRED'}:
            pointer(result.get('reason'), f'{check_id} reason')
    return checks


def evaluate_attestation(ident, raw):
    """Return a self-report status; never equate a yes answer with an observed PASS."""
    if raw is None:
        return {'status': 'ATTESTATION_REQUIRED', 'reason': 'No attestation supplied'}
    if not isinstance(raw, dict):
        return {'status': 'ATTESTATION_REQUIRED', 'reason': 'Attestation must be an object'}
    answer, evidence, answered_on = (raw.get(k) for k in ('answer', 'evidence', 'answered_on'))
    if not isinstance(answer, str) or answer not in ANSWERS:
        return {'status': 'ATTESTATION_REQUIRED', 'reason': 'Answer must be yes, no, or unknown'}
    try:
        evidence = pointer(evidence, f'{ident} evidence')
        if not isinstance(answered_on, str) or dt.date.fromisoformat(answered_on).isoformat() != answered_on:
            raise ValueError('answered_on must be YYYY-MM-DD')
        if dt.date.fromisoformat(answered_on) > dt.date.today():
            raise ValueError('answered_on cannot be in the future')
    except ValueError as exc:
        return {'status': 'ATTESTATION_REQUIRED', 'reason': str(exc)}
    return {'status': {'yes': 'ATTESTED_YES', 'no': 'ATTESTED_NO',
                       'unknown': 'ATTESTATION_UNKNOWN'}[answer],
            'answer': answer, 'evidence': evidence, 'answered_on': answered_on}


def question_for(item):
    criterion = item['criterion'].strip().rstrip('.?')
    return f'Does the submitted app satisfy this criterion: {criterion}? Cite specific evidence.'


def build_report(catalog, registry, config, run_results):
    """Join route declarations, observed check outcomes, and developer attestations."""
    if catalog.get('schema_version') != 1 or registry.get('schema_version') != 1:
        raise ValueError('unsupported catalog or registry schema')
    runs = validate_run_results(run_results, registry)
    attestations = config.get('attestations', {})
    if not isinstance(attestations, dict):
        raise ValueError('config attestations must be an object')
    obligations = [item for item in catalog.get('obligations', []) if item.get('kind') == 'obligation']
    ids = {item['id'] for item in obligations}
    if len(ids) != len(obligations):
        raise ValueError('duplicate obligation ID')
    unknown = set(attestations) - ids
    if unknown:
        raise ValueError('config contains unknown obligation ID: ' + sorted(unknown)[0])
    rows = []
    route_counts = Counter()
    route_runs = Counter()
    section_rows = defaultdict(list)
    not_run_reasons = Counter()
    for item in obligations:
        evaluated = []
        attestation = None
        route_counts.update({r['route'] for r in item['routes']})
        for route in item['routes']:
            kind, check_id = route['route'], route.get('check_id')
            if kind == 'attestation':
                if check_id not in registry['checks'] or registry['checks'][check_id]['route'] != kind:
                    raise ValueError('invalid attestation check: ' + item['id'] + '/' + str(check_id))
                attestation = evaluate_attestation(item['id'], attestations.get(item['id']))
                entry = {'route': kind, 'check_id': check_id, 'decides': route['decides'],
                         'run_status': attestation['status']}
                if attestation.get('reason'):
                    entry['reason'] = attestation['reason']
                if attestation.get('evidence'):
                    entry['evidence'] = attestation['evidence']
                evaluated.append(entry)
                if attestation['status'] != 'ATTESTATION_REQUIRED':
                    route_runs[kind] += 1
                continue
            if kind == 'not_app_checkable':
                raise ValueError('obligation cannot use not_app_checkable: ' + item['id'])
            if check_id not in registry['checks'] or registry['checks'][check_id]['route'] != kind:
                raise ValueError('invalid route check: ' + item['id'] + '/' + str(check_id))
            observed = runs.get(check_id)
            state = observed['status'] if observed else 'NOT_RUN'
            reason = (observed or {}).get('reason') or ('Check not invoked' if observed is None else None)
            entry = {'route': kind, 'check_id': check_id, 'decides': route['decides'],
                     'run_status': state}
            if reason:
                entry['reason'] = reason
            if observed and observed.get('evidence'):
                entry['evidence'] = observed['evidence']
            if state in {'NOT_RUN', 'SKIP'}:
                not_run_reasons[reason] += 1
            else:
                route_runs[kind] += 1
            evaluated.append(entry)
        decisive = [r for r in evaluated if r['decides'] == 'full' and
                    r['run_status'] in DECISIVE and r['route'] in AUTO_ROUTES | {'semantic'}]
        # A finding takes precedence over a pass. Semantic decisions cannot be
        # counted as automatic, even if both routes were available.
        decisive.sort(key=lambda r: (r['run_status'] != 'FINDING', r['route'] not in AUTO_ROUTES,
                                      r['check_id']))
        attestation_route = attestation is not None
        row = {'id': item['id'], 'apple_ref': item['apple_ref'], 'anchor': item['anchor'],
               'section': item['section'], 'criterion': item['criterion'], 'routes': evaluated,
               'question': question_for(item) if attestation_route else None}
        if decisive:
            chosen = decisive[0]
            prefix = 'AUTO' if chosen['route'] in AUTO_ROUTES else 'SEMANTIC'
            row.update(status=prefix + '_' + chosen['run_status'], decision_route=chosen['route'],
                       evidence=chosen['evidence'])
        elif attestation_route:
            row.update(status=attestation['status'], decision_route='attestation',
                       attestation=attestation)
            if 'evidence' in attestation:
                row['evidence'] = attestation['evidence']
        else:
            row.update(status='NOT_RUN', decision_route=None,
                       reason='No full decision route ran and no attestation route is registered')
        rows.append(row)
        section_rows[item['section']].append(row)
    statuses = Counter(row['status'] for row in rows)
    total = len(rows)
    auto_decided = sum(value for key, value in statuses.items() if key.startswith('AUTO_'))
    semantic_decided = sum(value for key, value in statuses.items() if key.startswith('SEMANTIC_'))
    self_reported = sum(value for key, value in statuses.items() if key.startswith('ATTESTED_'))
    routed = sum(bool(item['routes']) for item in obligations)
    summary = {'total_obligations': total, 'routed_obligations': routed,
               'routed_percent': round(100 * routed / total, 1) if total else 100.0,
               'automatically_decided': auto_decided,
               'automatically_decided_percent': round(100 * auto_decided / total, 1) if total else 0.0,
               'semantically_decided': semantic_decided,
               'self_reported': self_reported,
               'attestation_required': statuses['ATTESTATION_REQUIRED'],
               'attestation_unknown': statuses['ATTESTATION_UNKNOWN'],
               'status_counts': dict(sorted(statuses.items())),
               'route_counts': dict(sorted(route_counts.items())),
               'routes_run': dict(sorted(route_runs.items())),
               'not_run_reasons': dict(sorted(not_run_reasons.items()))}
    sections = {section: {'total': len(items),
                          'status_counts': dict(sorted(Counter(row['status'] for row in items).items()))}
                for section, items in sorted(section_rows.items())}
    return {'schema_version': 1, 'summary': summary, 'sections': sections, 'obligations': rows}


def markdown(report):
    summary = report['summary']
    lines = ['# Guideline run coverage', '',
             'Route availability and decisions made during this run are separate measures. '
             'Developer answers are self-reported.', '',
             f"Routed: {summary['routed_obligations']}/{summary['total_obligations']} "
             f"({summary['routed_percent']}%). Automatically decided in this run: "
             f"{summary['automatically_decided']} ({summary['automatically_decided_percent']}%). "
             f"Attestations required: {summary['attestation_required']}.", '',
             '| Section | Obligations | Outcomes |', '|---|---:|---|']
    for section, data in report['sections'].items():
        outcomes = ', '.join(f'{key}: {value}' for key, value in data['status_counts'].items())
        lines.append(f"| {section} | {data['total']} | {outcomes} |")
    lines += ['', '## Obligations', '']
    for row in report['obligations']:
        routes = ', '.join(f"{r['route']}:{r['run_status']}" for r in row['routes']) or 'none'
        lines += [f"### {row['apple_ref']} · {row['id']}", '',
                  f"Status: **{row['status']}**. Routes: {routes}.", '',
                  f"Criterion: {row['criterion']}", '']
        if row.get('question'):
            lines += [f"Question: {row['question']}", '']
        if row.get('evidence'):
            lines += [f"Evidence pointer: `{row['evidence']}`", '']
    if summary['not_run_reasons']:
        lines += ['## NOT_RUN and SKIP reasons', '']
        lines += [f'- {reason}: {count}' for reason, count in summary['not_run_reasons'].items()]
        lines.append('')
    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--catalog', type=Path, default=REF / 'guideline-obligations.json')
    parser.add_argument('--registry', type=Path, default=REF / 'check-registry.json')
    parser.add_argument('--config', type=Path, help='appstore-precheck JSON config; absent means no answers')
    parser.add_argument('--run-results', type=Path, help='JSON outcomes for checks actually invoked')
    parser.add_argument('--out', type=Path, help='write complete JSON report to this path')
    parser.add_argument('--markdown', type=Path, help='write Markdown run report to this path')
    args = parser.parse_args()
    try:
        catalog = read_object(args.catalog)
        registry = read_object(args.registry)
        config = read_object(args.config)
        run_results = read_object(args.run_results)
        report = build_report(catalog, registry, config, run_results)
        payload = json.dumps(report, indent=2, ensure_ascii=False, sort_keys=True) + '\n'
        if args.out:
            args.out.write_text(payload, encoding='utf-8')
        if args.markdown:
            args.markdown.write_text(markdown(report), encoding='utf-8')
        if not args.out:
            sys.stdout.write(payload)
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print('attestation-report: ' + str(exc), file=sys.stderr)
        return 2
    return 0


if __name__ == '__main__':
    sys.exit(main())
