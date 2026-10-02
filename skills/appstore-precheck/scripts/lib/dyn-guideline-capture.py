#!/usr/bin/env python3
"""Bounded, read-only collectors for six guideline observations on an owned device.

No build, package install, permission acceptance, credentials or arbitrary labels.
The caller establishes the fresh erase; this helper never creates/deletes devices.
"""
import argparse
import importlib.util
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import time

LIB = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('dyn_process', LIB / 'dyn-process.py')
process = importlib.util.module_from_spec(spec)
spec.loader.exec_module(process)
ACTIONS = {'capture': ('Start recording', 'Record video'),
           'music': ('Play music', 'Open Apple Music library'),
           'location': ('Use my location', 'Find nearby'),
           'miniapp': ('Browse mini apps', 'Open mini apps', 'Mini apps')}
SKIP_DIRS = {'.git', 'Pods', 'node_modules', 'build', 'DerivedData', '.build', '.planning', 'vendor'}


def command(argv, timeout=10):
    try:
        result = process.run(argv, timeout=timeout, grace=1, text=True,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return result.stdout if result.returncode == 0 else ''
    except (OSError, subprocess.TimeoutExpired, InterruptedError):
        return ''


def walk(tree, owner=''):
    if isinstance(tree, list):
        for item in tree:
            yield from walk(item, owner)
    elif isinstance(tree, dict):
        attrs = tree.get('attributes', {})
        owner = attrs.get('packageName') or attrs.get('bundleId') or owner
        if attrs:
            yield tree, dict(attrs, _owner=owner)
        for child in tree.get('children', []):
            yield from walk(child, owner)


def label(attrs):
    return next((attrs[k] for k in ('accessibilityText', 'text', 'label')
                 if isinstance(attrs.get(k), str) and attrs[k].strip()), '')


def frame(attrs):
    value = attrs.get('bounds', '')
    if isinstance(value, str):
        match = re.fullmatch(r'\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]', value)
        if match:
            x, y, right, bottom = map(int, match.groups())
            return (x, y, right, bottom) if right > x and bottom > y else None
    return None


def inside(inner, outer):
    return bool(inner and outer and inner[0] >= outer[0] and inner[1] >= outer[1]
                and inner[2] <= outer[2] and inner[3] <= outer[3])


def os_prompt(nodes):
    for node in nodes:
        for branch, attrs in walk(node):
            if attrs.get('_owner') not in ('com.apple.springboard', 'com.apple.SpringBoard'):
                continue
            kind = attrs.get('type', attrs.get('class', ''))
            if kind not in ('XCUIElementTypeAlert', 'UIAAlert'):
                continue
            text = ' '.join(label(a) for _, a in walk(branch)).lower()
            if 'location' in text and ('allow' in text or 'access' in text):
                return 'location'
            if ('apple music' in text or 'media library' in text) and ('allow' in text or 'access' in text):
                return 'music'
    return ''


def directory_facts(nodes, bounds, labels):
    heading = any(re.fullmatch(r'(mini[ -]?apps?|mini[ -]?games?|plugins?)', x, re.I) for x in labels)
    cells = [(n, a) for n, a in nodes if a.get('type', a.get('class')) in ('XCUIElementTypeCell', 'UIATableCell')]
    cells = [(n, a) for n, a in cells if any(label(child) for _, child in walk(n))]
    visible = [(n, a) for n, a in cells if inside(frame(a), bounds)]
    rated = sum(any(re.fullmatch(r'(?:Ages?\s*)?(?:4|9|12|13|16|17|18)\+|Rated\s+(?:E|E10\+|T|M|AO)', label(a), re.I)
                    for _, a in walk(n)) for n, _ in visible)
    unavailable = any(re.search(r'mini[ -]?app (?:directory|index|list) (?:is )?unavailable', x, re.I) for x in labels)
    return {'directory_heading': heading, 'directory_unavailable': unavailable,
            'visible_items': len(cells), 'fully_visible_items': len(visible), 'rated_items': rated}


def context_facts(nodes):
    app_nodes = [(n, a) for n, a in nodes if a.get('_owner') not in ('com.apple.springboard', 'com.apple.SpringBoard')]
    signature = [(label(a), frame(a), a.get('type', a.get('class', '')), a.get('_owner', '')) for _, a in app_nodes]
    return {'context_signature': hashlib.sha256(json.dumps(signature, sort_keys=True).encode()).hexdigest(),
            'app_owners': sorted({a['_owner'] for _, a in app_nodes if a.get('_owner')})}


def screen_facts(tree):
    nodes = list(walk(tree))
    labels = [label(a) for _, a in nodes if label(a)]
    bounds = frame(nodes[0][1]) if nodes else None
    facts = {'usable': len(nodes) >= 4 and len(labels) >= 3,
             'os_prompt': os_prompt([tree]), 'labels': labels,
             'app_context_observed': sum(bool(label(a)) for _, a in nodes if a.get('_owner') not in ('com.apple.springboard', 'com.apple.SpringBoard')) >= 3,
             'location_context': any(re.search(r'nearby|your location|current location|locate me|navigation|map', label(a), re.I) for _, a in nodes if a.get('_owner') not in ('com.apple.springboard', 'com.apple.SpringBoard'))}
    facts.update(directory_facts(nodes, bounds, labels))
    facts.update(context_facts(nodes))
    frames = {(label(a), frame(a)) for _, a in nodes if frame(a) and a.get('_owner') not in ('com.apple.springboard', 'com.apple.SpringBoard')}
    facts['recording_frames'] = {item for item in frames if re.fullmatch(r'Recording(?: \d{1,2}:\d{2})?|Stop recording', item[0], re.I)}
    facts['status_indicator'] = any(a.get('_owner') in ('com.apple.springboard', 'com.apple.SpringBoard')
                                     and a.get('type', a.get('class')) in ('XCUIElementTypeStatusBar', 'UIAStatusBar')
                                     and any(re.search(r'recording|camera in use|microphone in use', label(child), re.I)
                                             and inside(frame(child), frame(a)) for _, child in walk(n))
                                     for n, a in nodes)
    return facts


def load_tree(path):
    try:
        return json.loads(Path(path).read_text())
    except (OSError, ValueError):
        return {}


def safe_action(value):
    return isinstance(value, str) and '${' not in value and value in sum((list(x) for x in ACTIONS.values()), [])


def hierarchy(udid):
    raw = command(['maestro', '--device', udid, 'hierarchy'], 15)
    try:
        return json.loads(raw)
    except (ValueError, TypeError):
        return {}


def tap(udid, bundle, text):
    if not safe_action(text) or '${' in bundle:
        return False
    with tempfile.TemporaryDirectory(prefix='precheck-observe-flow-') as temp:
        flow = Path(temp) / 'flow.yaml'
        flow.write_text('appId: %s\n---\n- tapOn:\n    text: %s\n' % (json.dumps(bundle), json.dumps(text)))
        flow.chmod(0o600)
        try:
            result = process.run(['maestro', '--device', udid, 'test', '--debug-output', temp,
                                  '--test-output-dir', temp, str(flow)], 20, grace=1,
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return result.returncode == 0
        except (OSError, subprocess.TimeoutExpired, InterruptedError):
            return False


def screenshot(udid, path):
    try:
        result = process.run(['xcrun', 'simctl', 'io', udid, 'screenshot', '--type=png', str(path)],
                             10, grace=1, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return result.returncode == 0 and path.read_bytes()[:8] == b'\x89PNG\r\n\x1a\n'
    except (OSError, subprocess.TimeoutExpired, InterruptedError):
        return False


def source_signal(repo):
    if not repo:
        return False
    count = 0
    for folder, dirs, files in os.walk(repo, followlinks=False):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS and not Path(folder, d).is_symlink()]
        for name in files:
            path = Path(folder, name)
            if path.suffix not in ('.swift', '.m', '.mm') or path.is_symlink():
                continue
            count += 1
            if count > 1000:
                return False
            try:
                with path.open('rb') as handle:
                    text = handle.read(262144).decode('utf-8', errors='ignore')
            except OSError:
                continue
            if all(re.search(rx, text) for rx in ('WKScriptMessageHandler', 'evaluateJavaScript', r'https?://')):
                return True
    return False


def applicability(app, repo):
    try:
        with (Path(app) / 'Info.plist').open('rb') as handle:
            info = plistlib.load(handle)
    except (OSError, ValueError, plistlib.InvalidFileException):
        return {}
    if not isinstance(info, dict):
        return {}
    exe = info.get('CFBundleExecutable', '')
    valid_exe = isinstance(exe, str) and bool(exe) and '/' not in exe and exe not in ('.', '..')
    links = command(['otool', '-L', str(Path(app) / exe)]) if valid_exe else ''
    return {'capture': bool(re.search(r'/(ReplayKit|AVFoundation)\.framework/', links)),
            'music': bool(re.search(r'/MusicKit\.framework/', links)),
            'location': any(k.startswith('NSLocation') and k.endswith('UsageDescription') for k in info),
            'miniapp': source_signal(repo)}


def cpu_observation(pid, app, executable):
    obs = {'applicable': True, 'usable': False}
    if not str(pid).isdigit() or not executable or '/' in executable:
        return obs
    expected = str(Path(app).resolve() / executable)
    actual = command(['ps', '-p', str(pid), '-o', 'comm=']).strip()
    if actual != expected:
        obs['reason'] = 'Process identity did not match the installed executable; CPU was not sampled'
        return obs
    time.sleep(20)
    samples = []
    for _ in range(3):
        if command(['ps', '-p', str(pid), '-o', 'comm=']).strip() != expected:
            return obs
        try:
            samples.append(float(command(['ps', '-p', str(pid), '-o', '%cpu=']).strip()))
        except ValueError:
            return obs
        time.sleep(0.5)
    obs.update(usable=True, pid_verified=True, idle_seconds=20, samples=samples)
    return obs


def action_observation(args, mode, initial):
    before = screen_facts(hierarchy(args.udid))
    candidates = [s for s in ACTIONS[mode] if s in before['labels']]
    result = {'applicable': True, 'usable': before['usable'], 'flow_triggered': False}
    if not before['usable'] or not candidates:
        return result
    if before['context_signature'] != initial.get('context_signature') or before['app_owners'] != [args.bundle_id]:
        result.update(usable=False, reason='App context changed or ownership is unverified; action was not attempted')
        return result
    pre = args.out / (mode + '-before.png')
    post = args.out / (mode + '-after.png')
    pre_ok = screenshot(args.udid, pre) if mode == 'capture' else False
    if not tap(args.udid, args.bundle_id, candidates[0]):
        result['usable'] = False
        return result
    time.sleep(1)
    after = screen_facts(hierarchy(args.udid))
    if any(owner != args.bundle_id for owner in after['app_owners']) or (not after['app_owners'] and not after['os_prompt']):
        result.update(usable=False, reason='Post-action app context is unverified or belongs to another app')
        return result
    result.update({k: v for k, v in after.items() if k not in ('labels', 'recording_frames')})
    result.update(flow_triggered=True, prompt_phase='action', location_context=mode == 'location')
    if mode == 'capture':
        result['new_indicator_frame'] = bool(after['recording_frames'] - before['recording_frames'])
        result['screenshots_verified'] = pre_ok and screenshot(args.udid, post)
    return result


def observe(args):
    signals = applicability(args.app, args.repo)
    initial = screen_facts(load_tree(args.initial_tree))
    result = {'dyn-cpu-idle': cpu_observation(args.pid, args.app, args.executable)}
    modes = {'capture': 'dyn-capture-indicator', 'music': 'dyn-musickit-auth',
             'miniapp': 'dyn-miniapp-index', 'location': 'dyn-location-timing'}
    for mode, rule in modes.items():
        if not signals.get(mode):
            result[rule] = {'applicable': False}
        elif not initial['usable']:
            result[rule] = {'applicable': True, 'usable': False}
        elif mode == 'location' and initial['os_prompt'] == 'location':
            result[rule] = dict(initial, applicable=True, prompt_phase='launch')
        elif mode == 'miniapp' and initial['directory_heading']:
            result[rule] = dict(initial, applicable=True)
        else:
            result[rule] = action_observation(args, mode, initial)
        result[rule].pop('labels', None)
        result[rule].pop('recording_frames', None)
    result['dyn-miniapp-rating-label'] = dict(result['dyn-miniapp-index'])
    return result


def main():
    parser = argparse.ArgumentParser()
    for name in ('udid', 'bundle-id', 'app', 'pid', 'executable', 'initial-tree'):
        parser.add_argument('--' + name, required=True)
    parser.add_argument('--repeat', type=int, required=True)
    parser.add_argument('--fresh-owned', action='store_true')
    parser.add_argument('--repo', default='')
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    if '${' in args.bundle_id or not args.out.is_dir() or args.out.is_symlink():
        parser.error('safe bundle id and private output directory required')
    print(json.dumps({'repeat': args.repeat, 'fresh': args.fresh_owned,
                      'observations': observe(args)}, sort_keys=True))


if __name__ == '__main__':
    main()
