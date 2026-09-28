#!/usr/bin/env bash
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$ROOT/skills/appstore-precheck/scripts/lib/section5-review.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/risky/ios" "$TMP/risky/node_modules" "$TMP/clean/ios"
cat > "$TMP/risky/ios/Contacts.swift" <<'SWIFT'
import ContactsUI
let picker = CNContactPickerViewController()
let bulk = Button("Select All") { selectAllContacts() }
let selectedContacts = allContacts
SWIFT
cat > "$TMP/risky/ios/Browser.swift" <<'SWIFT'
import SafariServices
let safariVC = SFSafariViewController(url: pageURL)
safariVC.view.addSubview(coverView)
SWIFT
cat > "$TMP/risky/ios/Privacy.swift" <<'SWIFT'
import SwiftUI
let policy = Link("Privacy Policy", destination: policyURL)
SWIFT
cat > "$TMP/risky/node_modules/ignored.swift" <<'SWIFT'
let picker = CNContactPickerViewController()
Button("Select All") { selectAllContacts() }
SWIFT
cat > "$TMP/clean/ios/App.swift" <<'SWIFT'
import SwiftUI
// let picker = CNContactPickerViewController(); Button("Select All") {}
// let safariVC = SFSafariViewController(url: pageURL); safariVC.view.addSubview(coverView)
// let policy = Link("Privacy Policy", destination: policyURL)
let unrelated = Button("Select All") { chooseAllFiles() }
SWIFT
python3 "$CHECK" --repo "$TMP/risky" > "$TMP/risky.json"
python3 "$CHECK" --repo "$TMP/clean" > "$TMP/clean.json"
python3 "$CHECK" --repo "$TMP/missing" > "$TMP/missing.json"
python3 - "$TMP" "$ROOT" <<'PY'
import json
import pathlib
import sys

tmp, root = map(pathlib.Path, sys.argv[1:])
def checks(name):
    payload = json.loads((tmp/name).read_text())
    assert payload['schema_version'] == 1
    return {item['check_id']: item for item in payload['checks']}
risky, clean, missing = map(checks, ('risky.json', 'clean.json', 'missing.json'))
expected = {'section5-contact-select-all', 'section5-contact-preselect',
            'section5-safari-obscure', 'section5-privacy-entry'}
assert set(risky) == expected
assert all(item['status'] == 'NEEDS_REVIEW' for item in risky.values())
assert all(item['status'] == 'SKIP' for item in clean.values())
assert all(item['status'] == 'NOT_RUN' for item in missing.values())
assert all(e['file'] != 'node_modules/ignored.swift' for c in risky.values() for e in c['evidence'])
assert 'policyURL' not in (tmp/'risky.json').read_text()
assert 'selectedContacts' not in (tmp/'risky.json').read_text()
section = json.loads((root/'skills/appstore-precheck/references/obligations/5.json').read_text())
registry = json.loads((root/'skills/appstore-precheck/references/registry/section5.json').read_text())['checks']
items = {x['id']: x for x in section['obligations']}
for check_id in expected:
    assert check_id in registry
    linked = [x for x in items.values() if any(r.get('check_id') == check_id for r in x['routes'])]
    assert len(linked) == 1, (check_id, len(linked))
    assert any(r['route'] == 'attestation' for r in linked[0]['routes'])
    route = next(r for r in linked[0]['routes'] if r.get('check_id') == check_id)
    assert route['decides'] == 'partial'
PY
printf 'section 5 source review fixtures passed\n'
