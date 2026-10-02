"""Regression tests for post-release static-reader follow-ups."""
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SCAN = Path(__file__).resolve().parents[1] / 'skills/appstore-precheck/scripts/scan.sh'
ENGINE = ROOT / 'skills/appstore-precheck/scripts/lib/static-guidelines.py'
spec = importlib.util.spec_from_file_location('rules', ENGINE)
rules = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rules)


def evaluate(files):
    with tempfile.TemporaryDirectory() as folder:
        root = Path(folder)
        for name, value in files.items():
            target = root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(value) if isinstance(value, bytes) else target.write_text(value)
        return rules.evaluate(root, root / 'metadata', root / 'Info.plist', [])


class FollowupStatic(unittest.TestCase):
    def test_f1_special_files_do_not_block_reader(self):
        for name in ('Foo.swift', 'Info.plist'):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                os.mkfifo(root / name)
                started = time.monotonic()
                result = subprocess.run([sys.executable, '-B', str(ENGINE), '--root', folder,
                                         '--metadata', folder + '/metadata', '--plist', folder + '/Info.plist'],
                                        capture_output=True, text=True, timeout=2)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertLess(time.monotonic() - started, 2)
                self.assertIn('special file skipped', json.dumps(json.loads(result.stdout)['_input_gaps']))

    def test_f1_full_scan_does_not_block_on_fifo_sources(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); (root / 'ios/App').mkdir(parents=True)
            (root / 'ios/App/A.swift').write_text('import UIKit\n')
            os.mkfifo(root / 'ios/App/Foo.swift')
            started = time.monotonic()
            result = subprocess.run(['bash', str(SCAN), '--dir', folder], capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertLess(time.monotonic() - started, 20)

    def test_d2_metadata_read_errors_keep_relative_name_and_detail(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); meta = root / 'metadata/en-US'; meta.mkdir(parents=True)
            (meta / 'description.txt').write_bytes(b'x' * (2 * 1024 * 1024 + 1))
            row = rules.evaluate(root, root / 'metadata', root / 'Info.plist', [])['apple-endorsement-claims']
            self.assertEqual(row['status'], 'SKIP')
            self.assertIn('description.txt', row['reason'])
            self.assertIn('exceeds read limit', row['reason'])
            self.assertNotIn(folder, row['reason'])

    def test_f2_quoted_patterns_have_bounded_runtime(self):
        script = r"""import importlib.util, pathlib, sys, time
spec = importlib.util.spec_from_file_location('rules', sys.argv[1])
rules = importlib.util.module_from_spec(spec); spec.loader.exec_module(rules)
text = '\"install ' + (sys.argv[3] * (1024 * 1024 // len(sys.argv[3])))
p = pathlib.Path('App.swift')
c = {'src': {p: text}, 'resources': {}, 'files': {pathlib.Path('Podfile'): text},
     'main': {'LSApplicationQueriesSchemes': ['other']}}
start = time.monotonic()
getattr(rules, sys.argv[2])(c)
print(time.monotonic() - start)
"""
        for name, words in [('restart', 'reboot '), ('companion', 'install app to continue '),
                            ('call_filter', 'blocked numbers '), ('browser', 'Chromium '),
                            ('companion', ' ')]:
            with self.subTest(check=name):
                result = subprocess.run([sys.executable, '-B', '-c', script, str(ENGINE), name, words],
                                        capture_output=True, text=True, timeout=1)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertLess(float(result.stdout), 1)

    def test_f3_input_exception_reasons_omit_absolute_paths(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for prefix in ('/Users/private/app', '/home/private/app'):
                exc = PermissionError(13, 'Permission denied', prefix + '/metadata/description.txt')
                with patch.dict(rules.CHECKS, {'apple-endorsement-claims': lambda c: (_ for _ in ()).throw(exc)}):
                    row = rules.evaluate(root, root / 'metadata', root / 'Info.plist', [])['apple-endorsement-claims']
                self.assertEqual(row['status'], 'SKIP')
                self.assertIn('description.txt', row['reason'])
                self.assertNotIn('/Users/', json.dumps(row))
                self.assertNotIn('/home/', json.dumps(row))

    def test_f6_empty_release_notes_use_app_version(self):
        for version, status in [('1.0', 'PASS'), ('1.0.0', 'PASS'), ('2.3', 'WARN'), ('', 'WARN')]:
            with self.subTest(version=version):
                row = evaluate({'metadata/en-US/release_notes.txt': '',
                                'Info.plist': plistlib.dumps({'CFBundleShortVersionString': version})})['release-notes-specificity']
                self.assertEqual(row['status'], status)
                if status == 'PASS':
                    self.assertIn('empty release notes accepted for the initial version', row['reason'])
                elif not version:
                    self.assertIn('low-confidence', row['reason'])

    def test_f6_marketing_version_and_metadata_fallback(self):
        for files in ({'App.xcodeproj/project.pbxproj': 'MARKETING_VERSION = 1.0.0;'},
                      {'metadata/version.txt': '1.0.0'}):
            row = evaluate(dict(files, **{'metadata/en-US/release_notes.txt': ''}))['release-notes-specificity']
            self.assertEqual(row['status'], 'PASS')
        row = evaluate({'metadata/en-US/release_notes.txt': '', 'metadata/version.txt': '1.0',
                        'Info.plist': plistlib.dumps({'CFBundleShortVersionString': '2.3'}),
                        'App.xcodeproj/project.pbxproj': 'MARKETING_VERSION = 1.0;'})['release-notes-specificity']
        self.assertEqual(row['status'], 'WARN')

    def test_f7_document_title_requires_listing_and_file_access(self):
        listing = 'List(files) { Text($0) }'
        title = 'Text("Documents")'
        access = 'FileManager.default.contentsOfDirectory(atPath: path)'
        for source in (title, 'Text("Files")', title + listing, access + listing, title + access):
            self.assertEqual(evaluate({'App.swift': source})['document-browser-access']['status'], 'PASS', source)
        for api in (access, 'FileManager.default.enumerator(at: url)'):
            source = api + listing + title
            self.assertEqual(evaluate({'App.swift': source})['document-browser-access']['status'], 'WARN')
            for picker in ('UIDocumentPickerViewController()', '.fileImporter(isPresented: $show)', 'UIDocumentBrowserViewController()'):
                self.assertEqual(evaluate({'App.swift': source + picker})['document-browser-access']['status'], 'PASS')


if __name__ == '__main__':
    unittest.main()
