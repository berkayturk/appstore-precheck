#!/usr/bin/env python3
"""Offline ASC transport, target selection, privacy and name proof regressions."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock
import urllib.error

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / 'skills/appstore-precheck/scripts/lib'

def load(name):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), LIB / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

m = load('metadata-review')
v = load('verification-metadata')
TARGET = {'bundle_id': 'org.example.demo', 'platform': 'iOS', 'version': '1.2', 'build': '7'}

def row(ident, _type='appInfoLocalizations', **attributes):
    return {'id': ident, 'type': _type, 'attributes': attributes}

def page(rows, total=None, next_url=None):
    return {'data': rows, 'meta': {'paging': {'total': len(rows) if total is None else total}},
            'links': {'next': next_url}}

def fixture():
    return {'responses': {
        '/v1/apps/app': {'data': row('app', _type='apps', bundleId=TARGET['bundle_id'], primaryLocale='en-US')},
        '/v1/apps/app/appStoreVersions': page([row('ver', _type='appStoreVersions', versionString='1.2', platform='IOS')]),
        '/v1/appStoreVersions/ver/build': {'data': row('build', _type='builds', version='7')},
        '/v1/apps/app/appInfos': page([row('info', _type='appInfos')]),
        '/v1/appInfos/info/appInfoLocalizations': page([row('en', locale='en-US', name='Example')]),
    }}

def proof(f=None):
    return v.capture((f or fixture())['responses'], 'app', 'ver', False)

def evaluate(data):
    return v.evaluate(v.VERIFIER, [{'id': 'proof', 'kind': v.KIND, 'data': data}], {'profile': {'target': TARGET}})

class NameProofTests(unittest.TestCase):
    def test_complete_and_ascii_boundary(self):
        for size, status in ((1, 'PASS'), (30, 'PASS'), (31, 'FINDING')):
            data = proof()
            data['responses']['/v1/appInfos/info/appInfoLocalizations']['data'][0]['attributes']['name'] = 'A' * size
            result = evaluate(data)
            self.assertEqual(result['status'], status)
            self.assertEqual(result['applicability'], 'APPLICABLE')

    def test_unknown_not_promoted(self):
        changes = [lambda d: d.update(source='fixture'), lambda d: d.update(status='PASS', responses={}),
                   lambda d: d['responses'].pop('/v1/appStoreVersions/ver/build'),
                   lambda d: d['responses']['/v1/apps/app']['data']['attributes'].update(bundleId='wrong'),
                   lambda d: d['responses']['/v1/appStoreVersions/ver/build']['data']['attributes'].update(version='8'),
                   lambda d: d['responses']['/v1/apps/app/appStoreVersions']['data'][0]['attributes'].update(versionString='9'),
                   lambda d: d['responses']['/v1/apps/app/appStoreVersions']['data'][0]['attributes'].update(platform='MAC_OS'),
                   lambda d: d['responses']['/v1/appInfos/info/appInfoLocalizations']['data'][0]['attributes'].pop('name'),
                   lambda d: d['responses']['/v1/appInfos/info/appInfoLocalizations'].pop('meta'),
                   lambda d: d['responses']['/v1/appInfos/info/appInfoLocalizations']['data'][0]['attributes'].update(locale='fr-FR'),
                   lambda d: d['responses']['/v1/appInfos/info/appInfoLocalizations']['data'][0]['attributes'].update(name=''),
                   lambda d: d['responses']['/v1/appInfos/info/appInfoLocalizations']['data'][0]['attributes'].update(name='😀' * 31)]
        for change in changes:
            with self.subTest(change=changes.index(change)):
                data = proof()
                change(data)
                result = evaluate(data)
                self.assertEqual(result['status'], 'UNKNOWN')
                self.assertNotIn('applicability', result)

    def test_pagination_all_localizations_and_missing_second_page(self):
        data = proof()
        path = '/v1/appInfos/info/appInfoLocalizations'
        data['responses'][path] = page([row('en', locale='en-US', name='Example')], 2, v.BASE + path + '?cursor=next')
        self.assertEqual(evaluate(data)['status'], 'UNKNOWN')
        data['responses'][path + '?cursor=next'] = page([row('fr', locale='fr-FR', name='Example FR')], 2)
        self.assertEqual(evaluate(data)['status'], 'PASS')
        data['responses'][path + '?cursor=next']['data'][0]['attributes']['name'] = 'X' * 31
        self.assertEqual(evaluate(data)['status'], 'FINDING')

    def test_all_infos_needed_but_ambiguous_info_cannot_prove_finding(self):
        data = proof()
        data['responses']['/v1/apps/app/appInfos'] = page([row('info', _type='appInfos'), row('other', _type='appInfos')])
        self.assertEqual(evaluate(data)['status'], 'UNKNOWN')
        path = '/v1/appInfos/other/appInfoLocalizations'
        data['responses'][path] = page([row('other-en', locale='en-US', name='Other')])
        self.assertEqual(evaluate(data)['status'], 'PASS')
        data['responses'][path]['data'][0]['attributes']['name'] = 'X' * 31
        self.assertEqual(evaluate(data)['status'], 'UNKNOWN')

    def test_duplicate_locale_invalid_and_raw_pass_ignored(self):
        data = proof()
        data['responses']['/v1/appInfos/info/appInfoLocalizations'] = page([
            row('en', locale='en-US', name='Example'), row('duplicate', locale='en-US', name='Example')])
        self.assertEqual(evaluate(data)['status'], 'UNKNOWN')
        self.assertEqual(evaluate({'status': 'PASS', 'all_locales_complete': True})['status'], 'UNKNOWN')

    def test_wrong_resource_types_and_malformed_build_id(self):
        for path in fixture()['responses']:
            data = proof()
            row_value = data['responses'][path]['data']
            if isinstance(row_value, list):
                row_value = row_value[0]
            row_value['type'] = 'wrongResource'
            self.assertEqual(evaluate(data)['status'], 'UNKNOWN', path)
        for bad_id in ('../build', '', 42, 'béld'):
            data = proof()
            data['responses']['/v1/appStoreVersions/ver/build']['data']['id'] = bad_id
            self.assertEqual(evaluate(data)['status'], 'UNKNOWN')

    def test_uncertain_complete_capture_blocks_pass_but_incomplete_alternative_does_not(self):
        uncertain = proof()
        uncertain['responses']['/v1/appInfos/info/appInfoLocalizations']['data'][0]['attributes']['name'] = '😀' * 31
        payloads = [{'id': 'good', 'kind': v.KIND, 'data': proof()}, {'id': 'uncertain', 'kind': v.KIND, 'data': uncertain}]
        result = v.evaluate(v.VERIFIER, payloads, {'profile': {'target': TARGET}})
        self.assertEqual(result['status'], 'UNKNOWN')
        payloads[1]['data'] = {'status': 'PASS'}
        self.assertEqual(v.evaluate(v.VERIFIER, payloads, {'profile': {'target': TARGET}})['status'], 'PASS')
        decisive = proof()
        decisive['responses']['/v1/appInfos/info/appInfoLocalizations']['data'][0]['attributes']['name'] = 'X' * 31
        payloads.append({'id': 'bad', 'kind': v.KIND, 'data': decisive})
        self.assertEqual(v.evaluate(v.VERIFIER, payloads, {'profile': {'target': TARGET}})['status'], 'FINDING')

    def test_projection_masks_secrets_and_excludes_raw_review(self):
        data = fixture()
        data['responses']['/v1/appStoreVersions/ver/appStoreReviewDetail'] = {'data': row('review', demoAccountPassword='password-secret', notes='private-note')}
        data['responses']['/v1/apps/app']['data']['attributes']['secret'] = 'secret-content'
        with mock.patch.dict(os.environ, {'PRECHECK_DEMO_PASSWORD': 'Example'}):
            captured = proof(data)
        serialized = json.dumps(captured)
        for secret in ('Example', 'password-secret', 'private-note', 'secret-content'):
            self.assertNotIn(secret, serialized)
        self.assertEqual(evaluate(captured)['status'], 'UNKNOWN')

class CollectionTests(unittest.TestCase):
    def test_pagination_and_transport_gaps(self):
        path = '/v1/apps/app/appInfos'
        data = fixture()
        data['responses'][path] = page([row('info', _type='appInfos')], 2, v.BASE + path + '?cursor=2')
        data['responses'][path + '?cursor=2'] = page([row('other', _type='appInfos')], 2)
        self.assertEqual(len(m.ASC(data).items(path)), 2)
        for bad_next in ('https://evil.example/page', v.BASE + '/v1/apps/other/appInfos', v.BASE + path, 42):
            bad = copy.deepcopy(data)
            bad['responses'][path]['links']['next'] = bad_next
            with self.assertRaises(m.ApiError):
                m.ASC(bad).items(path)
        for problem in ('authorization', 'timeout'):
            bad = {'responses': {path: {'fixture_error': problem, 'detail': 'private-password'}}}
            with self.assertRaises(m.ApiError) as result:
                m.ASC(bad).items(path)
            self.assertNotIn('private-password', str(result.exception))

    def test_real_http_auth_and_timeout_masking(self):
        # Mock transport directly so fixture error handling cannot hide production bugs.
        api = m.ASC({"responses": {}})
        api.fixture = None
        api.token = 'private-token'
        for error in (urllib.error.HTTPError('private-url', 401, 'private-password', {}, None),
                      TimeoutError('private-password')):
            with mock.patch.object(m.urllib.request, 'build_opener') as opener:
                opener.return_value.open.side_effect = error
                with self.assertRaises(m.ApiError) as raised:
                    api.get('/v1/apps/app')
                self.assertNotIn('private', str(raised.exception))

    def test_deadline_and_missing_fields(self):
        api = m.ASC(fixture())
        api.deadline = 0
        with self.assertRaises(m.ApiError):
            api.get('/v1/apps/app')
        data = fixture()
        data['responses']['/v1/apps/app/appInfos'] = {'data': [None]}
        with self.assertRaises(m.ApiError):
            m.ASC(data).items('/v1/apps/app/appInfos')
        self.assertEqual(m.attrs({'attributes': None}), {})

    def test_exact_selection_no_latest_fallback(self):
        for field, value in (('version_id', 'wrong'), ('version_string', 'wrong'), ('build_number', 'wrong'), ('bundle_id', 'wrong')):
            kwargs = {'version_id': 'ver', 'bundle_id': TARGET['bundle_id'], 'version_string': '1.2', 'build_number': '7'}
            kwargs[field] = value
            result = m.collect_asc(m.ASC(fixture()), 'app', **kwargs)
            self.assertEqual(result['selection_status'], 'UNRESOLVED')
            self.assertIsInstance(result['review'], m.ApiError)
        data = fixture()
        data['responses']['/v1/apps/app/appStoreVersions'] = page([
            row('ver', _type='appStoreVersions', versionString='1.2', platform='IOS'), row('other', _type='appStoreVersions', versionString='1.3', platform='IOS')])
        result = m.collect_asc(m.ASC(data), 'app')
        self.assertEqual(result['selection_status'], 'UNRESOLVED')

    def test_no_credentials_means_live_not_run(self):
        with tempfile.TemporaryDirectory() as temp:
            env = {key: value for key, value in os.environ.items() if not key.startswith('ASC_')}
            result = subprocess.run(['python3', str(LIB / 'metadata-review.py'), '--repo', temp,
                                     '--asc-app-id', 'app'], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads(result.stdout)
            self.assertEqual(report['sources']['app_store_connect_status'], 'NOT_RUN')
            self.assertEqual(report['selection']['status'], 'UNRESOLVED')

    def test_cli_rejects_output_in_source(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'name.txt'
            path.write_text('original')
            result = subprocess.run(['python3', str(LIB / 'metadata-review.py'), '--repo', temp,
                                     '--out', str(path)], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(path.read_text(), 'original')

    def test_cli_private_capture_and_read_only_local_input(self):
        with tempfile.TemporaryDirectory() as temp:
            tmp = Path(temp)
            repo = tmp / 'app'
            local = repo / 'fastlane/metadata/en-US'
            local.mkdir(parents=True)
            (local / 'name.txt').write_text('Local Name')
            (local / 'support_url.txt').write_text('https://example.org/support')
            fixture_path, out = tmp / 'fixture.json', tmp / 'proof.json'
            fixture_path.write_text(json.dumps(fixture()))
            command = ['python3', str(LIB / 'metadata-review.py'), '--repo', str(repo), '--asc-app-id', 'app',
                       '--asc-version-id', 'ver', '--bundle-id', TARGET['bundle_id'], '--version', '1.2',
                       '--build-number', '7', '--asc-fixture', str(fixture_path), '--verification-evidence-out', str(out)]
            before = {str(p): p.read_bytes() for p in repo.rglob('*') if p.is_file()}
            result = subprocess.run(command, env=dict(os.environ, APPSTORE_PRECHECK_TEST_MODE='1'), capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads(result.stdout)
            self.assertEqual(out.stat().st_mode & 0o777, 0o600)
            self.assertEqual(evaluate(json.loads(out.read_text()))['status'], 'UNKNOWN')
            self.assertEqual(before, {str(p): p.read_bytes() for p in repo.rglob('*') if p.is_file()})
            remote = {x['check_id']: x['status'] for x in report['results']}
            local_results = {x['check_id']: x['status'] for x in report['local_results']}
            self.assertEqual(remote['meta-support-url'], 'SKIP')
            self.assertEqual(local_results['meta-support-url'], 'PASS')
            repeated = subprocess.run(command, env=dict(os.environ, APPSTORE_PRECHECK_TEST_MODE='1'), capture_output=True, text=True)
            self.assertNotEqual(repeated.returncode, 0)

if __name__ == '__main__':
    unittest.main()
