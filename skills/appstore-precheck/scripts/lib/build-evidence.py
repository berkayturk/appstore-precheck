#!/usr/bin/env python3
"""Finalize local build provenance. Source changes invalidate binding, not the app."""
import argparse
import hashlib
import importlib.util
import json
import os
import plistlib
import sys
from pathlib import Path

sys.dont_write_bytecode = True

SPEC = importlib.util.spec_from_file_location('source_snapshot', str(Path(__file__).resolve().parents[1] / 'source-snapshot.py'))
SNAPSHOT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SNAPSHOT)


def artifact_manifest(root):
    entries, stable = {}, True
    for path in sorted(root.rglob('*')):
        key = path.relative_to(root).as_posix()
        if path.is_symlink():
            entries[key] = {'kind': 'symlink', 'sha256': hashlib.sha256(os.readlink(str(path)).encode()).hexdigest()}
        elif path.is_file():
            try:
                before = path.stat()
                digest = hashlib.sha256()
                with path.open('rb') as stream:
                    for block in iter(lambda: stream.read(1024 * 1024), b''):
                        digest.update(block)
                after = path.stat()
                stable = stable and (before.st_mtime_ns, before.st_size, before.st_ino) == (after.st_mtime_ns, after.st_size, after.st_ino)
                entries[key] = {'kind': 'file', 'sha256': digest.hexdigest()}
            except OSError:
                stable = False
    return entries, stable


def finish(repo, copy, evidence, status, app, configuration):
    comparisons = {}
    for label, root in (('source', repo), ('copy', copy)):
        before_path = evidence / (label + '-before.json')
        if not before_path.exists():
            comparisons[label] = {'unchanged': False, 'reason': 'initial snapshot missing'}
            continue
        before = json.loads(before_path.read_text())
        try:
            after = SNAPSHOT.snapshot(root)
        except (OSError, ValueError):
            comparisons[label] = {'unchanged': False, 'reason': 'final snapshot unavailable'}
            continue
        (evidence / (label + '-after.json')).write_text(json.dumps(after, indent=2) + '\n')
        changed = sorted(key for key in set(before['entries']) | set(after['entries'])
                         if before['entries'].get(key) != after['entries'].get(key))
        comparisons[label] = {'unchanged': before['stable_read'] and after['stable_read'] and not changed,
                              'before_sha256': before['sha256'], 'after_sha256': after['sha256'],
                              'changed_paths': changed}
    initial_path = evidence / 'copy-initial.json'
    prepared_path = evidence / 'copy-before.json'
    preparation = {'changed_paths': [], 'original_and_prepared_hashes_are_distinct_identities': True}
    if initial_path.exists() and prepared_path.exists():
        initial, prepared = json.loads(initial_path.read_text()), json.loads(prepared_path.read_text())
        preparation['initial_sha256'] = initial['sha256']
        preparation['prepared_sha256'] = prepared['sha256']
        preparation['changed_paths'] = sorted(key for key in set(initial['entries']) | set(prepared['entries'])
                                              if initial['entries'].get(key) != prepared['entries'].get(key))
    eligible = status == 0 and all(value['unchanged'] for value in comparisons.values())
    report = {'schema_version': 1, 'build_exit_status': status, 'source_integrity': comparisons,
              'source_binding_eligible': eligible, 'configuration': configuration,
              'distribution': 'simulator', 'preparation': preparation, 'signed_distribution_verified': False,
              'physical_device_verified': False, 'artifact': None,
              'limitations': ['Source integrity is a before/after comparison, not an OS write sandbox.',
                              'Source identity for compilation is the prepared copy hash; preparation changes are retained separately.']}
    if app and Path(app).is_dir():
        app_path = Path(app)
        entries, stable = artifact_manifest(app_path)
        artifact_hash = hashlib.sha256(json.dumps(entries, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
        if not stable:
            report['source_binding_eligible'] = False
        try:
            info = plistlib.loads((app_path / 'Info.plist').read_bytes())
        except (OSError, ValueError):
            info = {}
        if not isinstance(info, dict):
            info = {}
        binary = info.get('CFBundleExecutable')
        report['artifact'] = {'path': str(app_path.resolve()), 'sha256': artifact_hash,
                              'hash_algorithm': 'sha256-canonical-relative-typed-file-digests-v1',
                              'stable_read': stable,
                              'bundle_id': info.get('CFBundleIdentifier'),
                              'version': info.get('CFBundleShortVersionString'), 'build': info.get('CFBundleVersion'),
                              'binary_sha256': (entries.get(binary) or {}).get('sha256')}
    if not comparisons['source']['unchanged']:
        report['limitations'].append('External source change: do not merge this evidence into the original source identity.')
    if not comparisons['copy']['unchanged']:
        report['limitations'].append('Build input copy changed: original snapshot cannot prove the exported build source.')
    (evidence / 'build-provenance.json').write_text(json.dumps(report, indent=2) + '\n')
    return 0 if report['source_binding_eligible'] else 3


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--copy', type=Path, required=True)
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--status', type=int, required=True)
    parser.add_argument('--app', default='')
    parser.add_argument('--configuration', default='unknown')
    args = parser.parse_args()
    return finish(args.repo, args.copy, args.evidence, args.status, args.app, args.configuration)


if __name__ == '__main__':
    raise SystemExit(main())
