#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
# shellcheck source=tests/_assert.sh
source tests/_assert.sh
source skills/appstore-precheck/scripts/lib/dyn-device.sh
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export DYN_OWNED_LEDGER="$TMP/owned-simulators.txt"
printf 'owned-device\n' > "$DYN_OWNED_LEDGER"
dyn_cmd_bounded() { printf '%s\n' "$*" >> "$TMP/calls"; }
dyn_device_teardown foreign-device
assert_eq "$(test -f "$TMP/calls" && cat "$TMP/calls")" '' 'unowned device cannot be deleted'
dyn_device_teardown owned-device
assert_contains "$(cat "$TMP/calls" 2>/dev/null)" 'delete owned-device' 'owned device is deleted'
python3 -B tests/runtime-blocking.py || fails=$((fails + 1))
exit "$fails"
