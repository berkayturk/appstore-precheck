"""Add only opt-in tier/run summaries; full check details remain in --out."""
import argparse
import collections
import json
from pathlib import Path
import sys


def augment(envelope, summary):
    result = dict(envelope)
    checks = json.loads(Path(summary['run_results']).read_text()).get('checks', {})
    counts = dict(collections.Counter(row.get('status', 'SKIP') for row in checks.values()))
    result['optional_review'] = {key: summary[key] for key in ('tiers', 'output_dir', 'run_results', 'input_errors')}
    result['coverage_run'] = {'check_status_counts': counts, 'scope': 'Only explicitly executed optional tiers; section inventory is separate.'}
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--opt-summary', required=True, type=Path)
    args = parser.parse_args()
    envelope = json.load(sys.stdin)
    if not isinstance(envelope, dict):
        parser.error('scan envelope must be an object')
    print(json.dumps(augment(envelope, json.loads(args.opt_summary.read_text()))))


if __name__ == '__main__':
    main()
