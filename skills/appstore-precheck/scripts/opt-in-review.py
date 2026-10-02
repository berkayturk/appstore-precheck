"""Coordinate explicitly requested tiers; default scan never invokes this runner."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
OWN_OUTPUTS = ('summary.json', 'run-results.json', 'artifact-review.json', 'metadata-review.json')


def module(name):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), HERE / 'lib' / (name + '.py'))
    value = importlib.util.module_from_spec(spec); spec.loader.exec_module(value)
    return value


PROCESS, SAFE, RECORDS = module('dyn-process'), module('safe_write'), module('optional-records')
merge_status = RECORDS.merge_status


def remove_stale_outputs(out):
    paths = [out / name for name in OWN_OUTPUTS]
    if not (out / 'runtime').is_symlink():
        paths.append(out / 'runtime/screen-inventory.json')
        if not (out / 'runtime/explore').is_symlink():
            paths.append(out / 'runtime/explore/screen-inventory.json')
    for path in paths:
        try:
            mode = path.lstat().st_mode
        except (FileNotFoundError, NotADirectoryError):
            continue
        if not stat.S_ISDIR(mode):
            path.unlink()


def run(command, timeout):
    try:
        return PROCESS.run(command, timeout, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    except (OSError, subprocess.TimeoutExpired):
        return None


def arguments():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--out-dir', type=Path)
    parser.add_argument('--app', type=Path)
    for name in ('build', 'metadata', 'no-runtime', 'demo-login', 'dynamic-blocking', 'dry-run', 'check-urls'):
        parser.add_argument('--' + name, action='store_true')
    for name in ('asc-version-id', 'asc-info-id', 'asc-app-id'):
        parser.add_argument('--' + name)
    args = parser.parse_args(); repo = args.repo.resolve()
    if not repo.is_dir() or (args.build and args.app):
        parser.error('existing --repo and at most one of --build/--app required')
    if (args.dynamic_blocking or args.demo_login) and not (args.build or args.app):
        parser.error('runtime flags require --app or --build')
    if args.no_runtime and (args.demo_login or args.dynamic_blocking):
        parser.error('--no-runtime conflicts with runtime flags')
    if (args.check_urls or args.asc_app_id or args.asc_info_id or args.asc_version_id) and not args.metadata:
        parser.error('metadata options require --metadata')
    if args.out_dir:
        out = args.out_dir.resolve()
        if out == repo or repo in out.parents:
            parser.error('--out-dir must be outside the user project')
        out.mkdir(parents=True, exist_ok=True)
    else:
        out = Path(tempfile.mkdtemp(prefix='precheck-review-'))
    args.repo, args.out_dir = repo, out
    return args


def json_tier(command, tier, args, checks, tiers, errors):
    result = run(command, 120)
    if result is None or result.returncode:
        tiers[tier] = 'SKIP: tool, input or deadline unavailable'; return
    try:
        payload = json.loads(result.stdout)
        path = args.out_dir / (tier + '-review.json')
        SAFE.write_text(path, json.dumps(payload, indent=2) + '\n')
        errors.extend(RECORDS.import_records(checks, payload.get('checks', payload.get('results', [])), str(path)))
        tiers[tier] = 'RAN'
    except (ValueError, TypeError, AttributeError):
        tiers[tier] = 'SKIP: unreadable tier results'


def build_tier(args, tiers):
    app = args.app.resolve() if args.app else None
    if args.build:
        command = ['bash', str(HERE / 'build-run.sh'), '--repo', str(args.repo), '--out', str(args.out_dir / 'artifact')]
        if args.dry_run:
            command.append('--dry-run')
        result = run(command, 2700)
        tiers['build'] = ('PLAN' if args.dry_run else 'RAN') if result and result.returncode == 0 else 'SKIP: build unavailable'
        if result and result.returncode == 0 and not args.dry_run:
            for line in result.stdout.splitlines():
                if line.startswith('app_path='):
                    app = Path(line.split('=', 1)[1])
    return app


def runtime_tier(args, app, checks, tiers):
    if not app or args.no_runtime or args.dry_run:
        return []
    command = ['bash', str(HERE / 'runtime-review.sh'), '--app', str(app), '--repo', str(args.repo), '--out', str(args.out_dir / 'runtime')]
    if args.demo_login:
        command.append('--demo-login')
    result = run(command, 1380)
    if not result or result.returncode:
        tiers['runtime'] = 'SKIP: simulator driver or deadline unavailable'; return []
    tiers['runtime'] = 'RAN'
    for line in result.stdout.splitlines():
        match = re.match(r'^DYNAMIC-(PASS|FINDING|SKIP): \S+ \[([^]]+)\] — (.*)$', line)
        if match:
            status, check_id, detail = match.groups()
            if status == 'FINDING' and not re.search(r'quorum 3/3(?:\D|$)', detail):
                status = 'SKIP'
            RECORDS.merge_result(checks, check_id.split(':')[0], status, detail, 'runtime/transcript.txt#' + check_id)
    # Only the structured allowlisted blocking validator can authorize escalation.
    validator = module('runtime-blocking')
    return validator.blocking(args.out_dir / 'runtime') if args.dynamic_blocking else []


def main():
    args = arguments(); remove_stale_outputs(args.out_dir)
    checks, errors = {}, []
    tiers = dict.fromkeys(('build', 'artifact', 'runtime', 'metadata'), 'NOT_RUN')
    app = build_tier(args, tiers)
    if app and not args.dry_run:
        json_tier(['bash', str(HERE / 'artifact-review.sh'), '--app', str(app), '--format', 'json'], 'artifact', args, checks, tiers, errors)
    blocking = runtime_tier(args, app, checks, tiers)
    if args.metadata:
        command = ['bash', str(HERE / 'metadata-review.sh'), '--repo', str(args.repo)]
        for name in ('asc_app_id', 'asc_info_id', 'asc_version_id'):
            if getattr(args, name):
                command += ['--' + name.replace('_', '-'), getattr(args, name)]
        if args.check_urls:
            command.append('--check-urls')
        json_tier(command, 'metadata', args, checks, tiers, errors)
    result_path = args.out_dir / 'run-results.json'
    SAFE.write_text(result_path, json.dumps({'checks': checks}, indent=2) + '\n')
    summary = {'schema_version': 1, 'tiers': tiers, 'blocking': blocking, 'input_errors': errors,
               'run_results': str(result_path), 'output_dir': str(args.out_dir)}
    SAFE.write_text(args.out_dir / 'summary.json', json.dumps(summary, indent=2) + '\n')
    print(json.dumps(summary)); return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except InterruptedError:
        raise SystemExit(143)
    except OSError as exc:
        print('opt-in-review: cannot write reports safely: ' + str(exc), file=sys.stderr)
        raise SystemExit(2)
