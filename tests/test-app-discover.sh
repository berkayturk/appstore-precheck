#!/usr/bin/env bash
# tests/test-app-discover.sh — app-discover.sh: find simulator .app candidates the USER
# already built, describe them (mtime, Debug/Release from the directory name, bundle id),
# recommend the newest, and stop. It never builds and never launches: the acceptance
# for the whole dynamic tier is that no xcodebuild / flutter / gradle ever runs from
# this repo's scripts. A shim PATH proves it.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck source=tests/_assert.sh
source "$HERE/_assert.sh"
AD="$ROOT/skills/appstore-precheck/scripts/app-discover.sh"
FX="$HERE/fixtures"

# A fake DerivedData tree + a fake Flutter build dir; XML plists so the parse works on
# ubuntu (no plutil) exactly as on macOS.
plist() { # plist <path> <bundle-id> <executable>
  cat > "$1" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>$3</string>
  <key>CFBundleIdentifier</key><string>$2</string>
  <key>DTXcode</key><string>2660</string>
  <key>DTSDKName</key><string>iphonesimulator26.5</string>
</dict></plist>
EOF
}
DD="$(mktemp -d)"
mkdir -p "$DD/AppA-abc/Build/Products/Debug-iphonesimulator/AppA.app" \
         "$DD/AppB-def/Build/Products/Release-iphonesimulator/AppB.app" \
         "$DD/Broken-ghi/Build/Products/Debug-iphonesimulator/Broken.app"
plist "$DD/AppA-abc/Build/Products/Debug-iphonesimulator/AppA.app/Info.plist" com.example.a AppA
plist "$DD/AppB-def/Build/Products/Release-iphonesimulator/AppB.app/Info.plist" com.example.b AppB
: > "$DD/Broken-ghi/Build/Products/Debug-iphonesimulator/Broken.app/README"   # no Info.plist
touch -t 202601010900 "$DD/AppA-abc/Build/Products/Debug-iphonesimulator/AppA.app"
touch -t 202606011200 "$DD/AppB-def/Build/Products/Release-iphonesimulator/AppB.app"
REPO="$(mktemp -d)"; cp -R "$FX/flutter-app/." "$REPO/"
mkdir -p "$REPO/build/ios/iphonesimulator/Runner.app"
plist "$REPO/build/ios/iphonesimulator/Runner.app/Info.plist" com.example.flutterapp Runner
touch -t 202603010900 "$REPO/build/ios/iphonesimulator/Runner.app"

section "candidates: every simulator .app with an Info.plist, newest first"
j="$(bash "$AD" --repo "$REPO" --derived-data "$DD" --json)"; st=$?
assert_eq "0" "$st" "exit 0 when candidates exist"
assert_eq "3" "$(jq '.candidates|length' <<<"$j")" "three candidates (the plist-less bundle is not one)"
assert_eq "com.example.b" "$(jq -r '.candidates[0].bundle_id' <<<"$j")" "newest first"
assert_eq "com.example.flutterapp" "$(jq -r '.candidates[1].bundle_id' <<<"$j")" "…then the Flutter build dir"
assert_eq "com.example.a" "$(jq -r '.candidates[2].bundle_id' <<<"$j")" "…oldest last"
assert_eq "release" "$(jq -r '.candidates[0].build_config' <<<"$j")" "Release-iphonesimulator -> release"
assert_eq "debug"   "$(jq -r '.candidates[2].build_config' <<<"$j")" "Debug-iphonesimulator -> debug"
assert_eq "unknown" "$(jq -r '.candidates[1].build_config' <<<"$j")" "build/ios/iphonesimulator carries no configuration in its name -> unknown, never guessed"
assert_eq "AppB" "$(jq -r '.candidates[0].name' <<<"$j")" "bundle name from the .app basename"
assert_contains "$(jq -r '.candidates[0].mtime_iso' <<<"$j")" "2026-06-01" "mtime rendered as a date a human can compare"
assert_eq "true" "$(jq '.candidates[0].mtime_epoch > .candidates[2].mtime_epoch' <<<"$j")" "epoch mtime present and ordered"
assert_eq "flutter" "$(jq -r .framework <<<"$j")" "framework detected from --repo"

section "the recommendation is the newest candidate and is only a recommendation"
assert_eq "com.example.b" "$(jq -r '.recommended.bundle_id' <<<"$j")" "recommended = newest"
assert_eq "release" "$(jq -r '.recommended.build_config' <<<"$j")" "recommended carries the build_config dynamic.sh needs"
assert_eq "false" "$(jq -r '.launched' <<<"$j")" "nothing was launched"
assert_contains "$(jq -r '.confirm' <<<"$j")" "confirm" "the envelope tells the agent to ask for explicit confirmation"
t="$(bash "$AD" --repo "$REPO" --derived-data "$DD")"
assert_contains "$t" "AppB.app" "text output lists the candidate"
assert_contains "$t" "release" "…with its configuration"
assert_contains "$t" "Recommended" "…and marks the recommendation"
assert_contains "$t" "explicit" "…and says to confirm before anything runs"

section "a Debug .app is reported as debug so the Phase 1 qualifier is never cleared by it"
j1="$(bash "$AD" --repo "$FX/clean-app" --derived-data "$DD" --json)"
assert_eq "debug" "$(jq -r '[.candidates[]|select(.bundle_id=="com.example.a")][0].build_config' <<<"$j1")" "Debug stays debug"
assert_contains "$(jq -r '.candidates[0].path' <<<"$j1")" "-iphonesimulator/" "path points at the simulator product"

section "no candidates: exit 3, runtime-not-audited, and a build hint we will NOT run"
E="$(mktemp -d)"
out="$(bash "$AD" --repo "$FX/clean-app" --derived-data "$E" 2>&1)"; st=$?
assert_eq "3" "$st" "exit 3 when nothing is found"
assert_contains "$out" "runtime-not-audited" "names the gap record the run will carry"
assert_contains "$out" "xcodebuild -sdk iphonesimulator" "native: the copy-paste hint is an xcodebuild simulator build"
assert_contains "$out" "-derivedDataPath" "…into a path of the user's choosing"
assert_contains "$out" "will not run" "and says plainly that this tool does not run it"
out="$(bash "$AD" --repo "$FX/flutter-app" --derived-data "$E" 2>&1)"
assert_contains "$out" "flutter build ios --simulator" "flutter: the hint is the flutter simulator build"
out="$(bash "$AD" --repo "$FX/rn-app" --derived-data "$E" 2>&1)"
assert_contains "$out" "expo prebuild" "rn: the hint mentions expo prebuild for managed projects"
assert_contains "$out" "Metro" "rn: and that a Debug build needs Metro"
out="$(bash "$AD" --repo "$FX/kmp-app" --derived-data "$E" 2>&1)"
assert_contains "$out" "iosApp" "kmp: the hint points at the iosApp Xcode project"
j="$(bash "$AD" --repo "$FX/clean-app" --derived-data "$E" --json 2>/dev/null)"
assert_eq "0" "$(jq '.candidates|length' <<<"$j")" "json: empty candidates"
assert_eq "null" "$(jq -r '.recommended' <<<"$j")" "json: no recommendation"
assert_contains "$(jq -r '.build_hint' <<<"$j")" "xcodebuild" "json: hint carried as data"
rm -rf "$E"

section "an explicit --framework overrides detection (the agent may know better)"
j="$(bash "$AD" --repo "$FX/clean-app" --derived-data "$DD" --framework rn --json)"
assert_eq "rn" "$(jq -r .framework <<<"$j")" "override honoured"
bash "$AD" --repo "$FX/clean-app" --derived-data "$DD" --framework cordova >/dev/null 2>&1; st=$?
assert_eq "64" "$st" "an unknown framework word is rejected"

section "discovery never builds, never launches"
shim="$(mktemp -d)"; marker="$shim/ran"
for tool in xcodebuild flutter gradle xcrun maestro simctl open; do
  printf '#!/bin/sh\necho %s >> "%s"\n' "$tool" "$marker" > "$shim/$tool"; chmod +x "$shim/$tool"
done
PATH="$shim:$PATH" bash "$AD" --repo "$REPO" --derived-data "$DD" --json >/dev/null
PATH="$shim:$PATH" bash "$AD" --repo "$FX/clean-app" --derived-data "$(mktemp -d)" >/dev/null 2>&1
[[ -e "$marker" ]] && { echo "  FAIL: a toolchain was invoked: $(tr '\n' ' ' < "$marker")"; fails=$((fails+1)); } || echo "  ok: no build or launch tool was invoked"
rm -rf "$shim"
# The word xcodebuild appears in the script only inside the hint text, never as a command.
assert_eq "0" "$(grep -vE '^\s*#' "$AD" | grep -E '^\s*xcodebuild|\$\(xcodebuild|; *xcodebuild|&& *xcodebuild|\| *xcodebuild' | grep -c . | tr -d ' ')" "no xcodebuild invocation in the script"

section "the repo is not written to"
before="$(find "$REPO" -type f | sort | md5sum 2>/dev/null || find "$REPO" -type f | sort | md5)"
bash "$AD" --repo "$REPO" --derived-data "$DD" --json >/dev/null
after="$(find "$REPO" -type f | sort | md5sum 2>/dev/null || find "$REPO" -type f | sort | md5)"
assert_eq "$before" "$after" "no file added under the repo"

rm -rf "$DD" "$REPO"
exit "$fails"
