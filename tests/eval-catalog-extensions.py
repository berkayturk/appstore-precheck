"""Versioned identifiers and tiers come from the catalog, never a numeric cutoff."""
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'eval/lib'))
import catalog
import validate_case
from parse_verdict import parse_verdict


class Extensions(unittest.TestCase):
    def test_v4_outcomes_stay_distinct_from_pass(self):
        for label, expected in [('SKIP', 'insufficient_evidence'), ('NO-SIGNAL', 'no_signal')]:
            response = {'content': [{'type': 'text', 'text': 'REVIEW-' + label + ': 1.1.1 — bounded evidence'}]}
            self.assertEqual(parse_verdict(response)['verdict'], expected)
        self.assertEqual(parse_verdict({'provider': 'typesafe', 'result': {'outcome': 'no_signal'}})['verdict'], 'no_signal')

    def test_future_identifier_is_rejected_by_historical_catalog(self):
        with self.assertRaises(ValueError):
            catalog.resolve({'catalog_version': 3, 'check_id': 999})

    def test_validator_resolves_tier_from_versioned_record(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); fixture = root / 'fixtures/case'; fixture.mkdir(parents=True)
            (fixture / 'evidence.txt').write_text('Synthetic evidence')
            case = {'id': 'check01-probe', 'check_id': 1, 'catalog_version': 4, 'tier': 'C',
                    'guideline': '1.2', 'expected': 'insufficient_evidence',
                    'rationale': 'Vision evidence is absent.', 'label_confirmed': False,
                    'fixture': 'fixtures/case/'}
            path = root / 'check01-probe.json'; path.write_text(json.dumps(case))
            with patch.object(validate_case, 'resolve', return_value={'tier': 'C'}):
                self.assertEqual(validate_case.check_case(path, root), [])


if __name__ == '__main__':
    unittest.main()
