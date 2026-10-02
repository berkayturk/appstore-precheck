"""Maintainer quote generation enforces the public twenty-five-word boundary."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class QuoteBoundary(unittest.TestCase):
    def test_quote_words_remain_bounded_with_large_character_override(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            words = ['syntheticword%d' % index for index in range(80)]
            (root / 'page.html').write_text('<li id="2.3.3"><p>' + ' '.join(words) + '</p></li>')
            (root / 'baseline.json').write_text(json.dumps({'all_sections': ['2.3.3'], 'covered_by_scan': ['2.3.3']}))
            fingerprints = root / 'fingerprints.json'
            fingerprints.write_text('{"sections":{}}')
            command = ['bash', str(ROOT / 'scripts/guideline-drift.sh'), '--html', str(root / 'page.html'),
                       '--baseline', str(root / 'baseline.json'), '--fingerprints', str(fingerprints)]
            result = subprocess.run(command + ['--reconcile'], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            environment = dict(os.environ, GD_QUOTE_CHARS='20000')
            result = subprocess.run(command + ['--quotes', '--quote-chars', '20000'],
                                    capture_output=True, text=True, env=environment)
            self.assertEqual(result.returncode, 0, result.stderr)
            quote = json.loads(fingerprints.read_text())['sections']['2.3.3']['quote']
            self.assertLessEqual(len(quote.split()), 25)
            self.assertEqual(quote.split(), words[:25])


if __name__ == '__main__':
    unittest.main()
