#!/usr/bin/env bash
# tests/test-dynamic-run.sh — dynamic-run.sh end to end WITHOUT a simulator: `xcrun`,
# `maestro` and `otool` are shims that record every call and act out a scenario
# (healthy / crash on every launch / crash once), so CI pins the device lifecycle
# order, the N=3 erase-between-repeats policy, delete-only-what-we-created, the
# quorum, the Metro guard, the Flutter/KMP pre-SKIPs and the dry-run plan. The
# only real code paths are the runner's own and png-uniform.py on real PNGs.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck source=tests/_assert.sh
source "$HERE/_assert.sh"
S="$ROOT/skills/appstore-precheck/scripts"
RUN="$S/dynamic-run.sh"
FX="$HERE/fixtures"
T="$(mktemp -d)"
SHIM="$T/shim"; mkdir -p "$SHIM"
export FAKE_CALLS="$T/calls.log" FAKE_PIDS="$T/pids" FAKE_SCENARIO=pass FAKE_PNG="$T/varied.png" FAKE_APP=""
export FAKE_COUNTER="$T/launches"

# A varied PNG for the screenshot shim (a flat one would be a "hung splash").
python3 - "$FAKE_PNG" <<'PY'
import sys, zlib, struct
w = h = 32
def chunk(t, d):
    b = t + d; return struct.pack('>I', len(d)) + b + struct.pack('>I', zlib.crc32(b) & 0xffffffff)
rows = b''.join(b'\x00' + b''.join(bytes([(x*8)&255, (y*8)&255, 128]) for x in range(w)) for y in range(h))
open(sys.argv[1], 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b''))
PY

cat > "$SHIM/xcrun" <<'EOF'
#!/usr/bin/env bash
# fake xcrun: records "simctl <verb> …" and acts out $FAKE_SCENARIO
printf '%s\n' "$*" >> "$FAKE_CALLS"
shift   # simctl
case "$1" in
  list)
    case "$2" in
      runtimes)    echo '{"runtimes":[{"platform":"iOS","isAvailable":true,"version":"26.5","identifier":"com.apple.CoreSimulator.SimRuntime.iOS-26-5"}]}' ;;
      devicetypes) echo '{"devicetypes":[{"productFamily":"iPhone","name":"iPhone 16","identifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-16"},{"productFamily":"iPhone","name":"iPhone 17","identifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-17"},{"productFamily":"iPhone","name":"iPod touch (7th generation)","identifier":"com.apple.CoreSimulator.SimDeviceType.iPod-touch--7th-generation-"},{"productFamily":"iPad","name":"iPad Pro 11-inch (M5)","identifier":"com.apple.CoreSimulator.SimDeviceType.iPad-Pro-11-inch-M5"}]}' ;;
    esac ;;
  create) echo "FAKE-UDID-$(( RANDOM ))" ;;
  install) [[ -d "$3" ]] || { echo "Unable to install: not a bundle" >&2; exit 1; } ;;
  get_app_container) echo "$FAKE_APP" ;;
  launch)
    n=0; [[ -f "$FAKE_COUNTER" ]] && n="$(cat "$FAKE_COUNTER")"; n=$((n+1)); echo "$n" > "$FAKE_COUNTER"
    case "$FAKE_SCENARIO" in
      crash) sh -c 'sleep 0.2' >/dev/null 2>&1 & ;;
      mixed) if [[ "$n" -eq 2 ]]; then sh -c 'sleep 0.2' >/dev/null 2>&1 & else sleep 20 >/dev/null 2>&1 & fi ;;
      *) sleep 20 >/dev/null 2>&1 & ;;
    esac
    pid=$!; echo "$pid" >> "$FAKE_PIDS"; echo "$4: $pid" ;;
  io) cp "$FAKE_PNG" "$5" ;;
  spawn) exec sleep 3600 ;;
  boot|bootstatus|status_bar|privacy|shutdown|erase|delete|ui) exit 0 ;;
  *) exit 0 ;;
esac
EOF
cat > "$SHIM/maestro" <<EOF
#!/usr/bin/env bash
printf 'maestro %s\n' "\$*" >> "$FAKE_CALLS"
cat "$FX/dynamic-hierarchies/clean.json"
EOF
cat > "$SHIM/otool" <<'EOF'
#!/bin/sh
printf '%s:\n\t/System/Library/Frameworks/UIKit.framework/UIKit (compatibility version 1.0.0)\n' "$2"
EOF
for t in xcodebuild flutter gradle; do printf '#!/bin/sh\necho %s >> "%s"\n' "$t" "$T/built" > "$SHIM/$t"; done
chmod +x "$SHIM"/*
export PATH="$SHIM:$PATH"

# The app under test: the bundle fixture placed under a Debug-iphonesimulator directory.
mkdir -p "$T/Debug-iphonesimulator"; cp -R "$FX/dynamic-bundle/Installed.app" "$T/Debug-iphonesimulator/"
APP="$T/Debug-iphonesimulator/Installed.app"; export FAKE_APP="$APP"
REPO="$T/repo"; mkdir -p "$REPO/ios/App"; cp "$FX/dynamic-bundle/repo/Info.plist" "$REPO/ios/App/Info.plist"

reset_calls() { : > "$FAKE_CALLS"; rm -f "$FAKE_COUNTER"; }
kill_fakes() { [[ -f "$FAKE_PIDS" ]] && { while read -r p; do kill "$p" 2>/dev/null; done < "$FAKE_PIDS"; : > "$FAKE_PIDS"; }; return 0; }
first_idx() { grep -n -- "$1" "$FAKE_CALLS" | head -1 | cut -d: -f1; }
count() { grep -c -- "$1" "$FAKE_CALLS"; }

# ---------------------------------------------------------------------------------
section "healthy app: lifecycle order, three repeats, delete only what we created"
reset_calls; FAKE_SCENARIO=pass
OUT1="$T/out1"
tx="$(bash "$RUN" --app "$APP" --repo "$REPO" --repeats 3 --window 1 --out "$OUT1" 2>"$T/err1")"; st=$?
kill_fakes
assert_eq "0" "$st" "exit 0"
[[ "$st" == 0 ]] || { echo "  runner stderr:"; sed 's/^/    /' "$T/err1"; }
assert_contains "$tx" "DYNAMIC-PASS: setup [dyn-install]" "D0 PASS"
assert_contains "$tx" "Debug-iphonesimulator/Installed.app" "D0 names the parent directory (dynamic.sh corroborates --build-config against it)"
assert_contains "$tx" "created by this run" "D0 says the device is ours"
assert_contains "$tx" "DYNAMIC-PASS: 2.1 [dyn-launch] — quorum 3/3 passed" "D1 quorum 3/3"
assert_contains "$tx" "process alive" "…with the signals"
assert_contains "$tx" "DYNAMIC-PASS: 2.1 [dyn-first-screen] — quorum 3/3 passed" "D2 quorum"
assert_contains "$tx" "DYNAMIC-PASS: 5.1.1 [dyn-shipped-bundle:NSCameraUsageDescription]" "shipped plist per-key line"
assert_contains "$tx" "DYNAMIC-FINDING: 5.1.1 [dyn-shipped-bundle:NSPhotoLibraryUsageDescription]" "repo-vs-bundle drift found (repo plist auto-located by bundle id)"
assert_contains "$tx" "DYNAMIC-PASS: 2.1 [dyn-shipped-sdk] — installed Info.plist: DTXcode=2660" "SDK line"
assert_contains "$tx" "DYNAMIC-PASS: 2.5.1 [dyn-shipped-links]" "otool line (shimmed clean)"
assert_contains "$tx" "DYNAMIC-PASS: 4.0 [dyn-dark-mode]" "dark-mode geometry over the (clean) hierarchy"
assert_contains "$tx" "DYNAMIC-PASS: 4.0 [dyn-dynamic-type]" "Dynamic Type geometry"
assert_contains "$tx" "DYNAMIC-SKIP: 5.1.2 [dyn-hosts-contacted]" "no host in an empty log -> SKIP"
assert_contains "$tx" "# agent: selector-based checks left for Maestro MCP" "native: selector checks handed to the agent"
assert_absent "$tx" "DYNAMIC-SKIP: 3.1.2 [dyn-restore-tap]" "native: no pre-SKIP"
# order
c="$(first_idx 'simctl create')"; b="$(first_idx 'simctl boot')"; bs="$(first_idx 'simctl bootstatus')"
sb="$(first_idx 'simctl status_bar')"; pr="$(first_idx 'simctl privacy')"; in="$(first_idx 'simctl install')"; la="$(first_idx 'simctl launch')"
assert_gt "$b" "$c" "create before boot"; assert_gt "$bs" "$b" "boot before bootstatus -b"
assert_gt "$sb" "$bs" "bootstatus before status_bar"; assert_gt "$pr" "$sb" "status_bar before privacy reset"
assert_gt "$in" "$pr" "privacy reset before install"; assert_gt "$la" "$in" "install before launch"
assert_contains "$(grep 'simctl bootstatus' "$FAKE_CALLS" | head -1)" " -b" "bootstatus waits with -b"
assert_contains "$(grep 'simctl status_bar' "$FAKE_CALLS" | head -1)" "override --time 9:41 --batteryLevel 100" "deterministic status bar"
assert_contains "$(grep 'simctl privacy' "$FAKE_CALLS" | head -1)" "reset all" "every grant reset"
assert_contains "$(grep 'simctl launch' "$FAKE_CALLS" | head -1)" "--terminate-running-process" "launch terminates a running instance"
assert_eq "3" "$(count 'simctl launch')" "three launches"
assert_eq "2" "$(count 'simctl erase')" "erased between repeats (N-1 times)"
assert_eq "3" "$(count 'simctl install')" "re-installed after each erase"
assert_eq "5" "$(count 'simctl io .* screenshot')" "a screenshot per repeat (3) plus dark mode and Dynamic Type"
assert_eq "1" "$(count 'simctl delete')" "exactly one delete"
udid="$(grep -oE 'simctl install (FAKE-UDID-[0-9]+)' "$FAKE_CALLS" | head -1 | awk '{print $3}')"
assert_contains "$(grep 'simctl delete' "$FAKE_CALLS")" "$udid" "…and it deletes the device this run created"
assert_gt "$(first_idx 'simctl delete')" "$(grep -n 'simctl launch' "$FAKE_CALLS" | tail -1 | cut -d: -f1)" "delete comes last"
assert_contains "$(grep 'simctl ui' "$FAKE_CALLS")" "appearance dark" "dark appearance switched on"
assert_contains "$(grep 'simctl ui' "$FAKE_CALLS")" "appearance light" "…and back"
assert_contains "$(grep 'simctl ui' "$FAKE_CALLS")" "content_size accessibility-extra-extra-extra-large" "AX5 text size"
assert_eq "$(count 'maestro')" "$(grep -c 'hierarchy' "$FAKE_CALLS")" "every Maestro invocation is a single hierarchy read (one flow per call)"
[[ -e "$T/built" ]] && { echo "  FAIL: a build tool ran"; fails=$((fails+1)); } || echo "  ok: no xcodebuild / flutter / gradle invocation"
assert_eq "debug" "$(jq -r .build_config "$OUT1/run.json")" "run.json: build_config from the directory name"
assert_eq "true" "$(jq -r .device.created_by_this_run "$OUT1/run.json")" "run.json: device ownership"
assert_eq "3" "$(jq -r .launch.pass "$OUT1/run.json")" "run.json: launch tally"
assert_eq "3" "$(jq -r '.d1_d2_seconds | length' "$OUT1/run.json")" "run.json: D1+D2 durations recorded per repeat"
assert_eq "3" "$(jq -r '.timing.observation_seconds | length' "$OUT1/run.json")" "run.json: separate pure observation durations recorded"
assert_eq "true" "$(jq '[range(0;3) as $i | .d1_d2_seconds[$i] >= .timing.observation_seconds[$i]] | all' "$OUT1/run.json")" "legacy duration retains lifecycle overhead"
assert_contains "$(jq -r .next "$OUT1/run.json")" "--build-config debug" "run.json: the dynamic.sh command carries the config"
assert_eq "$(grep -c '^DYNAMIC-' "$OUT1/transcript.txt")" "$(grep -c '^DYNAMIC-' <<<"$tx")" "transcript file mirrors stdout"

section "the transcript reconciles through dynamic.sh (debug guard intact)"
recs="$(bash "$S/dynamic.sh" --transcript "$OUT1/transcript.txt" --target simulator --build-config debug --format jsonl)"
assert_eq "0" "$(jq -r 'select(.severity!="SKIP" and .confidence==null) | .rule_id' <<<"$recs" | grep -c .)" "every observation is under a catalogued id"
assert_eq "true" "$(jq -r 'select(.rule_id=="dyn-shipped-bundle:NSPhotoLibraryUsageDescription") | .needs_build_verification' <<<"$recs")" "a validator-blocking runtime WARN on a Debug bundle still needs build verification"
bash "$S/dynamic.sh" --transcript "$OUT1/transcript.txt" --build-config release >/dev/null 2>"$T/warn"
assert_contains "$(cat "$T/warn")" "Debug-iphonesimulator" "claiming release over this transcript is caught by the D0 line"

# ---------------------------------------------------------------------------------
section "crash on every launch: FINDING 3/3, layout not judged"
reset_calls; FAKE_SCENARIO=crash
tx="$(bash "$RUN" --app "$APP" --repeats 3 --window 1 --out "$T/out2" 2>/dev/null)"; kill_fakes
assert_contains "$tx" "DYNAMIC-FINDING: 2.1 [dyn-launch] — quorum 3/3: failed on every launch" "unanimous crash -> FINDING"
assert_contains "$tx" "process gone" "…with the failing signal"
assert_contains "$tx" "DYNAMIC-FINDING: 2.1 [dyn-first-screen]" "no first screen either"
assert_contains "$tx" "DYNAMIC-SKIP: 4.0 [dyn-dark-mode] — app did not stay up" "geometry SKIPped, not invented"
assert_eq "1" "$(count 'simctl delete')" "device still deleted after failures"

section "crash once: FINDING with its ratio, never unanimous"
reset_calls; FAKE_SCENARIO=mixed
tx="$(bash "$RUN" --app "$APP" --repeats 3 --window 1 --out "$T/out3" 2>/dev/null)"; kill_fakes
assert_contains "$tx" "DYNAMIC-FINDING: 2.1 [dyn-launch] — quorum 1/3: failed on 1 of 3 launches (not unanimous" "1/3 -> ratio in the line"
assert_contains "$tx" "DYNAMIC-PASS: 4.0 [dyn-dark-mode]" "the app stayed up on some launches, so layout is judged"

# ---------------------------------------------------------------------------------
section "React Native without Metro: launch checks SKIP, bundle checks still run"
reset_calls; FAKE_SCENARIO=pass
RN="$T/rn"; cp -R "$FX/rn-app" "$RN"
tx="$(bash "$RUN" --app "$APP" --repo "$RN" --repeats 3 --window 1 --out "$T/out4" 2>/dev/null)"; kill_fakes
assert_contains "$tx" "DYNAMIC-SKIP: 2.1 [dyn-launch] — Metro bundler not running" "Metro guard"
assert_contains "$tx" "main.jsbundle" "…explains the embedded-bundle alternative"
assert_eq "0" "$(count 'simctl launch')" "no launch attempted"
assert_gt "$(count 'simctl install')" "0" "installed anyway (shipped-bundle reads need the container)"
assert_contains "$tx" "DYNAMIC-PASS: 2.1 [dyn-shipped-sdk]" "shipped-bundle lines still produced"
assert_contains "$tx" "DYNAMIC-SKIP: 4.0 [dyn-dark-mode]" "layout SKIP"
assert_eq "true" "$(jq -r .metro_skipped "$T/out4/run.json")" "run.json records the Metro skip"
# An embedded bundle needs no Metro.
mkdir -p "$T/Release-iphonesimulator"; cp -R "$APP" "$T/Release-iphonesimulator/"; : > "$T/Release-iphonesimulator/Installed.app/main.jsbundle"
reset_calls
tx="$(FAKE_APP="$T/Release-iphonesimulator/Installed.app" bash "$RUN" --app "$T/Release-iphonesimulator/Installed.app" --repo "$RN" --repeats 2 --window 1 --out "$T/out5" 2>/dev/null)"; kill_fakes
assert_eq "2" "$(count 'simctl launch')" "with main.jsbundle the launches happen (and --repeats 2 is honoured)"
assert_eq "release" "$(jq -r .build_config "$T/out5/run.json")" "Release-iphonesimulator -> release"

section "Flutter: unexecuted selector checks retain measured accessibility scope"
reset_calls
FL="$T/fl"; cp -R "$FX/flutter-app" "$FL"
tx="$(bash "$RUN" --app "$APP" --repo "$FL" --repeats 1 --window 1 --out "$T/out6" 2>/dev/null)"; kill_fakes
assert_contains "$tx" "DYNAMIC-SKIP: 3.1.2 [dyn-restore-tap] — flutter accessibility tree observed" "D3b scoped SKIP"
assert_contains "$tx" "DYNAMIC-SKIP: 2.1 [dyn-demo-login]" "D5 pre-SKIP"
assert_contains "$tx" "DYNAMIC-SKIP: 5.1.1(ii) [dyn-permission-prompt]" "D4 trigger half pre-SKIP"
assert_contains "$tx" "dedicated selector flows were not executed" "…with the actual flow limitation"
assert_absent "$tx" "not driveable on flutter" "healthy tree is not labeled undriveable"
assert_contains "$tx" "DYNAMIC-PASS: 2.1 [dyn-launch]" "observation-based D1 still runs"
assert_contains "$tx" "Dart HttpClient bypasses CFNetwork" "empty host list on Flutter names the CFNetwork blind spot"
assert_contains "$tx" "--pktap" "…and the opt-in remedy"

section "--udid mode: a user device is never created, erased or deleted"
reset_calls
tx="$(bash "$RUN" --udid USER-DEVICE-1 --bundle-id com.example.installed --repeats 2 --window 1 --out "$T/out7" 2>/dev/null)"; kill_fakes
assert_contains "$tx" "not created by this run: never erased, reset or deleted" "D0 states the ownership"
assert_eq "0" "$(count 'simctl create')" "no create"
assert_eq "0" "$(count 'simctl erase')" "no erase"
assert_eq "0" "$(count 'simctl delete')" "no delete"
assert_eq "0" "$(count 'simctl privacy')" "no privacy reset on a user device"
assert_eq "2" "$(count 'simctl launch')" "relaunched twice"

section "--dry-run prints the plan and touches nothing"
reset_calls
tx="$(bash "$RUN" --app "$APP" --repo "$REPO" --repeats 3 --window 5 --ipad --dry-run --out "$T/out8" 2>&1)"; st=$?
assert_eq "0" "$st" "exit 0"
assert_eq "0" "$(grep -c . "$FAKE_CALLS")" "no simctl / maestro call was made"
assert_contains "$tx" "PLAN: xcrun simctl create precheck-" "plans the create"
assert_contains "$tx" "PLAN: xcrun simctl bootstatus UDID-PLAN" "plans bootstatus"
assert_contains "$tx" "PLAN: xcrun simctl status_bar UDID-PLAN" "plans the status bar"
assert_contains "$tx" "PLAN: xcrun simctl privacy UDID-PLAN" "plans privacy reset"
assert_contains "$tx" "PLAN: xcrun simctl install UDID-PLAN" "plans the install"
assert_eq "4" "$(grep -c 'PLAN: SIMCTL_CHILD_CFNETWORK_DIAGNOSTICS=3 xcrun simctl launch --terminate-running-process' <<<"$tx")" "three iPhone launches + one iPad launch planned, each with CFNetwork diagnostics"
assert_eq "2" "$(grep -c 'PLAN: xcrun simctl erase' <<<"$tx")" "two erases planned"
assert_contains "$tx" "PLAN: xcrun simctl delete UDID-PLAN" "plans the delete of the created device"
assert_contains "$tx" "PLAN: maestro --device UDID-PLAN" "plans the hierarchy reads"
assert_contains "$tx" "one Maestro invocation, one flow" "…one flow per call"
assert_contains "$tx" "PLAN: sleep 5   # observation window" "window honoured"
assert_contains "$tx" "DYNAMIC-SKIP: 2.4.1 [dyn-ipad-layout] — dry run" "iPad step planned, observed nothing"
assert_absent "$tx" "xcodebuild" "no build in the plan"
assert_eq "true" "$(jq -r .dry_run "$T/out8/run.json")" "run.json says dry run"

section "argument validation"
bash "$RUN" --app "$APP" --repeats 0 >/dev/null 2>&1; st=$?; assert_eq "64" "$st" "--repeats 0 rejected"
bash "$RUN" >/dev/null 2>&1; st=$?; assert_eq "64" "$st" "no --app / --udid rejected"
bash "$RUN" --udid X >/dev/null 2>&1; st=$?; assert_eq "64" "$st" "--udid without --bundle-id rejected"
bash "$RUN" --app "$T/nonexistent.app" >/dev/null 2>&1; st=$?; assert_eq "66" "$st" "missing .app is exit 66"
bash "$RUN" --app "$APP" --framework cordova >/dev/null 2>&1; st=$?; assert_eq "64" "$st" "unknown framework rejected"

section "deadline and cancellation clean the owned simulator"
reset_calls
PRECHECK_RUNTIME_DEADLINE_SECONDS=3 bash "$RUN" --app "$APP" --window 60 --out "$T/deadline" > "$T/deadline.txt" 2>/dev/null
st=$?
assert_eq "124" "$st" "deadline has an explicit timeout status"
assert_eq "1" "$(count 'simctl delete')" "deadline runs owned-device cleanup"
assert_eq "$(cat "$T/deadline/owned-simulators.txt")" "$(cat "$T/deadline/deleted-simulators.txt")" "deadline ownership ledger matches successful deletion"
kill_fakes
reset_calls
bash "$RUN" --app "$APP" --window 60 --out "$T/cancel" > "$T/cancel.txt" 2>/dev/null & runner_pid=$!
for _ in {1..100}; do
  [[ -s "$T/cancel/owned-simulators.txt" ]] && grep -q 'simctl launch' "$FAKE_CALLS" && break
  sleep 0.05
done
kill -TERM "$runner_pid"
wait "$runner_pid"; st=$?
assert_eq "143" "$st" "cancel has an explicit cancellation status"
assert_eq "1" "$(count 'simctl delete')" "cancel runs owned-device cleanup"
kill_fakes

section "the runner never contains a build invocation"
assert_eq "0" "$(grep -vE '^\s*#' "$RUN" "$S"/lib/dyn-*.sh | grep -E '(^|[;&|] *|\$\()(xcodebuild|flutter build|gradle)' | grep -c . | tr -d ' ')" "no xcodebuild / flutter build / gradle command in the runner or its libs"

kill_fakes
rm -rf "$T"
exit "$fails"
