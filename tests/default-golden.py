"""Pin existing findings/text while allowing only new PASS/WARN/SKIP rule additions."""
import hashlib
import json
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GOLDEN = ROOT / 'tests/golden/default-v1.19.0.json'


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False).encode()).hexdigest()


def capture(scanner, fixture):
    env = dict(os.environ, APPSTORE_PRECHECK_CONFIG='/nonexistent')
    env.pop('APPSTORE_PRECHECK_NO_EVIDENCE', None)
    command = ['bash', str(scanner), '--dir', str(fixture)]
    text = subprocess.check_output(command, env=env, text=True)
    report = json.loads(subprocess.check_output(command + ['--format', 'json'], env=env, text=True))
    return text.splitlines(), report


def baseline_record(lines, report):
    return {'lines': [digest(line) for line in lines],
            'findings': [digest(finding) for finding in report['findings']],
            'rules': sorted({finding['rule_id'] for finding in report['findings']}),
            'envelope_keys': sorted(report), 'summary_keys': sorted(report['summary'])}


def metadata_gap_compat(lines, report):
    """Only the review-authorized metadata count/list expansion is normalized."""
    import copy
    import re
    script = ROOT / 'skills/appstore-precheck/scripts'
    command = 'source "$1/findings.sh"; source "$1/evidence.sh"; rules_with_evidence metadata "$2"'
    lists = [subprocess.check_output(['bash', '-c', command, 'bash', str(script), cap], text=True).splitlines()
             for cap in ('55', '999')]
    old, new = lists
    before = str(len(new)) + ' store-listing checks did not run.'
    after = str(len(old)) + ' store-listing checks did not run.'
    def line_compat(line):
        if line.startswith('SKIP: metadata — no fastlane metadata directory detected; '):
            if before not in line:
                raise AssertionError('metadata gap count disagrees with catalogue')
            return line.replace(before, after, 1)
        if line == '      ' + ' '.join(new):
            return '      ' + ' '.join(old)
        return line
    result = copy.deepcopy(report)
    for finding in result['findings']:
        if finding['rule_id'] == 'store-listing-not-audited':
            finding['message'] = line_compat('SKIP: ' + finding['message'])[6:]
            key = '|'.join(str(finding.get(k) or '') for k in ('rule_id', 'file', 'line', 'message'))
            finding['id'] = hashlib.sha256(key.encode()).hexdigest()[:16]
    return [line_compat(line) for line in lines], result


def compare(baseline, lines, report):
    findings = report['findings']
    old = [finding for finding in findings if finding['rule_id'] in baseline['rules']]
    new = [finding for finding in findings if finding['rule_id'] not in baseline['rules']]
    if [digest(f) for f in old] != baseline['findings']:
        raise AssertionError('existing JSON finding removed, reordered or changed')
    if any(f['severity'] not in ('PASS', 'WARN', 'SKIP') for f in new):
        raise AssertionError('new JSON findings must be PASS/WARN/SKIP')
    allowed = {f['severity'] + ': ' + f['message'] for f in new}
    index, addition = 0, False
    for line in lines:
        if index < len(baseline['lines']) and digest(line) == baseline['lines'][index]:
            index += 1
            addition = False
        elif line in allowed:
            addition = True
        elif addition and line.startswith('      '):
            continue
        else:
            raise AssertionError('existing text changed or unsupported addition: ' + line)
    if index != len(baseline['lines']):
        raise AssertionError('existing text line removed')
    if not set(baseline['envelope_keys']).issubset(report):
        raise AssertionError('existing envelope field removed')
    if not set(baseline['summary_keys']).issubset(report['summary']):
        raise AssertionError('existing summary field removed')


def mutation_probes(baseline, lines, report):
    import copy
    for change in ('remove', 'rewrite', 'new-fail'):
        probe = copy.deepcopy(report)
        if change == 'remove':
            probe['findings'].pop(0)
        elif change == 'rewrite':
            probe['findings'][0]['message'] += ' changed'
        else:
            probe['findings'].append(dict(probe['findings'][0], rule_id='new-rule',
                                          severity='FAIL' if change == 'new-fail' else 'SKIP'))
        try:
            compare(baseline, lines, probe)
        except AssertionError:
            continue
        raise AssertionError('golden accepted destructive mutation: ' + change)
    probe = copy.deepcopy(report)
    probe['findings'].append(dict(probe['findings'][0], rule_id='new-rule',
                                  severity='WARN', message='2.1 synthetic new concern'))
    compare(baseline, lines + ['WARN: 2.1 synthetic new concern'], probe)
    probe['findings'][-1].update(severity='SKIP', message='synthetic explicit input gap')
    compare(baseline, lines + ['SKIP: synthetic explicit input gap'], probe)


def main():
    data = json.loads(GOLDEN.read_text())
    scanner = ROOT / 'skills/appstore-precheck/scripts/scan.sh'
    for name, baseline in data['fixtures'].items():
        lines, report = capture(scanner, ROOT / 'tests/fixtures' / name)
        lines, report = metadata_gap_compat(lines, report)
        compare(baseline, lines, report)
        mutation_probes(baseline, lines, report)
        print('PASS: additions-only golden: ' + name)
    print('PASS: golden rejects removal, rewrites, new FAIL; accepts additive SKIP')


if __name__ == '__main__':
    main()
