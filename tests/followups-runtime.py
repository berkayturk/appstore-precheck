"""Post-release regressions for runtime output safety and redaction claims."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / 'skills/appstore-precheck/scripts/lib'


def load(name):
    spec = importlib.util.spec_from_file_location(name, LIB / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class FollowupRuntime(unittest.TestCase):
    def test_f4_inventory_symlink_is_refused(self):
        with tempfile.TemporaryDirectory() as folder:
            out = Path(folder)
            victim = out / 'victim'
            victim.write_text('unchanged')
            (out / 'screen-inventory.json').symlink_to(victim)
            result = subprocess.run([sys.executable, '-B', str(LIB / 'dyn-explore.py'), '--out', folder,
                                     '--screens', str(ROOT / 'tests/fixtures/runtime/clean')], capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(victim.read_text(), 'unchanged')

    def test_f4_capture_symlinks_are_refused(self):
        explore = load('dyn-explore')
        for suffix in ('json', 'png'):
            with self.subTest(suffix=suffix), tempfile.TemporaryDirectory() as folder:
                out = Path(folder)
                victim = out / 'victim'
                victim.write_text('unchanged')
                (out / ('screen.' + suffix)).symlink_to(victim)
                def command(argv, *args, **kwargs):
                    if argv[0] == 'maestro':
                        return json.dumps({'attributes': {'text': 'Home'}})
                    Path(argv[-1]).write_text('image bytes')
                    return ''
                with patch.object(explore, 'command', side_effect=command):
                    try:
                        explore.capture_screen('owned', out, 'screen', time.monotonic() + 30)
                    except OSError:
                        pass
                self.assertEqual(victim.read_text(), 'unchanged')

    def test_f5_redaction_does_not_depend_on_secure_field_types(self):
        scrub = load('dyn-scrub')
        tree = {'attributes': {'accessibilityText': 'demo-password', 'text': 'demo-user'},
                'children': [{'attributes': {'class': 'XCUIElementTypeSecureTextField', 'text': 'Password'}}]}
        with patch.dict(os.environ, {'PRECHECK_DEMO_PASSWORD': 'demo-password', 'PRECHECK_DEMO_USERNAME': 'demo-user'}):
            clean = scrub.scrub_tree(tree)
        self.assertNotIn('demo-password', json.dumps(clean))
        self.assertNotIn('demo-user', json.dumps(clean))
        self.assertEqual(clean['children'][0]['attributes']['text'], 'Password')
        policy = (ROOT / 'SECURITY.md').read_text()
        self.assertIn('secure-field detection is not relied on', policy)


if __name__ == '__main__':
    unittest.main()
