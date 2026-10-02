import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import urllib.error

S = Path(__file__).resolve().parents[1] / 'skills/appstore-precheck/scripts'


def load(name):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), S / 'lib' / (name + '.py'))
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module


class Metadata(unittest.TestCase):
    def test_present_declarations_remain_unverified(self):
        from types import SimpleNamespace
        module = load('metadata-review')
        args = SimpleNamespace(login_required=True)
        asc = {'age': {'data': {'attributes': {'violence': 'NONE'}}},
               'review': {'data': {'attributes': {'notes': 'Review steps', 'demoAccountName': 'demo', 'demoAccountPassword': 'secret'}}},
               'purchases': [{'attributes': {'reviewNote': 'Review purchase'}}], 'subscriptions': [],
               'iap_screenshots': [{'data': {'id': 'screenshot'}}]}
        rows = []
        with tempfile.TemporaryDirectory() as folder:
            for part in (module.review_part_0, module.review_part_1, module.review_part_2):
                part(args, asc, Path(folder), rows)
        self.assertEqual(len(rows), 5)
        for row in rows:
            self.assertEqual(row['status'], 'NEEDS_REVIEW', row)
            self.assertIn('unverified', row['reason'])

    def run_review(self, repo, *extra):
        r = subprocess.run(['bash', str(S / 'metadata-review.sh'), '--repo', str(repo)] + list(extra), capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        return json.loads(r.stdout)

    def test_locale_exclusions_and_missing_url(self):
        with tempfile.TemporaryDirectory() as temporary:
            repo = Path(temporary); metadata = repo / 'fastlane/metadata'
            for locale in ['en-US', 'review_information', 'trade_representative_contact_information', 'default']:
                (metadata / locale).mkdir(parents=True)
            for name in ['privacy_url', 'support_url']:
                (metadata / 'en-US' / (name + '.txt')).write_text('https://example.com')
            report = self.run_review(repo)
            records = {r['check_id']:r for r in report['results']}
            self.assertEqual(records['meta-privacy-url']['status'], 'PASS')
            self.assertEqual(records['meta-support-url']['status'], 'PASS')
            (metadata / 'en-US/support_url.txt').unlink()
            records = {r['check_id']:r for r in self.run_review(repo)['results']}
            self.assertEqual(records['meta-support-url']['status'], 'NEEDS_REVIEW')

    def test_absent_sources_abstain_and_api_error_reason_is_retained(self):
        with tempfile.TemporaryDirectory() as temporary:
            report = self.run_review(temporary)
            self.assertTrue(all(r['status'] == 'NOT_RUN' for r in report['results']))
            fixture = Path(temporary) / 'fixture.json'; fixture.write_text('{}')
            env = dict(os.environ, APPSTORE_PRECHECK_TEST_MODE='1')
            r = subprocess.run(['bash', str(S / 'metadata-review.sh'), '--repo', temporary, '--asc-app-id', 'app', '--asc-fixture', str(fixture)], env=env, capture_output=True, text=True)
            self.assertEqual(r.returncode, 0)
            self.assertIn('Fixture API response collection malformed', json.loads(r.stdout)['asc_error'])

    def test_client_encodes_ids_refuses_redirects_and_signs_der(self):
        module = load('asc-client')
        self.assertEqual(module.encode_id('a/b?c'), 'a%2Fb%3Fc')
        with self.assertRaises(urllib.error.URLError):
            module.NoRedirect().redirect_request(None, None, 302, None, None, 'https://attacker.example')
        self.assertEqual(len(module.der_to_jose(bytes.fromhex('3006020101020102'))), 64)
        with self.assertRaises(module.ApiError):
            module.der_to_jose(b'bad')
        api = module.ASC({'responses': {'/v1/apps/a': {'data': {'id': 'a'}}}})
        self.assertEqual(api.get('/v1/apps/a')['data']['id'], 'a')
        with self.assertRaises(module.ApiError):
            api.get('https://attacker.example')


if __name__ == '__main__':
    unittest.main()
