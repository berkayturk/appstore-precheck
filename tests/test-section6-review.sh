#!/usr/bin/env bash
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$ROOT/skills/appstore-precheck/scripts/lib/section6-review.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/risky/ios/App" "$TMP/risky/node_modules/ignore" "$TMP/clean/ios/App" "$TMP/manifest-only"
cat > "$TMP/risky/Podfile.lock" <<'LOCK'
PODS:
  - FirebaseAnalytics (1.0)
LOCK
cat > "$TMP/risky/ios/App/Accessory.swift" <<'SWIFT'
import CoreBluetooth
final class AccessoryController {
    let manager = CBCentralManager()
}
SWIFT
cat > "$TMP/risky/node_modules/ignore/Unused.swift" <<'SWIFT'
import ExternalAccessory
SWIFT
cat > "$TMP/clean/ios/App/App.swift" <<'SWIFT'
import SwiftUI
struct AppView: View { var body: some View { Text("Hello") } }
SWIFT
cat > "$TMP/manifest-only/package.json" <<'JSON'
{"dependencies":{"react-native":"1.0","react-native-ble-plx":"3.0"}}
JSON
python3 "$CHECK" --repo "$TMP/risky" > "$TMP/risky.json"
python3 "$CHECK" --repo "$TMP/clean" > "$TMP/clean.json"
python3 "$CHECK" --repo "$TMP/manifest-only" > "$TMP/manifest-only.json"
python3 "$CHECK" --repo "$TMP/missing" > "$TMP/missing.json"
python3 - "$TMP" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
def checks(name):
    data = json.loads((p / name).read_text())
    assert data['schema_version'] == 1
    return {x['check_id']: x for x in data['checks']}
risky, clean, manifest, missing = map(checks, ('risky.json', 'clean.json', 'manifest-only.json', 'missing.json'))
expected = {'section6-external-components', 'section6-special-hardware'}
assert set(risky) == expected
assert all(x['status'] == 'NEEDS_REVIEW' for x in risky.values())
assert all(x['status'] == 'SKIP' for x in clean.values())
assert all(x['status'] == 'NOT_RUN' for x in missing.values())
assert manifest['section6-external-components']['status'] == 'NEEDS_REVIEW'
assert manifest['section6-special-hardware']['status'] == 'SKIP'
assert {e['signal'] for e in risky['section6-external-components']['evidence']} == {'dependency_manifest'}
assert {e['signal'] for e in risky['section6-special-hardware']['evidence']} == {'hardware_api_hint'}
assert all('node_modules' not in e['file'] for x in risky.values() for e in x['evidence'])
assert 'FirebaseAnalytics' not in (p / 'risky.json').read_text()
assert 'react-native-ble-plx' not in (p / 'manifest-only.json').read_text()
PY
python3 - "$ROOT" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
ref = root / 'skills/appstore-precheck/references'
registry = json.loads((ref / 'registry/section6.json').read_text())['checks']
items = json.loads((ref / 'obligations/intro.json').read_text())['obligations']
expected = {'section6-external-components': 1, 'section6-special-hardware': 1}
assert set(registry) == set(expected)
for check_id, count in expected.items():
    linked = [x for x in items if any(r.get('check_id') == check_id for r in x['routes'])]
    assert len(linked) == count, (check_id, len(linked))
    assert all(any(r['route'] == 'attestation' for r in x['routes']) for x in linked)
    assert all(next(r for r in x['routes'] if r.get('check_id') == check_id)['decides'] == 'partial' for x in linked)
metadata_links = {
    'meta-demo-account': 'atom-884097dadb564c018667d7c730d75f61',
    'meta-review-notes': 'atom-f9a98fc9b0544658a3b9a4b0152a160e',
    'meta-iap-review-notes': 'atom-89ba978493b44f34a8ed0f9e9d4b9bb1',
}
catalog = json.loads((ref / 'guideline-obligations.json').read_text())['obligations']
by_id = {x['id']: x for x in catalog}
for check_id, ident in metadata_links.items():
    item = by_id[ident]
    # Intro aliases retain lineage; the actual duty and its route live on the
    # linked canonical obligation after the reviewed catalog correction.
    candidates = [item] if item['kind'] == 'obligation' else [by_id[k] for k in item['related']]
    routes = [r for x in candidates if x['kind'] == 'obligation'
              for r in x['routes'] if r.get('check_id') == check_id]
    assert routes, (check_id, ident)
    assert all(r['route'] == 'metadata' and r['decides'] == 'partial' for r in routes)
PY
printf 'section 6 review fixtures passed\n'
