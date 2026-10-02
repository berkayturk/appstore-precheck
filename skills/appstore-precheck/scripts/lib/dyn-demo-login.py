#!/usr/bin/env python3
"""Run one opt-in demo login attempt without writing credentials to reports."""
import importlib.util
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile


_spec = importlib.util.spec_from_file_location("dyn_process", pathlib.Path(__file__).with_name("dyn-process.py"))
_process = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_process)
_scrub_spec = importlib.util.spec_from_file_location('dyn_scrub', pathlib.Path(__file__).with_name('dyn-scrub.py'))
_scrub = importlib.util.module_from_spec(_scrub_spec)
_scrub_spec.loader.exec_module(_scrub)



MAESTRO_EXPR = "${"


def hierarchy(udid, dirname, env):
    result = _process.run(["maestro", "--device", udid, "hierarchy"],
                          stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                          timeout=45, cwd=dirname, env=env)
    if result.returncode:
        raise ValueError("Hierarchy unavailable")
    tree = json.loads(result.stdout.decode("utf-8", "replace"))
    # Selectors stay in memory; redact values without erasing secure-field labels.
    values = set()
    def visit(obj):
        if isinstance(obj, dict):
            attrs = obj.get("attributes", {})
            if isinstance(attrs, dict):
                values.update(_scrub.scrub_text(v.strip()) for k, v in attrs.items()
                              if k in ("text", "accessibilityText") and isinstance(v, str))
            for child in obj.get("children", []):
                visit(child)
        elif isinstance(obj, list):
            for child in obj:
                visit(child)
    visit(tree)
    return values


def settings(bundle):
    keys = {'user': ('USERNAME', ''), 'password': ('PASSWORD', ''), 'success': ('SUCCESS_TEXT', ''),
            'failure': ('FAILURE_TEXT', ''), 'user_field': ('USER_FIELD', 'Email'),
            'password_field': ('PASSWORD_FIELD', 'Password'), 'submit': ('SUBMIT', 'Sign In')}
    values = {key: os.getenv('PRECHECK_DEMO_' + name, default) for key, (name, default) in keys.items()}
    if not all(values.values()):
        raise ValueError('demo credentials or selectors unavailable')
    if os.getenv('PRECHECK_DEMO_AUTHORIZED_TEST') != '1' or os.getenv('PRECHECK_DEMO_ENVIRONMENT') not in ('test', 'sandbox'):
        raise ValueError('demo login requires an authorized test/sandbox environment')
    if any(MAESTRO_EXPR in value for value in list(values.values()) + [bundle]):
        raise ValueError('demo values contain a Maestro expression; login not attempted')
    return values


def flow(bundle, values):
    return ('appId: ' + json.dumps(bundle) + '\n---\n' +
            '- tapOn: ' + json.dumps('^' + re.escape(values['user_field']) + '$') + '\n' +
            '- inputText: ' + json.dumps(values['user']) + '\n' +
            '- tapOn: ' + json.dumps('^' + re.escape(values['password_field']) + '$') + '\n' +
            '- inputText: ' + json.dumps(values['password']) + '\n' +
            '- tapOn: ' + json.dumps('^' + re.escape(values['submit']) + '$') + '\n')


def drive(udid, bundle, values, dirname):
    path = pathlib.Path(dirname) / 'login.yaml'; path.write_text(flow(bundle, values)); path.chmod(0o600)
    env = dict(os.environ, MAESTRO_CLI_NO_ANALYTICS='1')
    before = hierarchy(udid, dirname, env)
    controls = {values['user_field'], values['password_field'], values['submit']}
    if len(before) < 4 or not controls.issubset(before) or values['success'] in before or values['success'] == values['failure']:
        return 'SKIP\tlogin start state/selectors are ambiguous or unavailable'
    command = ['maestro', '--device', udid, 'test', '--debug-output', str(path.parent / 'debug'),
               '--test-output-dir', str(path.parent / 'output'), str(path)]
    result = _process.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=45, cwd=dirname, env=env)
    if result.returncode:
        return 'SKIP\tMaestro could not drive login; selectors or driver unavailable'
    after = hierarchy(udid, dirname, env)
    if len(after) < 4 or (values['success'] in after and values['failure'] in after):
        return 'SKIP\tlogin postcondition ambiguous or accessibility evidence insufficient'
    if values['success'] in after:
        return 'PASS\tdemo start/action/new success selector observed; backend scope requires review'
    if values['failure'] in after:
        return 'FINDING\texplicit login rejection observed after the submitted demo attempt'
    return 'SKIP\tneither success nor failure selector observed'


def attempt(udid, bundle):
    try:
        values = settings(bundle)
        with tempfile.TemporaryDirectory(prefix='precheck-demo-') as temporary:
            os.chmod(temporary, 0o700)
            return drive(udid, bundle, values, temporary)
    except (OSError, subprocess.SubprocessError, ValueError):
        return 'SKIP\tdemo prerequisites, driver or hierarchy unavailable; no conclusion'


def main():
    if len(sys.argv) != 3:
        return 'SKIP\tinternal demo driver arguments missing'
    return attempt(*sys.argv[1:])


if __name__ == '__main__':
    print(main())
