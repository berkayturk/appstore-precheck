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

# --- Phase 1 additions (machine-readable, honest) -------------------------------------
section "every D-check carries a rule_id the transcript parser can read"
for id in dyn-install dyn-launch dyn-first-screen dyn-paywall-visible dyn-permission-prompt \
          dyn-demo-login dyn-screenshot-parity dyn-restore-tap; do
  assert_contains "$DOC" "$id" "rule id $id documented"
done
assert_contains "$DOC" "[dyn-" "the output format carries the id in brackets"

section "D3b: tap Restore Purchases and expect a non-inert response"
d3b="$(awk '/^### D3b/,/^### D4/' "$REF")"
assert_not_empty "$d3b" "D3b step exists"
assert_contains "$d3b" "accessibilityText" "the button is located via accessibilityText (Maestro hierarchy field)"
assert_contains "$d3b" "DYNAMIC-SKIP" "no button -> SKIP"
assert_contains "$d3b" "receipt" "restore completion requires transaction evidence"

section "launch health is a conjunction of four signals, and a degenerate tree is never a FINDING"
d1="$(awk '/^### D1/,/^### D3 /' "$REF")"
assert_contains "$d1" "process" "signal: process alive"
assert_contains "$d1" "uniform" "signal: screenshot not uniform"
assert_contains "$d1" "log stream" "signal: no crash in log stream"
assert_contains "$d1" "accessibility" "signal: accessibility tree"
assert_contains "$d1" "Flutter" "degenerate tree (Flutter/Compose) named"
assert_contains "$d1" "could not be read" "an unreadable signal is recorded, not assumed"

section "the promise is no-write, not read-only: the tier executes the user's code"
assert_contains "$DOC" "executes your application code" "the honest wording"
assert_absent "$(grep -i 'read-only' "$REF" | grep -vi 'not read-only\|no longer\|was called')" "Read-only w.r.t." "the old read-only heading is gone"
assert_contains "$DOC" "network" "network exposure explained"
assert_contains "$DOC" "credential" "credential exposure explained"
assert_contains "$DOC" "runtime-not-audited" "the gap record for a run without a build"
assert_contains "$DOC" "dynamic.sh" "the transcript is fed to dynamic.sh"
sec="$(cat "$ROOT/SECURITY.md")"
assert_contains "$sec" "executes" "SECURITY.md says Phase 6 executes application code"

# --- Phase 2 additions (discovery, framework awareness, determinism) -------------------
section "Phase 2: every new observation has a rule id in the reference"
for id in dyn-dark-mode dyn-dynamic-type dyn-ipad-layout dyn-shipped-bundle dyn-shipped-sdk \
          dyn-shipped-links dyn-hosts-contacted; do
  assert_contains "$DOC" "$id" "rule id $id documented"
done
# The reference and dynamic.sh must agree on the catalogue: every id dynamic.sh knows is in the doc.
while IFS= read -r id; do
  assert_contains "$DOC" "$id" "catalogue id $id appears in the reference"
done < <(sed -n '/^dyn_catalogue() {/,/^}/p' "$ROOT/skills/appstore-precheck/scripts/dynamic.sh" | grep -oE 'dyn-[a-z-]+' | sort -u)

section "Phase 2: determinism policy is written down"
assert_contains "$DOC" "N=3" "three repeats"
assert_contains "$DOC" "3/3" "a crash finding needs every repeat"
assert_contains "$DOC" "not unanimous" "a mixed result carries its ratio"
assert_contains "$DOC" "erase" "erase between repeats"
assert_contains "$DOC" "status_bar" "deterministic status bar"
assert_contains "$DOC" "9:41" "…Apple's clock"
assert_contains "$DOC" "privacy" "privacy reset"
assert_contains "$DOC" "--terminate-running-process" "launch terminates a running instance"
assert_contains "$DOC" "One flow per Maestro invocation" "one flow per call (iOS 26 driver)"
assert_contains "$DOC" "accessibilityText" "labels are read from accessibilityText"
assert_contains "$DOC" "driver timeout" "a driver timeout is a SKIP"

section "Phase 2: discovery, never a build"
assert_contains "$DOC" "app-discover.sh" "discovery script named"
assert_contains "$DOC" "explicit confirmation" "the user confirms a candidate"
assert_contains "$DOC" "never builds" "the tier never builds"
assert_contains "$DOC" "directory name" "build config comes from the directory name"

section "Phase 2: framework awareness"
assert_contains "$DOC" "framework-detect.sh" "detector named"
assert_contains "$DOC" "Metro" "RN needs Metro for a Debug build"
assert_contains "$DOC" "8081" "…on port 8081"
assert_contains "$DOC" "framework-not-audited" "the static gap record is cross-referenced"
assert_contains "$DOC" "measured accessibility" "selector capability is observed, not inferred from framework"
assert_contains "$DOC" "pktap" "the Flutter host blind spot has an opt-in remedy"

exit "$fails"
