#!/usr/bin/env python3
import importlib.util
import json
import pathlib
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('explore', ROOT / 'skills/appstore-precheck/scripts/lib/dyn-explore.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class NavigationTests(unittest.TestCase):
    def test_default_never_runs_flow(self):
        calls = []
        def command(argv, timeout, cwd=None):
            calls.append(argv)
            return json.dumps({'children': [{'attributes': {'text': label, 'clickable': True}}
                                           for label in ['Report', 'Block', 'Restore', 'Continue', 'Settings']]})
        original = m.command
        m.command = command
        try:
            with tempfile.TemporaryDirectory() as tmp:
                result = m.live_explore('owned', 'org.example.app', pathlib.Path(tmp), 25, 1)
            self.assertEqual(1, len(result))
            self.assertFalse(any('test' in call for call in calls))
            self.assertFalse(any(a['safe_to_tap'] for a in result[0]['actions']))
        finally:
            m.command = original

    def test_authorized_navigation_records_real_sequence(self):
        calls = []
        def command(argv, timeout, cwd=None):
            calls.append(argv)
            phase = sum('test' in x for x in calls)
            text = ['Home', 'Settings', 'Help', 'About'] if phase < 2 else ['Preferences', 'Back', 'Help', 'About']
            return json.dumps({'children': [{'attributes': {'text': label, 'clickable': True}} for label in text]})
        original = m.command
        m.command = command
        try:
            with tempfile.TemporaryDirectory() as tmp:
                root = pathlib.Path(tmp)
                authorization = {'schema_version': 1, 'authorized': True, 'environment': 'sandbox',
                                 'selectors': ['Settings'], 'transitions': {'Settings':
                                 {'flow': 'navigation', 'start': 'Home', 'success': 'Preferences', 'failure': 'Error'}}}
                m.live_explore('owned', 'org.example.app', root, 25, 1, authorization)
                packet = json.loads((root / 'transition-evidence.json').read_text())
                self.assertEqual(1, len(packet['flows']))
                attempt = packet['flows'][0]['attempts'][0]
                self.assertFalse(attempt['fresh'])
                self.assertEqual('completed', attempt['driver_status'])
                self.assertTrue((root / attempt['postcondition']['evidence']['path']).exists())
                spec = importlib.util.spec_from_file_location('replay', ROOT / 'skills/appstore-precheck/scripts/lib/dyn-transitions.py')
                replay = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(replay)
                self.assertEqual('OBSERVED_PASS', replay.evaluate(packet, root)['flows'][0]['status'])
        finally:
            m.command = original

    def test_production_authorization_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(ValueError):
                m.live_explore('owned', 'org.example.app', pathlib.Path(tmp), 25, 1,
                               {'schema_version': 1, 'authorized': True, 'environment': 'production', 'selectors': ['Continue']})


if __name__ == '__main__':
    unittest.main()
