#!/usr/bin/env python3
"""Summarize actual corpus observations without treating gaps as success."""
import hashlib, json, os, plistlib, re, statistics, sys
from pathlib import Path

manifest = json.loads(Path(sys.argv[1]).read_text())
out = Path(sys.argv[2])
rows = []

def load(path, default):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError, TypeError):
        return default

def comparison(observed, wanted):
    # Infrastructure gaps and mixed votes are not positive/negative detections.
    if observed in ('SKIP', 'NOT_RUN', 'ERROR', 'MIXED'):
        return None
    return observed == wanted

def timings(run):
    lifecycle = run.get('d1_d2_seconds', [])
    pure = run.get('timing', {}).get('observation_seconds', [])
    return {'lifecycle_seconds': lifecycle, 'observation_seconds': pure,
            'lifecycle_median_seconds': statistics.median(lifecycle) if lifecycle else None,
            'observation_median_seconds': statistics.median(pure) if pure else None,
            'legacy_60_second_gate': ('PASS' if statistics.median(lifecycle) < 60 else 'FAIL')
                if lifecycle and run.get('repeats') == 10 and run.get('window_seconds') == 5
                else 'NOT_EVALUATED',
            'method': 'Lifecycle includes per-repeat erase/boot/install where performed, plus D1/D2. Observation excludes lifecycle; it cannot satisfy the legacy gate.'}

for case in manifest['cases']:
    d = out / case['framework'] / case['variant']
    if not (d / 'state').exists():
        continue
    state = (d / 'state').read_text().strip()
    transcript = (d / 'runtime/transcript.txt')
    content = transcript.read_text(errors='replace') if transcript.exists() else ''
    matches = re.findall(r'^DYNAMIC-(PASS|FINDING|SKIP):[^\n]*\[dyn-launch\]', content, re.M)
    observed = matches[-1] if matches else 'NOT_RUN'
    expected = case['expected_launch']
    if state == 'RAN' and observed != 'NOT_RUN':
        matched = comparison(observed, expected)
    else:
        matched = None
    records = []
    for kind, rule in re.findall(r'^DYNAMIC-([A-Z_]+):[^\n]*\[([^]]+)\]', content, re.M):
        records.append({'rule': rule, 'result': kind})
    inventory = d / 'runtime/screen-inventory.json'
    checks = {}
    if inventory.exists():
        try:
            data = json.loads(inventory.read_text())
            checks = {c['check_id']: c.get('status', 'NOT_RUN')
                      for c in data.get('checks', []) if 'check_id' in c}
        except (OSError, ValueError, TypeError):
            pass
    captured_labels = set()
    for hierarchy in (d / 'runtime').glob('screen-*.json'):
        raw = load(hierarchy, {})
        def collect(value):
            if isinstance(value, dict):
                for key, item in value.items():
                    if key in ('text', 'label', 'accessibilityText') and isinstance(item, str):
                        captured_labels.add(item)
                    collect(item)
            elif isinstance(value, list):
                for item in value:
                    collect(item)
        collect(raw)
    runtime_seed_matches = {label: (label in captured_labels if captured_labels else None)
                            for label in case.get('expected_runtime_labels', [])}
    expected_checks = case.get('expected_checks', {})
    observed_checks = {check_id: checks.get(check_id, 'NOT_RUN')
                       for check_id in expected_checks}
    check_matches = {
        check_id: (comparison(observed_checks[check_id], wanted)
                   if state == 'RAN' and observed_checks[check_id] != 'NOT_RUN'
                   else None)
        for check_id, wanted in expected_checks.items()
    }
    expected_bundle = case.get('expected_bundle', {})
    bundle_matches = {key: None for key in expected_bundle}
    build_log = d / 'build.txt'
    if expected_bundle and build_log.exists():
        app_paths = re.findall(r'^app_path=(.*)$', build_log.read_text(), re.M)
        if app_paths:
            try:
                info = plistlib.loads((Path(app_paths[-1]) / 'Info.plist').read_bytes())
                bundle_matches = {
                    key: (key not in info if wanted == 'absent'
                          else isinstance(info.get(key), str) and bool(info[key].strip()))
                    for key, wanted in expected_bundle.items()
                }
            except (OSError, ValueError, plistlib.InvalidFileException):
                pass
    run = load(d / 'runtime/run.json', {})
    votes = run.get('launch', {})
    mixed = bool(votes.get('pass', 0) and votes.get('finding', 0))
    if mixed:
        matched = None
    inspection = load(out / 'integrity.json', {})
    cleanup = load(out / 'simulators-after.json', {})
    udid = run.get('device', {}).get('udid')
    known_devices = [v.get('udid') for group in cleanup.get('devices', {}).values() for v in group]
    owned_deleted = (udid not in known_devices) if udid and run.get('device', {}).get('created_by_this_run') and 'devices' in cleanup else None
    transitions = load(d / 'runtime/transition-evidence.json', {})
    reason = '' 
    if state != 'RAN':
        for log in (d / 'build.txt', d / 'runtime.txt'):
            if log.exists():
                for line in log.read_text(errors='replace').splitlines():
                    if line.startswith(('SKIP:', 'ERROR:')):
                        reason = line[:300]
                        break
            if reason:
                break
    rows.append({'framework': case['framework'], 'variant': case['variant'],
                 'state': state, 'expected_launch': expected,
                 'observed_launch': observed, 'launch_matched': matched,
                 'targeted_defects': case['defects'], 'observations': records,
                 'expected_checks': expected_checks, 'observed_checks': observed_checks,
                 'check_matches': check_matches,
                 'expected_bundle': expected_bundle, 'bundle_matches': bundle_matches,
                 'runtime_seed_matches': runtime_seed_matches,
                 'reason': reason, 'launch_votes': votes, 'mixed': mixed,
                 'false_positive': bool(expected == 'PASS' and observed == 'FINDING' and not mixed),
                 'miss': bool(expected == 'FINDING' and observed == 'PASS' and not mixed),
                 'check_misses': [k for k,v in check_matches.items() if v is False],
                 'check_gaps': [k for k,v in check_matches.items() if v is None],
                 'integrity': {'path': str(out / 'integrity.json'), 'unchanged': inspection.get('unchanged'), 'before_sha256': inspection.get('before', {}).get('sha256'), 'after_sha256': inspection.get('after', {}).get('sha256')}, 'owned_simulator_deleted': owned_deleted,
                 'timing': timings(run), 'flow_evidence': transitions,
                 'observation_kind': 'live' if state == 'RAN' else 'not_run'})
(out / 'panel.json').write_text(json.dumps({'schema_version': 2, 'cases': rows, 'summary': {'false_positives': sum(r['false_positive'] for r in rows), 'misses': sum(r['miss'] for r in rows), 'mixed': sum(r['mixed'] for r in rows), 'skip_or_not_run': sum(r['observed_launch'] in ('SKIP','NOT_RUN') for r in rows), 'expected_check_misses': sum(len(r['check_misses']) for r in rows), 'expected_check_gaps': sum(len(r['check_gaps']) for r in rows)}}, indent=2) + '\n')
with (out / 'panel.tsv').open('w') as f:
    f.write('framework\tvariant\tstate\texpected_launch\tobserved_launch\tlaunch_matched\tcheck_matches\tbundle_matches\treason\n')
    for r in rows:
        values = [r['framework'], r['variant'], r['state'], r['expected_launch'],
                  r['observed_launch'], str(r['launch_matched']),
                  str(sum(v is True for v in r['check_matches'].values())) + '/' +
                  str(sum(v is not None for v in r['check_matches'].values())) +
                  ' of ' + str(len(r['check_matches'])),
                  str(sum(v is True for v in r['bundle_matches'].values())) + '/' +
                  str(len(r['bundle_matches'])),
                  r['reason'].replace('\t', ' ')]
        f.write('\t'.join(values) + '\n')
print((out / 'panel.tsv').read_text(), end='')
print('report=' + str(out / 'panel.json'))
