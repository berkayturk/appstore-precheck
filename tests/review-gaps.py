"""Visible reader failures and unique run-section accounting."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCAN = ROOT / 'skills/appstore-precheck/scripts/scan.sh'
LIB = SCAN.parent / 'lib'


class ReviewGaps(unittest.TestCase):
    def test_m2_reader_errors_are_visible_for_every_check(self):
        script = r'''SCRIPT_DIR="$1"; ROOT="$2"; META_DIR="$2"; INFO_PLIST="$2/Info.plist"
GREP_PRUNE=()
set_rule() { :; }; set_evidence() { :; }; warn() { printf 'WARN: %s\n' "$1"; }; pass() { :; }
skip() { printf 'SKIP: %s\n' "$1"; }
python3() {
  case "$3" in
    *) if [[ "$MODE" == crash ]]; then echo 'reader crash sentinel' >&2; return 8; fi
       printf '{"_reader_error":"reader timeout after 60 seconds"}' ;;
  esac
}
command() {
  if [[ "$MODE" == missing && "$1" == -v && "$2" == python3 ]]; then return 1; fi
  builtin command "$@"
}
MODE="$3"
source "$SCRIPT_DIR/lib/scan-guidelines.sh"
printf '%s' "$COVERAGE_GAPS_JSON" | jq -e 'length == 16' >/dev/null
'''
        with tempfile.TemporaryDirectory() as folder:
            for mode, expected in [('crash', 'reader invocation failed'), ('timeout', 'reader timeout'), ('missing', 'Python 3 or jq unavailable')]:
                result = subprocess.run(['bash', '-c', script, 'bash', str(SCAN.parent), folder, mode], text=True, capture_output=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('16 check(s) did not run', result.stdout)
                self.assertIn(expected, result.stdout)
                if mode == 'crash':
                    self.assertIn('reader crash sentinel', result.stderr)

    def test_m2_empty_tree_reports_modular_gap_in_text_and_json(self):
        with tempfile.TemporaryDirectory() as folder:
            env = dict(os.environ, APPSTORE_PRECHECK_CONFIG='/nonexistent')
            cmd = ['bash', str(SCAN), '--dir', folder]
            text = subprocess.check_output(cmd, text=True, env=env)
            self.assertIn('SKIP: modular-checks-not-audited', text)
            self.assertIn('Source directory unavailable', text)
            report = json.loads(subprocess.check_output(cmd + ['--format', 'json'], env=env))
            self.assertGreaterEqual(report['summary']['not_audited'], 15)
            (Path(folder) / '.precheck-ignore').write_text('modular-checks-not-audited\n')
            text = subprocess.check_output(cmd, text=True, env=env)
            self.assertNotIn('SKIP: modular-checks-not-audited', text)

    def test_m5_duplicate_gaps_are_one_section_and_pass_is_not_a_risk_touch(self):
        script = 'SCRIPT_DIR="$1"; source "$1/lib/coverage-run.sh"; COVERAGE_GAPS_JSON="$2"; coverage_run_json'
        gaps = [{'rule_id': x, 'guideline': '4.5.6', 'status': 'SKIP', 'reason': 'missing'} for x in ('text', 'icon')]
        report = {'findings': [{'severity': 'PASS', 'guideline': '2.4.4'}], 'summary': {'not_audited': 0}}
        result = subprocess.check_output(['bash', '-c', script, 'test', str(SCAN.parent), json.dumps(gaps)], input=json.dumps(report), text=True)
        result = json.loads(result)
        self.assertEqual(result['coverage_sections']['skip'], 1)
        self.assertEqual(result['coverage_sections']['touched'], 0)

    def test_f8_only_checks_are_counted_and_reasons_are_grouped(self):
        rows = {slug: {'status': 'PASS', 'reason': 'No signal', 'file': ''} for slug in (
            'release-notes-specificity', 'device-restart-instructions', 'browser-engine',
            'intent-handler-parity', 'call-filter-controls', 'face-authentication',
            'document-browser-access', 'extension-bundle-parity', 'matter-extension',
            'extension-advertising', 'ar-integration-depth', 'companion-app-required',
            'game-center-id-sharing', 'metadata-emoji', 'miniapp-native-bridge', 'apple-endorsement-claims')}
        for slug, reason in [('browser-engine', 'reader timeout'), ('call-filter-controls', 'reader timeout'),
                             ('release-notes-specificity', 'metadata unavailable')]:
            rows[slug].update(status='SKIP', reason=reason)
        rows['_input_gaps'] = {'count': 1, 'paths': ['Broken.swift']}
        script = r'''SCRIPT_DIR="$1"; ROOT="$2"; META_DIR="$2"; INFO_PLIST="$2/Info.plist"
GREP_PRUNE=()
set_rule() { :; }; set_evidence() { :; }; warn() { :; }; pass() { :; }; skip() { printf 'SKIP: %s\n' "$1"; }
python3() { printf '%s' "$ROWS"; }
source "$SCRIPT_DIR/lib/scan-guidelines.sh"
'''
        result = subprocess.run(['bash', '-c', script, '_', str(SCAN.parent), '/tmp'],
                                env=dict(os.environ, ROWS=json.dumps(rows)), text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('3 check(s) did not run:', result.stdout)
        self.assertIn('browser-engine, call-filter-controls (reader timeout)', result.stdout)
        self.assertIn('release-notes-specificity (metadata unavailable)', result.stdout)
        self.assertIn('source-inputs-not-audited', result.stdout)
        self.assertIn('metadata-emoji-icon-not-audited', result.stdout)

    def test_f8_supplemental_gap_is_not_presented_as_an_unrun_check(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'App.swift').write_text('Text("Welcome")')
            (root / 'Info.plist').write_text('<plist><dict><key>CFBundleIdentifier</key><string>org.app</string></dict></plist>')
            (root / 'Widget').mkdir()
            (root / 'Widget/Info.plist').write_text('<plist><dict><key>CFBundleIdentifier</key><string>org.app.widget</string><key>NSExtension</key><dict/></dict></plist>')
            meta = root / 'fastlane/metadata/en-US'
            meta.mkdir(parents=True)
            (meta / 'release_notes.txt').write_text('Added a reading list.')
            text = subprocess.check_output(['bash', str(SCAN), '--dir', folder], text=True)
            summary = next(line for line in text.splitlines() if line.startswith('SKIP: modular-checks-not-audited'))
            self.assertNotIn('0 check(s) did not run: ;', summary)
            self.assertIn('additional coverage gaps:', summary)


if __name__ == '__main__':
    unittest.main()
