import importlib.util
from pathlib import Path
import tempfile
import unittest

S = Path(__file__).resolve().parents[1] / 'skills/appstore-precheck/scripts/lib/artifact-review.py'


class ArtifactReview(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location('artifact', S)
        self.module = importlib.util.module_from_spec(spec); spec.loader.exec_module(self.module)

    def test_framework_dlopen_is_not_a_loading_finding(self):
        with tempfile.TemporaryDirectory() as temporary:
            binary = Path(temporary) / 'binary'; binary.write_bytes(b'dlopen HTTP')
            self.assertEqual(self.module.review_loading(binary)['status'], 'PASS')
            binary.write_bytes(b'download executable')
            self.assertEqual(self.module.review_loading(binary)['status'], 'NEEDS_REVIEW')
        self.assertEqual(self.module.review_loading(None)['status'], 'SKIP')

    def test_entitlements_ats_sdk_and_scheme_signals(self):
        module = self.module
        self.assertEqual(module.review_entitlements({}, {'com.apple.developer.healthkit': True}, '', None)['status'], 'NEEDS_REVIEW')
        self.assertEqual(module.review_entitlements({}, {}, '', None)['status'], 'PASS')
        self.assertEqual(module.review_entitlements({}, None, 'unavailable', None)['status'], 'SKIP')
        self.assertEqual(module.review_ats({'NSAppTransportSecurity': {'NSAllowsArbitraryLoads': True}})['status'], 'NEEDS_REVIEW')
        self.assertEqual(module.review_ats({})['status'], 'PASS')
        self.assertEqual(module.review_sdk({'MinimumOSVersion': '27.0', 'DTSDKName': 'iphoneos26.0'})['status'], 'FINDING')
        self.assertEqual(module.review_schemes({'LSApplicationQueriesSchemes': ['https']})['status'], 'PASS')
        self.assertEqual(module.review_schemes({'LSApplicationQueriesSchemes': ['cydia']})['status'], 'NEEDS_REVIEW')

    def test_missing_artifact_and_tool_abstain(self):
        with tempfile.TemporaryDirectory() as temporary:
            app, _, _ = self.module.select_app(None, Path(temporary))
            self.assertIsNone(app)
            binary = Path(temporary) / 'app'; binary.write_bytes(b'binary')
            self.module.tool = lambda *args: None
            self.assertEqual(self.module.review_private(Path(temporary), binary)['status'], 'SKIP')


if __name__ == '__main__':
    unittest.main()
