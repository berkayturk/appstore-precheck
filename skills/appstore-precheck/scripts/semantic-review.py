#!/usr/bin/env python3
"""Prepare, execute, or replay advisory TypeSafe evidence bundles."""
import argparse
import json
import sys
from pathlib import Path

from semantic.collect import collect
from semantic.engine import render_text, request_for, run_job, validate_bundle
from semantic.questions import MODEL, VERSION, WORKFLOWS


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument('--repo', type=Path, help='collect bounded app evidence locally')
    source.add_argument('--bundle', type=Path, help='explicit evidence bundle; see references/typesafe.md')
    source.add_argument('--workflows', action='store_true', help='show available workflows and required context')
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--prepare', action='store_true', help='print bundle without inference (default for --repo)')
    mode.add_argument('--dry-run', action='store_true', help='print exact requests without inference')
    mode.add_argument('--live', action='store_true', help='send supplied evidence to TypeSafe; needs TYPESAFE_API_KEY')
    parser.add_argument('--cache-dir', type=Path, help='optional private cache; without --live, replay only')
    parser.add_argument('--model', default=MODEL)
    parser.add_argument('--format', choices=['json', 'text'], default='json')
    args = parser.parse_args(argv)
    if args.workflows:
        print(json.dumps(WORKFLOWS, ensure_ascii=False, indent=2))
        return 0
    try:
        bundle = collect(args.repo) if args.repo else json.loads(args.bundle.read_text(encoding='utf-8'))
        validate_bundle(bundle)
        if args.prepare or (args.repo and not args.live and not args.dry_run and not args.cache_dir):
            print(json.dumps(bundle, ensure_ascii=False, indent=2))
            return 0
        # Validate every request before starting any billable work.
        requests = [request_for(j, args.model) for j in bundle['jobs']]
        if args.dry_run:
            print(json.dumps({'version': VERSION, 'requests': requests}, ensure_ascii=False, indent=2))
            return 0
        results = [run_job(j, args.model, args.live, args.cache_dir) for j in bundle['jobs']]
        if args.format == 'text':
            print('\n'.join(render_text(r) for r in results))
        else:
            print(json.dumps({'schema_version': 1, 'advisory': True, 'mode': 'shadow',
                              'questions_version': VERSION, 'model_requested': args.model,
                              'catalog_version': bundle.get('catalog_version'),
                              'results': results, 'summary': {
                                  'jobs': len(results),
                                  'pierre_review': sum(r['action'] == 'pierre_review' for r in results),
                                  'estimated_cost_usd': sum(r.get('estimated_cost_usd') or 0 for r in results),
                                  'unknown_cost_requests': sum(r.get('estimated_cost_usd') is None for r in results)}},
                             ensure_ascii=False, indent=2))
        return 0  # Advisory outcomes have no scanner/release exit-code meaning.
    except (ValueError, OSError, KeyError) as exc:
        print('semantic-review: invalid or unreadable input (%s)' % type(exc).__name__, file=sys.stderr)
        return 64


if __name__ == '__main__':
    sys.exit(main())
