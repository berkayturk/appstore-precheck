#!/usr/bin/env python3
"""Hash a source tree without writing to it; retain only hashes and relative paths."""
import argparse
import hashlib
import json
import os
from pathlib import Path

# Git internals, downloaded dependencies and generated outputs are not source.
EXCLUDED = {'.git', 'node_modules', 'Pods', 'build', 'DerivedData', '.build', '__pycache__', '.dart_tool'}


def snapshot(root):
    root = Path(root).resolve()
    if not root.is_dir():
        raise ValueError('source directory unavailable')
    entries, errors = {}, []
    for base, dirs, files in os.walk(str(root), followlinks=False):
        dirs[:] = sorted(d for d in dirs if d not in EXCLUDED)
        for name in sorted(files + [d for d in dirs if (Path(base)/d).is_symlink()]):
            path = Path(base) / name
            key = path.relative_to(root).as_posix()
            try:
                if path.is_symlink():
                    digest = hashlib.sha256(os.readlink(str(path)).encode()).hexdigest()
                    entries[key] = {'kind': 'symlink', 'sha256': digest}
                    continue
                before = path.stat()
                h = hashlib.sha256()
                with path.open('rb') as f:
                    for block in iter(lambda: f.read(1024 * 1024), b''):
                        h.update(block)
                after = path.stat()
                if (before.st_mtime_ns, before.st_size, before.st_ino) != (after.st_mtime_ns, after.st_size, after.st_ino):
                    errors.append(key)
                entries[key] = {'kind': 'file', 'sha256': h.hexdigest(), 'mode': before.st_mode & 0o777}
            except OSError:
                errors.append(key)
    digest = hashlib.sha256(json.dumps(entries, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
    return {'schema_version': 1, 'sha256': digest, 'entries': entries,
            'stable_read': not errors, 'read_errors': errors, 'excluded_directories': sorted(EXCLUDED)}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--repo', type=Path, required=True)
    p.add_argument('--out', type=Path, required=True)
    p.add_argument('--compare', type=Path)
    a = p.parse_args()
    root, out = a.repo.resolve(), a.out.resolve()
    if out == root or root in out.parents:
        p.error('--out must be outside the source tree')
    result = snapshot(root)
    if a.compare:
        prior = json.loads(a.compare.read_text())
        result['unchanged'] = prior.get('stable_read') is True and result['stable_read'] and prior.get('sha256') == result['sha256']
        result['changed_paths'] = sorted(k for k in set(prior['entries']) | set(result['entries']) if prior['entries'].get(k) != result['entries'].get(k))
    out.write_text(json.dumps(result, indent=2) + '\n')
    return 0 if result['stable_read'] and result.get('unchanged', True) else 1


if __name__ == '__main__':
    raise SystemExit(main())
