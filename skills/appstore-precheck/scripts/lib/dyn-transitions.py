#!/usr/bin/env python3
"""Replay hashed state transitions, not button inventories or compliance assertions.

A successful replay establishes the selected start/action/postcondition only. It
never establishes a whole guideline, backend authenticity, or human approval.
"""
import argparse
import hashlib
import json
import pathlib

FLOWS = ('login', 'logout', 'guest', 'deletion', 'siwa', 'restore', 'paywall',
         'permission-grant', 'permission-deny', 'ugc-report', 'ugc-block',
         'ugc-filter', 'navigation')
EXTERNAL = {'login', 'deletion', 'restore', 'siwa', 'ugc-report', 'ugc-block', 'ugc-filter'}
LIMITATIONS = [
    'Replay proves only selected state transitions, not complete guideline compliance.',
    'Recorded files need independent provenance, target scope and freshness validation.',
    'Simulator evidence cannot establish physical-device or distribution behavior.',
]


def read_evidence(ref, root):
    if not isinstance(ref, dict) or not isinstance(ref.get('path'), str):
        raise ValueError('Missing recorded evidence')
    path = pathlib.Path(ref['path'])
    # Replay files are portable local artifacts. Do not load outside the packet.
    if path.is_absolute() or '..' in path.parts:
        raise ValueError('Evidence must remain inside the transition packet')
    path = (root / path).resolve()
    try:
        path.relative_to(root.resolve())
    except ValueError:
        raise ValueError('Evidence symlink escapes the transition packet')
    raw = path.read_bytes()
    if hashlib.sha256(raw).hexdigest() != ref.get('sha256'):
        raise ValueError('Recorded evidence hash mismatch')
    return json.loads(raw)


def labels(tree):
    result = []
    if isinstance(tree, dict):
        attrs = tree.get('attributes', {})
        if isinstance(attrs, dict):
            for name in ('text', 'accessibilityText', 'label', 'contentDescription'):
                if isinstance(attrs.get(name), str) and attrs[name].strip():
                    result.append(attrs[name].strip())
        for child in tree.get('children', []):
            result.extend(labels(child))
    elif isinstance(tree, list):
        for child in tree:
            result.extend(labels(child))
    return result


def attempt_result(attempt, root):
    if not isinstance(attempt, dict) or attempt.get('driver_status') != 'completed':
        raise ValueError('Driver did not complete; app behavior is unresolved')
    start, action = attempt['start'], attempt['action']
    expected, post = attempt['expected'], attempt['postcondition']
    before = labels(read_evidence(start['evidence'], root))
    after = labels(read_evidence(post['evidence'], root))
    if len(set(before)) < 4 or len(set(after)) < 4:
        raise ValueError('Degenerate accessibility evidence')
    if not start.get('selector') or start['selector'] not in before:
        raise ValueError('Start state not observed')
    if action.get('type') != 'tap' or action.get('selector') not in before:
        raise ValueError('Action selector not observed in start state')
    events = read_evidence(action['evidence'], root).get('events', [])
    if not any(isinstance(x, dict) and x.get('action') == action['type'] and
               x.get('selector') == action['selector'] and x.get('result') == 'completed'
               for x in events):
        raise ValueError('No completed action in recorded driver trace')
    success, failure = expected.get('success'), expected.get('failure')
    if not isinstance(success, str) or not success or success == failure:
        raise ValueError('Expected postcondition is missing or ambiguous')
    # A persistent label already visible before the action is not transition proof.
    passed = success in after and success not in before
    failed = isinstance(failure, str) and failure in after and failure not in before
    if passed and failed:
        raise ValueError('Contradictory postconditions')
    return 'PASS' if passed else 'FAILURE' if failed else 'UNKNOWN'


def evaluate_flow(flow, root):
    row = {'id': flow.get('id'), 'flow': flow.get('flow'), 'status': 'UNRESOLVED',
           'attempts': [], 'reason': '', 'missing': []}
    if flow.get('flow') not in FLOWS:
        row['reason'] = 'Unknown flow; no completion inferred'
        return row
    attempts = flow.get('attempts', [])
    if not isinstance(attempts, list) or not attempts:
        row['reason'] = 'No recorded start/action/expected/postcondition sequence'
        return row
    for attempt in attempts:
        try:
            status = attempt_result(attempt, root)
            reason = 'Selected postcondition observed' if status == 'PASS' else 'Expected result not established'
        except (OSError, ValueError, KeyError, TypeError, AttributeError):
            status, reason = 'UNKNOWN', 'Incomplete, invalid, ambiguous, or unreadable transition evidence'
        row['attempts'].append({'id': attempt.get('id') if isinstance(attempt, dict) else None,
                                'status': status, 'reason': reason})
    statuses = [a['status'] for a in row['attempts']]
    name = flow['flow']
    if name in EXTERNAL:
        # A caller's backend_ready/confirmed booleans or receipt-shaped JSON cannot
        # prove server state, authenticity, account ownership, or test authorization.
        row['missing'] = ['Independently reviewed authorized test environment and backend evidence']
        if name == 'restore':
            row['missing'].append('Validated StoreKit transaction/receipt and restored entitlement')
        if name == 'deletion':
            row['missing'].append('Backend deletion completion, session revocation and retention review')
        if name == 'siwa':
            row['missing'].append('Provider parity, shared features and applicable exception review')
        row['reason'] = 'UI transition recorded; external outcome requires independent evidence review'
    elif name == 'paywall':
        row['reason'] = 'Paywall transition recorded; price, period, terms, privacy and product/storefront consistency require review'
        row['missing'] = ['Product/storefront-bound disclosure and link content review']
    elif name.startswith('permission-'):
        row['reason'] = 'Permission UI transition recorded; OS grant/deny state and subsequent app behavior require review'
        row['missing'] = ['OS permission state and feature behavior after grant/denial']
    elif statuses and all(s == 'PASS' for s in statuses):
        row['status'], row['reason'] = 'OBSERVED_PASS', 'Recorded start, completed action and new expected postcondition match'
    elif (len(attempts) == 3 and all(s == 'FAILURE' for s in statuses) and
          all(a.get('fresh') is True and a.get('environment_id') and a.get('id') for a in attempts) and
          len({a['environment_id'] for a in attempts}) == 3 and len({a['id'] for a in attempts}) == 3):
        row['status'], row['reason'] = 'OBSERVED_FAILURE', 'Explicit failure postcondition in three distinct fresh recorded environments; scope/provenance review still required'
    else:
        row['reason'] = 'Missing, mixed or non-independent attempts cannot establish a runtime violation'
    return row


def evaluate(packet, root):
    if not isinstance(packet, dict) or packet.get('schema_version') != 1 or not isinstance(packet.get('flows'), list):
        raise ValueError('Expected schema_version 1 and flows list')
    rows = []
    for flow in packet['flows']:
        if not isinstance(flow, dict):
            rows.append({'id': None, 'status': 'UNRESOLVED', 'reason': 'Malformed flow record'})
            continue
        rows.append(evaluate_flow(flow, root))
    return {'schema_version': 1, 'kind': 'runtime-transition-replay', 'flows': rows,
            'scope': packet.get('scope', {}), 'limitations': LIMITATIONS}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--transitions', required=True, type=pathlib.Path)
    parser.add_argument('--out', required=True, type=pathlib.Path)
    args = parser.parse_args()
    try:
        result = evaluate(json.loads(args.transitions.read_text()), args.transitions.resolve().parent)
    except (OSError, ValueError) as error:
        parser.error(str(error))
    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / 'transition-review.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))


if __name__ == '__main__':
    main()
