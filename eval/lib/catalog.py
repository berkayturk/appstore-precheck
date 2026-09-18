"""Stable identities for the current review catalog; prose remains in the checklist."""
import json
from pathlib import Path

CATALOG_PATH = Path(__file__).resolve().parents[2] / 'skills/appstore-precheck/references/review-catalog.json'
CATALOG = json.loads(CATALOG_PATH.read_text(encoding='utf-8'))
BY_NUMBER = {c['number']: c for c in CATALOG['checks']}
BY_KEY = {c['key']: c for c in CATALOG['checks']}


def resolve(case):
    check = BY_NUMBER[case['check_id']]
    if case.get('check_key', check['key']) != check['key']:
        raise ValueError('check_key does not match current catalog number')
    return check
