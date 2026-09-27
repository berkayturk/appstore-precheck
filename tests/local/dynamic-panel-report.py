#!/usr/bin/env python3
"""Summarize actual corpus observations without treating gaps as success."""
import json
import math
import plistlib
import re
import statistics
import sys
from pathlib import Path


def load(path, default):
    try:
        value = json.loads(path.read_text())
        return value if isinstance(value, type(default)) else default
    except (OSError, ValueError, TypeError):
        return default


def comparison(observed, wanted):
    return None if observed in ('SKIP', 'NOT_RUN', 'ERROR', 'MIXED', 'INCONSISTENT') else observed == wanted


def timings(run, comparable):
    def samples(value):
        return [n for n in value if type(n) in (int, float) and n >= 0 and math.isfinite(n)] if isinstance(value, list) else []
    lifecycle = samples(run.get('d1_d2_seconds', []))
    timing = run.get('timing') if isinstance(run.get('timing'), dict) else {}
    pure = samples(timing.get('observation_seconds', []))
    comparable = comparable and len(lifecycle) == 10 and run.get('window_seconds') == 5
    return {'lifecycle_seconds': lifecycle, 'observation_seconds': pure,
            'lifecycle_median_seconds': statistics.median(lifecycle) if lifecycle else None,
            'observation_median_seconds': statistics.median(pure) if pure else None,
            'legacy_60_second_gate': ('PASS' if statistics.median(lifecycle) <= 60 else 'FAIL') if comparable else 'NOT_EVALUATED',
            'method': 'Lifecycle includes per-repeat erase/boot/install where performed, plus D1/D2. Observation excludes lifecycle; it cannot satisfy the legacy gate.'}


def ledger(path):
    try:
        return set(path.read_text().split())
    except OSError:
        return set()


def cleanup_proof(d, out, run):
    cleanup = load(d / 'simulators-after.json', load(out / 'simulators-after.json', {}))
    if not isinstance(cleanup.get('devices'), dict):
        return None
    if any(not isinstance(group, list) or any(not isinstance(v, dict) or not isinstance(v.get('udid'), str) for v in group) for group in cleanup['devices'].values()):
        return None
    known = {v.get('udid') for group in cleanup['devices'].values() if isinstance(group, list)
             for v in group if isinstance(v, dict)}
    owned = ledger(d / 'runtime/owned-simulators.txt')
    deleted = ledger(d / 'runtime/deleted-simulators.txt')
    device = run.get('device') if isinstance(run.get('device'), dict) else {}
    if not owned or device.get('created_by_this_run') is not True:
        return None
    if device.get('udid') not in owned:
        return None
    return not bool(owned & known) and owned <= deleted and not ledger(d / 'runtime/cleanup-failures.txt')


def case_report(case, out):
    d = out / case['framework'] / case['variant']
    if not (d / 'state').exists():
        return None
    state = (d / 'state').read_text().strip()
    run = load(d / 'runtime/run.json', {})
    votes = run.get('launch') if isinstance(run.get('launch'), dict) else {}
    repeats = run.get('repeats')
    votes_valid = (type(repeats) is int and repeats > 0 and
                   all(type(votes.get(k)) is int and votes[k] >= 0 for k in ('pass', 'finding', 'skip')) and
                   sum(votes[k] for k in ('pass', 'finding', 'skip')) == repeats)
    live = state == 'RAN' and run.get('dry_run') is False and votes_valid
    transcript = d / 'runtime/transcript.txt'
    content = transcript.read_text(errors='replace') if transcript.exists() else ''
    matches = re.findall(r'^DYNAMIC-(PASS|FINDING|SKIP):[^\n]*\[dyn-launch\]', content, re.M)
    raw_observed = matches[-1] if matches else 'NOT_RUN'
    observed = raw_observed if live else 'NOT_RUN'
    mixed = live and sum(votes[k] > 0 for k in ('pass', 'finding', 'skip')) > 1
    if mixed:
        observed = 'MIXED'
    elif live and observed in ('PASS', 'FINDING') and votes[observed.lower()] != repeats:
        observed = 'INCONSISTENT'
    expected = case['expected_launch']
    matched = comparison(observed, expected)
    records = [{'rule': rule, 'result': kind} for kind, rule in
               re.findall(r'^DYNAMIC-([A-Z_]+):[^\n]*\[([^]]+)\]', content, re.M)] if live else []
    inventory = load(d / 'runtime/screen-inventory.json', {}) if live else {}
    inventory_checks = inventory.get('checks') if isinstance(inventory.get('checks'), list) else []
    checks = {c['check_id']: c.get('status', 'NOT_RUN') for c in inventory_checks
              if isinstance(c, dict) and 'check_id' in c}
    captured_labels = set()
    def collect(value):
        if isinstance(value, dict):
            for key, item in value.items():
                if key in ('text', 'label', 'accessibilityText') and isinstance(item, str) and item.strip():
                    captured_labels.add(item)
                collect(item)
        elif isinstance(value, list):
            for item in value:
                collect(item)
    if live:
        for pattern in ('screen-*.json', 'hierarchy-*.json'):
            for hierarchy in (d / 'runtime').glob(pattern):
                collect(load(hierarchy, {}))
    runtime_seed_matches = {label: (label in captured_labels if captured_labels else None)
                            for label in case.get('expected_runtime_labels', [])}
    expected_checks = case.get('expected_checks', {})
    observed_checks = {key: checks.get(key, 'NOT_RUN') for key in expected_checks}
    check_matches = {key: comparison(observed_checks[key], wanted) for key, wanted in expected_checks.items()}
    expected_bundle = case.get('expected_bundle', {})
    bundle_matches = {key: None for key in expected_bundle}
    build_log = d / 'build.txt'
    if expected_bundle and build_log.exists():
        app_paths = re.findall(r'^app_path=(.*)$', build_log.read_text(), re.M)
        if app_paths:
            try:
                info = plistlib.loads((Path(app_paths[-1]) / 'Info.plist').read_bytes())
                bundle_matches = {key: (key not in info if wanted == 'absent' else isinstance(info.get(key), str) and bool(info[key].strip())) for key, wanted in expected_bundle.items()}
            except (OSError, ValueError, plistlib.InvalidFileException):
                pass
    case_bound = (d / 'integrity.json').exists()
    integrity_path = d / 'integrity.json' if case_bound else out / 'integrity.json'
    inspection = load(integrity_path, {})
    before = inspection.get('before') if isinstance(inspection.get('before'), dict) else {}
    after = inspection.get('after') if isinstance(inspection.get('after'), dict) else {}
    bound_unchanged = (case_bound and inspection.get('unchanged') is True and
                       before.get('stable_read') is True and after.get('stable_read') is True and
                       isinstance(before.get('sha256'), str) and
                       re.fullmatch(r'[0-9a-f]{64}', before['sha256']) is not None and
                       before['sha256'] == after.get('sha256'))
    device = run.get('device') if isinstance(run.get('device'), dict) else {}
    comparable = (live and observed == 'PASS' and expected == 'PASS' and case['framework'] == 'swiftui' and
                  case['variant'] == 'clean' and repeats == 10 and device.get('created_by_this_run') is True and
                  bound_unchanged)
    reason = ''
    if not live:
        for log in (d / 'build.txt', d / 'runtime.txt'):
            if log.exists():
                reason = next((line[:300] for line in log.read_text(errors='replace').splitlines()
                               if line.startswith(('SKIP:', 'ERROR:', 'DYNAMIC-SKIP:'))), '')
                if reason:
                    break
        reason = reason or 'No current completed live run with valid repeat metadata'
    return {'framework': case['framework'], 'variant': case['variant'], 'state': state,
            'expected_launch': expected, 'observed_launch': observed, 'raw_observed_launch': raw_observed,
            'launch_matched': matched, 'targeted_defects': case['defects'], 'observations': records,
            'expected_checks': expected_checks, 'observed_checks': observed_checks, 'check_matches': check_matches,
            'expected_bundle': expected_bundle, 'bundle_matches': bundle_matches, 'runtime_seed_matches': runtime_seed_matches,
            'reason': reason, 'launch_votes': votes if live else {}, 'mixed': mixed,
            'false_positive': expected == 'PASS' and observed == 'FINDING',
            'miss': expected == 'FINDING' and observed == 'PASS',
            'check_misses': [k for k,v in check_matches.items() if v is False],
            'check_gaps': [k for k,v in check_matches.items() if v is None],
            'integrity': {'path': str(integrity_path), 'binding': 'case_snapshot' if case_bound else 'unbound_panel_fallback', 'unchanged': bound_unchanged if case_bound else None,
                          'before_sha256': before.get('sha256'),
                          'after_sha256': after.get('sha256')},
            'owned_simulator_deleted': cleanup_proof(d, out, run) if live else None,
            'timing': timings(run if live else {}, comparable),
            'flow_evidence': load(d / 'runtime/transition-evidence.json', {}) if live else {},
            'observation_kind': 'live' if live else 'not_run'}


manifest = json.loads(Path(sys.argv[1]).read_text())
out = Path(sys.argv[2])
rows = [row for case in manifest['cases'] for row in [case_report(case, out)] if row is not None]
summary = {'false_positives': sum(r['false_positive'] for r in rows), 'misses': sum(r['miss'] for r in rows),
           'mixed': sum(r['mixed'] for r in rows),
           'skip_or_not_run': sum(r['observed_launch'] in ('SKIP','NOT_RUN','INCONSISTENT') for r in rows),
           'expected_check_misses': sum(len(r['check_misses']) for r in rows),
           'expected_check_gaps': sum(len(r['check_gaps']) for r in rows)}
(out / 'panel.json').write_text(json.dumps({'schema_version': 2, 'cases': rows, 'summary': summary}, indent=2) + '\n')
with (out / 'panel.tsv').open('w') as f:
    f.write('framework\tvariant\tstate\texpected_launch\tobserved_launch\tlaunch_matched\tcheck_matches\tbundle_matches\treason\n')
    for r in rows:
        f.write('\t'.join([r['framework'],r['variant'],r['state'],r['expected_launch'],r['observed_launch'],str(r['launch_matched']),
            str(sum(v is True for v in r['check_matches'].values())) + '/' + str(sum(v is not None for v in r['check_matches'].values())) + ' of ' + str(len(r['check_matches'])),
            str(sum(v is True for v in r['bundle_matches'].values())) + '/' + str(len(r['bundle_matches'])), r['reason'].replace('\t',' ')]) + '\n')
print((out / 'panel.tsv').read_text(), end='')
print('report=' + str(out / 'panel.json'))
