from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1]
class Docs(unittest.TestCase):
    def test_m15_inventory_and_blocking_scope(self):
        text = (ROOT / 'skills/appstore-precheck/references/methodology.md').read_text()
        self.assertIn('sections touched, not automatic verification', '\n'.join(text.splitlines()[:8]))
        text = (ROOT / 'skills/appstore-precheck/references/simulator-dynamic-review.md').read_text()
        self.assertNotIn('No blocking channel is enabled', text)
        self.assertIn('--dynamic-blocking', text)
    def test_n5_no_machine_specific_paths(self):
        self.assertNotIn('/Users/bt/', (ROOT / 'docs/field-tests.md').read_text())
if __name__ == '__main__':
    unittest.main()
