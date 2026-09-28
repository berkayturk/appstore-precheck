#!/usr/bin/env python3
"""Small shared invariants for evidence verification; Python 3.8+ stdlib."""
import datetime as dt
import hashlib
import re
from pathlib import Path

SCOPE_FIELDS = ('bundle_id', 'version', 'build', 'artifact_sha256', 'source_sha256',
                'platform', 'os', 'devices', 'storefronts', 'backend', 'distribution')
CLOSED = {'VERIFIED_PASS', 'VERIFIED_FINDING', 'NOT_APPLICABLE_VERIFIED'}


def iso_date(value):
    if not isinstance(value, str):
        raise ValueError('expected ISO date')
    parsed = dt.date.fromisoformat(value)
    if parsed.isoformat() != value:
        raise ValueError('expected ISO date')
    return parsed


def scope_matches(target, scope):
    """Unknown identity never acts as wildcard, and target arrays match exactly."""
    if not isinstance(target, dict) or not isinstance(scope, dict):
        return False
    return all(target.get(k) not in (None, '', [], 'unknown') and
               scope.get(k) == target[k] for k in SCOPE_FIELDS)


def validate_profile(profile):
    if not isinstance(profile, dict) or profile.get('schema_version') != 1:
        raise ValueError('unsupported profile version')
    if not isinstance(profile.get('target'), dict):
        raise ValueError('profile target must be an object')
    target = profile['target']
    for key in SCOPE_FIELDS:
        value = target.get(key)
        if value is None:
            continue
        if key in ('devices', 'storefronts'):
            if not isinstance(value, list) or not value or any(not isinstance(x, str) or not x.strip() for x in value):
                raise ValueError('target arrays must contain nonempty strings')
        elif not isinstance(value, str) or not value.strip():
            raise ValueError('target values must be strings or null')
        if key.endswith('_sha256') and not re.fullmatch(r'[a-f0-9]{64}', value):
            raise ValueError('target hash must be SHA-256')
        if key == 'distribution' and value not in ('simulator', 'distribution', 'physical'):
            raise ValueError('unsupported distribution scope')
    date = iso_date(profile.get('reviewed_at'))
    if date > dt.date.today():
        raise ValueError('review date is in the future')
    facts = profile.get('facts', {})
    if not isinstance(facts, dict):
        raise ValueError('profile facts must be an object')
    for fact in facts.values():
        if not isinstance(fact, dict) or 'value' not in fact:
            raise ValueError('fact needs a value; null represents unknown')
        if fact['value'] is not None and (not fact.get('evidence_ids') or
                                         not fact.get('scope') or not fact.get('observed_at')):
            raise ValueError('known fact requires evidence, scope and date')
    return profile


def evidence_errors(row, profile, base, max_age_days=30):
    """Return safe field errors, never echo input payloads or credentials."""
    if not isinstance(row, dict):
        return ['evidence must be an object']
    errors = []
    for key in ('id', 'kind', 'collector'):
        if not isinstance(row.get(key), str) or not row[key].strip():
            errors.append('missing ' + key)
    if not isinstance(row.get('limitations'), list):
        errors.append('limitations must be a list')
    if not isinstance(row.get('scope'), dict) or not scope_matches(profile['target'], row['scope']):
        errors.append('unknown or mismatched scope')
    try:
        age = (iso_date(profile['reviewed_at']) - iso_date(row.get('collected_at'))).days
        if not 0 <= age <= max_age_days:
            errors.append('stale or future evidence')
    except (ValueError, TypeError):
        errors.append('invalid collection date')
    raw = row.get('path')
    if not isinstance(raw, str) or not raw or '://' in raw or '\n' in raw:
        errors.append('expected local evidence path')
    else:
        try:
            path = Path(raw)
            path = path if path.is_absolute() else Path(base) / path
            if not path.is_file():
                errors.append('missing evidence file')
            elif hashlib.sha256(path.read_bytes()).hexdigest() != row.get('sha256'):
                errors.append('evidence hash mismatch')
        except (OSError, ValueError):
            errors.append('unreadable evidence file')
    return errors


def reduce_status(applicability, required, satisfied, violated, na_verified=False, conflict=False):
    """Inputs are evaluator-proven condition IDs, never raw caller status labels."""
    if violated and applicability == 'APPLICABLE':
        return 'VERIFIED_FINDING'
    if conflict:
        return 'UNRESOLVED'
    if applicability == 'NOT_APPLICABLE' and na_verified:
        return 'NOT_APPLICABLE_VERIFIED'
    if applicability == 'APPLICABLE' and required and set(required) <= set(satisfied):
        return 'VERIFIED_PASS'
    return 'UNRESOLVED'


def summarize(rows):
    from collections import Counter
    counts = Counter(row['status'] for row in rows)
    total = len(rows)
    percent = lambda n: round(100.0 * n / total, 2) if total else 0.0
    return {'total_obligations': total, 'status_counts': dict(sorted(counts.items())),
            'decided_percent': percent(sum(counts[k] for k in CLOSED)),
            'verified_pass_percent': percent(counts['VERIFIED_PASS']),
            'verified_not_applicable': counts['NOT_APPLICABLE_VERIFIED'],
            'ready': bool(total) and all(row['status'] in
                    {'VERIFIED_PASS', 'NOT_APPLICABLE_VERIFIED'} for row in rows)}
