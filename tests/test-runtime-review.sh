#!/usr/bin/env bash
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REVIEW="$ROOT/skills/appstore-precheck/scripts/runtime-review.sh"
FIX="$ROOT/tests/fixtures/runtime"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

bash "$REVIEW" --screens "$FIX/clean" --out "$TMP/clean" > "$TMP/clean.json"
bash "$REVIEW" --screens "$FIX/risky" --out "$TMP/risky" > "$TMP/risky.json"
bash "$REVIEW" --screens "$FIX/degenerate" --out "$TMP/degenerate" > "$TMP/degenerate.json"
python3 - "$TMP" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
def load(name):
    d=json.loads((p/(name+'.json')).read_text())
    assert (p/name/'screen-inventory.json').exists()
    return d, {c['check_id']:c for c in d['checks']}
clean, cc = load('clean')
risky, rc = load('risky')
deg, dc = load('degenerate')
assert len(cc)==len(rc)==len(dc)==13
assert cc['dyn-placeholder']['status']=='PASS'
assert rc['dyn-placeholder']['status']=='NEEDS_REVIEW'
assert rc['dyn-account-deletion']['status']=='NEEDS_REVIEW'
assert rc['dyn-siwa-parity']['status']=='NEEDS_REVIEW'
assert rc['dyn-restore-response']['status']=='NEEDS_REVIEW'
assert rc['dyn-paywall-disclosure']['status']=='NEEDS_REVIEW'
assert rc['dyn-ugc-safety']['status']=='NEEDS_REVIEW'
assert rc['dyn-permission-purpose']['status']=='NEEDS_REVIEW'
assert rc['dyn-login-wall']['status']=='NEEDS_REVIEW'
assert rc['dyn-external-payment']['status']=='NEEDS_REVIEW'
assert rc['dyn-navigation-crash']['status']=='SKIP'
assert rc['dyn-layout-review']['status']=='NEEDS_REVIEW'
assert all(x['status']=='SKIP' for x in dc.values())
assert clean['screens'][0]['actions'][0]['safe_to_tap']
assert not any(x['safe_to_tap'] for x in risky['screens'][0]['actions'] if x['label']=='Delete Account')
assert clean['screen_budget']==25 and clean['time_budget_seconds']==360
PY

printf 'api.example.invalid\n' > "$TMP/hosts.txt"
printf '%s\n' '{}' > "$TMP/PrivacyInfo.xcprivacy"
mkdir "$TMP/installed.app" "$TMP/source.app"
bash "$REVIEW" --screens "$FIX/clean" --hosts "$TMP/hosts.txt" \
  --privacy-manifest "$TMP/PrivacyInfo.xcprivacy" \
  --installed-bundle "$TMP/installed.app" --source-bundle "$TMP/source.app" \
  --out "$TMP/context" > "$TMP/context.json"
python3 - "$TMP/context.json" <<'PY'
import json, sys
c = {x['check_id']:x for x in json.load(open(sys.argv[1]))['checks']}
assert c['dyn-host-privacy']['status']=='NEEDS_REVIEW'
assert c['dyn-bundle-drift']['status']=='NEEDS_REVIEW'
PY

cat > "$TMP/mixed.txt" <<'TXT'
DYNAMIC-FINDING: 2.1 [dyn-launch] — quorum 1/3: failed on 1 of 3 launches (not unanimous); fresh erase verified
DYNAMIC-FINDING: 2.1 [dyn-demo-login] — quorum 2/3: failed on two; fresh erase verified
TXT
bash "$REVIEW" --dynamic-blocking --transcript "$TMP/mixed.txt" > "$TMP/block.txt"
test ! -s "$TMP/block.txt"
cat > "$TMP/all.txt" <<'TXT'
DYNAMIC-FINDING: 2.1 [dyn-launch] — quorum 3/3: failed on every launch; fresh erase verified
DYNAMIC-FINDING: 2.1 [dyn-demo-login] — quorum 3/3: login rejected; fresh erase verified
TXT
bash "$REVIEW" --dynamic-blocking --transcript "$TMP/all.txt" > "$TMP/block.txt"
test "$(grep -c '^FAIL:' "$TMP/block.txt")" -eq 2
grep -q 'without --dynamic-blocking' "$TMP/block.txt"

mkdir "$TMP/bin"
cat > "$TMP/bin/maestro" <<'SH'
#!/bin/sh
case "$*" in
  *test*) exit 0 ;;
  *hierarchy*)
    if [ "$FAKE_DEMO_KIND" = success ]; then
      printf '%s\n' '{"attributes":{"text":"Dashboard"},"children":[]}'
    else
      printf '%s\n' '{"attributes":{"text":"Invalid credentials"},"children":[]}'
    fi ;;
esac
SH
chmod +x "$TMP/bin/maestro"
DEMO="$ROOT/skills/appstore-precheck/scripts/lib/dyn-demo-login.py"
export PRECHECK_DEMO_USERNAME=reviewer@example.invalid PRECHECK_DEMO_PASSWORD=fixture-secret
export PRECHECK_DEMO_SUCCESS_TEXT=Dashboard PRECHECK_DEMO_FAILURE_TEXT='Invalid credentials'
export PRECHECK_DEMO_BACKEND_READY=1 FAKE_DEMO_KIND=success
result="$(PATH="$TMP/bin:$PATH" python3 "$DEMO" FIXTURE-UDID org.example.app)"
[[ "$result" == PASS$'\t'* ]]
[[ "$result" != *fixture-secret* && "$result" != *reviewer@example.invalid* ]]
export FAKE_DEMO_KIND=failure
result="$(PATH="$TMP/bin:$PATH" python3 "$DEMO" FIXTURE-UDID org.example.app)"
[[ "$result" == FINDING$'\t'* ]]
unset PRECHECK_DEMO_BACKEND_READY
result="$(PATH="$TMP/bin:$PATH" python3 "$DEMO" FIXTURE-UDID org.example.app)"
[[ "$result" == SKIP$'\t'* ]]

printf '#!/bin/sh\nexit 1\n' > "$TMP/bin/xcrun"
chmod +x "$TMP/bin/xcrun"
RUN="$ROOT/skills/appstore-precheck/scripts/dynamic-run.sh"
APP="$ROOT/tests/fixtures/dynamic-bundle/Installed.app"
PATH="$TMP/bin:$PATH" bash "$RUN" --app "$APP" --dynamic-blocking \
  --dry-run --out "$TMP/block-plan" > "$TMP/plan.txt" 2>/dev/null
test "$(grep -c 'PLAN: xcrun simctl erase' "$TMP/plan.txt")" -eq 3
PATH="$TMP/bin:$PATH" bash "$RUN" --app "$APP" --dynamic-blocking \
  --repeats 2 --dry-run --out "$TMP/bad-plan" >/dev/null 2>&1 && exit 1

cat > "$TMP/bin/xcrun" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_CALLS"
shift
case "$1" in
  list)
    case "$2" in
      runtimes) printf '%s\n' '{"runtimes":[{"platform":"iOS","isAvailable":true,"version":"26.5","identifier":"iOS-26.5"}]}' ;;
      devicetypes) printf '%s\n' '{"devicetypes":[{"productFamily":"iPhone","name":"iPhone 17","identifier":"iPhone-17"}]}' ;;
    esac ;;
  create) printf 'FIXTURE-UDID\n' ;;
  get_app_container) printf '%s\n' "$FAKE_APP" ;;
  launch) sh -c 'sleep 0.1' >/dev/null 2>&1 & printf 'org.example.app: %s\n' "$!" ;;
  io) exit 1 ;;
  spawn) exit 0 ;;
  *) exit 0 ;;
esac
SH
chmod +x "$TMP/bin/xcrun"
export FAKE_APP="$APP" FAKE_CALLS="$TMP/calls.log"
: > "$FAKE_CALLS"
PATH="$TMP/bin:$PATH" bash "$RUN" --app "$APP" --dynamic-blocking \
  --window 1 --out "$TMP/live-block" > "$TMP/live-block.txt" 2>/dev/null
test "$(grep -c '^FAIL: 2.1 \[dyn-launch\]' "$TMP/live-block.txt")" -eq 1
test "$(grep -c 'simctl erase' "$FAKE_CALLS")" -eq 3
test "$(grep -c 'simctl delete' "$FAKE_CALLS")" -eq 1
: > "$FAKE_CALLS"
PATH="$TMP/bin:$PATH" bash "$RUN" --app "$APP" --window 1 \
  --out "$TMP/live-default" > "$TMP/live-default.txt" 2>/dev/null
test ! "$(grep -c '^FAIL:' "$TMP/live-default.txt")" -gt 0
test "$(grep -c 'simctl erase' "$FAKE_CALLS")" -eq 2

bash "$REVIEW" --screens "$FIX/clean" --max-screens 26 --out "$TMP/invalid" >/dev/null 2>&1 && exit 1
printf 'runtime review fixtures passed\n'
