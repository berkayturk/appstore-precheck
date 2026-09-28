#!/usr/bin/env bash
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$ROOT/skills/appstore-precheck/scripts/lib/section1-review.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/risky/ios" "$TMP/clean/ios" "$TMP/risky/node_modules"
cat > "$TMP/risky/ios/Community.swift" <<'SWIFT'
func createPost() { submitComment() }
func reportPost() { }
func blockUser() { }
// No prepublication control was shown by this fixture.
import FirebaseAnalytics
let offer = "Buy ammunition now"
let claim = "Measure blood pressure with your phone"
SWIFT
cat > "$TMP/risky/Podfile.lock" <<'LOCK'
  - GoogleMobileAds (1.0)
LOCK
cat > "$TMP/risky/node_modules/ignored.ts" <<'TS'
const contentFilter = true
TS
cat > "$TMP/clean/ios/App.swift" <<'SWIFT'
func openSettings() { }
SWIFT
python3 "$CHECK" --repo "$TMP/risky" --kids-category yes > "$TMP/risky.json"
python3 "$CHECK" --repo "$TMP/clean" > "$TMP/clean.json"
python3 "$CHECK" --repo "$TMP/missing" > "$TMP/missing.json"
python3 - "$TMP" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
def checks(name):
    data = json.loads((p/name).read_text())
    assert data['schema_version'] == 1
    return {c['check_id']: c for c in data['checks']}
risky, clean, missing = map(checks, ('risky.json', 'clean.json', 'missing.json'))
assert set(risky) == {'section1-ugc-controls','section1-kids-dependencies','section1-safety-signals'}
assert all(c['status'] == 'NEEDS_REVIEW' for c in risky.values())
assert risky['section1-ugc-controls']['facets'] == {'prepublication_filter': False, 'report': True, 'block': True}
assert {e['signal'] for e in risky['section1-kids-dependencies']['evidence']} == {'analytics','advertising'}
assert {e['signal'] for e in risky['section1-safety-signals']['evidence']} == {'weapons_commerce','medical_measurement'}
assert all(e['file'] != 'node_modules/ignored.ts' for c in risky.values() for e in c['evidence'])
assert all(c['status'] == 'SKIP' for c in clean.values())
assert all(c['status'] == 'NOT_RUN' for c in missing.values())
assert 'Buy ammunition now' not in (p/'risky.json').read_text()
PY
python3 - "$ROOT" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
section = json.loads((root/'skills/appstore-precheck/references/obligations/1.json').read_text())
registry = json.loads((root/'skills/appstore-precheck/references/registry/section1.json').read_text())['checks']
items = {x['id']:x for x in section['obligations']}
expected = {
 'section1-ugc-controls': 3,
 'section1-kids-dependencies': 2,
 'section1-safety-signals': 5,
}
assert set(registry) == set(expected)
for check_id, count in expected.items():
    linked = [x for x in items.values() if any(r.get('check_id') == check_id for r in x['routes'])]
    assert len(linked) == count, (check_id, len(linked))
    assert all(any(r['route']=='attestation' for r in x['routes']) for x in linked)
    assert all(next(r for r in x['routes'] if r.get('check_id')==check_id)['decides']=='partial' for x in linked)
PY
printf 'section 1 review fixtures passed\n'
