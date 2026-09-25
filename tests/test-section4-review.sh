#!/usr/bin/env bash
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$ROOT/skills/appstore-precheck/scripts/lib/section4-review.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/risky/ios/Keyboard" "$TMP/risky/ios/Safari/Resources" "$TMP/risky/ios/App" "$TMP/clean/ios/App" "$TMP/safe-extension/ios/Keyboard" "$TMP/safe-extension/ios/Safari/Resources" "$TMP/risky/node_modules"
cat > "$TMP/risky/ios/Keyboard/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>NSExtension</key><dict><key>NSExtensionPointIdentifier</key><string>com.apple.keyboard-service</string></dict></dict></plist>
PLIST
cat > "$TMP/risky/ios/Keyboard/KeyboardView.swift" <<'SWIFT'
import UIKit
import GoogleMobileAds
import StoreKit
class KeyboardView: UIInputViewController {
    func showAd() { let banner = GADBannerView() }
    func checkout() { SKPaymentQueue.default() }
}
SWIFT
cat > "$TMP/risky/ios/Safari/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>NSExtension</key><dict><key>NSExtensionPointIdentifier</key><string>com.apple.Safari.web-extension</string></dict></dict></plist>
PLIST
cat > "$TMP/risky/ios/Safari/Resources/manifest.json" <<'JSON'
{"manifest_version": 3, "host_permissions": ["<all_urls>"]}
JSON
cat > "$TMP/risky/ios/App/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>CFBundleDisplayName</key><string>Apple Photos Plus</string></dict></plist>
PLIST
cat > "$TMP/risky/ios/App/Home.swift" <<'SWIFT'
let launchTitle = "Coming soon"
SWIFT
cat > "$TMP/clean/ios/App/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>CFBundleDisplayName</key><string>My Notes</string></dict></plist>
PLIST
cat > "$TMP/safe-extension/ios/Keyboard/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>NSExtension</key><dict><key>NSExtensionPointIdentifier</key><string>com.apple.keyboard-service</string></dict></dict></plist>
PLIST
cat > "$TMP/safe-extension/ios/Keyboard/KeyboardView.swift" <<'SWIFT'
class KeyboardView: UIInputViewController {
    func next() { advanceToNextInputMode() }
}
SWIFT
cat > "$TMP/safe-extension/ios/Safari/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>NSExtension</key><dict><key>NSExtensionPointIdentifier</key><string>com.apple.Safari.web-extension</string></dict></dict></plist>
PLIST
cat > "$TMP/safe-extension/ios/Safari/Resources/manifest.json" <<'JSON'
{"manifest_version": 3, "host_permissions": ["https://example.org/*"]}
JSON
cat > "$TMP/risky/node_modules/fake.swift" <<'SWIFT'
let ignored = GADBannerView()
SWIFT
python3 "$CHECK" --repo "$TMP/risky" > "$TMP/risky.json"
python3 "$CHECK" --repo "$TMP/clean" > "$TMP/clean.json"
python3 "$CHECK" --repo "$TMP/safe-extension" > "$TMP/safe-extension.json"
python3 "$CHECK" --repo "$TMP/missing" > "$TMP/missing.json"
python3 - "$TMP" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
def checks(name):
    data = json.loads((p / name).read_text())
    assert data['schema_version'] == 1
    return {x['check_id']: x for x in data['checks']}
risky, clean, safe, missing = map(checks, ('risky.json', 'clean.json', 'safe-extension.json', 'missing.json'))
expected = {'section4-extension-commerce', 'section4-keyboard-navigation',
            'section4-safari-access', 'section4-apple-branding', 'section4-placeholder-copy'}
assert set(risky) == expected
assert all(x['status'] == 'NEEDS_REVIEW' for x in risky.values())
assert all(x['status'] == 'SKIP' for x in clean.values())
assert all(x['status'] == 'NOT_RUN' for x in missing.values())
assert safe['section4-extension-commerce']['status'] == 'SKIP'
assert safe['section4-keyboard-navigation']['status'] == 'NEEDS_REVIEW'
assert safe['section4-keyboard-navigation']['facets'] == {'next_keyboard_source_hint': True}
assert safe['section4-safari-access']['status'] == 'NEEDS_REVIEW'
assert safe['section4-safari-access']['facets'] == {'broad_host_access': False}
assert safe['section4-apple-branding']['status'] == 'SKIP'
assert safe['section4-placeholder-copy']['status'] == 'SKIP'
commerce = risky['section4-extension-commerce']
assert commerce['facets'] == {'advertising': True, 'in_app_purchase': True}
assert {x['signal'] for x in commerce['evidence']} == {'extension_type', 'advertising', 'in_app_purchase'}
keyboard = risky['section4-keyboard-navigation']
assert keyboard['facets'] == {'next_keyboard_source_hint': False}
assert {x['signal'] for x in keyboard['evidence']} == {'keyboard_extension'}
assert risky['section4-safari-access']['facets'] == {'broad_host_access': True}
assert {x['signal'] for x in risky['section4-safari-access']['evidence']} == {'safari_extension', 'broad_host_access'}
assert {x['signal'] for x in risky['section4-apple-branding']['evidence']} == {'brand_name_signal'}
assert {x['signal'] for x in risky['section4-placeholder-copy']['evidence']} == {'placeholder_copy'}
assert 'Apple Photos Plus' not in (p / 'risky.json').read_text()
assert all('node_modules' not in x['file'] for check in risky.values() for x in check['evidence'])
PY
python3 - "$ROOT" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
reference = root / 'skills/appstore-precheck/references'
registry = json.loads((reference / 'registry/section4.json').read_text())['checks']
items = json.loads((reference / 'obligations/4.json').read_text())['obligations']
expected = {
    'section4-extension-commerce': 2,
    'section4-keyboard-navigation': 1,
    'section4-safari-access': 1,
    'section4-apple-branding': 1,
    'section4-placeholder-copy': 2,
}
assert set(registry) == set(expected)
for check_id, count in expected.items():
    linked = [x for x in items if any(r.get('check_id') == check_id for r in x['routes'])]
    assert len(linked) == count, (check_id, len(linked))
    assert all(any(r['route'] == 'attestation' for r in x['routes']) for x in linked)
    assert all(next(r for r in x['routes'] if r.get('check_id') == check_id)['decides'] == 'partial' for x in linked)
PY
printf 'section 4 review fixtures passed\n'
