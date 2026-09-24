#!/usr/bin/env python3
"""Evaluate pinned Jev against versioned cases; --dry-run needs no credentials."""
import argparse
import datetime
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'skills/appstore-precheck/scripts'))
sys.path.insert(0, str(ROOT / 'eval/lib'))
from catalog import CATALOG, resolve, procedure_path
from build_request import extract_procedure, fixture_files
from validate_case import check_case
from semantic.engine import atomic_json, digest, request_for, run_job, validate_bundle, THRESHOLDS
from semantic.questions import MODEL, VERSION
from semantic.collect import redact
from semantic.client import ServiceError, validate_response


def job_for(case, dataset):
    check = resolve(case)
    visual_assets = any(p.suffix.lower() in ('.png', '.jpg', '.jpeg', '.mp4', '.mov')
                        for p in (dataset / case['fixture']).rglob('*'))
    evidence = [{'id': 'e%d' % i, 'path': path, 'line': 1, 'text': redact(text)}
                for i, (path, text) in enumerate(fixture_files(dataset / case['fixture'])) if text.strip()]
    for kind, text in sorted(case.get('fetched_urls', {}).items()):
        if text.strip():
            evidence.append({'id': 'e%d' % len(evidence), 'path': 'prefetched/' + kind, 'line': 1, 'text': redact(text)})
    return {'id': case['id'], 'workflow': 'review', 'check_key': check['key'],
            'context': {'check_definition': {**check, 'procedure': extract_procedure(procedure_path(case).read_text(), check['number'])},
                        'scope': 'entire synthetic fixture, not a real shipping app'},
            'coverage': {'complete': not (check['requires_vision'] and visual_assets),
                         'missing': ['visual evidence cannot be inspected by Jev']
                         if check['requires_vision'] and visual_assets else []},
            'evidence': evidence}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model', default=MODEL)
    parser.add_argument('--repeat', type=int, default=3)
    parser.add_argument('--cases', default='*')
    parser.add_argument('--out', type=Path)
    parser.add_argument('--dataset', type=Path, default=ROOT / 'eval/dataset')
    parser.add_argument('--baseline', action='store_true')
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args(argv)
    if not 1 <= args.repeat <= 10:
        parser.error('--repeat must be 1..10')
    paths = sorted((args.dataset / 'cases').glob(args.cases + '.json'))
    if not paths:
        parser.error('no cases match')
    cases, jobs = [], []
    try:
        for path in paths:
            errors = check_case(path, args.dataset)
            if errors:
                raise ValueError(path.name + ': ' + '; '.join(errors))
            case = json.loads(path.read_text())
            cases.append(case)
            jobs.append(job_for(case, args.dataset))
        validate_bundle({'version': 1, 'jobs': jobs})
        requests = [request_for(job, args.model) for job in jobs]
        if args.dry_run:
            print(json.dumps(requests, ensure_ascii=False, indent=2))
            return 0
        if not os.environ.get('TYPESAFE_API_KEY'):
            raise ValueError('TYPESAFE_API_KEY is not set; use --dry-run for offline inspection')
        stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
        out = args.out or ROOT / ('eval/baseline' if args.baseline else 'eval/runs') / (stamp + '-typesafe-' + args.model)
        # Snapshot cases and all request inputs. Repeats are intentional fresh calls,
        # never cache replays that would falsely inflate consistency.
        fingerprint = digest({'cases': cases, 'requests': requests, 'catalog': CATALOG,
                              'version': VERSION, 'thresholds': THRESHOLDS})
        versions = sorted({c.get('catalog_version', 2) for c in cases})
        manifest = {'provider': 'typesafe', 'catalog_version': versions[0] if len(versions) == 1 else None,
                    'case_catalog_versions': versions, 'model': args.model,
                    'max_tokens': None, 'thinking': 'none', 'effort': 'typed judgments',
                    'repeat': args.repeat, 'run_date': stamp, 'dataset_sha256': digest(cases),
                    'prompt_sha256': fingerprint, 'questions_version': VERSION, 'thresholds': THRESHOLDS,
                    'generator': 'eval/typesafe/run.py', 'api': 'https://api.typesafe.ai/v1/systemone'}
        if (out / 'manifest.json').exists():
            previous = json.loads((out / 'manifest.json').read_text())
            if previous.get('prompt_sha256') != fingerprint or previous.get('repeat') != args.repeat:
                raise ValueError('refusing to mix model, evidence, dataset, rubric, or repeat versions')
            manifest = previous
        atomic_json(out / 'manifest.json', manifest)
        atomic_json(out / 'cases.json', cases)
        failed = 0
        for job, request in zip(jobs, requests):
            atomic_json(out / job['id'] / 'request.json', request)
            for rep in range(1, args.repeat + 1):
                path = out / job['id'] / ('rep%d.json' % rep)
                if path.exists():
                    try:
                        cached_result = json.loads(path.read_text())['result']
                        validate_response(cached_result['response'], request)
                        expected_key = digest({'request': request, 'questions_version': VERSION, 'thresholds': THRESHOLDS})
                        if cached_result['request_sha256'] == expected_key:
                            continue
                    except (ValueError, KeyError, ServiceError):
                        pass  # Resume retries failed/malformed attempts, never a valid result.
                result = run_job(job, args.model, live=True)
                failed += 'response' not in result and result['outcome'] == 'insufficient_evidence'
                atomic_json(path, {'provider': 'typesafe', 'result': result})
                print('%s rep%d -> %s' % (job['id'], rep, result['outcome']))
        print('TypeSafe run: ' + str(out))
        return 1 if failed else 0
    except (ValueError, OSError) as exc:
        print('typesafe eval: ' + str(exc), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
