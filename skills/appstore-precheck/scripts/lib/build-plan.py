"""Resolve an unambiguous build input and copy without live source symlinks."""
import fnmatch
import os
from pathlib import Path
import shutil
import subprocess

EXCLUDED = {'.git', 'node_modules', 'Pods', 'build', 'DerivedData', '.build', '.dart_tool',
            '__pycache__', '.gradle', '.kotlin', '.idea'}
SECRETS = ('.env*', '.npmrc', '.netrc', '*.pem', '*.key', '*.jks', '*.keystore',
           'key.properties', '.sentryclirc', '*Secrets*.xcconfig', '*asc-key*.json',
           '*.p8', '*.p12', '*.mobileprovision', '.appstore-precheck.json',
           'id_rsa*', 'id_ed25519*', '.git-credentials', '*.keychain-db',
           'credentials*.json', 'service-account*.json')


def excluded(path):
    return (path.name in EXCLUDED or any(fnmatch.fnmatch(path.name, pattern) for pattern in SECRETS)
            or ('review_information' in path.parts and
                (path.name.startswith('demo_') or 'password' in path.name.lower())))


def projects(repo):
    found = []
    for base, dirs, files in os.walk(repo):
        dirs[:] = sorted(d for d in dirs if not excluded(Path(base) / d))
        for name in list(dirs):
            if name.endswith(('.xcworkspace', '.xcodeproj')):
                found.append(str((Path(base) / name).relative_to(repo))); dirs.remove(name)
    # An ordinary CocoaPods workspace and its sibling project are one build choice.
    workspaces = [p for p in found if p.endswith('.xcworkspace')]
    if len(workspaces) == 1:
        sibling = workspaces[0][:-len('.xcworkspace')] + '.xcodeproj'
        found = [p for p in found if p != sibling]
    return sorted(found) or (['Package.swift'] if (repo / 'Package.swift').is_file() else [])


def flutter_target_allowed(target, repo):
    caches = [Path.home() / '.pub-cache']
    if os.environ.get('PUB_CACHE'):
        caches.append(Path(os.environ['PUB_CACHE']).expanduser())
    for cache in caches:
        cache = cache.resolve()
        if cache in (Path('/'), Path.home().resolve(), repo) or repo in cache.parents or cache in repo.parents:
            continue
        if cache in target.parents:
            parts = target.relative_to(cache).parts
            if len(parts) >= 2 and parts[0] in ('hosted', 'git'):
                return True
    sdk_roots = []
    if os.environ.get('FLUTTER_ROOT'):
        sdk_roots.append(Path(os.environ['FLUTTER_ROOT']).expanduser())
    executable = shutil.which('flutter')
    if executable:
        sdk_roots.append(Path(executable).resolve().parent.parent)
    for sdk in sdk_roots:
        sdk = sdk.resolve()
        if sdk in (Path('/'), Path.home().resolve(), repo) or repo in sdk.parents or sdk in repo.parents:
            continue
        if sdk in target.parents and (sdk / 'bin/flutter').is_file() and (sdk / 'packages/flutter/pubspec.yaml').is_file():
            return True
    return False


def allowed_link(path, repo):
    rel = path.relative_to(repo)
    if any(rel.parts[i:i + 2] == ('ios', '.symlinks') for i in range(len(rel.parts) - 2)):
        return flutter_target_allowed(path.resolve(), repo.resolve())
    if '.xcframework/' in rel.as_posix() and rel.as_posix().endswith('/Versions/Current'):
        return path.resolve().parent == path.parent.resolve()
    return False


def checked_links(repo):
    links = []
    for base, dirs, files in os.walk(repo, followlinks=False):
        dirs[:] = [d for d in dirs if not excluded(Path(base) / d)]
        for name in dirs + files:
            path = Path(base) / name
            if excluded(path) or not path.is_symlink():
                continue
            if not allowed_link(path, repo) or not path.exists():
                raise ValueError('unsupported or broken source symlink: ' + str(path.relative_to(repo)))
            target = path.resolve()
            if target.is_dir() and any(p.is_symlink() for p in target.rglob('*')):
                raise ValueError('nested symlinks in materialized input: ' + str(path.relative_to(repo)))
            links.append(path)
    return links


def copy_inputs(repo, destination):
    links = checked_links(repo)
    command = ['rsync', '-a']
    for pattern in sorted(EXCLUDED) + list(SECRETS):
        command += ['--exclude=' + pattern]
    command += ['--exclude=review_information/demo_*', '--exclude=review_information/*[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]*']
    command += ['--exclude=/' + p.relative_to(repo).as_posix() for p in links]
    destination.mkdir(parents=True, exist_ok=True)
    subprocess.run(command + ['--', str(repo) + '/', str(destination) + '/'], check=True, capture_output=True)
    for path in links:
        target = destination / path.relative_to(repo)
        target.parent.mkdir(parents=True, exist_ok=True)
        if path.is_dir():
            shutil.copytree(path.resolve(), target, ignore=lambda base, names: [n for n in names if excluded(Path(base) / n)])
        else:
            shutil.copy2(path.resolve(), target)
