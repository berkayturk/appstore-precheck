"""Bounded, local-only evidence collection. No builds, URL fetches, or credential reads."""
import json
import os
import plistlib
import re
from pathlib import Path

REFERENCES = Path(__file__).resolve().parents[2] / 'references'
SKIP = {'.git', '.codex', '.agents', '.claude', 'node_modules', 'Pods', 'Carthage',
        'build', 'DerivedData', '.build', 'eval', 'tests', 'Tests', '.typesafe-cache'}
SUFFIXES = {'.swift', '.m', '.mm', '.h', '.plist', '.entitlements', '.xcprivacy', '.xcstrings'}
METADATA = {'name.txt', 'subtitle.txt', 'description.txt', 'keywords.txt', 'release_notes.txt',
            'promotional_text.txt', 'privacy_url.txt', 'support_url.txt', 'notes.txt'}


def redact(text):
    text = re.sub(r'-----BEGIN [^-]*PRIVATE KEY-----.*?-----END [^-]*PRIVATE KEY-----',
                  '[REDACTED PRIVATE KEY]', text, flags=re.S)
    text = re.sub(r'(?i)((?:api[_-]?key|secret|password|token)\s*[=:]\s*[\"\'])([^\"\'\n]+)',
                  r'\1[REDACTED]', text)
    text = re.sub(r'(?im)(\b(?:api[_-]?key|secret|password|token)\s*[:=]\s*)(?![\"\'\[])([^\s,;]+)',
                  r'\1[REDACTED]', text)
    return re.sub(r'(?is)(<key>[^<]*(?:password|secret|api[_-]?key)[^<]*</key>\s*<string>).*?(</string>)',
                  r'\1[REDACTED]\2', text)


def collect(repo):
    repo = Path(repo).resolve()
    if not repo.is_dir():
        raise ValueError('repository path is not a directory')
    evidence, missing, plists, catalogs = [], [], [], []
    total = 0
    for directory, dirs, files in os.walk(repo, followlinks=False):
        dirs[:] = sorted(d for d in dirs if d not in SKIP and not d.startswith('.')
                         and not Path(directory, d).is_symlink())
        for name in sorted(files):
            path = Path(directory, name)
            if path.is_symlink() or path.suffix not in SUFFIXES and name not in METADATA:
                continue
            if path.stat().st_size > 64_000 or len(evidence) >= 48 or total >= 70_000:
                missing.append('collection limit: ' + path.relative_to(repo).as_posix())
                continue
            rel = path.relative_to(repo).as_posix()
            try:
                raw = path.read_bytes()
                if path.suffix in ('.plist', '.entitlements', '.xcprivacy'):
                    parsed = plistlib.loads(raw)
                    if path.suffix == '.plist' and isinstance(parsed, dict):
                        plists.append((rel, parsed))
                    text = raw.decode('utf-8') if not raw.startswith(b'bplist') else plistlib.dumps(parsed).decode()
                else:
                    text = raw.decode('utf-8')
                if path.suffix == '.xcstrings':
                    catalogs.append((rel, json.loads(text)))
            except (OSError, ValueError, UnicodeError, plistlib.InvalidFileException):
                missing.append('unreadable: ' + rel)
                continue
            # Skip empty files; no claims can cite them as evidence spans.
            if not text.strip():
                continue
            if len(text) > 5_000:
                missing.append('truncated: ' + rel)
            shown = redact(text[:5_000])
            evidence.append({'id': 'e%d' % len(evidence), 'path': rel, 'line': 1, 'text': shown,
                             'kind': 'manifest' if path.suffix in ('.plist', '.entitlements', '.xcprivacy') else
                             ('metadata' if name in METADATA else 'source'),
                             'representation': 'decoded plist' if raw.startswith(b'bplist') else 'source'})
            total += len(shown)
    catalog = json.loads((REFERENCES / 'review-catalog.json').read_text())
    prose = (REFERENCES / 'pierre-deep-review.md').read_text()
    jobs = []
    for check in catalog['checks']:
        gaps = list(missing)
        if not evidence:
            gaps.append('no readable app evidence')
        if check['requires_vision']:
            gaps.append('requires host vision review; Jev is text-only')
        if check['key'] in ('privacy-consistency', 'tracking-consistency', 'developer-identity'):
            gaps.append('live privacy/support contents must be supplied by the host')
        procedure = re.search(r'^### %d — .*?(?=^### |^---$)' % check['number'], prose, re.M | re.S)
        jobs.append({'id': check['key'], 'workflow': 'review', 'check_key': check['key'],
                     'context': {'check_definition': {**check, 'procedure': procedure[0] if procedure else check['question']},
                                 'scope': 'repository source review only; not proof of a shipping binary'},
                     'coverage': {'complete': not gaps, 'missing': gaps[:64]}, 'evidence': evidence})
    # Purpose quality is bounded to the actual string, separately from broad project review.
    for rel, parsed in plists:
        for key, value in sorted(parsed.items()):
            if re.fullmatch(r'NS[A-Za-z]+UsageDescription', key) and isinstance(value, str) and value.strip():
                jobs.append({'id': 'purpose-%d' % len(jobs), 'workflow': 'purpose',
                             'context': {'permission_key': key, 'text': redact(value), 'locale': 'base',
                                         'feature_description': 'Not yet verified; host must supply feature evidence.'},
                             'coverage': {'complete': False, 'missing': ['feature implementation not verified']},
                             'evidence': [{'id': 'purpose', 'path': rel, 'line': 1, 'text': key + ': ' + redact(value),
                                           'representation': 'parsed plist value; line 1 identifies file, not value location'}]})
    # Source-language values are candidates regardless of regex matches. Batch size stays bounded.
    for rel, catalog_data in catalogs:
        if not isinstance(catalog_data, dict):
            continue
        language = catalog_data.get('sourceLanguage', 'unknown')
        strings = catalog_data.get('strings', {})
        if not isinstance(strings, dict):
            continue
        for key, entry in sorted(strings.items()):
            if len(jobs) >= 120:
                break
            if not isinstance(entry, dict):
                continue
            value = entry.get('localizations', {}).get(language, {}).get('stringUnit', {}).get('value', key)
            if not isinstance(value, str) or not value.strip():
                continue
            jobs.append({'id': 'copy-%d' % len(jobs), 'workflow': 'copy',
                         'context': {'text': redact(value), 'locale': language, 'ui_role': 'unverified',
                                     'flow_stage': 'unverified'},
                         'coverage': {'complete': False, 'missing': ['UI role and handler require host inspection']},
                         'evidence': [{'id': 'copy', 'path': rel, 'line': 1, 'text': key + ': ' + redact(value),
                                       'representation': 'parsed String Catalog value'}]})
    return {'version': 1, 'catalog_version': catalog['version'], 'jobs': jobs[:128],
            'collection_notes': ['Bounded source collection. Inspect before sending. Redaction is best-effort.',
                                 'Line 1 on parsed plist/String Catalog values identifies the file, not an exact value line.',
                                 'Complete means coverage of the stated source scope, never runtime verification.',
                                 'Enrich missing context and coverage through the host; no credentials are required.']}
