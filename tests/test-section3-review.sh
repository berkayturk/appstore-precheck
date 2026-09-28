#!/usr/bin/env bash
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$ROOT/skills/appstore-precheck/scripts/lib/section3-review.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/risky/ios" "$TMP/clean/ios" "$TMP/unentitled/ios" "$TMP/risky/node_modules"
cat > "$TMP/risky/ios/Commerce.swift" <<'SWIFT'
import StoreKit
import Stripe
func unlockWithLicenseKey(_ code: String) { }
let offer = "7 day free trial, then $19.99 per month. Auto renews. Cancel anytime. Premium includes offline access. Terms and privacy policy."
func openExternalCheckout() { }
let lootBox = "Buy a mystery box with random rewards. Rare prize odds: 5%."
let personalLoan = "Personal loan: 48% APR including fees. Repay within 30 days."
SWIFT
cat > "$TMP/risky/ios/App.entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>com.apple.developer.storekit.external-purchase-link</key><true/></dict></plist>
PLIST
cat > "$TMP/risky/ios/Products.storekit" <<'JSON'
{"products":[{"productID":"sample.once","type":"Non-Consumable","displayPrice":"9.99"}],"subscriptionGroups":[{"subscriptions":[{"productID":"sample.premium","type":"RecurringSubscription","displayPrice":"19.99","recurringSubscriptionPeriod":"P3D","introductoryOffer":{"period":"P1W"}}]}]}
JSON
cat > "$TMP/risky/node_modules/ignored.swift" <<'SWIFT'
let secret = "Stripe 99% APR"
SWIFT
cat > "$TMP/clean/ios/App.swift" <<'SWIFT'
func openSettings() { }
SWIFT
cat > "$TMP/unentitled/ios/Checkout.swift" <<'SWIFT'
func openExternalCheckout() { }
SWIFT
printf '{broken JSON' > "$TMP/unentitled/ios/Invalid.storekit"
python3 "$CHECK" --repo "$TMP/risky" > "$TMP/risky.json"
python3 "$CHECK" --repo "$TMP/clean" > "$TMP/clean.json"
python3 "$CHECK" --repo "$TMP/unentitled" > "$TMP/unentitled.json"
python3 "$CHECK" --repo "$TMP/missing" > "$TMP/missing.json"
python3 - "$TMP" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
def checks(name):
    data = json.loads((p/name).read_text())
    assert data['schema_version'] == 1
    return {c['check_id']: c for c in data['checks']}
risky, clean, unentitled, missing = map(checks, ('risky.json', 'clean.json', 'unentitled.json', 'missing.json'))
expected = {'section3-payment-mechanisms', 'section3-license-unlock', 'section3-subscription-offer',
            'section3-external-entitlement', 'section3-iap-catalog',
            'section3-random-item-odds', 'section3-loan-terms'}
assert set(risky) == expected
assert all(c['status'] == 'NEEDS_REVIEW' for c in risky.values())
assert all(c['status'] == 'SKIP' for c in clean.values())
assert all(c['status'] == 'NOT_RUN' for c in missing.values())
assert unentitled['section3-external-entitlement']['status'] == 'NEEDS_REVIEW'
assert unentitled['section3-external-entitlement']['facets'] == {
    'external_checkout': True, 'entitlement': False}
assert unentitled['section3-iap-catalog']['status'] == 'SKIP'
assert risky['section3-payment-mechanisms']['facets'] == {
    'storekit': True, 'external_payment': True}
assert risky['section3-license-unlock']['facets'] == {'license_unlock': True}
assert risky['section3-subscription-offer']['facets'] == {
    'offer': True, 'price': True, 'duration': True, 'renewal': True,
    'cancellation': True, 'benefits': True, 'terms': True}
assert risky['section3-external-entitlement']['facets']['entitlement'] is True
assert risky['section3-iap-catalog']['facets'] == {
    'product': True, 'subscription': True, 'price': True,
    'introductory_offer': True, 'period_present': True, 'short_period': True}
assert any(e['signal'] == 'local_short_subscription_period' for e in risky['section3-iap-catalog']['evidence'])
assert risky['section3-random-item-odds']['facets'] == {'random_purchase': True, 'odds': True}
assert risky['section3-loan-terms']['facets'] == {
    'loan': True, 'apr': True, 'fees': True, 'repayment': True}
for name, check in risky.items():
    assert check['evidence'], name
    assert all('signal' in e and 'file' in e for e in check['evidence'])
    assert all(not e['file'].startswith('node_modules/') for e in check['evidence'])
raw = (p/'risky.json').read_text()
assert 'sample.premium' not in raw and '48% APR' not in raw
assert 'Stripe 99% APR' not in raw
PY
python3 - "$ROOT" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
section = json.loads((root/'skills/appstore-precheck/references/obligations/3.json').read_text())
registry = json.loads((root/'skills/appstore-precheck/references/registry/section3.json').read_text())['checks']
items = {x['id']: x for x in section['obligations']}
assert len(registry) == 7
for check_id in registry:
    linked = [x for x in items.values() if any(r.get('check_id') == check_id for r in x['routes'])]
    assert linked, check_id
    assert all(x['kind'] == 'obligation' for x in linked)
    assert all(any(r['route'] == 'attestation' for r in x['routes']) for x in linked)
    assert all(next(r for r in x['routes'] if r.get('check_id') == check_id)['decides'] == 'partial' for x in linked)
PY
printf 'section 3 review fixtures passed\n'
