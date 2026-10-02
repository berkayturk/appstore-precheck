#!/usr/bin/env python3
"""Conservative D12-D17 observations; incomplete evidence always abstains.

Capture and MusicKit checks establish positive observations only. Missing visual
or OS evidence is never proof that a warning or authorization was omitted.
"""
import argparse
import json
from pathlib import Path
import statistics

RULES = {'dyn-cpu-idle': '2.4.2', 'dyn-capture-indicator': '2.5.14',
         'dyn-musickit-auth': '4.5.2', 'dyn-miniapp-index': '4.7.4',
         'dyn-miniapp-rating-label': '4.7.5', 'dyn-location-timing': '5.1.5'}


def evaluate(rule, obs):
    if not isinstance(obs, dict):
        return 'SKIP', 'Malformed observation'
    if not obs.get('applicable'):
        return 'SKIP', 'No applicable shipped or source signal was established'
    if not obs.get('usable'):
        return 'SKIP', obs.get('reason', 'Missing, timed-out or degenerate observation')
    if rule == 'dyn-cpu-idle':
        samples = obs.get('samples', [])
        if not obs.get('pid_verified') or obs.get('idle_seconds', 0) < 20 or len(samples) != 3:
            return 'SKIP', 'Need a verified app process and three samples after 20 idle seconds'
        if any(not isinstance(x, (int, float)) or isinstance(x, bool) or not 0 <= x <= 10000 for x in samples):
            return 'SKIP', 'CPU samples are invalid'
        median = statistics.median(samples)
        return ('FINDING' if median > 40 else 'PASS'), 'Observed idle process CPU median %.1f%% (advisory)' % median
    if rule == 'dyn-miniapp-index':
        if obs.get('directory_heading') and obs.get('directory_unavailable'):
            return 'FINDING', 'Observed mini-app directory explicitly reported unavailable; scope is this screen'
        if obs.get('directory_heading') and obs.get('visible_items', 0):
            return 'PASS', 'Mini-app directory and entries observed on the captured screen'
        return 'SKIP', 'Partial exploration cannot establish absence of a directory'
    if rule == 'dyn-miniapp-rating-label':
        total = obs.get('fully_visible_items', 0)
        if not obs.get('directory_heading') or not total:
            return 'SKIP', 'No fully visible mini-app entries with readable geometry were captured'
        missing = total - obs.get('rated_items', 0)
        return ('FINDING' if missing > 0 else 'PASS'), '%d/%d fully visible entries lacked an accessible age label; inspect screenshots' % (missing, total)
    if rule == 'dyn-location-timing':
        if obs.get('os_prompt') != 'location':
            return 'SKIP', 'No location alert with verified OS ownership and alert class was captured'
        if obs.get('prompt_phase') == 'launch' and obs.get('app_context_observed'):
            return 'FINDING', 'OS location permission appeared before any user action; app purpose and request justification were not assessed (timing observation only)'
        if obs.get('prompt_phase') == 'action' and obs.get('location_context'):
            return 'PASS', 'OS location permission followed an explicit location action'
        return 'SKIP', 'Location prompt observed, but its request context is ambiguous'
    return observe_only(rule, obs)


def observe_only(rule, obs):
    if rule == 'dyn-musickit-auth':
        if obs.get('flow_triggered') and obs.get('os_prompt') == 'music':
            return 'PASS', 'OS media-library authorization alert observed after an explicit music action'
        return 'SKIP', 'Music authorization absence is inconclusive; library access was not independently established'
    if rule == 'dyn-capture-indicator':
        required = ('flow_triggered', 'new_indicator_frame', 'status_indicator', 'screenshots_verified')
        if all(obs.get(k) for k in required):
            return 'PASS', 'New app recording frame and OS status indicator observed with before/after screenshots'
        return 'SKIP', 'Recording indicators require OS status-bar geometry and a new labelled app frame; missing evidence needs vision review'
    return 'SKIP', 'Unknown check'


def aggregate(repeats, rule):
    ids = [r.get('repeat') for r in repeats]
    valid = all(isinstance(x, int) and not isinstance(x, bool) and x > 0 for x in ids)
    valid = valid and all(r.get('fresh') is True and isinstance(r.get('observations'), dict) for r in repeats)
    if len(repeats) < 3 or not valid or len(set(ids)) != len(ids):
        return 'SKIP', 'Need at least three distinct observations on freshly erased owned devices'
    votes = [evaluate(rule, r.get('observations', {}).get(rule, {})) for r in repeats]
    kinds = [v[0] for v in votes]
    if len(set(kinds)) == 1 and kinds[0] != 'SKIP':
        return kinds[0], 'quorum %d/%d; fresh erase verified; %s' % (len(votes), len(votes), votes[-1][1])
    return 'SKIP', 'No unanimous complete observations (PASS=%d FINDING=%d SKIP=%d); %s' % (kinds.count('PASS'), kinds.count('FINDING'), kinds.count('SKIP'), votes[-1][1])


def read_repeats(path, expected):
    if path.is_dir():
        repeats = []
        for number in range(1, expected + 1):
            try:
                record = json.loads((path / ('repeat-%d.json' % number)).read_text())
                if not isinstance(record, dict) or record.get('repeat') != number:
                    raise ValueError('invalid repeat')
            except (OSError, ValueError):
                record = {'repeat': number, 'fresh': False, 'observations': {}}
            repeats.append(record)
        return repeats
    try:
        records = json.loads(path.read_text())
        return records if isinstance(records, list) and all(isinstance(r, dict) for r in records) else []
    except (OSError, ValueError):
        return []


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('observations', type=Path)
    parser.add_argument('--expected', type=int, default=0)
    args = parser.parse_args()
    repeats = read_repeats(args.observations, args.expected)
    for rule, guideline in RULES.items():
        kind, message = aggregate(repeats, rule)
        print('DYNAMIC-%s: %s [%s] — %s' % (kind, guideline, rule, message))


if __name__ == '__main__':
    main()
