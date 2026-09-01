#!/usr/bin/env bash
# tests/test-phase6-doc.sh — contract of the Phase 6 (local dynamic simulator tier)
# reference. The tier is agent-mode prose, not code, so this pins the honesty rules
# that were found wrong by the 2026-09-01 research:
#   D3: StoreKit configuration is a scheme Run-action setting; `xcrun simctl launch`
#       does not apply it, so an empty paywall is the EXPECTED default and must be
#       DYNAMIC-SKIP, never DYNAMIC-FINDING.
#   D0: the .app-path branch had no install step and could not be driven as written.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck source=tests/_assert.sh
source "$HERE/_assert.sh"
REF="$ROOT/skills/appstore-precheck/references/simulator-dynamic-review.md"
DOC="$(cat "$REF")"

section "DYNAMIC-SKIP is a defined output class"
assert_contains "$DOC" "DYNAMIC-SKIP:" "DYNAMIC-SKIP prefix documented"
assert_gt "$(grep -c 'DYNAMIC-SKIP' "$REF")" "3" "DYNAMIC-SKIP used in the rules, the D0 step and the D3 check"

section "D3 never invents a paywall finding under simctl launch"
d3="$(awk '/^### D3/,/^### D4/' "$REF")"
assert_contains "$d3" "DYNAMIC-SKIP: 3.1.2" "D3 emits SKIP when no price is visible"
assert_contains "$d3" "simctl launch" "D3 names the cause (StoreKit config is not applied by simctl launch)"
assert_contains "$d3" "Xcode" "D3 explains when prices CAN be observed (launched from Xcode with a StoreKit config)"
assert_absent   "$(grep -i 'no price' <<<"$d3" | grep -i 'FINDING')" "FINDING" "an empty paywall is never a FINDING"

section "D0 installs the .app before anything launches"
d0="$(awk '/^### D0/,/^### D1/' "$REF")"
assert_not_empty "$d0" "D0 step exists"
assert_contains "$d0" "simctl install" "D0 installs the supplied .app"
assert_contains "$d0" "CFBundleIdentifier" "D0 reads the bundle id from Info.plist"
assert_contains "$d0" "plutil" "via plutil, not a guess"
assert_contains "$d0" "DYNAMIC-SKIP" "install failure skips every D-check"

section "device lifecycle is hardened"
assert_absent   "$DOC" "Prefer a disposable simulator" "the soft 'prefer' wording is gone"
assert_contains "$DOC" "simctl create" "the tier creates its own device"
assert_contains "$DOC" "never touches an existing device" "and never uses a pre-existing one"

exit "$fails"
