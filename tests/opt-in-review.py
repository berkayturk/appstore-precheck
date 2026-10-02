import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

S = Path(__file__).resolve().parents[1] / 'skills/appstore-precheck/scripts'


def load(name):
    spec = importlib.util.spec_from_file_location(name.replace('/', '_'), S / (name + '.py'))
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module


class OptionalReview(unittest.TestCase):
    def test_missing_tool_returns_127(self):
        result = load('lib/dyn-process').run(['no-precheck-binary-here'], 1, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.assertEqual(result.returncode, 127)

    def test_sibling_skip_cannot_be_hidden(self):
        module = load('opt-in-review')
        for first, second in [('PASS', 'SKIP'), ('SKIP', 'PASS'), ('PASS', 'NOT_RUN')]:
            self.assertEqual(module.merge_status(first, second), 'REVIEW_REQUIRED')
        self.assertEqual(module.merge_status('PASS', 'PASS'), 'PASS')
        self.assertEqual(module.merge_status('PASS', 'FINDING'), 'FINDING')

    def test_stale_report_links_never_touch_their_targets(self):
        module = load('opt-in-review')
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary); out = base / 'out'; out.mkdir()
            victim = base / 'victim'; victim.write_text('unchanged')
            (out / 'summary.json').symlink_to(victim)
            (out / 'unrelated.txt').write_text('retained')
            module.remove_stale_outputs(out)
            self.assertEqual(victim.read_text(), 'unchanged')
            self.assertFalse((out / 'summary.json').exists())
            self.assertTrue((out / 'unrelated.txt').exists())
            writer = load('lib/safe_write')
            (out / 'link').symlink_to(victim)
            with self.assertRaises(OSError):
                writer.write_text(out / 'link', 'changed')

    def test_metadata_options_require_the_metadata_tier(self):
        with tempfile.TemporaryDirectory() as temporary:
            result = subprocess.run(['python3', str(S / 'opt-in-review.py'), '--repo', temporary, '--check-urls'], capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)
            self.assertIn('--metadata', result.stderr)

    def test_output_containment_is_usage_error(self):
        with tempfile.TemporaryDirectory() as temporary:
            command = ['python3', str(S / 'opt-in-review.py'), '--repo', temporary, '--build', '--dynamic-blocking', '--out-dir', temporary]
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)
            self.assertIn('outside', result.stderr)

    def test_missing_output_is_reported_and_unrequested_tiers_stay_not_run(self):
        with tempfile.TemporaryDirectory() as temporary:
            result = subprocess.run(['python3', str(S / 'opt-in-review.py'), '--repo', temporary], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads(result.stdout)
            out = Path(report['output_dir'])
            self.assertTrue((out / 'summary.json').is_file())
            self.assertEqual(set(report['tiers'].values()), {'NOT_RUN'})
            import shutil
            shutil.rmtree(out)


if __name__ == '__main__':
    unittest.main()
