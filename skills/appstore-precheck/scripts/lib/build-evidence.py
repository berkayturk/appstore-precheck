"""Small local source-integrity report; no distribution attestation."""
import hashlib
import json
import os
import stat
from pathlib import Path


PRUNE = {'.git', 'node_modules', 'Pods', 'build', 'DerivedData', '.build', '.dart_tool',
         '__pycache__', '.gradle', '.kotlin', '.idea'}


def file_digest(path):
    fd = os.open(str(path), os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW)
    with os.fdopen(fd, 'rb') as stream:
        if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
            return None
        digest = hashlib.sha256()
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
        return digest.hexdigest()


def snapshot(root):
    result = {}
    for base, dirs, files in os.walk(root, followlinks=False):
        dirs[:] = sorted(d for d in dirs if d not in PRUNE)
        for name in sorted(files + [d for d in dirs if (Path(base) / d).is_symlink()]):
            path = Path(base) / name
            mode = path.lstat().st_mode
            if stat.S_ISLNK(mode):
                digest = hashlib.sha256(os.readlink(path).encode()).hexdigest()
            elif stat.S_ISREG(mode):
                digest = file_digest(path)
            else:
                continue
            if digest is not None:
                result[path.relative_to(root).as_posix()] = digest
    return result


def finish(repo, before, out, configuration, app):
    unchanged = before == snapshot(repo)
    report = {'source_unchanged': unchanged, 'configuration': configuration,
              'app': str(app) if app else None, 'distribution': 'simulator',
              'signed_distribution_verified': False, 'physical_device_verified': False,
              'source_snapshot_scope': 'Regular files and symlink text; special files excluded.',
              'source_snapshot_excluded_directories': sorted(PRUNE)}
    (out / 'build-provenance.json').write_text(json.dumps(report, indent=2) + '\n')
    return unchanged
