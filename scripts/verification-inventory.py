#!/usr/bin/env python3
"""Derive a conservative evidence backlog; classifications are not decisions."""
import argparse
import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REF = ROOT / 'skills/appstore-precheck/references'


def inventory(catalog):
    rows = []
    for item in catalog['obligations']:
        if item['kind'] != 'obligation':
            continue
        routes = {r['route'] for r in item['routes']}
        automatic = routes & {'static', 'artifact', 'runtime', 'metadata'}
        category = ('mixed' if automatic else 'human-review' if 'semantic' in routes
                    else 'developer-evidence')
        rows.append({'obligation_id': item['id'], 'section': item['section'],
                     'apple_ref': item['apple_ref'], 'criterion': item['criterion'],
                     'classification': category, 'applicability_status': 'UNKNOWN',
                     'applicability_conditions': item['applicability'],
                     'exceptions': item['exceptions'], 'routes': item['routes'],
                     'owner': 'developer / qualified reviewer',
                     'gap': 'Establish scoped applicability and sufficient evidence; keyword signals and generic answers are not proof.'})
    return {'schema_version': 1, 'total': len(rows),
            'classes': dict(Counter(x['classification'] for x in rows)),
            'unknown_applicability': len(rows), 'obligations': rows}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--out', type=Path, required=True)
    args = p.parse_args()
    args.out.write_text(json.dumps(inventory(json.loads((REF / 'guideline-obligations.json').read_text())), indent=2)+'\n')


if __name__ == '__main__':
    main()
