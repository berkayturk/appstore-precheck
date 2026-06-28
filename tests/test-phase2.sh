#!/usr/bin/env bash
# tests/test-phase2.sh — unit tests for the Phase 2 wrapper (phase2-precheck.sh).
# Secret-free: uses --dry-run with fake credentials, so it never calls Apple and
# needs no real key. Verifies the key-JSON shape, the command construction, the
# token cleanup, and the required-input errors.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/_assert.sh
source "$DIR/_assert.sh"
P2="$DIR/../skills/appstore-precheck/scripts/phase2-precheck.sh"

# Fake credentials. ASC_P8_PATH is a non-existent path, so --dry-run treats its
# value as literal key text — no real .p8 required.
export ASC_KEY_ID="TESTKEYID"
export ASC_ISSUER_ID="00000000-test-issuer"
export ASC_P8_PATH="-----BEGIN PRIVATE KEY-----FAKEKEYMATERIAL-----END PRIVATE KEY-----"

section "dry-run builds the command and validates the key JSON"
out="$(bash "$P2" --dry-run com.example.app 2>&1)"; code=$?
assert_eq "$code" "0" "dry-run exits 0"
assert_contains "$out" "DRY-RUN: would run: fastlane run precheck" "prints the precheck command"
assert_contains "$out" "app_identifier:com.example.app"            "app identifier wired in"
assert_contains "$out" "include_in_app_purchases:false"            "IAP excluded (covered by Phase 1)"
assert_contains "$out" "default_rule_level::error"                 "rule level set to error"
assert_contains "$out" "api_key_path:"                             "api_key_path points at the built key"
assert_contains "$out" "key json OK"                               "key JSON has key_id/issuer_id/key"

section "app identifier via APP_IDENTIFIER env also works"
out="$(APP_IDENTIFIER=com.env.app bash "$P2" --dry-run 2>&1)"
assert_contains "$out" "app_identifier:com.env.app" "APP_IDENTIFIER honored"

section "no key file is left behind"
before=$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'asc-key.*' 2>/dev/null | wc -l | tr -d ' ')
bash "$P2" --dry-run com.example.app >/dev/null 2>&1
after=$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'asc-key.*' 2>/dev/null | wc -l | tr -d ' ')
assert_eq "$after" "$before" "temp key JSON is cleaned up on exit"

section "missing required input fails loudly"
rc=0; ( unset ASC_KEY_ID; bash "$P2" --dry-run com.example.app ) >/dev/null 2>&1 || rc=$?
assert_eq "$( (( rc != 0 )) && echo nonzero || echo zero )" "nonzero" "missing ASC_KEY_ID exits non-zero"
rc=0; bash "$P2" --dry-run >/dev/null 2>&1 || rc=$?
assert_eq "$rc" "64" "missing app identifier exits 64"
rc=0; bash "$P2" --bogus com.example.app >/dev/null 2>&1 || rc=$?
assert_eq "$rc" "64" "unknown option exits 64"

echo
if (( fails == 0 )); then echo "test-phase2: ALL PASSED"; else echo "test-phase2: $fails FAILED"; fi
exit "$fails"
