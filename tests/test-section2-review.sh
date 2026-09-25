#!/usr/bin/env bash
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$ROOT/skills/appstore-precheck/scripts/lib/section2-review.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/risky/ios" "$TMP/risky/fastlane/screenshots/en-US" "$TMP/risky/node_modules" "$TMP/clean/ios"
cat > "$TMP/risky/ios/App.swift" <<'SWIFT'
import SwiftUI
struct AppView: View {
  var body: some View { Text("Lorem ipsum") }
  func load() { URLSession.shared.dataTask(with: endpoint).resume() }
  func login() { authenticateUser() }
  func later() { fatalError("TODO") }
}
SWIFT
cat > "$TMP/risky/node_modules/ignored.ts" <<'TS'
Text("Lorem ipsum")
TS
printf 'fake-image' > "$TMP/risky/fastlane/screenshots/en-US/phone.png"
cat > "$TMP/clean/ios/App.swift" <<'SWIFT'
import SwiftUI
// Text("Lorem ipsum") in a comment is not app content.
struct AppView: View { var body: some View { Text("Welcome") } }
SWIFT
python3 "$CHECK" --repo "$TMP/risky" > "$TMP/risky.json"
python3 "$CHECK" --repo "$TMP/clean" > "$TMP/clean.json"
python3 "$CHECK" --repo "$TMP/missing" > "$TMP/missing.json"
python3 - "$TMP" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
def checks(name):
    payload = json.loads((p/name).read_text())
    assert payload['schema_version'] == 1
    return {item['check_id']: item for item in payload['checks']}
risky, clean, missing = map(checks, ('risky.json', 'clean.json', 'missing.json'))
expected = {'section2-completeness-signals', 'section2-review-access-signals', 'section2-screenshot-packet'}
assert set(risky) == expected
assert all(item['status'] == 'NEEDS_REVIEW' for item in risky.values())
assert all(item['status'] == 'SKIP' for item in clean.values())
assert all(item['status'] == 'NOT_RUN' for item in missing.values())
assert risky['section2-completeness-signals']['facets'] == {'placeholder': True, 'unfinished_code': True}
assert risky['section2-review-access-signals']['facets'] == {'login': True, 'network': True}
assert risky['section2-screenshot-packet']['facets'] == {'image_count': 1, 'locales': 1}
assert all(e.get('file') != 'node_modules/ignored.ts' for c in risky.values() for e in c['evidence'])
assert 'Lorem ipsum' not in (p/'risky.json').read_text()
assert 'authenticateUser' not in (p/'risky.json').read_text()
PY
python3 - "$ROOT" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
section = json.loads((root/'skills/appstore-precheck/references/obligations/2.json').read_text())
registry = json.loads((root/'skills/appstore-precheck/references/registry/section2.json').read_text())['checks']
items = {x['id']: x for x in section['obligations']}
expected = {
  'section2-completeness-signals': 4,
  'section2-review-access-signals': 2,
  'section2-screenshot-packet': 2,
  'meta-demo-account': 1,
  'meta-iap-review-notes': 1,
  'meta-screenshots': 2,
  'artifact-debug': 2,
  'artifact-private-api': 1,
  'artifact-executable-loading': 1,
}
for check_id, count in expected.items():
    linked = [x for x in items.values() if any(r.get('check_id') == check_id for r in x['routes'])]
    assert len(linked) >= count, (check_id, len(linked))
    assert all(any(r['route']=='attestation' for r in x['routes']) for x in linked if x['kind']=='obligation')
    assert all(next(r for r in x['routes'] if r.get('check_id')==check_id)['decides']=='partial' for x in linked)
PY
printf 'section 2 review fixtures passed\n'
