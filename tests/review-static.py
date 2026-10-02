"""Regression counterexamples from review round one."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
ENGINE = ROOT / 'skills/appstore-precheck/scripts/lib/static-guidelines.py'
spec = importlib.util.spec_from_file_location('rules', ENGINE)
rules = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rules)


def evaluate(files):
    with tempfile.TemporaryDirectory() as folder:
        root = Path(folder)
        for name, value in files.items():
            p = root / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_bytes(value) if isinstance(value, bytes) else p.write_text(value)
        return rules.evaluate(root, root / 'fastlane/metadata', root / 'Info.plist', [])


class ReviewStatic(unittest.TestCase):
    def test_m7_release_notes_allowed_and_initial_version(self):
        for value in ('Bug fixes', 'Bug fixes and improvements'):
            self.assertEqual(evaluate({'fastlane/metadata/en-US/release_notes.txt': value})['release-notes-specificity']['status'], 'PASS')
        self.assertEqual(evaluate({'fastlane/metadata/en-US/release_notes.txt': '', 'fastlane/metadata/version.txt': '1.0'})['release-notes-specificity']['status'], 'PASS')
        result = evaluate({'fastlane/metadata/en-US/release_notes.txt': ''})['release-notes-specificity']
        self.assertEqual(result['status'], 'WARN'); self.assertIn('low-confidence', result['reason'])

    def test_m7_browser_brand_boundaries(self):
        for text in ('"abcdef123cef"', '"blink"', '"SuperChromium"'):
            result = evaluate({'App.swift': 'let value = 1', 'Package.resolved': text})
            self.assertEqual(result['browser-engine']['status'], 'PASS')
        self.assertEqual(evaluate({'App.swift': 'let value = 1', 'Podfile': "pod 'Chromium'"})['browser-engine']['status'], 'WARN')

    def test_m7_activity_is_not_intent(self):
        import plistlib
        result = evaluate({'App.swift': 'let value = 1', 'Info.plist': plistlib.dumps({'NSUserActivityTypes': ['search']})})
        self.assertEqual(result['intent-handler-parity']['status'], 'PASS')

    def test_m7_extension_manifest_absence_and_generated_id(self):
        import plistlib
        result = evaluate({'App.swift': 'class Filter: CXCallDirectoryProvider {}'})
        self.assertEqual(result['extension-bundle-parity']['status'], 'PASS')
        result = evaluate({'App.swift': 'let value = 1', 'Info.plist': plistlib.dumps({'CFBundleIdentifier': 'org.example.app'}), 'Widget/Info.plist': plistlib.dumps({'NSExtension': {}})})
        self.assertEqual(result['extension-bundle-parity']['status'], 'SKIP')
        self.assertIn('bundle id resolved by build settings', result['extension-bundle-parity']['reason'])

    def test_m7_root_extension_does_not_capture_app_ads(self):
        import plistlib
        result = evaluate({'ios/Info.plist': plistlib.dumps({'NSExtension': {}}), 'ios/App.swift': 'import GoogleMobileAds'})
        self.assertEqual(result['extension-advertising']['status'], 'SKIP')
        self.assertIn('extension source dir unresolved', result['extension-advertising']['reason'].lower())

    def test_m7_official_phone_app_is_not_apple_endorsement(self):
        self.assertEqual(evaluate({'fastlane/metadata/en-US/description.txt': 'The official iPhone app of Example'})['apple-endorsement-claims']['status'], 'PASS')

    def test_m7_generic_verify_is_not_authentication(self):
        self.assertEqual(evaluate({'App.swift': 'let face: VNFaceObservation; func verifyImageQuality() {}'})['face-authentication']['status'], 'PASS')

    def test_m16_remote_script_url_is_bounded(self):
        text = 'WKScriptMessageHandler evaluateJavaScript CLLocationManager "https://' + 'a' * 3000 + '.js"'
        self.assertEqual(evaluate({'App.swift': text})['miniapp-native-bridge']['status'], 'PASS')

    def test_m1_empty_source_tree_is_not_clean(self):
        result = evaluate({})
        for key in rules.CHECKS:
            if key not in ('release-notes-specificity', 'apple-endorsement-claims'):
                self.assertEqual(result[key]['status'], 'SKIP', key)

    def test_browser_brand_in_source_file_name_is_not_an_engine(self):
        pbx = 'path = "Eye Blink.swift"; sourceTree = "<group>"; path = "Gecko Tracker.m";'
        src = {'App.swift': 'import UIKit'}
        self.assertEqual(evaluate(dict(src, **{'App.xcodeproj/project.pbxproj': pbx}))['browser-engine']['status'], 'PASS')
        self.assertEqual(evaluate(dict(src, **{'Podfile': "pod 'Chromium'"}))['browser-engine']['status'], 'WARN')

    def test_m1_missing_main_plist_abstains_for_manifest_comparisons(self):
        result = evaluate({'App.swift': 'Text("Welcome")'})
        for key in ('intent-handler-parity', 'companion-app-required'):
            self.assertEqual(result[key]['status'], 'SKIP', key)

    def test_m3_utf16_strings_and_file_local_gaps(self):
        result = evaluate({'App.swift': 'let view = UIWebView()',
                           'Localizable.strings': '"restart" = "Restart your device";'.encode('utf-16'),
                           'Broken.js': b'\xff'})
        self.assertEqual(result['browser-engine']['status'], 'WARN')
        self.assertEqual(result['device-restart-instructions']['status'], 'WARN')
        self.assertEqual(result['_input_gaps']['count'], 1)
        self.assertEqual(result['_input_gaps']['paths'], ['Broken.js'])

    def test_m3_flutter_link_cache_is_pruned(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); (root / 'ios/.symlinks').mkdir(parents=True)
            (root / 'ios/.symlinks/plugin').symlink_to('/unavailable-cache')
            (root / 'App.swift').write_text('let view = UIWebView()')
            result = rules.evaluate(root, root / 'meta', root / 'Info.plist', [])
            self.assertEqual(result['browser-engine']['status'], 'WARN')
            self.assertNotIn('_input_gaps', result)

    def test_b2_metadata_emoji_is_not_a_violation(self):
        result = evaluate({'fastlane/metadata/en-US/name.txt': 'My journal 😀'})
        self.assertEqual(result['metadata-emoji']['status'], 'PASS')
        self.assertNotIn('metadata', result['metadata-emoji']['reason'].lower())

    def test_b2_embedded_emoji_artwork_is_a_narrow_signal(self):
        for name in ('Assets.xcassets/emoji-face.imageset/face.png', 'Resources/AppleColorEmoji.ttc', 'Resources/emoji_smile.png'):
            with self.subTest(name=name):
                self.assertEqual(evaluate({name: b'asset'})['metadata-emoji']['status'], 'WARN')

    def test_b3_system_picker_satisfies_document_access(self):
        for source in ('let picker = UIDocumentPickerViewController()', 'view.fileImporter(isPresented: $show) {}', 'let browser = UIDocumentBrowserViewController()'):
            self.assertEqual(evaluate({'App.swift': source})['document-browser-access']['status'], 'PASS')

    def test_b3_custom_browser_without_system_access_warns(self):
        result = evaluate({'Browser.swift': 'let files = FileManager.default.contentsOfDirectory(atPath: path)\nList(files) { Text($0) }.navigationTitle("Documents")'})
        self.assertEqual(result['document-browser-access']['status'], 'WARN')
        self.assertEqual(evaluate({'App.swift': 'Text("Welcome")'})['document-browser-access']['status'], 'PASS')

    def test_b1_reader_timeout_has_an_explicit_reason(self):
        path = ENGINE.with_name('static-reader.py')
        spec = importlib.util.spec_from_file_location('reader', path)
        reader = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(reader)
        from unittest.mock import patch
        with patch.object(reader.subprocess, 'run', side_effect=subprocess.TimeoutExpired(['reader'], 60)):
            self.assertIn('reader timeout', reader.read([], 60)['_reader_error'])

    def test_b1_large_source_tree_finishes_within_five_seconds(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for i in range(1500):
                (root / ('File%d.swift' % i)).write_text('let value = 1\n' * 80)
            started = time.monotonic()
            try:
                subprocess.run(['python3', '-B', str(ENGINE), '--root', folder,
                                '--metadata', folder + '/metadata', '--plist', folder + '/Info.plist'],
                               stdout=subprocess.DEVNULL, check=True, timeout=5)
            except subprocess.TimeoutExpired:
                self.fail('1500 source files exceeded the five second budget')
            self.assertLess(time.monotonic() - started, 5)


if __name__ == '__main__':
    unittest.main()
