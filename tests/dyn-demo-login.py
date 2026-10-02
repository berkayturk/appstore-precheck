import importlib.util
import os
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

S = Path(__file__).resolve().parents[1] / 'skills/appstore-precheck/scripts/lib/dyn-demo-login.py'


class Demo(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location('demo', S)
        self.module = importlib.util.module_from_spec(spec); spec.loader.exec_module(self.module)
        self.env = {'PRECHECK_DEMO_USERNAME': 'test-user', 'PRECHECK_DEMO_PASSWORD': 'test-secret',
                    'PRECHECK_DEMO_SUCCESS_TEXT': 'Welcome', 'PRECHECK_DEMO_FAILURE_TEXT': 'Rejected',
                    'PRECHECK_DEMO_AUTHORIZED_TEST': '1', 'PRECHECK_DEMO_ENVIRONMENT': 'test'}

    def attempt(self, outcome):
        values = iter([{'Email', 'Password', 'Sign In', 'Login'}, {outcome, 'Menu', 'Help', 'Settings'}])
        with patch.dict(os.environ, self.env, clear=True), patch.object(self.module, 'hierarchy', side_effect=lambda *a: next(values)), patch.object(self.module._process, 'run', return_value=subprocess.CompletedProcess([], 0)):
            return self.module.attempt('owned', 'com.example.app')

    def test_success_failure_and_ambiguous_result(self):
        self.assertTrue(self.attempt('Welcome').startswith('PASS\t'))
        result = self.attempt('Rejected')
        self.assertTrue(result.startswith('FINDING\t'))
        self.assertNotIn('test-secret', result); self.assertNotIn('test-user', result)
        self.assertTrue(self.attempt('Unrelated').startswith('SKIP\t'))

    def test_missing_credentials_unsafe_values_and_timeout_skip(self):
        with patch.dict(os.environ, {}, clear=True):
            self.assertTrue(self.module.attempt('owned', 'app').startswith('SKIP\t'))
        with patch.dict(os.environ, self.env, clear=True):
            self.assertTrue(self.module.attempt('owned', '${bad}').startswith('SKIP\t'))
            with patch.object(self.module, 'hierarchy', side_effect=subprocess.TimeoutExpired('maestro', 1)):
                self.assertTrue(self.module.attempt('owned', 'app').startswith('SKIP\t'))


if __name__ == '__main__':
    unittest.main()
