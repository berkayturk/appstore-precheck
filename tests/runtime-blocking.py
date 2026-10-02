import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


class RuntimeBlocking(unittest.TestCase):
    def setUp(self):
        path = Path(__file__).resolve().parents[1] / 'skills/appstore-precheck/scripts/lib/runtime-blocking.py'
        spec = importlib.util.spec_from_file_location('blocking', path)
        self.module = importlib.util.module_from_spec(spec); spec.loader.exec_module(self.module)

    def test_unanimity_freshness_and_positive_crash_required(self):
        with tempfile.TemporaryDirectory() as temporary:
            out = Path(temporary)
            report = {'device': {'created_by_this_run': True}, 'fresh_erases': 3, 'dry_run': False,
                      'repeats': 3, 'launch': {'pass': 0, 'finding': 3, 'skip': 0}}
            transcript = 'DYNAMIC-FINDING: 2.1 [dyn-launch] — quorum 3/3: failed; process gone; fresh erase verified\n'
            (out / 'transcript.txt').write_text(transcript)
            (out / 'run.json').write_text(json.dumps(report))
            self.assertEqual(len(self.module.blocking(out)), 1)
            for field, value in [('fresh_erases', 2), ('dry_run', True), ('repeats', 1)]:
                changed = dict(report, **{field: value}); (out / 'run.json').write_text(json.dumps(changed))
                self.assertEqual(self.module.blocking(out), [])
            (out / 'run.json').write_text(json.dumps(report))
            (out / 'transcript.txt').write_text(transcript.replace('process gone', 'flat screenshot'))
            self.assertEqual(self.module.blocking(out), [])


if __name__ == '__main__':
    unittest.main()
