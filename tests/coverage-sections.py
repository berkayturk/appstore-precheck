"""Executable coverage claims, not a hand-entered percentage."""
import copy
import importlib.util
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SKILL = ROOT / 'skills/appstore-precheck'
SPEC = importlib.util.spec_from_file_location('coverage_sections', SKILL / 'scripts/lib/coverage-sections.py')
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def copy_repository_inputs(directory):
    root = Path(directory)
    skill = root / 'skills/appstore-precheck'
    shutil.copytree(SKILL, skill)
    shutil.copytree(ROOT / 'corpus/synthetic/semantic-v4', root / 'corpus/synthetic/semantic-v4')
    return skill


class CoverageSections(unittest.TestCase):
    def setUp(self):
        self.base = json.loads((SKILL / 'guidelines-baseline.json').read_text())

    def report(self, base=None):
        return MODULE.build_report(SKILL, base or self.base)

    def test_denominator_and_dynamic_baseline_correction(self):
        report = self.report()
        self.assertEqual(report['denominator'], 102)
        self.assertEqual(report['parent_sections_count'], 16)
        self.assertEqual(report['not_counted_count'], 12)
        self.assertEqual(report['human_only'], 9)
        self.assertEqual(report['errors'], [])
        # D9 is an existing check missing from the old baseline, not a new detector.
        self.assertIn('dyn-ipad-layout', report['sources']['2.4.1'])
        self.assertGreaterEqual(report['covered'], 93)
        self.assertNotIn('1.2', report['covered_sections'])
        self.assertIn('deep-38', report['sources']['1.2.1'])

    def test_missing_executable_claim_is_an_error(self):
        base = copy.deepcopy(self.base)
        base['covered_by_scan'].append('1.1.1')
        self.assertTrue(any('1.1.1' in e for e in self.report(base)['errors']))

    def test_unknown_duplicate_and_human_only_claims_are_errors(self):
        for section in ('8.8', self.base['covered_by_scan'][0], '1.1.7'):
            base = copy.deepcopy(self.base)
            base['covered_by_scan'].append(section)
            self.assertTrue(self.report(base)['errors'], section)

    def test_exclusions_require_reasons_and_known_sections(self):
        base = copy.deepcopy(self.base)
        base['not_counted']['2.4.3'] = ''
        self.assertTrue(self.report(base)['errors'])
        base['human_only']['8.8'] = 'invented'
        self.assertTrue(self.report(base)['errors'])

    def test_dormant_module_does_not_count_as_a_scanner(self):
        with tempfile.TemporaryDirectory() as directory:
            skill = copy_repository_inputs(directory)
            (skill / 'scripts/lib/scan-dormant.sh').write_text('set_rule "fake"\nwarn "1.1.1 synthetic"\n')
            base = copy.deepcopy(self.base)
            base['covered_by_scan'].append('1.1.1')
            self.assertTrue(MODULE.build_report(skill, base)['errors'])

    def test_catalog_and_dynamic_table_are_cross_checked(self):
        with tempfile.TemporaryDirectory() as directory:
            skill = copy_repository_inputs(directory)
            catalog = skill / 'references/review-catalog.json'
            data = json.loads(catalog.read_text())
            data['checks'] = [c for c in data['checks'] if c['guideline'] != '1.4.1']
            catalog.write_text(json.dumps(data))
            dynamic = skill / 'scripts/dynamic.sh'
            dynamic.write_text(dynamic.read_text().replace('dyn-ipad-layout', 'dyn-removed'))
            errors = MODULE.build_report(skill, self.base)['errors']
            self.assertTrue(any('1.4.1' in e for e in errors))
            self.assertTrue(any('dyn-ipad-layout' in e for e in errors))

    def test_new_deep_sources_require_procedure_fixture_and_supported_kinds(self):
        for broken in ('procedure', 'fixture', 'kind'):
            with self.subTest(broken=broken), tempfile.TemporaryDirectory() as directory:
                skill = copy_repository_inputs(directory)
                if broken == 'procedure':
                    path = skill / 'references/pierre-deep-review.md'
                    path.write_text(path.read_text().replace('### 53 —', '### 153 —'))
                elif broken == 'fixture':
                    path = Path(directory) / 'corpus/synthetic/semantic-v4/cases.json'
                    cases = json.loads(path.read_text())
                    cases['cases'] = [c for c in cases['cases'] if c['check_number'] != 53]
                    path.write_text(json.dumps(cases))
                else:
                    path = skill / 'references/review-catalog.json'
                    catalog = json.loads(path.read_text())
                    next(c for c in catalog['checks'] if c['number'] == 53)['evidence_inputs'] = ['invented-input']
                    path.write_text(json.dumps(catalog))
                report = MODULE.build_report(skill, self.base)
                self.assertTrue(any('deep-53' in error for error in report['errors']))
                self.assertNotIn('deep-53', report['sources'].get('4.10', []))

    def test_host_inputs_require_explicit_context_declarations(self):
        with tempfile.TemporaryDirectory() as directory:
            skill = copy_repository_inputs(directory)
            path = skill / 'references/review-catalog.json'
            catalog = json.loads(path.read_text())
            check = next(c for c in catalog['checks'] if c['number'] == 32)
            check['required_context'] = []
            path.write_text(json.dumps(catalog))
            report = MODULE.build_report(skill, self.base)
            self.assertTrue(any('deep-32' in error and 'screenshots' in error for error in report['errors']))

    def test_positive_only_routes_are_explicit_without_changing_denominator(self):
        report = self.report()
        self.assertEqual(report['touched'], 93)
        self.assertEqual(report['positive_only'], 2)
        self.assertEqual(report['positive_only_sections'], ['2.5.14', '4.5.2'])
        self.assertEqual(report['denominator'], 102)
        self.assertIn('93 touched, 2 positive-only', MODULE.summary_line(report))
        for section in ('2.5.14', '4.5.2'):
            self.assertEqual(report['source_details'][section]['scope'], 'partial (positive-only observation)')
            self.assertIn('partial (positive-only observation)',
                          next(line for line in MODULE.markdown(report).splitlines() if line.startswith('| '+section+' |')))

    def test_generated_document_and_surface_counts(self):
        report = self.report()
        self.assertEqual((ROOT / 'docs/guideline-coverage.md').read_text(), MODULE.markdown(report))
        summary = MODULE.summary_line(report)
        for name in ('README.md', 'MAINTENANCE.md', 'CHANGELOG.md',
                     'skills/appstore-precheck/SKILL.md',
                     'skills/appstore-precheck/references/methodology.md'):
            self.assertIn(summary, (ROOT / name).read_text(), name)
        self.assertLess(len((SKILL / 'SKILL.md').read_text().splitlines()), 500)

    def test_cli_json_and_invalid_args(self):
        command = ['bash', str(SKILL / 'scripts/coverage-sections.sh')]
        result = subprocess.run(command + ['--json'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)['errors'], [])
        self.assertEqual(subprocess.run(command + ['--bogus'], capture_output=True).returncode, 2)


if __name__ == '__main__':
    unittest.main()
