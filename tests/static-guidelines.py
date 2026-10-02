#!/usr/bin/env python3
"""Each contract rule has independent labeled positive and clean evidence."""
import importlib.util
import json
import pathlib
import plistlib
import tempfile
import unittest
from unittest import mock

ROOT = pathlib.Path(__file__).resolve().parents[1]
ENGINE = ROOT / 'skills/appstore-precheck/scripts/lib/static-guidelines.py'
CASES = json.loads((ROOT / 'tests/fixtures/static-guideline-cases.json').read_text())


def evaluate(files):
    spec = importlib.util.spec_from_file_location('static_guidelines', ENGINE)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    with tempfile.TemporaryDirectory() as folder:
        root = pathlib.Path(folder)
        for path, value in files.items():
            target = root / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(value) if isinstance(value, bytes) else target.write_text(value)
        return module.evaluate(root, root / 'fastlane/metadata', root / 'Info.plist', [])


class StaticRules(unittest.TestCase):
    def test_malformed_xml_manifest_abstains_without_losing_metadata(self):
        result = evaluate({'Info.plist': '<plist><dict>',
                           'fastlane/metadata/en-US/name.txt': 'Daily Journal'})
        self.assertEqual(result['intent-handler-parity']['status'], 'SKIP')
        self.assertEqual(result['metadata-emoji']['status'], 'PASS')

    def test_binary_plist_remains_valid_evidence(self):
        result = evaluate({'Info.plist': plistlib.dumps({'LSSupportsOpeningDocumentsInPlace': True}, fmt=plistlib.FMT_BINARY),
                           'App.swift': 'let picker = UIDocumentPickerViewController()'})
        self.assertEqual(result['document-browser-access']['status'], 'PASS')

    def test_oversized_source_abstains_instead_of_missing_handler_warning(self):
        result = evaluate({'Info.plist': '<plist><dict><key>INIntentsSupported</key><array><string>SendIntent</string></array></dict></plist>',
                           'Handler.swift': '// filler' * 240000 + '\nclass Handler: INExtension {}'})
        self.assertEqual(result['intent-handler-parity']['status'], 'SKIP')
        self.assertIn('Handler.swift', str(result['_input_gaps']))

    def test_invalid_utf8_source_resource_and_plist_abstain(self):
        for name in ('App.swift', 'Localizable.xcstrings', 'Info.plist'):
            with self.subTest(name=name):
                result = evaluate({name: b'\xffinvalid'})
                self.assertEqual(result['call-filter-controls']['status'], 'SKIP')
                self.assertEqual(result['browser-engine']['status'], 'SKIP')

    def test_unreadable_source_abstains(self):
        original = pathlib.Path.read_text
        def deny(path, *args, **kwargs):
            if path.name == 'Blocked.swift':
                raise PermissionError('permission denied')
            return original(path, *args, **kwargs)
        with mock.patch.object(pathlib.Path, 'read_text', deny):
            result = evaluate({'Blocked.swift': 'import Matter'})
        self.assertEqual(result['matter-extension']['status'], 'SKIP')
        self.assertIn('Blocked.swift', str(result['_input_gaps']))

    def test_unreadable_metadata_abstains_for_related_rules(self):
        original = pathlib.Path.read_text
        def deny(path, *args, **kwargs):
            if path.name in ('description.txt', 'release_notes.txt'):
                raise PermissionError('permission denied')
            return original(path, *args, **kwargs)
        with mock.patch.object(pathlib.Path, 'read_text', deny):
            result = evaluate({'fastlane/metadata/en-US/release_notes.txt': 'Update',
                               'fastlane/metadata/en-US/description.txt': 'A journal'})
        for rule in ('release-notes-specificity', 'apple-endorsement-claims'):
            self.assertEqual(result[rule]['status'], 'SKIP')
        self.assertEqual(result['browser-engine']['status'], 'SKIP')

    def test_invalid_and_oversized_metadata_abstain(self):
        for value in (b'\xff', 'x' * (2 * 1024 * 1024 + 1)):
            with self.subTest(size=len(value)):
                result = evaluate({'fastlane/metadata/en-US/release_notes.txt': value})
                for rule in ('release-notes-specificity', 'apple-endorsement-claims'):
                    self.assertEqual(result[rule]['status'], 'SKIP')

    def test_restart_test_name_is_not_user_facing_copy(self):
        for module in ('Testing', 'XCTest'):
            with self.subTest(module=module):
                result = evaluate({'ClockTests.swift': 'import ' + module + '\n@Test("reboot detected when monotonic regresses")'})
                self.assertEqual(result['device-restart-instructions']['status'], 'PASS')

    def test_large_string_catalog_is_read_with_a_separate_bounded_limit(self):
        result = evaluate({'App.swift': 'import Foundation', 'Localizable.xcstrings': ' ' * (3 * 1024 * 1024) + 'restart your device'})
        self.assertEqual(result['device-restart-instructions']['status'], 'WARN')
        result = evaluate({'Localizable.xcstrings': ' ' * (8 * 1024 * 1024 + 1)})
        self.assertEqual(result['device-restart-instructions']['status'], 'SKIP')

    def test_built_bundle_resources_do_not_hide_source_evidence(self):
        result = evaluate({'output/release/App.xcarchive/Products/App.app/en.lproj/Localizable.strings': b'\xff',
                           'App.swift': 'let browser = UIWebView()'})
        self.assertEqual(result['browser-engine']['status'], 'WARN')
        self.assertIn('App.swift', result['browser-engine']['file'])

    def test_pruned_dependency_does_not_create_source_gap(self):
        result = evaluate({'App.swift': 'import Foundation', 'Pods/Invalid.swift': b'\xff', 'node_modules/large.js': 'x' * (2 * 1024 * 1024 + 1)})
        self.assertEqual(result['browser-engine']['status'], 'PASS')

    def test_voip_callkit_is_not_a_blocking_extension(self):
        result = evaluate({'App.swift': 'import CallKit\nlet provider = CXProvider(configuration: config)'})
        self.assertEqual(result['call-filter-controls']['status'], 'PASS')

    def test_dependency_variable_is_not_browser_engine(self):
        result = evaluate({'App.swift': 'import Foundation', 'Package.swift': '// Chromium\nlet blink = false'})
        self.assertEqual(result['browser-engine']['status'], 'PASS')

    def test_help_string_is_not_deprecated_webview_usage(self):
        result = evaluate({'App.swift': 'Text("Migrate UIWebView projects with our guide")'})
        self.assertEqual(result['browser-engine']['status'], 'PASS')

    def test_dependency_and_comment_pruning(self):
        result = evaluate({'Pods/Bad.swift': 'let p = UIWebView()',
                           'App.swift': '// let p = UIWebView()\n/* import Matter */\nlet title = "Welcome"'})
        self.assertEqual(result['browser-engine']['status'], 'PASS')
        self.assertEqual(result['matter-extension']['status'], 'PASS')

    def test_deprecated_webview_needs_shipping_review(self):
        result = evaluate({'App.swift': 'let p = UIWebView()'})['browser-engine']
        self.assertEqual(result['status'], 'WARN')
        self.assertIn('shipping target', result['reason'])

    def test_modern_appintent_does_not_require_legacy_plist(self):
        result = evaluate({'Info.plist': plistlib.dumps({'CFBundleIdentifier':'org.app'}), 'App.swift': 'struct OpenJournal: AppIntent { func perform() {} }'})
        self.assertEqual(result['intent-handler-parity']['status'], 'PASS')

    def test_unresolved_extension_bundle_id_abstains(self):
        result = evaluate({'Info.plist': '<plist><dict><key>CFBundleIdentifier</key><string>$(PRODUCT_BUNDLE_IDENTIFIER)</string></dict></plist>',
                           'Widget/Info.plist': '<plist><dict><key>NSExtension</key><dict/></dict></plist>'})
        self.assertEqual(result['extension-bundle-parity']['status'], 'SKIP')

    def test_document_picker_missing_plist_is_compliant(self):
        result = evaluate({'App.swift': 'let picker = UIDocumentPickerViewController()'})
        self.assertEqual(result['document-browser-access']['status'], 'PASS')

    def test_release_notes_empty_and_description_duplicate(self):
        for text in ('', 'A journal.'):
            with self.subTest(text=text):
                result = evaluate({'fastlane/metadata/en-US/release_notes.txt': text,
                                   'fastlane/metadata/en-US/description.txt': 'A journal.'})
                self.assertEqual(result['release-notes-specificity']['status'], 'WARN')

    def test_contact_and_review_folders_are_not_store_locales(self):
        result = evaluate({'fastlane/metadata/review_information/name.txt': 'Apple recommends 😀',
                           'fastlane/metadata/default/name.txt': 'Apple recommends 😀',
                           'fastlane/metadata/en-US/name.txt': 'Daily Journal'})
        self.assertEqual(result['metadata-emoji']['status'], 'PASS')
        self.assertEqual(result['apple-endorsement-claims']['status'], 'PASS')

    def test_game_identifier_other_file_is_not_data_flow(self):
        result = evaluate({'App.swift': 'import GameKit\nlet id = GKLocalPlayer.local.gamePlayerID',
                           'Network.swift': 'let request = URLRequest(url: endpoint)'})
        self.assertEqual(result['game-center-id-sharing']['status'], 'PASS')



def case_test(case, kind):
    def test(self):
        result = evaluate(case[kind])[case['rule_id']]
        expected = 'WARN' if kind == 'positive' else 'PASS'
        if kind == 'skip':
            expected = 'SKIP'
        self.assertEqual(result['status'], expected, result)
        self.assertTrue(result['reason'])
    return test


for case in CASES:
    for kind in ('positive', 'clean', 'skip'):
        if case.get(kind) is not None:
            setattr(StaticRules, 'test_%s_%s' % (case['rule_id'].replace('-', '_'), kind),
                    case_test(case, kind))

if __name__ == '__main__':
    unittest.main(verbosity=2)
