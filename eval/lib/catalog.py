"""Stable identities for the current review catalog; prose remains in the checklist."""
import json
from pathlib import Path

CATALOG_PATH = Path(__file__).resolve().parents[2] / 'skills/appstore-precheck/references/review-catalog.json'
CATALOG = json.loads(CATALOG_PATH.read_text(encoding='utf-8'))
BY_NUMBER = {c['number']: c for c in CATALOG['checks']}
BY_KEY = {c['key']: c for c in CATALOG['checks']}


def resolve(case):
    version = case.get('catalog_version', 2)
    if type(version) is not int:
        raise ValueError('catalog_version must be an integer')
    if version == CATALOG['version']:
        checks = BY_NUMBER
    elif version in (2, 3):
        frozen = json.loads((Path(__file__).resolve().parents[1] / ('catalog-history/review-catalog-v%d.json' % version)).read_text())
        checks = {c['number']: c for c in frozen['checks']}
    else:
        raise ValueError('unsupported historical catalog version; explicit migration required')
    if type(case.get('check_id')) is not int or case['check_id'] not in checks:
        raise ValueError('check_id is absent from the selected catalog version')
    check = checks[case['check_id']]
    if case.get('check_key', check['key']) != check['key']:
        raise ValueError('check_key does not match current catalog number')
    return check


def procedure_path(case):
    version = case.get('catalog_version', 2)
    if version in (2, 3):
        resolve(case)
        return Path(__file__).resolve().parents[1] / ('catalog-history/pierre-deep-review-v%d.md' % version)
    resolve(case)
    return CATALOG_PATH.parent / 'pierre-deep-review.md'


def fingerprint():
    """Bind eval resume to all supported catalog definitions and procedures."""
    import hashlib
    paths = [CATALOG_PATH, CATALOG_PATH.parent / 'pierre-deep-review.md',
             Path(__file__).resolve().parents[1] / 'catalog-history/review-catalog-v2.json',
             procedure_path({'catalog_version': 2, 'check_id': 1}),
             Path(__file__).resolve().parents[1] / 'catalog-history/review-catalog-v3.json',
             procedure_path({'catalog_version': 3, 'check_id': 1})]
    content = json.dumps([p.read_text(encoding='utf-8') for p in paths], ensure_ascii=False)
    return hashlib.sha256(content.encode()).hexdigest()


if __name__ == '__main__':
    print(fingerprint())
