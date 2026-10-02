#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
# shellcheck source=tests/_assert.sh
source tests/_assert.sh
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
S="$(pwd)/skills/appstore-precheck/scripts"
# shellcheck source=skills/appstore-precheck/scripts/lib/optin-scan.sh
source "$S/lib/optin-scan.sh"
OPT_BUILD=0 OPT_APP=app OPT_DEMO=0 OPT_NO_RUNTIME=0 OPT_DYN_BLOCK=0 OPT_OUT=""
cfg_bool() { echo true; }
APPSTORE_PRECHECK_TRUST_CONFIG=0
optin_trust
assert_eq "$OPT_DEMO" 0 'untrusted repository cannot turn on demo login'
APPSTORE_PRECHECK_TRUST_CONFIG=1
optin_trust
assert_eq "$OPT_DEMO" 1 'trusted config may turn on demo login'
printf x > "$TMP/not-directory"
rc=0
bash "$S/scan.sh" --dir tests/fixtures/clean-app --build --dynamic-blocking --out "$TMP/not-directory" > "$TMP/result" 2>&1 || rc=$?
assert_eq "$rc" 64 'invalid blocking output is usage error'
python3 "$S/augment-json.py" --opt-summary /nonexistent < /dev/null >/dev/null 2>&1
assert_gt "$?" 0 'invalid envelope cannot become an optional report'
exit "$fails"
