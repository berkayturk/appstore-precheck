#!/usr/bin/env python3
"""Conservative verification adapter for recorded runtime UI transitions.

Caller-defined selectors prove a narrow observation, not the policy criterion.
Until a criterion-specific trusted matcher and independent collector provenance
are available, this verifier explicitly keeps guideline decisions unresolved.
"""
import importlib.util
import pathlib

VERIFIERS = {'dyn-state-transition-v1': {'positive': False, 'finding': False,
                                       'evidence_kinds': ['runtime-transition']}}
_spec = importlib.util.spec_from_file_location('dyn_transitions', pathlib.Path(__file__).with_name('dyn-transitions.py'))
_replay = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_replay)


def evaluate(verifier, payloads, context):
    ids = []
    observations = []
    if verifier != 'dyn-state-transition-v1':
        return {'status': 'UNKNOWN', 'reason': 'Unsupported runtime verifier', 'evidence_ids': []}
    for item in payloads:
        if item.get('kind') != 'runtime-transition':
            continue
        try:
            result = _replay.evaluate(item['data'], pathlib.Path(item['path']).resolve().parent)
        except (OSError, KeyError, TypeError, ValueError):
            continue
        ids.append(item['id'])
        observations.extend(row['status'] for row in result['flows'])
    return {'status': 'UNKNOWN', 'reason': 'Transition replay observations: %s. Criterion-specific sufficiency and external outcome review remain required.' %
            (', '.join(observations) or 'none'), 'evidence_ids': ids}
