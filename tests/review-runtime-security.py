"""Review regressions for runtime credential and optional-operation boundaries."""
import importlib.util
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
S = ROOT / 'skills/appstore-precheck/scripts'


def load(name):
    spec = importlib.util.spec_from_file_location(name, S / 'lib' / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ReviewRuntimeSecurity(unittest.TestCase):
    def test_m6a_shared_scrubber_removes_credentials_and_authenticated_identity(self):
        scrub = load('dyn-scrub')
        tree = {'attributes': {'accessibilityText': 'Alice Example', 'value': 'demo-pass'},
                'children': [{'attributes': {'text': 'person@example.test'}},
                             {'attributes': {'text': 'Settings', 'type': 'Button', 'bounds': '[0,0][10,10]'}}]}
        with patch.dict(os.environ, {'PRECHECK_DEMO_PASSWORD': 'demo-pass'}):
            plain = json.dumps(scrub.scrub_tree(tree))
            authenticated = scrub.scrub_tree(tree, authenticated=True, allowed={'Settings'})
        self.assertNotIn('demo-pass', plain)
        self.assertNotIn('person@example.test', plain)
        self.assertNotIn('Alice Example', json.dumps(authenticated))
        self.assertEqual(authenticated['children'][1]['attributes']['text'], 'Settings')
        self.assertEqual(authenticated['children'][1]['attributes']['bounds'], '[0,0][10,10]')

    def test_m6_persisted_hierarchy_is_scrubbed_before_write(self):
        scrub = load('dyn-scrub')
        raw = json.dumps({'attributes': {'text': 'person@example.test'}, 'children': [
            {'attributes': {'text': 'never-save-password', 'accessibilityText': 'never-save-password'}}]}).encode()
        result = subprocess.CompletedProcess([], 0, stdout=raw)
        process = SimpleNamespace(run=lambda *a, **kw: result)
        safe_write = scrub.sibling('safe_write')
        with tempfile.TemporaryDirectory() as temporary:
            target = Path(temporary) / 'dark.json'
            with patch.dict(os.environ, {'PRECHECK_DEMO_PASSWORD': 'never-save-password'}), \
                    patch.object(scrub, 'sibling', side_effect=lambda name: process if name == 'dyn-process' else safe_write):
                self.assertEqual(scrub.capture('owned', target, 1), 2)
            saved = target.read_text()
            self.assertNotIn('person@example.test', saved)
            self.assertNotIn('never-save-password', saved)
            self.assertEqual(len(list(Path(temporary).iterdir())), 1)

    def test_m6_demo_secure_field_selector_survives_in_memory_scrubbing(self):
        demo = load('dyn-demo-login')
        tree = {'attributes': {'text': 'Login'}, 'children': [
            {'attributes': {'text': 'Email'}}, {'attributes': {'text': 'Sign In'}},
            {'attributes': {'accessibilityText': 'Password', 'type': 'XCUIElementTypeSecureTextField'}}]}
        result = subprocess.CompletedProcess([], 0, stdout=json.dumps(tree).encode())
        with patch.object(demo._process, 'run', return_value=result):
            labels = demo.hierarchy('owned', '/private/tmp', {})
        self.assertIn('Password', labels)
        self.assertIn('Email', labels)
        self.assertIn('Sign In', labels)

    def test_m6b_non_navigation_actions_are_denied(self):
        explore = load('dyn-explore')
        denied = 'report block allow accept agree confirm yes follow like share invite reset clear unsubscribe cancel deactivate transfer order donate restore continue'.split(',')
        denied = ['Report user', 'Block user', 'Continue', 'Sign in', 'Restore purchases'] + [w.title() for w in denied[0].split()]
        for label in denied:
            with self.subTest(label=label):
                self.assertFalse(explore.safe_to_tap(label, None))
        self.assertTrue(explore.safe_to_tap('Settings', None))
        runner = (S / 'runtime-review.sh').read_text()
        self.assertNotIn('"$HERE/dynamic-run.sh" --explore', runner)

    def test_m6c_maestro_artifacts_use_private_temporary_output(self):
        explore = load('dyn-explore')
        calls = []
        def command(argv, *args, **kwargs):
            calls.append(argv)
            self.assertIn('--debug-output', argv)
            self.assertIn('--test-output-dir', argv)
            for flag in ('--debug-output', '--test-output-dir'):
                path = Path(argv[argv.index(flag) + 1])
                self.assertIn(out.resolve(), path.resolve().parents)
            return ''
        with tempfile.TemporaryDirectory() as temporary:
            out = Path(temporary)
            with patch.object(explore, 'command', side_effect=command):
                explore.navigate('owned', 'com.example.app', ('Settings',), out, time.monotonic() + 30)
            self.assertEqual(list(out.iterdir()), [])
        self.assertEqual(len(calls), 1)

    def test_m6_authenticated_capture_withholds_images_and_free_text(self):
        explore = load('dyn-explore')
        tree = {'attributes': {'text': 'Private Profile'}, 'children': [
            {'attributes': {'text': 'Alice Example'}}, {'attributes': {'text': 'Settings'}},
            {'attributes': {'text': 'person@example.test'}}]}
        with tempfile.TemporaryDirectory() as temporary:
            with patch.object(explore, 'command', return_value=json.dumps(tree)) as command:
                screen, _ = explore.capture_screen('owned', Path(temporary), 'screen', time.monotonic() + 30,
                                                   authenticated=True, allowed={'Settings'})
            self.assertEqual(command.call_count, 1)
            self.assertIsNone(screen['screenshot'])
            saved = (Path(temporary) / 'screen.json').read_text()
            self.assertNotIn('Alice Example', saved)
            self.assertNotIn('person@example.test', saved)
            self.assertIn('Settings', saved)

    def test_m6_demo_login_occurs_after_geometry_and_requires_navigation_opt_in(self):
        runner = (S / 'dynamic-run.sh').read_text()
        self.assertLess(runner.index('geometry_pass dyn-dark-mode'), runner.index('run_demo_phase\n'))
        self.assertIn('--authorized-navigation)', runner)
        self.assertIn('DEMO && EXPLORE', runner)
        self.assertIn('authenticated exploration disabled', runner)

    def test_n9_mixed_quorum_documented_in_d1(self):
        reference = (S.parent / 'references/simulator-dynamic-review.md').read_text()
        d1 = next(line for line in reference.splitlines() if line.startswith('| D1 |'))
        self.assertIn('2 PASS + 1 SKIP', d1)
        self.assertIn('SKIP', d1)

    def test_n1_unused_device_sweep_removed(self):
        self.assertNotIn('dyn_sweep_owned()', (S / 'lib/dyn-device.sh').read_text())

    def test_n2_observation_deadline_and_diagnostics(self):
        with tempfile.TemporaryDirectory() as temporary:
            script = '''source "$1/lib/dyn-guidelines.sh"
DYN_EXT_DIR="$2"; OUT="$2"; HERE="$1"; UDID=owned; BID=app; INSTALLED=app; EXE=app; REPO=""; LAST_SIGNALS=alive,varied,clean,4
python3() { printf '%s\\n' "$*" > "$OUT/args"; echo 'driver deadline reached' >&2; return 124; }
dyn_extended_capture 1
'''
            subprocess.run(['bash', '-c', script, '_', str(S), temporary], check=True, stdout=subprocess.PIPE)
            self.assertIn('--timeout 240', (Path(temporary) / 'args').read_text())
            self.assertIn('driver deadline reached', (Path(temporary) / 'repeat-1.stderr.log').read_text())

    def test_f11_missing_jq_rejects_explicit_blocking(self):
        script = '''source "$1/lib/optin-scan.sh"
OPT_BUILD=0; OPT_APP=app; OPT_METADATA=0; OPT_OUT="$2"; OPT_NO_RUNTIME=0; OPT_DEMO=0; OPT_DYN_BLOCK=1; OPT_DRY=0; OPT_URLS=0; OPT_ASC=""; OPT_ASC_VERSION=""; OPT_ASC_INFO=""; ROOT="$2"; SCRIPT_DIR="$1"; FORMAT=text
python3() { return 0; }
command() { if [[ "$1" == -v && "$2" == jq ]]; then return 1; else builtin command "$@"; fi; }
set_rule() { :; }; skip() { echo "SKIP: $*"; }; fail() { echo "FAIL: $*"; }
optin_run
'''
        with tempfile.TemporaryDirectory() as temporary:
            result = subprocess.run(['bash', '-c', script, '_', str(S), temporary], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.assertEqual(result.returncode, 64)
        self.assertIn('--dynamic-blocking needs jq', result.stderr)
        self.assertNotIn('SKIP:', result.stdout)
        self.assertNotIn('OPT-IN:', result.stdout)

    def test_n4_nat64_addresses_are_not_public_fetch_targets(self):
        metadata = load('metadata-review')
        for address in ('64:ff9b::7f00:1', '64:ff9b::a00:1', '64:ff9b::808:808'):
            with self.subTest(address=address), patch.object(metadata.socket, 'getaddrinfo', return_value=[
                    (socket.AF_INET6, socket.SOCK_STREAM, 6, '', (address, 443, 0, 0))]):
                self.assertEqual(metadata.checked_addresses('example.test', 443), [])

    def test_n8_security_scope_documented(self):
        policy = (ROOT / 'SECURITY.md').read_text()
        for command in ('npm ci', 'pod install', 'expo prebuild', 'flutter pub get', 'gradle', '--check-urls', 'HEAD'):
            self.assertIn(command, policy)


if __name__ == '__main__':
    unittest.main()
