#!/usr/bin/env python3
"""Synthetic runtime observations: applicability, hierarchy provenance and quorum."""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from types import SimpleNamespace
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / 'skills/appstore-precheck/scripts/lib'
spec = importlib.util.spec_from_file_location('checks', LIB / 'dyn-guidelines.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
FIXTURES = Path(__file__).with_name('fixtures') / 'dynamic-guideline-expansion'


class GuidelineChecks(unittest.TestCase):
    def test_rule_fixtures(self):
        for path in sorted(FIXTURES.glob('*.json')):
            fixture = json.loads(path.read_text())
            for name, case in fixture['cases'].items():
                with self.subTest(rule=fixture['rule'], case=name):
                    kind, reason = m.evaluate(fixture['rule'], case['observation'])
                    self.assertEqual(kind, case['expected'])
                    self.assertTrue(reason)

    def test_quorum_and_partial_evidence(self):
        observation = json.loads((FIXTURES / 'cpu.json').read_text())['cases']['risky']['observation']
        repeat = {'fresh': True, 'repeat': 1, 'observations': {'dyn-cpu-idle': observation}}
        repeats = [dict(repeat, repeat=n) for n in (1, 2, 3)]
        self.assertEqual(m.aggregate(repeats, 'dyn-cpu-idle')[0], 'FINDING')
        self.assertEqual(m.aggregate(repeats[:2], 'dyn-cpu-idle')[0], 'SKIP')
        repeats[1]['fresh'] = False
        self.assertEqual(m.aggregate(repeats, 'dyn-cpu-idle')[0], 'SKIP')
        repeats[1]['fresh'] = True
        repeats[1] = copy.deepcopy(repeats[1])
        repeats[1]['observations']['dyn-cpu-idle']['samples'] = [1, 2, 1]
        self.assertEqual(m.aggregate(repeats, 'dyn-cpu-idle')[0], 'SKIP')
        self.assertEqual(m.aggregate([repeat] * 3, 'dyn-cpu-idle')[0], 'SKIP')

    def test_capture_producers(self):
        capture_spec = importlib.util.spec_from_file_location('capture', LIB / 'dyn-guideline-capture.py')
        c = importlib.util.module_from_spec(capture_spec)
        capture_spec.loader.exec_module(c)
        def node(label, kind='', children=None, owner='com.example.app', bounds='[0,0][100,30]'):
            return {'attributes': {'accessibilityText': label, 'type': kind,
                                   'packageName': owner, 'bounds': bounds}, 'children': children or []}
        os_alert = node('Allow location access?', 'XCUIElementTypeAlert', owner='com.apple.springboard')
        self.assertEqual(c.os_prompt([os_alert]), 'location')
        fake_alert = copy.deepcopy(os_alert)
        fake_alert['attributes']['packageName'] = 'com.example.app'
        self.assertEqual(c.os_prompt([fake_alert]), '')
        cell = node('Chess', 'XCUIElementTypeCell', [node('Play'), node('4+')], bounds='[0,50][100,150]')
        tree = node('Mini apps', 'XCUIElementTypeApplication', [cell, node('Browse'), node('Search')], bounds='[0,0][100,300]')
        facts = c.screen_facts(tree)
        self.assertTrue(facts['usable'])
        self.assertEqual(facts['fully_visible_items'], 1)
        self.assertEqual(facts['rated_items'], 1)
        self.assertFalse(c.screen_facts(node('Flutter'))['usable'])
        self.assertFalse(c.safe_action('${danger}'))

    def test_live_producers_and_fresh_transcripts(self):
        capture_spec = importlib.util.spec_from_file_location('capture', LIB / 'dyn-guideline-capture.py')
        c = importlib.util.module_from_spec(capture_spec)
        capture_spec.loader.exec_module(c)
        with tempfile.TemporaryDirectory() as temp:
            app = Path(temp).resolve() / 'App.app'
            values = iter([str(app / 'Demo'), str(app / 'Demo'), '55', str(app / 'Demo'), '65', str(app / 'Demo'), '60'])
            with mock.patch.object(c, 'command', side_effect=lambda _argv: next(values)), mock.patch.object(c.time, 'sleep') as sleep:
                cpu = c.cpu_observation('123', str(app), 'Demo')
                self.assertEqual(m.evaluate('dyn-cpu-idle', cpu)[0], 'FINDING')
                sleep.assert_any_call(20)
            with mock.patch.object(c, 'command', return_value='wrong process'), mock.patch.object(c.time, 'sleep') as sleep:
                self.assertFalse(c.cpu_observation('123', str(app), 'Demo')['usable'])
                sleep.assert_not_called()
            self.assertEqual(m.evaluate('dyn-miniapp-index', {'applicable': True, 'usable': False, 'directory_unavailable': True})[0], 'SKIP')
            transcript = Path(temp) / 'records.txt'
            transcript.write_text('DYNAMIC-FINDING: 2.4.2 [dyn-cpu-idle] — quorum 1/1; fresh erase verified\n'
                                  'DYNAMIC-FINDING: 2.4.2 [dyn-cpu-idle] — quorum 3/3; fresh erase verified; CPU 60%\n')
            raw = subprocess.check_output(['bash', str(LIB.parent / 'dynamic.sh'), '--transcript', str(transcript), '--build-config', 'debug'])
            records = json.loads(raw)['findings']
            self.assertEqual([r['severity'] for r in records], ['SKIP', 'WARN'])
            self.assertEqual(records[1]['confidence'], 'judgment-call')
            self.assertEqual(records[1]['build_config'], 'debug')

    def test_os_prompt_and_directory_evidence_end_to_end(self):
        capture_spec = importlib.util.spec_from_file_location('capture', LIB / 'dyn-guideline-capture.py')
        c = importlib.util.module_from_spec(capture_spec)
        capture_spec.loader.exec_module(c)
        def node(text, role='', children=None, owner='com.example.app', bounds='[0,0][200,30]'):
            return {'attributes': {'accessibilityText': text, 'type': role, 'packageName': owner, 'bounds': bounds}, 'children': children or []}
        app_nodes = [node('Home'), node('Settings'), node('Help')]
        alert = node('Allow access to your location?', 'XCUIElementTypeAlert', owner='com.apple.springboard')
        root = node('', 'XCUIElementTypeApplication', app_nodes + [alert], bounds='[0,0][200,800]')
        facts = c.screen_facts(root)
        self.assertFalse(facts['location_context'])
        self.assertEqual(m.evaluate('dyn-location-timing', dict(facts, applicable=True, prompt_phase='launch'))[0], 'FINDING')
        directory = node('Mini apps', 'XCUIElementTypeApplication', [node('Search'), node('Browse'), node('Mini app directory unavailable')], bounds='[0,0][200,800]')
        self.assertEqual(m.evaluate('dyn-miniapp-index', dict(c.screen_facts(directory), applicable=True))[0], 'FINDING')
        cell = node('Chess', 'XCUIElementTypeCell', [node('Play')], bounds='[0,50][200,150]')
        directory['children'][-1] = cell
        facts = dict(c.screen_facts(directory), applicable=True)
        self.assertEqual(m.evaluate('dyn-miniapp-rating-label', facts)[0], 'FINDING')
        cell['children'].append(node('12+'))
        self.assertEqual(m.evaluate('dyn-miniapp-rating-label', dict(c.screen_facts(directory), applicable=True))[0], 'PASS')
        music_prompt = node('Allow access to Apple Music?', 'XCUIElementTypeAlert', owner='com.apple.springboard')
        music = node('', 'XCUIElementTypeApplication', app_nodes + [music_prompt])
        before = node('', 'XCUIElementTypeApplication', app_nodes + [node('Play music')])
        with tempfile.TemporaryDirectory() as temp:
            args = SimpleNamespace(udid='owned', bundle_id='com.example.app', out=Path(temp))
            with mock.patch.object(c, 'hierarchy', side_effect=[before, music]), mock.patch.object(c, 'tap', return_value=True), mock.patch.object(c.time, 'sleep'):
                obs = c.action_observation(args, 'music', c.screen_facts(before))
                self.assertEqual(m.evaluate('dyn-musickit-auth', obs)[0], 'PASS')

    def test_recording_geometry_producer(self):
        capture_spec = importlib.util.spec_from_file_location('capture', LIB / 'dyn-guideline-capture.py')
        c = importlib.util.module_from_spec(capture_spec)
        capture_spec.loader.exec_module(c)
        def node(text, role='', children=None, owner='com.example.app', bounds='[0,100][200,140]'):
            return {'attributes': {'accessibilityText': text, 'type': role, 'packageName': owner, 'bounds': bounds}, 'children': children or []}
        before = node('', 'XCUIElementTypeApplication', [node('Start recording'), node('Library'), node('Help')], bounds='[0,0][200,800]')
        indicator = node('Recording', owner='com.apple.springboard', bounds='[0,0][100,20]')
        status = node('', 'XCUIElementTypeStatusBar', [indicator], owner='com.apple.springboard', bounds='[0,0][200,30]')
        after = node('', 'XCUIElementTypeApplication', [node('Stop recording'), node('Library'), node('Help'), status], bounds='[0,0][200,800]')
        with tempfile.TemporaryDirectory() as temp:
            args = SimpleNamespace(udid='owned', bundle_id='com.example.app', out=Path(temp))
            with mock.patch.object(c, 'hierarchy', side_effect=[before, after]), mock.patch.object(c, 'tap', return_value=True), mock.patch.object(c, 'screenshot', return_value=True), mock.patch.object(c.time, 'sleep'):
                obs = c.action_observation(args, 'capture', c.screen_facts(before))
            self.assertEqual(m.evaluate('dyn-capture-indicator', obs)[0], 'PASS')
            obs['status_indicator'] = False
            self.assertEqual(m.evaluate('dyn-capture-indicator', obs)[0], 'SKIP')
            after['children'][-1]['attributes']['packageName'] = 'com.example.app'
            self.assertFalse(c.screen_facts(after)['status_indicator'])

    def test_localized_location_context_is_not_judged_by_english_regex(self):
        spec = importlib.util.spec_from_file_location('capture', LIB / 'dyn-guideline-capture.py')
        c = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(c)
        def node(text, owner='com.example.app', role='XCUIElementTypeStaticText'):
            return {'attributes': {'accessibilityText': text, 'packageName': owner, 'type': role}, 'children': []}
        prompt = node('Allow access to your location?', 'com.apple.springboard', 'XCUIElementTypeAlert')
        for title in ('Yakınımdaki eczaneler', 'Pharmacies à proximité', 'Nearby pharmacies'):
            tree = node('')
            tree['children'] = [node(title), node('Konumumu kullan'), node('Harita'), prompt]
            facts = c.screen_facts(tree)
            kind, message = m.evaluate('dyn-location-timing', dict(facts, applicable=True, prompt_phase='launch'))
            self.assertEqual(kind, 'FINDING')
            self.assertIn('before any user action', message)
            self.assertIn('purpose and request justification were not assessed', message)
            self.assertNotIn('without context', message)
            self.assertNotIn('or visible location context', message)

    def test_action_context_switches_abstain(self):
        spec = importlib.util.spec_from_file_location('capture', LIB / 'dyn-guideline-capture.py')
        c = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(c)
        def tree(title, action, owner='com.example.app'):
            def n(label):
                return {'attributes': {'accessibilityText': label, 'packageName': owner}, 'children': []}
            root = n(title)
            root['children'] = [n(action), n('Help'), n('Settings')]
            return root
        with tempfile.TemporaryDirectory() as temp:
            args = SimpleNamespace(udid='owned', bundle_id='com.example.app', out=Path(temp))
            for mode, rule in [('capture', 'dyn-capture-indicator'), ('music', 'dyn-musickit-auth'), ('miniapp', 'dyn-miniapp-index'), ('location', 'dyn-location-timing')]:
                initial = tree('Home', c.ACTIONS[mode][0])
                changed = tree('Another screen', c.ACTIONS[mode][0])
                with mock.patch.object(c, 'hierarchy', return_value=changed), mock.patch.object(c, 'screenshot', return_value=True), mock.patch.object(c, 'tap') as tap:
                    obs = c.action_observation(args, mode, c.screen_facts(initial))
                tap.assert_not_called()
                self.assertEqual(m.evaluate(rule, obs)[0], 'SKIP')
                self.assertIn('context', obs['reason'])
                foreign = tree('Another app', 'Mini apps', 'com.example.other')
                with mock.patch.object(c, 'hierarchy', side_effect=[initial, foreign]), mock.patch.object(c, 'tap', return_value=True), mock.patch.object(c, 'screenshot', return_value=True), mock.patch.object(c.time, 'sleep'):
                    obs = c.action_observation(args, mode, c.screen_facts(initial))
                self.assertEqual(m.evaluate(rule, obs)[0], 'SKIP')

    def test_sequential_actions_do_not_reuse_changed_screen(self):
        spec = importlib.util.spec_from_file_location('capture', LIB / 'dyn-guideline-capture.py')
        c = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(c)
        def node(text):
            return {'attributes': {'accessibilityText': text, 'packageName': 'com.example.app'}, 'children': []}
        initial = node('Home')
        initial['children'] = [node(labels[0]) for labels in c.ACTIONS.values()]
        changed = copy.deepcopy(initial)
        changed['attributes']['accessibilityText'] = 'Recording screen'
        with tempfile.TemporaryDirectory() as temp:
            args = SimpleNamespace(udid='owned', bundle_id='com.example.app', out=Path(temp),
                                   app='App.app', repo='', pid='123', executable='App', initial_tree='initial.json')
            with mock.patch.object(c, 'applicability', return_value=dict.fromkeys(c.ACTIONS, True)), mock.patch.object(c, 'load_tree', return_value=initial), mock.patch.object(c, 'cpu_observation', return_value={}):
                with mock.patch.object(c, 'hierarchy', side_effect=[initial, changed, changed, changed, changed]), mock.patch.object(c, 'tap', return_value=True) as tap, mock.patch.object(c, 'screenshot', return_value=True), mock.patch.object(c.time, 'sleep'):
                    observations = c.observe(args)
            self.assertEqual(tap.call_count, 1)
            for rule in ('dyn-musickit-auth', 'dyn-miniapp-index', 'dyn-miniapp-rating-label', 'dyn-location-timing'):
                self.assertEqual(m.evaluate(rule, observations[rule])[0], 'SKIP')
                self.assertIn('context changed', observations[rule]['reason'])

    def test_reconciliation_catalogue(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'transcript.txt'
            path.write_text('\n'.join('DYNAMIC-SKIP: %s [%s] — missing fresh observations' % (g, r)
                                      for r, g in m.RULES.items()))
            raw = subprocess.check_output(['bash', str(LIB.parent / 'dynamic.sh'), '--transcript', str(path)])
            records = json.loads(raw)['findings']
            self.assertEqual({r['rule_id'] for r in records}, set(m.RULES))
            self.assertTrue(all(r['severity'] == 'SKIP' and r['confidence'] is None for r in records))


if __name__ == '__main__':
    unittest.main()
