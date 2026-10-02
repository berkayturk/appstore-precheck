"""Explicit build tier, operating exclusively in a disposable project copy."""
import argparse
import importlib.util
import json
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time


def module(name):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), Path(__file__).with_name(name + '.py'))
    value = importlib.util.module_from_spec(spec); spec.loader.exec_module(value)
    return value


PLAN, EXEC, EVIDENCE = module('build-plan'), module('build-exec'), module('build-evidence')


def arguments():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=Path('.'))
    parser.add_argument('--out', type=Path)
    parser.add_argument('--framework', choices=['native', 'rn', 'flutter', 'kmp'])
    parser.add_argument('--platform', default='ios')
    parser.add_argument('--timeout', type=int, default=1200)
    parser.add_argument('--deadline', type=int, default=2400)
    parser.add_argument('--dry-run', action='store_true')
    return parser.parse_args()


def scheme_list(output):
    schemes = set()
    decoder = json.JSONDecoder()
    for index, char in enumerate(output):
        if char != '{':
            continue
        try:
            data, _ = decoder.raw_decode(output[index:])
        except ValueError:
            continue
        if isinstance(data, dict):
            for value in data.values():
                if isinstance(value, dict) and isinstance(value.get('schemes'), list):
                    schemes.update(s for s in value['schemes'] if isinstance(s, str))
    return sorted(schemes)


def prepare_framework(args, copy, step):
    if args.framework != 'rn':
        return
    choices = [('pnpm-lock.yaml', ['pnpm', 'i', '--frozen-lockfile']), ('yarn.lock', ['yarn', '--frozen-lockfile']),
               ('package-lock.json', ['npm', 'ci']), ('npm-shrinkwrap.json', ['npm', 'ci'])]
    command = next((command for file, command in choices if (copy / file).is_file()), None)
    if command is None:
        raise ValueError('React Native requires a reproducible package-manager lockfile')
    if step(command)[0]:
        raise ValueError('dependency installation failed; inspect build.log')
    data = json.loads((copy / 'package.json').read_text()) if (copy / 'package.json').is_file() else {}
    expo = 'expo' in dict(data.get('dependencies', {}), **data.get('devDependencies', {}))
    if expo and step(['npx', 'expo', 'prebuild', '--platform', 'ios', '--no-install'])[0]:
        raise ValueError('Expo prebuild failed; inspect build.log')
    if (copy / 'ios/Podfile').is_file() and step(['pod', 'install', '--project-directory=ios'])[0]:
        raise ValueError('pod installation failed; inspect build.log')


def run_steps(args, copy, work, out, project):
    end = time.monotonic() + args.deadline
    def step(command):
        remaining = min(args.timeout, end - time.monotonic())
        if remaining <= 0:
            raise ValueError('build deadline exceeded')
        return EXEC.execute(command, copy, work / 'home', out / 'build.log', remaining)
    prepare_framework(args, copy, step)
    found = PLAN.projects(copy)
    if args.framework == 'rn' and len(found) != 1:
        raise ValueError('generated project selection is ambiguous: ' + ', '.join(found))
    project = found[0] if found else project
    flags = [] if project == 'Package.swift' else ['-workspace' if project.endswith('.xcworkspace') else '-project', project]
    if args.framework == 'flutter':
        for command in (['flutter', 'pub', 'get'], ['flutter', 'build', 'ios', '--simulator']):
            if step(command)[0]:
                raise ValueError('Flutter command failed; inspect build.log')
        return 'debug', list((copy / 'build/ios/iphonesimulator').glob('*.app'))
    code, output = step(['xcodebuild', '-list', '-json'] + flags)
    if code:
        raise ValueError('scheme discovery failed; inspect build.log')
    schemes = scheme_list(output)
    if len(schemes) != 1:
        raise ValueError('select one shared scheme; candidates: ' + ', '.join(schemes))
    for config in ('Release', 'Debug'):
        if config == 'Debug' and args.framework == 'kmp' and (copy / 'gradlew').is_file():
            if step(['./gradlew', '--project-cache-dir', str(work / 'gradle-cache'), ':shared:linkDebugFrameworkIosSimulatorArm64'])[0]:
                raise ValueError('KMP framework preparation failed; inspect build.log')
        command = ['xcodebuild'] + flags + ['-scheme', schemes[0], '-sdk', 'iphonesimulator', '-configuration', config,
                  '-derivedDataPath', str(work / 'dd'), 'CODE_SIGNING_ALLOWED=NO', 'build']
        if step(command)[0] == 0:
            return config.lower(), list((work / 'dd/Build/Products' / (config + '-iphonesimulator')).glob('*.app'))
    raise ValueError('Release and Debug build failed; inspect build.log')


def build(args, repo, project, out):
    before = EVIDENCE.snapshot(repo)
    config, exported = 'unknown', None
    try:
        with tempfile.TemporaryDirectory(prefix='precheck-build-') as temporary:
            work = Path(temporary); copy = work / 'project'
            PLAN.copy_inputs(repo, copy)
            config, apps = run_steps(args, copy, work, out, project)
            if len(apps) != 1 or not (apps[0] / 'Info.plist').is_file():
                raise ValueError('build must produce exactly one simulator .app')
            exported = out / (config.title() + '-iphonesimulator') / apps[0].name
            exported.parent.mkdir(parents=True, exist_ok=True)
            shutil.copytree(apps[0], exported)
            print('app_path=' + str(exported))
            print('build_config=' + config)
    finally:
        if not EVIDENCE.finish(repo, before, out, config, exported):
            raise ValueError('source changed during build; evidence is not bound')


def interrupted(signum, frame):
    raise KeyboardInterrupt()


def project_candidates(repo, framework):
    projects = PLAN.projects(repo)
    if framework == 'flutter' or len(projects) == 1:
        return projects
    if framework == 'rn' and not projects and (repo / 'package.json').is_file():
        data = json.loads((repo / 'package.json').read_text())
        if 'expo' in dict(data.get('dependencies', {}), **data.get('devDependencies', {})):
            return []
    raise ValueError('select one Xcode project/workspace; candidates: ' + ', '.join(projects))


def main():
    args = arguments(); repo = args.repo.resolve()
    home = Path.home().resolve()
    if repo in (Path('/'), home) or repo in home.parents or args.timeout < 1 or args.deadline < 1:
        print('build-run: unsafe repository or invalid timeout', file=sys.stderr); return 64
    if not repo.is_dir():
        print('build-run: repository missing', file=sys.stderr); return 66
    if args.framework is None:
        args.framework = subprocess.check_output(['bash', str(Path(__file__).resolve().parents[1] / 'framework-detect.sh'), '--root', str(repo)], text=True).strip() or 'native'
    try:
        if args.platform != 'ios':
            raise ValueError('platform not audited: ' + args.platform)
        projects = project_candidates(repo, args.framework)
        PLAN.checked_links(repo)
        if args.dry_run:
            print('PLAN: isolated copy; Release then Debug; CODE_SIGNING_ALLOWED=NO; project=' + ', '.join(projects)); return 0
        tool = 'flutter' if args.framework == 'flutter' else 'xcodebuild'
        if not shutil.which(tool) or not shutil.which('rsync'):
            raise ValueError(tool + '/rsync unavailable; install tools or provide an existing .app')
        out = args.out.resolve() if args.out else Path(tempfile.mkdtemp(prefix='precheck-artifact-'))
        if out == repo or repo in out.parents:
            raise ValueError('--out must be outside the source project')
        if repo == Path(tempfile.gettempdir()).resolve() or repo in Path(tempfile.gettempdir()).resolve().parents:
            raise ValueError('temporary directory must be outside source project')
        out.mkdir(parents=True, exist_ok=True)
        print('artifact_dir=' + str(out))
        for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
            signal.signal(sig, interrupted)
        build(args, repo, projects[0] if projects else '', out)
        return 0
    except KeyboardInterrupt:
        print('SKIP: build interrupted'); return 130
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        print('SKIP: build-run — ' + str(exc)); return 3


if __name__ == '__main__':
    raise SystemExit(main())
