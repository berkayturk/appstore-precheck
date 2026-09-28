"""Narrow, evidence-derived App Store app-name limit verifier (stdlib only).

ASC captures are private, integrity-bound evidence, not authenticated transcripts.
The outer evaluator checks file hash, freshness and full scope. A caller's PASS,
completeness flag or local directory listing is never accepted as proof.
"""
import os
import re
import urllib.parse

VERIFIER = 'metadata.app-name-length.v1'
KIND = 'metadata-asc-snapshot'
VERIFIERS = {VERIFIER: {'positive': True, 'finding': True, 'applicability': True,
                        'evidence_kinds': [KIND]}}
BASE = 'https://api.appstoreconnect.apple.com'
ID = r'[A-Za-z0-9-]+'
ROUTE = re.compile(r'/v1/(?:apps/' + ID + r'(?:/appInfos|/appStoreVersions)?|'
                   r'appInfos/' + ID + r'/appInfoLocalizations|appStoreVersions/' + ID + r'/build)$')
ATTRIBUTES = ('bundleId', 'primaryLocale', 'versionString', 'platform', 'version', 'locale', 'name')


def capture(responses, app_id, version_id, fixture):
    """Allowlist the tiny name-proof projection; never persist raw review details."""
    secrets = [os.environ.get(key, '') for key in
               ('ASC_KEY_ID', 'ASC_ISSUER_ID', 'ASC_KEY_PATH',
                'PRECHECK_DEMO_USERNAME', 'PRECHECK_DEMO_PASSWORD')]

    def safe_text(value):
        if not isinstance(value, str) or any(secret and secret in value for secret in secrets):
            return None
        return value

    def resource(row):
        if not isinstance(row, dict):
            return None
        attrs = row.get('attributes')
        return {'id': safe_text(row.get('id')), 'type': safe_text(row.get('type')),
                'attributes': {key: safe_text(attrs[key]) for key in ATTRIBUTES if key in attrs}
                if isinstance(attrs, dict) else {}}

    projected = {}
    for path, response in responses.items():
        if safe_text(path) is None or not ROUTE.fullmatch(path.split('?', 1)[0]) or not isinstance(response, dict):
            continue
        data = response.get('data')
        value = {'data': [resource(row) for row in data] if isinstance(data, list) else resource(data)}
        links = response.get('links')
        if isinstance(links, dict):
            next_url = links.get('next')
            value['links'] = {'next': None if next_url is None else (safe_text(next_url) or '[UNAVAILABLE]')}
        meta = response.get('meta')
        if isinstance(meta, dict) and isinstance(meta.get('paging'), dict):
            total = meta['paging'].get('total')
            if type(total) is int:
                value['meta'] = {'paging': {'total': total}}
        projected[path] = value
    return {'schema_version': 1, 'collector': 'appstore-precheck.metadata.v1',
            'source': 'fixture' if fixture else 'asc', 'app_id': safe_text(app_id),
            'version_id': safe_text(version_id), 'responses': projected}


def attrs(row):
    value = row.get('attributes') if isinstance(row, dict) else None
    return value if isinstance(value, dict) else {}


def resource(row, kind):
    return (isinstance(row, dict) and row.get('type') == kind and
            isinstance(row.get('id'), str) and re.fullmatch(ID, row['id']) is not None)


def unique(rows, ident):
    found = [row for row in rows if row.get('id') == ident]
    return found[0] if len(found) == 1 else None


def collection(responses, path):
    """Follow recorded same-resource pages and require ASC's total count."""
    rows, seen, expected = [], set(), None
    current = path
    for _ in range(10):
        if current in seen:
            return None
        seen.add(current)
        page = responses.get(current)
        if not isinstance(page, dict) or not isinstance(page.get('data'), list):
            return None
        if any(not isinstance(row, dict) or not isinstance(row.get('id'), str) or
               not row['id'] for row in page['data']):
            return None
        rows.extend(page['data'])
        meta = page.get('meta')
        paging = meta.get('paging') if isinstance(meta, dict) else None
        total = paging.get('total') if isinstance(paging, dict) else None
        if type(total) is int:
            if total < 0 or (expected is not None and total != expected):
                return None
            expected = total
        links = page.get('links')
        if not isinstance(links, dict):
            return None
        next_url = links.get('next')
        if next_url is None:
            if expected != len(rows) or len({row['id'] for row in rows}) != len(rows):
                return None
            return rows
        if not isinstance(next_url, str):
            return None
        url = urllib.parse.urlparse(next_url)
        if url.scheme != 'https' or url.netloc != 'api.appstoreconnect.apple.com' or url.path != path or url.fragment:
            return None
        current = url.path + ('?' + url.query if url.query else '')
    return None


def observation(data, target):
    if (not isinstance(data, dict) or data.get('schema_version') != 1 or
            data.get('collector') != 'appstore-precheck.metadata.v1' or data.get('source') != 'asc'):
        return None
    app_id, version_id = data.get('app_id'), data.get('version_id')
    if not all(isinstance(x, str) and re.fullmatch(ID, x) for x in (app_id, version_id)):
        return None
    responses = data.get('responses')
    if not isinstance(responses, dict):
        return None
    app_path = '/v1/apps/' + app_id
    app_response = responses.get(app_path, {})
    app = app_response.get('data') if isinstance(app_response, dict) else None
    app_attrs = attrs(app)
    if (not resource(app, 'apps') or app.get('id') != app_id or
            not target.get('bundle_id') or app_attrs.get('bundleId') != target['bundle_id'] or
            target.get('platform') not in ('IOS', 'iOS', 'ios')):
        return None
    versions = collection(responses, app_path + '/appStoreVersions')
    infos = collection(responses, app_path + '/appInfos')
    if (not versions or not infos or any(not resource(row, 'appStoreVersions') for row in versions) or
            any(not resource(row, 'appInfos') for row in infos)):
        return None
    version = unique(versions, version_id)
    if (not version or attrs(version).get('platform') != 'IOS' or not target.get('version') or
            attrs(version).get('versionString') != target['version']):
        return None
    build_response = responses.get('/v1/appStoreVersions/' + version_id + '/build', {})
    build = build_response.get('data') if isinstance(build_response, dict) else None
    if not resource(build, 'builds') or not target.get('build') or attrs(build).get('version') != target['build']:
        return None
    names = []
    for info in infos:
        if not re.fullmatch(ID, info['id']):
            return None
        localizations = collection(responses, '/v1/appInfos/' + info['id'] + '/appInfoLocalizations')
        if not localizations or any(not resource(row, 'appInfoLocalizations') for row in localizations):
            return None
        locales = [attrs(row).get('locale') for row in localizations]
        if (any(not isinstance(locale, str) or not locale for locale in locales) or
                len(set(locales)) != len(locales) or not app_attrs.get('primaryLocale') or
                app_attrs['primaryLocale'] not in locales):
            return None
        for row in localizations:
            name = attrs(row).get('name')
            if not isinstance(name, str) or not name.strip() or '[REDACTED]' in name:
                return None
            names.append(name)
    # UTF-16 length is a conservative upper bound on code points/graphemes.
    # Decisive negative is restricted to printable ASCII (no counting ambiguity).
    try:
        within = all(len(name.encode('utf-16-le')) // 2 <= 30 for name in names)
    except UnicodeError:
        return None
    violation = len(infos) == 1 and any(len(name) > 30 and all(' ' <= c <= '~' for c in name) for name in names)
    return 'FINDING' if violation else ('PASS' if within else 'UNCERTAIN')


def evaluate(verifier, payloads, context):
    unknown = {'status': 'UNKNOWN', 'reason': 'Complete matching ASC app/version/build and localized names are required',
               'evidence_ids': []}
    if verifier != VERIFIER:
        return unknown
    passes, uncertain = [], []
    for evidence in payloads:
        if evidence.get('kind') != KIND:
            continue
        status = observation(evidence.get('data'), context.get('profile', {}).get('target', {}))
        if status == 'FINDING':
            return {'status': status, 'reason': 'A localized name in the sole app info exceeds 30 ASCII characters',
                    'evidence_ids': [evidence['id']], 'applicability': 'APPLICABLE'}
        if status == 'PASS':
            passes.append(evidence['id'])
        elif status == 'UNCERTAIN':
            uncertain.append(evidence['id'])
    if uncertain:
        return {'status': 'UNKNOWN', 'reason': 'A matching complete capture contains a name whose limit or relevant App Info is uncertain',
                'evidence_ids': uncertain}
    if passes:
        return {'status': 'PASS', 'reason': 'Every name across all returned app infos and complete localizations is at most 30 UTF-16 units',
                'evidence_ids': passes, 'applicability': 'APPLICABLE'}
    return unknown
