import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class Explore(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location('explore', ROOT / 'skills/appstore-precheck/scripts/lib/dyn-explore.py')
        self.module = importlib.util.module_from_spec(spec); spec.loader.exec_module(self.module)

    def test_clean_risky_and_degenerate_inventory(self):
        for kind in ('clean', 'risky', 'degenerate'):
            tree = json.loads((ROOT / 'tests/fixtures/runtime' / kind / 'home.json').read_text())
            screens = [self.module.summarize(tree, 'home')]
            records = {r['check_id']:r for r in self.module.evaluate(screens, {})}
            if kind == 'degenerate':
                self.assertTrue(all(r['status'] == 'SKIP' for r in records.values()))
            else:
                self.assertNotEqual(records['dyn-placeholder']['status'], 'PASS')
                self.assertIn('1', records['dyn-placeholder']['reason'])
            if kind == 'risky':
                self.assertEqual(records['dyn-external-payment']['status'], 'REVIEW_REQUIRED')

    def test_default_denylist_optional_allowlist_and_expression_rejection(self):
        self.assertTrue(self.module.safe_to_tap('Settings', None))
        self.assertFalse(self.module.safe_to_tap('Buy subscription', None))
        self.assertFalse(self.module.safe_to_tap('${sendSecrets()}', None))
        self.assertFalse(self.module.safe_to_tap('Settings', {'Help'}))
        with tempfile.TemporaryDirectory() as temporary:
            with self.assertRaises(ValueError):
                self.module.live_explore('owned-device', '${bad}', Path(temporary), 1, 1)

    def test_missing_screens_are_not_run(self):
        self.assertTrue(all(row['status'] == 'NOT_RUN' for row in self.module.evaluate([], {})))


if __name__ == '__main__':
    unittest.main()
