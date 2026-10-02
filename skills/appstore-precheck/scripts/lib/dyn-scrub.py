#!/usr/bin/env python3
"""Redact runtime hierarchies before any persistent write; raw trees stay in memory."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess

EMAIL = re.compile(r'[A-Za-z0-9.!#$%&\x27*+/=?^_`{|}~-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+')
STRUCTURAL = {'bounds', 'type', 'class', 'packageName', 'bundleId'}


def sibling(name):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def scrub_text(value):
    for key in ('USERNAME', 'PASSWORD'):
        secret = os.getenv('PRECHECK_DEMO_' + key, '')
        if secret:
            value = value.replace(secret, '[redacted]')
    return EMAIL.sub('[redacted email]', value)


def scrub_tree(value, authenticated=False, allowed=None, key=''):
    allowed = allowed or set()
    if isinstance(value, str):
        clean = scrub_text(value)
        if authenticated and key not in STRUCTURAL and clean not in allowed:
            return '[redacted]'
        return clean
    if isinstance(value, list):
        return [scrub_tree(x, authenticated, allowed, key) for x in value]
    if isinstance(value, dict):
        secure = any('securetextfield' in str(value.get(k, '')).lower() for k in ('type', 'class'))
        return {scrub_text(k): ('[redacted]' if secure and k in ('text', 'value', 'accessibilityText', 'label')
                               else scrub_tree(v, authenticated, allowed, k)) for k, v in value.items()}
    return value


def count_nodes(value):
    if isinstance(value, list):
        return sum(count_nodes(x) for x in value)
    if isinstance(value, dict):
        return int('attributes' in value) + sum(count_nodes(x) for x in value.get('children', []))
    return 0


def capture(udid, out, timeout):
    result = sibling('dyn-process').run(['maestro', '--device', udid, 'hierarchy'],
                                      timeout=timeout, grace=1, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    if result.returncode:
        raise ValueError('Hierarchy driver failed')
    tree = scrub_tree(json.loads(result.stdout.decode('utf-8')))
    sibling('safe_write').write_text(out, json.dumps(tree, ensure_ascii=True))
    return count_nodes(tree)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--udid', required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--timeout', type=float, default=45)
    args = parser.parse_args()
    try:
        print(capture(args.udid, args.out, args.timeout))
    except (OSError, ValueError, subprocess.SubprocessError):
        print('unread')
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
