"""Audited verifier dispatch. A policy label cannot create executable capability."""
import importlib.util
from functools import lru_cache
from pathlib import Path

VERIFIERS = {
    'runtime.launch-crash.v1': {'positive': False, 'finding': True, 'applicability': True,
                              'evidence_kinds': ['runtime-transcript']},
}
MODULES = ('verification-artifact.py', 'verification-metadata.py', 'verification-runtime.py')


@lru_cache(maxsize=1)
def extension_modules():
    modules = []
    for filename in MODULES:
        path = Path(__file__).parent / filename
        if path.is_file():
            spec = importlib.util.spec_from_file_location(filename.replace('-', '_'), path)
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            modules.append(module)
    return tuple(modules)


def extensions():
    return iter(extension_modules())


def capabilities():
    result = dict(VERIFIERS)
    for module in extensions():
        result.update(getattr(module, 'VERIFIERS', {}))
    return result


def launch_crash(payloads, context):
    """Only unanimous fresh process-exit observations prove a launch violation."""
    bundle = context['profile']['target']['bundle_id']
    for evidence in payloads:
        data = evidence.get('data')
        if evidence['kind'] != 'runtime-transcript' or not isinstance(data, dict):
            continue
        runs = data.get('runs')
        if data.get('schema_version') != 1 or not isinstance(runs, list) or len(runs) != 3:
            continue
        environments, failures = set(), 0
        for run in runs:
            if not isinstance(run, dict):
                break
            env = run.get('environment_id')
            if (not isinstance(env, str) or not env or env in environments or
                    run.get('fresh_environment') is not True or
                    run.get('driver_timeout') is not False or
                    run.get('backend_available') is not True or
                    not isinstance(run.get('accessibility_node_count'), int) or
                    run['accessibility_node_count'] < 2):
                break
            environments.add(env)
            events = run.get('events')
            if not isinstance(events, list) or len(events) != 2:
                break
            start, end = events
            if not isinstance(start, dict) or not isinstance(end, dict):
                break
            if (start.get('type') != 'launch_started' or start.get('bundle_id') != bundle or
                    end.get('type') != 'process_exited' or end.get('bundle_id') != bundle or
                    type(end.get('exit_code')) is not int or end['exit_code'] == 0):
                break
            failures += 1
        if failures == 3:
            return {'status': 'FINDING', 'reason': 'Three independent fresh launches exited abnormally',
                    'evidence_ids': [evidence['id']], 'applicability': 'APPLICABLE'}
    return {'status': 'UNKNOWN', 'reason': 'No complete unanimous fresh launch-crash evidence',
            'evidence_ids': []}


def evaluate(verifier, payloads, context):
    if verifier == 'runtime.launch-crash.v1':
        return launch_crash(payloads, context)
    for module in extensions():
        if verifier in getattr(module, 'VERIFIERS', {}):
            return module.evaluate(verifier, payloads, context)
    return {'status': 'UNKNOWN', 'reason': 'Verifier is not implemented', 'evidence_ids': []}
