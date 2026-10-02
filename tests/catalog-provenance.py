import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class Provenance(unittest.TestCase):
    def test_v3_is_frozen_and_v4_is_current(self):
        current = json.loads((ROOT / 'skills/appstore-precheck/references/review-catalog.json').read_text())
        frozen = json.loads((ROOT / 'eval/catalog-history/review-catalog-v3.json').read_text())
        self.assertEqual(current['version'], 4)
        self.assertEqual(frozen['version'], 3)
        self.assertEqual(current['checks'][:31], frozen['checks'])
        spec = importlib.util.spec_from_file_location('catalog', ROOT / 'eval/lib/catalog.py')
        module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
        for version in (2, 3, 4):
            self.assertEqual(module.resolve({'catalog_version': version, 'check_id': 31})['number'], 31)
        self.assertEqual(module.procedure_path({'catalog_version': 3, 'check_id': 31}).name, 'pierre-deep-review-v3.md')
        self.assertEqual(len(module.fingerprint()), 64)


if __name__ == '__main__':
    unittest.main()
