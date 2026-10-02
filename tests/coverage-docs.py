"""Keep current prose counts derived while preserving historical identifiers."""
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class CoverageDocs(unittest.TestCase):
    def test_current_counts_change_but_check_identifiers_do_not(self):
        spec = importlib.util.spec_from_file_location('coverage_docs', ROOT / 'scripts/update-coverage-docs.py')
        module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
        report = {'static_vectors': 71, 'deep_checks': 56}
        text = '55 vectors; 31 semantic checks; all 31 checks; check 31 (4.0); canonical 31-check table; N of 31 findings'
        result = module.prose_counts(text, report)
        self.assertEqual(result, '71 vectors; 56 semantic checks; all 56 checks; check 31 (4.0); canonical 56-check table; N of 56 findings')
        self.assertEqual(module.prose_counts(result, report), result)


    def test_released_changelog_counts_remain_historical(self):
        from unittest.mock import patch
        import tempfile
        spec = importlib.util.spec_from_file_location('coverage_docs', ROOT / 'scripts/update-coverage-docs.py')
        module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); (root / 'docs').mkdir()
            (root / 'docs/guideline-coverage.md').write_text('same')
            (root / 'CHANGELOG.md').write_text('## [Unreleased]\n55 vectors\n## [2.0.0]\n55 vectors\n')
            with patch.object(module, 'ROOT', root), patch.object(module, 'SURFACES', ('CHANGELOG.md',)):
                changes = module.replacements({'static_vectors': 71, 'deep_checks': 56}, 'summary', 'same')
            self.assertEqual(changes[root / 'CHANGELOG.md'], '## [Unreleased]\n71 vectors\n## [2.0.0]\n55 vectors\n')


if __name__ == '__main__':
    unittest.main()
