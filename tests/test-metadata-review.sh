#!/usr/bin/env bash
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUN="$ROOT/skills/appstore-precheck/scripts/metadata-review.sh"
export APPSTORE_PRECHECK_TEST_MODE=1
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/clean/fastlane/metadata/en-US" "$TMP/clean/fastlane/metadata/review_information" \
  "$TMP/clean/fastlane/screenshots/en-US" "$TMP/broken/fastlane/metadata/en-US" \
  "$TMP/broken/fastlane/metadata/review_information" "$TMP/broken/fastlane/screenshots"
printf 'Business\n' > "$TMP/clean/fastlane/metadata/primary_category.txt"
printf 'https://example.org/privacy\n' > "$TMP/clean/fastlane/metadata/en-US/privacy_url.txt"
printf 'https://example.org/support\n' > "$TMP/clean/fastlane/metadata/en-US/support_url.txt"
printf 'Review setup details\n' > "$TMP/clean/fastlane/metadata/review_information/notes.txt"
printf 'private-demo-user\n' > "$TMP/clean/fastlane/metadata/review_information/demo_user.txt"
printf 'private-demo-password\n' > "$TMP/clean/fastlane/metadata/review_information/demo_password.txt"
printf 'png' > "$TMP/clean/fastlane/screenshots/en-US/1.png"
printf 'not-a-url\n' > "$TMP/broken/fastlane/metadata/en-US/privacy_url.txt"
printf 'https://example.org/support\n' > "$TMP/broken/fastlane/metadata/en-US/support_url.txt"
printf 'private-demo-user\n' > "$TMP/broken/fastlane/metadata/review_information/demo_user.txt"

cat > "$TMP/clean-asc.json" <<'JSON'
{"responses":{
  "/v1/apps/test-app/appInfos":{"data":[{"id":"info-1","attributes":{"state":"PREPARE_FOR_SUBMISSION"},"relationships":{"primaryCategory":{"data":{"id":"BUSINESS"}}}}]},
  "/v1/appInfos/info-1/ageRatingDeclaration":{"data":{"id":"age-1","attributes":{"violenceRealistic":"NONE","userGeneratedContent":false}}},
  "/v1/appInfos/info-1/appInfoLocalizations":{"data":[{"id":"loc-info","attributes":{"locale":"en-US","privacyPolicyUrl":"https://example.org/privacy"}}]},
  "/v1/apps/test-app/appStoreVersions":{"data":[{"id":"ver-1","attributes":{"platform":"IOS","appStoreState":"PREPARE_FOR_SUBMISSION","createdDate":"2026-01-01T00:00:00Z"}}]},
  "/v1/appStoreVersions/ver-1/appStoreReviewDetail":{"data":{"id":"review-1","attributes":{"demoAccountRequired":true,"demoAccountName":"private-demo-user","demoAccountPassword":"private-demo-password","notes":"Review setup details"}}},
  "/v1/appStoreVersions/ver-1/appStoreVersionLocalizations":{"data":[{"id":"loc-1","attributes":{"locale":"en-US","supportUrl":"https://example.org/support"}}]},
  "/v1/appStoreVersionLocalizations/loc-1/appScreenshotSets":{"data":[{"id":"set-1","attributes":{"screenshotDisplayType":"APP_IPHONE_67"}}]},
  "/v1/appScreenshotSets/set-1/appScreenshots":{"data":[{"id":"screen-1","attributes":{"fileName":"private-screenshot.png"}}]},
  "/v1/apps/test-app/inAppPurchasesV2":{"data":[{"id":"iap-1","attributes":{"reviewNote":"private-iap-instructions"}}]},
  "/v2/inAppPurchases/iap-1/appStoreReviewScreenshot":{"data":{"id":"iap-screen"}},
  "/v1/apps/test-app/subscriptionGroups":{"data":[{"id":"group-1"}]},
  "/v1/subscriptionGroups/group-1/subscriptions":{"data":[{"id":"sub-1","attributes":{"reviewNote":"private-subscription-instructions"}}]},
  "/v1/subscriptions/sub-1/appStoreReviewScreenshot":{"data":{"id":"sub-screen"}},
  "/v1/apps/test-app/appPriceSchedule":{"data":{"id":"price-1","relationships":{"baseTerritory":{"data":{"id":"USA"}},"manualPrices":{"data":[{"id":"manual-1"}]}}}},
  "/v1/apps/test-app/appAvailabilityV2":{"data":{"id":"availability-1","attributes":{"availableInNewTerritories":true}}},
  "/v2/appAvailabilities/availability-1/territoryAvailabilities":{"data":[{"id":"territory-1","attributes":{"available":true}}]}
}}
JSON
cat > "$TMP/broken-asc.json" <<'JSON'
{"responses":{
  "/v1/apps/test-app/appInfos":{"data":[{"id":"info-1","attributes":{},"relationships":{"primaryCategory":{"data":null}}}]},
  "/v1/appInfos/info-1/ageRatingDeclaration":{"data":null},
  "/v1/appInfos/info-1/appInfoLocalizations":{"data":[{"id":"loc-info","attributes":{"locale":"en-US","privacyPolicyUrl":""}}]},
  "/v1/apps/test-app/appStoreVersions":{"data":[{"id":"ver-1","attributes":{"platform":"IOS"}}]},
  "/v1/appStoreVersions/ver-1/appStoreReviewDetail":{"data":{"id":"review-1","attributes":{"demoAccountRequired":true,"demoAccountName":"","demoAccountPassword":"","notes":""}}},
  "/v1/appStoreVersions/ver-1/appStoreVersionLocalizations":{"data":[{"id":"loc-1","attributes":{"locale":"en-US","supportUrl":""}}]},
  "/v1/appStoreVersionLocalizations/loc-1/appScreenshotSets":{"data":[]},
  "/v1/apps/test-app/inAppPurchasesV2":{"data":[{"id":"iap-1","attributes":{"reviewNote":""}}]},
  "/v2/inAppPurchases/iap-1/appStoreReviewScreenshot":{"data":null},
  "/v1/apps/test-app/subscriptionGroups":{"data":[{"id":"group-1"}]},
  "/v1/subscriptionGroups/group-1/subscriptions":{"data":[{"id":"sub-1","attributes":{"reviewNote":""}}]},
  "/v1/subscriptions/sub-1/appStoreReviewScreenshot":{"data":null},
  "/v1/apps/test-app/appPriceSchedule":{"data":null},
  "/v1/apps/test-app/appAvailabilityV2":{"data":{"id":"availability-1","attributes":{"availableInNewTerritories":false}}},
  "/v2/appAvailabilities/availability-1/territoryAvailabilities":{"data":[{"id":"territory-1","attributes":{"available":false}}]}
}}
JSON

bash "$RUN" --repo "$TMP/clean" --login-required --asc-app-id test-app \
  --asc-fixture "$TMP/clean-asc.json" > "$TMP/clean.json"
bash "$RUN" --repo "$TMP/broken" --login-required --asc-app-id test-app \
  --asc-fixture "$TMP/broken-asc.json" > "$TMP/broken.json"
bash "$RUN" --repo "$TMP/broken" > "$TMP/offline.json"

python3 - "$TMP" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
clean = json.loads((root / 'clean.json').read_text())
broken = json.loads((root / 'broken.json').read_text())
offline = json.loads((root / 'offline.json').read_text())
good = {x['check_id']: x for x in clean['results']}
bad = {x['check_id']: x for x in broken['results']}
assert len(good) == 11 and len(bad) == 11, (good.keys(), bad.keys())
assert set(x['status'] for x in good.values()) == {'PASS'}, good
for check_id in good:
    assert bad[check_id]['status'] == 'NEEDS_REVIEW', (check_id, bad[check_id])
assert 'private-' not in (root / 'clean.json').read_text()
assert 'private-' not in (root / 'broken.json').read_text()
assert clean['sources']['app_store_connect_fixture'] is True
assert {x['check_id']: x['status'] for x in offline['results']}['meta-age-rating'] == 'NOT_RUN'
assert {x['check_id']: x['status'] for x in offline['results']}['meta-review-notes'] == 'NEEDS_REVIEW'
PY

# A transport/API failure is a gap, not an automatic clean result.
printf '{"responses":{}}\n' > "$TMP/error-asc.json"
bash "$RUN" --repo "$TMP/clean" --asc-app-id test-app --asc-fixture "$TMP/error-asc.json" > "$TMP/error.json"
python3 - "$TMP/error.json" <<'PY'
import json, sys
r = {x['check_id']: x['status'] for x in json.load(open(sys.argv[1]))['results']}
assert r['meta-age-rating'] == 'SKIP', r
assert r['meta-price'] == 'SKIP', r
PY

# URL reachability never attempts loopback or private addresses.
python3 - "$ROOT" <<'PY'
import importlib.util, pathlib, sys
path = pathlib.Path(sys.argv[1]) / 'skills/appstore-precheck/scripts/lib/metadata-review.py'
spec = importlib.util.spec_from_file_location('metadata_review', str(path))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
assert not module.public_url('http://127.0.0.1/private')
assert not module.public_url('http://[::1]/private')
assert not module.valid_url('file:///etc/passwd')
PY

# The OpenSSL signature must be JWT raw R||S, and must verify as ES256.
if command -v openssl >/dev/null 2>&1; then
  openssl ecparam -name prime256v1 -genkey -noout -out "$TMP/key.p8" 2>/dev/null
  openssl pkey -in "$TMP/key.p8" -pubout -out "$TMP/pub.pem" 2>/dev/null
  python3 - "$ROOT" "$TMP" <<'PY'
import base64, importlib.util, json, pathlib, subprocess, sys
root, tmp = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
path = root / 'skills/appstore-precheck/scripts/lib/metadata-review.py'
spec = importlib.util.spec_from_file_location('metadata_review', str(path))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
token = module.make_jwt('KEYID', 'ISSUERID', str(tmp / 'key.p8'))
parts = token.split('.')
assert len(parts) == 3
decode = lambda part: base64.urlsafe_b64decode(part + '=' * (-len(part) % 4))
assert json.loads(decode(parts[0])) == {'alg': 'ES256', 'kid': 'KEYID', 'typ': 'JWT'}
payload = json.loads(decode(parts[1]))
assert payload['iss'] == 'ISSUERID' and payload['aud'] == 'appstoreconnect-v1'
assert 0 < payload['exp'] - payload['iat'] <= 1200
raw = decode(parts[2])
assert len(raw) == 64
def der_integer(part):
    part = part.lstrip(b'\x00') or b'\x00'
    if part[0] & 128:
        part = b'\x00' + part
    return b'\x02' + bytes([len(part)]) + part
content = der_integer(raw[:32]) + der_integer(raw[32:])
der = b'\x30' + bytes([len(content)]) + content
(tmp / 'input').write_bytes('.'.join(parts[:2]).encode())
(tmp / 'signature').write_bytes(der)
verified = subprocess.run(['openssl', 'dgst', '-sha256', '-verify', str(tmp / 'pub.pem'),
                           '-signature', str(tmp / 'signature'), str(tmp / 'input')],
                          capture_output=True, check=False)
assert verified.returncode == 0, verified.stderr
PY
fi
echo 'metadata review fixtures: PASS'
