#!/usr/bin/env bash
# Portable command-plan and source-isolation fixtures for the opt-in build runner.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
source "$HERE/_assert.sh"
RUN="$ROOT/skills/appstore-precheck/scripts/build-run.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/build-temp"
export TMPDIR="$TMP/build-temp"

section "failure classification ignores Xcode configuration chatter"
python3 - "$ROOT" <<'PYTEST'
import importlib.util, pathlib, sys
sys.dont_write_bytecode=True
path=pathlib.Path(sys.argv[1])/'skills/appstore-precheck/scripts/lib/build-exec.py'
spec=importlib.util.spec_from_file_location('build_exec',path)
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
noise='    export CODE_SIGN_CONTEXT_CLASS\\=XCiPhoneSimulatorCodeSignContext\n'
cases=[
    (noise+'FAILURE: Build failed with an exception.\nExecution failed for task :shared:compileKotlin.', 'BUILD_FAILED'),
    ('CodeSign /tmp/Example.app\nFAILURE: Gradle compilation failed.', 'BUILD_FAILED'),
    ('certificate verify failed while fetching a Maven dependency', 'BUILD_FAILED'),
    (noise+"ld: warning: framework 'OptionalKit' not found\nUndefined symbols for architecture x86_64", 'BUILD_FAILED'),
    ('error: Signing for "Example" requires a development team.', 'SIGNING'),
    ('Command CodeSign failed with a nonzero exit code', 'SIGNING'),
    ('error: No signing certificate "iOS Distribution" found', 'SIGNING'),
    ('SDK iphonesimulator not found', 'MISSING_SDK'),
]
for sample, expected in cases:
    actual=m.classify(sample)
    assert actual==expected, (expected,actual)
PYTEST
assert_eq "$?" 0 "environment, warnings and TLS errors are not code-signing failures"

hash_tree() {
  python3 - "$1" <<'PY'
import hashlib, os, sys
root = sys.argv[1]
h = hashlib.sha256()
for base, dirs, files in os.walk(root):
    dirs.sort(); files.sort()
    for name in files:
        p = os.path.join(base, name)
        h.update(os.path.relpath(p, root).encode())
        h.update(os.readlink(p).encode() if os.path.islink(p) else open(p, 'rb').read())
print(h.hexdigest())
PY
}
mkproject() {
  local name="$1"
  mkdir -p "$TMP/$name/ios/App.xcodeproj" "$TMP/$name/ios/App" "$TMP/$name/.git" \
    "$TMP/$name/node_modules" "$TMP/$name/Pods" "$TMP/$name/build" "$TMP/$name/DerivedData"
  printf 'source\n' > "$TMP/$name/ios/App/App.swift"
  for d in .git node_modules Pods build DerivedData; do printf 'excluded\n' > "$TMP/$name/$d/sentinel"; done
}

section "native plan and source hash"
mkproject native
printf 'demo_password=never-print-this-secret\n' > "$TMP/native/.env"
printf '{"demo_credentials":{"password":"never-print-this-secret"}}\n' > "$TMP/native/.appstore-precheck.json"
printf 'never-print-this-secret\n' > "$TMP/native/dev-asc-key-1.json"
before="$(hash_tree "$TMP/native")"
out="$(bash "$RUN" --repo "$TMP/native" --dry-run)"; st=$?
assert_eq "$st" 0 "native dry run succeeds"
assert_contains "$out" 'framework=native' "native detected"
assert_contains "$out" 'xcodebuild -list -json' "scheme discovery planned"
assert_contains "$out" '-sdk iphonesimulator -configuration Release' "Release simulator planned"
assert_contains "$out" '-derivedDataPath' "derived data isolated"
assert_contains "$out" 'CODE_SIGNING_ALLOWED=NO build' "signing disabled"
assert_absent "$out" 'npm ci' "native plan has no JS install"
assert_eq "$(hash_tree "$TMP/native")" "$before" "dry run leaves source untouched"
mkdir -p "$TMP/native/ios/App.xcodeproj/project.xcworkspace"
out="$(bash "$RUN" --repo "$TMP/native" --dry-run)"
assert_contains "$out" '-project ios/App.xcodeproj' "internal project workspace does not shadow Xcode project"
assert_absent "$out" '-workspace ios/App.xcodeproj/project.xcworkspace' "nested workspace not selected"

section "React Native bare and lockfile installers"
mkproject rn
printf '{"dependencies":{"react-native":"0.76.0"}}\n' > "$TMP/rn/package.json"
printf '{}\n' > "$TMP/rn/package-lock.json"
printf 'platform :ios\n' > "$TMP/rn/ios/Podfile"
out="$(bash "$RUN" --repo "$TMP/rn" --dry-run)"
assert_contains "$out" 'framework=rn' "RN detected"
assert_contains "$out" 'npm ci' "npm lockfile selects npm ci"
assert_contains "$out" 'pod install' "pods planned"
assert_absent "$out" 'expo prebuild' "bare RN has no Expo prebuild"
rm "$TMP/rn/package-lock.json"
printf 'lock\n' > "$TMP/rn/yarn.lock"
out="$(bash "$RUN" --repo "$TMP/rn" --dry-run)"
assert_contains "$out" 'yarn --frozen-lockfile' "yarn lockfile selects frozen install"
rm "$TMP/rn/yarn.lock"
printf 'lock\n' > "$TMP/rn/pnpm-lock.yaml"
out="$(bash "$RUN" --repo "$TMP/rn" --dry-run)"
assert_contains "$out" 'pnpm i --frozen-lockfile' "pnpm lockfile selects frozen install"

section "Expo, Flutter and KMP plans"
mkproject expo
printf '{"dependencies":{"expo":"53.0.0","react-native":"0.79.0"}}\n' > "$TMP/expo/package.json"
printf '{}\n' > "$TMP/expo/package-lock.json"
out="$(bash "$RUN" --repo "$TMP/expo" --dry-run)"
assert_contains "$out" 'npx expo prebuild --platform ios --no-install' "Expo prebuild planned"
assert_contains "$out" 'npm ci' "Expo installs JS dependencies first"
assert_absent "$out" 'flutter build' "Expo plan has no Flutter build"
mkdir -p "$TMP/flutter/ios/Runner.xcodeproj"
printf 'name: fixture\n' > "$TMP/flutter/pubspec.yaml"
out="$(bash "$RUN" --repo "$TMP/flutter" --dry-run)"
assert_contains "$out" 'flutter pub get' "Flutter dependencies planned"
assert_contains "$out" 'flutter build ios --simulator' "Flutter simulator build planned"
assert_contains "$out" 'build_config=debug' "Flutter simulator is Debug"
assert_absent "$out" 'xcodebuild' "Flutter plan has no Xcode invocation"
mkdir -p "$TMP/kmp/iosApp/iosApp.xcodeproj"
printf 'plugins {}\n' > "$TMP/kmp/build.gradle.kts"
out="$(bash "$RUN" --repo "$TMP/kmp" --dry-run)"
assert_contains "$out" 'framework=kmp' "KMP detected"
assert_contains "$out" 'iosApp/iosApp.xcodeproj' "KMP iOS Xcode project planned"
assert_absent "$out" 'gradle' "Gradle task not invented without project signal"
assert_absent "$out" 'npm ci' "KMP plan has no JS install"

section "unsupported platform is an explicit gap"
out="$(bash "$RUN" --repo "$TMP/native" --platform watchos --dry-run)"; st=$?
assert_eq "$st" 3 "unsupported platform exits SKIP"
assert_contains "$out" 'platform-not-audited' "platform gap recorded"

section "actual isolated copy with a fake Xcode tool"
mkdir -p "$TMP/bin" "$TMP/output"
cat > "$TMP/bin/xcodebuild" <<'SH'
#!/usr/bin/env bash
if [[ " $* " == *" -list -json "* ]]; then
  printf 'simulator diagnostic {not-json} before scheme output\n'
  printf '{"project":{"name":"App","schemes":["A-Library","App"]}}\n'
  exit 0
fi
if [[ " $* " != *" -scheme App "* ]]; then exit 98; fi
if [[ -e .env || -e .appstore-precheck.json || -e dev-asc-key-1.json || -e .git/sentinel || -e node_modules/sentinel || -e Pods/sentinel || -e build/sentinel || -e DerivedData/sentinel ]]; then exit 98; fi
printf 'never-print-this-secret\n'
if [[ -f "$(dirname "$0")/missing-sdk" ]]; then printf 'SDK iphonesimulator not found\n'; exit 65; fi
if [[ -f "$(dirname "$0")/sleep-build" ]]; then sleep 2; fi
if [[ -f "$(dirname "$0")/sleep-long" ]]; then touch "$(dirname "$0")/started"; sleep 30; fi
mkdir -p build
printf 'tool ran\n' > build/tool-wrote-here
if [[ -f "$(dirname "$0")/mutate-copy" ]]; then printf 'changed\n' >> ios/App/App.swift; fi
if [[ -f "$(dirname "$0")/mutate-original" ]]; then printf 'concurrent fixture change\n' >> "$(cat "$(dirname "$0")/mutate-original")"; fi
dd=''; cfg=''
while [[ $# -gt 0 ]]; do
  case "$1" in -derivedDataPath) dd="$2"; shift 2;; -configuration) cfg="$2"; shift 2;; *) shift;; esac
done
if [[ "$cfg" == Release && -f "$(dirname "$0")/fail-release" ]]; then exit 65; fi
if [[ -f "$(dirname "$0")/ide-state" ]]; then
  mkdir -p .gradle .kotlin .idea ios/App.xcodeproj/xcuserdata
  printf 'cache\n' > .gradle/cache.bin; printf 'k\n' > .kotlin/session; printf 'i\n' > .idea/workspace.xml
  printf 'u\n' > ios/App.xcodeproj/xcuserdata/u.xcuserstate
  orig="$(cat "$(dirname "$0")/ide-state")"
  mkdir -p "$orig/.idea" "$orig/ios/App.xcodeproj/xcuserdata"
  printf '%s\n' "$RANDOM" > "$orig/.idea/workspace.xml"
  printf '%s\n' "$RANDOM" > "$orig/ios/App.xcodeproj/xcuserdata/u.xcuserstate"
fi
mkdir -p "$dd/Build/Products/$cfg-iphonesimulator/App.app"
printf '<?xml version="1.0"?><plist><dict><key>CFBundleIdentifier</key><string>test.app</string></dict></plist>\n' > "$dd/Build/Products/$cfg-iphonesimulator/App.app/Info.plist"
if [[ -f "$(dirname "$0")/two-apps" ]]; then
  mkdir -p "$dd/Build/Products/$cfg-iphonesimulator/Clip.app"
  cp "$dd/Build/Products/$cfg-iphonesimulator/App.app/Info.plist" "$dd/Build/Products/$cfg-iphonesimulator/Clip.app/Info.plist"
fi
SH
chmod +x "$TMP/bin/xcodebuild"
printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/xcrun"; chmod +x "$TMP/bin/xcrun"
before="$(hash_tree "$TMP/native")"
out="$(PATH="$TMP/bin:$PATH" bash "$RUN" --repo "$TMP/native" --out "$TMP/output" --timeout 20)"; st=$?
assert_eq "$st" 0 "fake native build succeeds"
assert_contains "$out" 'build_config=release' "Release recorded"
assert_eq "$(hash_tree "$TMP/native")" "$before" "actual build leaves source content untouched"
[[ -f "$TMP/output/precheck/Build/Products/Release-iphonesimulator/App.app/Info.plist" ]] || { echo '  FAIL: .app exported'; fails=$((fails+1)); }
[[ -e "$TMP/native/tool-wrote-here" ]] && { echo '  FAIL: build wrote into source'; fails=$((fails+1)); }
assert_absent "$out" 'never-print-this-secret' "stdout contains no credential"
ad="$(bash "$ROOT/skills/appstore-precheck/scripts/app-discover.sh" --repo "$TMP/native" --derived-data "$TMP/output" --json)"; st=$?
assert_eq "$st" 0 "export is discoverable by app-discover"
assert_contains "$ad" 'Release-iphonesimulator/App.app' "discovery sees exported Release app"
: > "$TMP/bin/fail-release"
PATH="$TMP/bin:$PATH" bash "$RUN" --repo "$TMP/native" --out "$TMP/output" --timeout 20 > "$TMP/fallback.out"; st=$?
assert_eq "$st" 0 "Debug fallback succeeds"
assert_contains "$(cat "$TMP/fallback.out")" 'build_config=debug' "Debug fallback recorded"
assert_absent "$(cat "$TMP/fallback.out")" 'never-print-this-secret' "tool output is not echoed"

out="$(PATH="$TMP/bin:$PATH" bash "$RUN" --repo "$TMP/native" --out "$TMP/output" --timeout 20 --keep-build)"; st=$?
assert_eq "$st" 0 "--keep-build succeeds"
workspace="$(printf '%s\n' "$out" | sed -n 's/^build_workspace=//p')"
[[ -d "$workspace/project" ]] || { echo '  FAIL: --keep-build retained copy'; fails=$((fails+1)); }
[[ -e "$workspace/project/.env" || -e "$workspace/project/.appstore-precheck.json" ]] && { echo '  FAIL: secret file copied'; fails=$((fails+1)); }
assert_absent "$(cat "$(printf '%s\n' "$out" | sed -n 's/^event_log=//p')")" 'never-print-this-secret' "persistent event log contains no credential"
rm -rf "$workspace"

section "copied source mutation prevents proof binding"
: > "$TMP/bin/mutate-copy"
out="$(PATH="$TMP/bin:$PATH" bash "$RUN" --repo "$TMP/native" --out "$TMP/output" --timeout 20)"; st=$?
assert_eq "$st" 3 "copied input mutation is SKIP"
assert_contains "$out" 'provenance binding unavailable' "copy mutation is an evidence gap"
report="$(printf '%s\n' "$out" | sed -n 's/^build_evidence=//p')"
python3 - "$report" <<'PYTEST'
import json, sys
r=json.load(open(sys.argv[1]))
assert r['source_integrity']['source']['unchanged']
assert not r['source_integrity']['copy']['unchanged']
assert not r['source_binding_eligible']
PYTEST
assert_eq "$?" 0 "mutation report preserves original integrity and rejects binding"
rm "$TMP/bin/mutate-copy"

section "concurrent original source change is an evidence gap"
printf '%s\n' "$TMP/native/ios/App/App.swift" > "$TMP/bin/mutate-original"
out="$(PATH="$TMP/bin:$PATH" bash "$RUN" --repo "$TMP/native" --out "$TMP/output" --timeout 20)"; st=$?
assert_eq "$st" 3 "external source change exits SKIP"
report="$(printf '%s\n' "$out" | sed -n 's/^build_evidence=//p')"
python3 - "$report" <<'PYTEST'
import json, sys
r=json.load(open(sys.argv[1]))
assert not r['source_integrity']['source']['unchanged']
assert r['source_integrity']['copy']['unchanged']
assert not r['source_binding_eligible']
assert any('External source change' in x for x in r['limitations'])
PYTEST
assert_eq "$?" 0 "external change does not become an app finding"
rm "$TMP/bin/mutate-original"

section "failure classes and deadlines stay SKIP"
rm -f "$TMP/bin/fail-release"
: > "$TMP/bin/missing-sdk"
out="$(PATH="$TMP/bin:$PATH" bash "$RUN" --repo "$TMP/native" --out "$TMP/output" --timeout 20)"; st=$?
assert_eq "$st" 3 "missing SDK exits SKIP"
assert_contains "$out" 'MISSING_SDK' "missing SDK classified"
rm -f "$TMP/bin/missing-sdk"
: > "$TMP/bin/sleep-build"
out="$(PATH="$TMP/bin:$PATH" bash "$RUN" --repo "$TMP/native" --out "$TMP/output" --timeout 1)"; st=$?
assert_eq "$st" 3 "tool deadline exits SKIP"
assert_contains "$out" 'TIMEOUT' "timeout classified"
rm -f "$TMP/bin/sleep-build"

section "unsafe output paths and symlinks are rejected before writing"
before="$(hash_tree "$TMP/native")"
out="$(PATH="$TMP/bin:$PATH" bash "$RUN" --repo "$TMP/native" --out "$TMP/native/artifact")"; st=$?
assert_eq "$st" 3 "output inside source is SKIP"
assert_eq "$(hash_tree "$TMP/native")" "$before" "unsafe output request leaves source unchanged"
mkdir -p "$TMP/linked"
ln -s "$TMP/native/ios/App/App.swift" "$TMP/linked/escape.swift"
out="$(bash "$RUN" --repo "$TMP/linked" --out "$TMP/output")"; st=$?
assert_eq "$st" 3 "symlink input is SKIP"
assert_contains "$out" 'symlink' "symlink gap explained"

section "links with excluded dependency names are rejected too"
rm -rf "$TMP/native/node_modules"
ln -s "$TMP/native" "$TMP/native/node_modules"
out="$(PATH="$TMP/bin:$PATH" bash "$RUN" --repo "$TMP/native" --out "$TMP/output" --timeout 20)"; st=$?
assert_eq "$st" 3 "excluded-name node_modules symlink is SKIP, not silently ignored"
assert_contains "$out" 'symlink' "node_modules symlink reason"
rm "$TMP/native/node_modules"; mkdir -p "$TMP/native/node_modules"; printf 'excluded\n' > "$TMP/native/node_modules/sentinel"

section "isolated build can use caller-provided CocoaPods gem path"
cat > "$TMP/bin/gem-probe" <<'SH'
#!/bin/sh
case "$GEM_PATH:$LC_ALL" in */gems:C.UTF-8) exit 0 ;; *) exit 9 ;; esac
SH
chmod +x "$TMP/bin/gem-probe"
mkdir -p "$TMP/probe-home" "$TMP/probe-tmp"
out="$(GEM_PATH="$TMP/gems" python3 "$ROOT/skills/appstore-precheck/scripts/lib/build-exec.py" \
  --step gem-probe --cwd "$TMP" --timeout 10 --log "$TMP/probe-events.jsonl" \
  --home "$TMP/probe-home" --temp "$TMP/probe-tmp" -- "$TMP/bin/gem-probe")"; st=$?
assert_eq "$st" 0 "temporary CocoaPods gem path and UTF-8 locale reach the child tool"
assert_contains "$out" 'STATUS=OK' "gem path probe completes"

section "retained provenance and cleanup after success, error and timeout"
python3 - "$TMP/output" <<'PYTEST'
import json, pathlib, sys
root=pathlib.Path(sys.argv[1])
reports=[json.loads(p.read_text()) for p in root.glob('build-evidence.*/build-provenance.json')]
assert reports and any(r['source_binding_eligible'] for r in reports)
assert any(r['build_exit_status']==3 for r in reports)
for r in reports:
    assert r['distribution']=='simulator'
    assert r['signed_distribution_verified'] is False
    assert r['physical_device_verified'] is False
for p in root.glob('build-evidence.*/build-events.jsonl'):
    assert 'never-print-this-secret' not in p.read_text()
PYTEST
assert_eq "$?" 0 "all build outcomes retain sanitized evidence and limited scope"
remaining="$(find "$TMP/build-temp" -maxdepth 1 -type d -name 'appstore-precheck-build.*' -print)"
assert_eq "$remaining" '' "owned build workspaces cleaned on success, error and timeout"

section "runner deadline kills descendants and retains no raw output"
cat > "$TMP/bin/child-probe" <<'SH'
#!/bin/sh
(sleep 2; touch "$HOME/escaped-child") &
sleep 5
SH
chmod +x "$TMP/bin/child-probe"
out="$(python3 "$ROOT/skills/appstore-precheck/scripts/lib/build-exec.py" \
  --step child-probe --cwd "$TMP" --timeout 1 --log "$TMP/probe-events.jsonl" \
  --home "$TMP/probe-home" --temp "$TMP/probe-tmp" -- "$TMP/bin/child-probe")"; st=$?
assert_eq "$st" 3 "descendant deadline returns SKIP"
sleep 2
[[ ! -f "$TMP/probe-home/escaped-child" ]] || { echo '  FAIL: timed out child survived'; fails=$((fails+1)); }
assert_contains "$out" 'TIMEOUT' "descendant timeout classified"

section "Flutter generated configuration is prepared before the compilation snapshot"
cat > "$TMP/bin/flutter" <<'SH'
#!/usr/bin/env bash
if [[ "$1 $2" == 'pub get' ]]; then exit 0; fi
if [[ "$1 $2" != 'build ios' ]]; then exit 9; fi
mkdir -p ios/Flutter/ephemeral
for f in ios/Flutter/Generated.xcconfig ios/Flutter/ephemeral/flutter_native_integration.env ios/Flutter/flutter_export_environment.sh; do
  printf 'generated simulator configuration\n' > "$f"
done
if [[ " $* " == *' --config-only '* ]]; then exit 0; fi
if [[ -f "$(dirname "$0")/mutate-flutter-config" ]]; then printf 'compiler mutated configuration\n' >> ios/Flutter/Generated.xcconfig; fi
mkdir -p build/ios/iphonesimulator/Runner.app
printf '<?xml version="1.0"?><plist><dict><key>CFBundleIdentifier</key><string>test.flutter</string></dict></plist>\n' > build/ios/iphonesimulator/Runner.app/Info.plist
SH
chmod +x "$TMP/bin/flutter"
before="$(hash_tree "$TMP/flutter")"
out="$(PATH="$TMP/bin:$PATH" bash "$RUN" --repo "$TMP/flutter" --framework flutter --out "$TMP/flutter-artifact" --timeout 20)"; st=$?
assert_eq "$st" 0 "Flutter prepared configuration leaves compiler snapshot unchanged"
assert_eq "$(hash_tree "$TMP/flutter")" "$before" "Flutter preparation never writes to original source"
report="$(printf '%s\n' "$out" | sed -n 's/^build_evidence=//p')"
python3 - "$report" <<'PYTEST'
import json, pathlib, sys
p=pathlib.Path(sys.argv[1]);r=json.loads(p.read_text())
assert r['source_binding_eligible'] is True
assert r['source_integrity']['copy']['unchanged'] is True
assert set(r['preparation']['changed_paths']) == {'ios/Flutter/Generated.xcconfig','ios/Flutter/ephemeral/flutter_native_integration.env','ios/Flutter/flutter_export_environment.sh'}
steps=[json.loads(line)['step'] for line in (p.parent/'build-events.jsonl').read_text().splitlines()]
assert steps==['flutter-pub','flutter-config','flutter-build']
PYTEST
assert_eq "$?" 0 "Flutter provenance distinguishes generated preparation from compilation"
: > "$TMP/bin/mutate-flutter-config"
out="$(PATH="$TMP/bin:$PATH" bash "$RUN" --repo "$TMP/flutter" --framework flutter --out "$TMP/flutter-artifact" --timeout 20)"; st=$?
assert_eq "$st" 3 "Flutter compiler-time source mutation still rejects binding"
assert_contains "$out" 'provenance binding unavailable' "Flutter generated files were not excluded from integrity checks"

section "symlinks named like excluded directories cannot escape the copy"
for linkpath in ios/Pods build; do
  rm -rf "$TMP/escape" "$TMP/outside"
  mkproject escape
  rm -rf "$TMP/escape/$linkpath"
  mkdir -p "$TMP/outside"; printf 'outside\n' > "$TMP/outside/sentinel"
  ln -s "$TMP/outside" "$TMP/escape/$linkpath"
  outside_before="$(hash_tree "$TMP/outside")"
  out="$(PATH="$TMP/bin:$PATH" bash "$RUN" --repo "$TMP/escape" --out "$TMP/output" --timeout 20)"; st=$?
  assert_eq "$st" 3 "$linkpath symlink is SKIP"
  assert_contains "$out" 'symlink' "$linkpath symlink reason reported"
  assert_eq "$(hash_tree "$TMP/outside")" "$outside_before" "$linkpath link never let a tool write outside the copy"
done
rm -rf "$TMP/escape" "$TMP/outside"
mkproject escape
mkdir -p "$TMP/outside"; printf 'outside\n' > "$TMP/outside/secret-target"
ln -s "$TMP/outside/secret-target" "$TMP/escape/.env.local"
ln -s "$TMP/outside/secret-target" "$TMP/escape/Auth.p12"
out="$(PATH="$TMP/bin:$PATH" bash "$RUN" --repo "$TMP/escape" --out "$TMP/output" --timeout 20)"; st=$?
assert_eq "$st" 0 "secret-named links are excluded from the copy and do not block the build"
rm -rf "$TMP/escape" "$TMP/outside"

section "tool availability is checked before any project code runs"
mkdir -p "$TMP/farm" "$TMP/pre-bin"
for c in awk basename cat chmod cp dirname env find grep head ls mkdir mktemp mv python3 rm rsync sed sleep sort tr uname wc tail touch cut date readlink tee id sh bash; do
  p="$(command -v "$c" 2>/dev/null)" && [[ -x "$p" ]] && ln -sf "$p" "$TMP/farm/$c"
done
for t in npm yarn pnpm npx pod flutter; do
  printf '#!/bin/sh\ntouch "%s/ran-%s"\nexit 0\n' "$TMP/pre-bin" "$t" > "$TMP/pre-bin/$t"; chmod +x "$TMP/pre-bin/$t"
done
mkproject rnpre
printf '{\n  "dependencies": {\n    "react-native": "0.76.0"\n  }\n}\n' > "$TMP/rnpre/package.json"
printf '{}\n' > "$TMP/rnpre/package-lock.json"; printf 'platform :ios\n' > "$TMP/rnpre/ios/Podfile"
out="$(PATH="$TMP/pre-bin:$TMP/farm" bash "$RUN" --repo "$TMP/rnpre" --out "$TMP/output" --timeout 20)"; st=$?
assert_eq "$st" 3 "React Native without Xcode is SKIP"
assert_contains "$out" 'xcodebuild' "missing Xcode is named"
assert_eq "$(ls "$TMP/pre-bin" | grep -c '^ran-')" 0 "no npm/pod/expo step ran without xcodebuild"
mkdir -p "$TMP/flutterpre/ios/Runner.xcodeproj"; printf 'name: fixture\n' > "$TMP/flutterpre/pubspec.yaml"
out="$(PATH="$TMP/pre-bin:$TMP/farm" bash "$RUN" --repo "$TMP/flutterpre" --out "$TMP/output" --timeout 20)"; st=$?
assert_eq "$st" 3 "Flutter without Xcode is SKIP"
assert_eq "$(ls "$TMP/pre-bin" | grep -c '^ran-')" 0 "no flutter step ran without xcodebuild"
printf '#!/bin/sh\nexit 0\n' > "$TMP/pre-bin/xcodebuild"; chmod +x "$TMP/pre-bin/xcodebuild"
out="$(PATH="$TMP/pre-bin:$TMP/farm" bash "$RUN" --repo "$TMP/rnpre" --out "$TMP/output" --timeout 20)"; st=$?
assert_eq "$st" 3 "Xcode without xcrun is SKIP"
assert_contains "$out" 'xcrun' "missing xcrun named"
assert_eq "$(ls "$TMP/pre-bin" | grep -c '^ran-')" 0 "no install step ran without xcrun"
rm -f "$TMP/pre-bin/xcodebuild"

section "IDE and Gradle state is not source"
printf '%s\n' "$TMP/native" > "$TMP/bin/ide-state"
out="$(PATH="$TMP/bin:$PATH" bash "$RUN" --repo "$TMP/native" --out "$TMP/output" --timeout 20)"; st=$?
assert_eq "$st" 0 "build writing .gradle/.kotlin/.idea/xcuserdata is not a source change"
assert_absent "$out" 'source identity changed' "no source-changed skip"
rm -f "$TMP/bin/ide-state"; rm -rf "$TMP/native/.idea" "$TMP/native/ios/App.xcodeproj/xcuserdata"
mkdir -p "$TMP/kmp2/iosApp/iosApp.xcodeproj" "$TMP/kmpbin"
printf 'plugins {}\n' > "$TMP/kmp2/build.gradle.kts"
cat > "$TMP/kmp2/gradlew" <<SH
#!/bin/sh
printf '%s|%s\n' "\$PWD" "\$*" >> "$TMP/kmp-gradle-calls"
mkdir -p .gradle .kotlin
printf 'x\n' > .gradle/state; printf 'y\n' > .kotlin/session
touch "$TMP/kmp-linked"
SH
chmod +x "$TMP/kmp2/gradlew"
cat > "$TMP/kmpbin/xcodebuild" <<SH
#!/usr/bin/env bash
if [[ " \$* " == *" -list -json "* ]]; then printf '{"project":{"name":"iosApp","schemes":["iosApp"]}}\n'; exit 0; fi
if [[ ! -f "$TMP/kmp-linked" ]]; then printf "ld: framework 'shared' not found\n"; exit 65; fi
mkdir -p .gradle .kotlin; printf 'z\n' > .gradle/more
dd=''; cfg=''
while [[ \$# -gt 0 ]]; do case "\$1" in -derivedDataPath) dd="\$2"; shift 2;; -configuration) cfg="\$2"; shift 2;; *) shift;; esac; done
mkdir -p "\$dd/Build/Products/\$cfg-iphonesimulator/iosApp.app"
printf '<?xml version="1.0"?><plist><dict><key>CFBundleIdentifier</key><string>t</string></dict></plist>\n' > "\$dd/Build/Products/\$cfg-iphonesimulator/iosApp.app/Info.plist"
SH
chmod +x "$TMP/kmpbin/xcodebuild"; cp "$TMP/bin/xcrun" "$TMP/kmpbin/xcrun"
rm -f "$TMP/kmp-linked" "$TMP/kmp-gradle-calls"
out="$(cd "$TMP" && PATH="$TMP/kmpbin:$PATH" bash "$RUN" --repo "$TMP/kmp2" --out "$TMP/kmp-out" --timeout 20)"; st=$?
assert_eq "$st" 0 "KMP gradlew fallback resolves ./gradlew in the step directory and build stays bound"
assert_absent "$out" 'source identity changed' "KMP .gradle/.kotlin writes are not a source change"
assert_contains "$(cat "$TMP/kmp-gradle-calls" 2>/dev/null)" '--project-cache-dir' "gradle project cache is redirected"
case "$(cut -d'|' -f2 "$TMP/kmp-gradle-calls" 2>/dev/null)" in *"$TMP/kmp2"*) echo '  FAIL: gradle cache inside source'; fails=$((fails+1));; *) echo '  ok: gradle cache path is not the source tree';; esac

section "multiple application bundles are ambiguous"
: > "$TMP/bin/two-apps"
out="$(PATH="$TMP/bin:$PATH" bash "$RUN" --repo "$TMP/native" --out "$TMP/output" --timeout 20)"; st=$?
assert_eq "$st" 3 "App Clip style output with two .app bundles is SKIP"
assert_contains "$out" 'more than one' "ambiguity reason"
rm -f "$TMP/bin/two-apps"

section "secret files are recorded as presence only"
mkdir -p "$TMP/secrets/fastlane/metadata/review_information"
printf 'abc\n' > "$TMP/secrets/.env"; printf 'x\n' > "$TMP/secrets/AuthKey_ABC.p8"; printf 'pw\n' > "$TMP/secrets/fastlane/metadata/review_information/demo_password.txt"
printf 'y\n' > "$TMP/secrets/a.mobileprovision"; printf 'z\n' > "$TMP/secrets/dev-asc-key-1.json"; printf 'src\n' > "$TMP/secrets/main.swift"
python3 "$ROOT/skills/appstore-precheck/scripts/source-snapshot.py" --repo "$TMP/secrets" --out "$TMP/secrets-snap.json"
python3 - "$TMP/secrets-snap.json" <<'PYTEST'
import hashlib, json, sys
raw = open(sys.argv[1]).read()
e = json.loads(raw)['entries']
for k in ('.env', 'AuthKey_ABC.p8', 'fastlane/metadata/review_information/demo_password.txt', 'a.mobileprovision', 'dev-asc-key-1.json'):
    assert e[k] == {'kind': 'file', 'secret': True}, (k, e.get(k))
assert 'sha256' in e['main.swift']
for value in (b'abc\n', b'x\n', b'pw\n', b'y\n', b'z\n'):
    assert hashlib.sha256(value).hexdigest() not in raw
PYTEST
assert_eq "$?" 0 "secret snapshot entries carry no hash, size or mode"
out="$(PATH="$TMP/bin:$PATH" bash "$RUN" --repo "$TMP/native" --out "$TMP/output" --timeout 20)"
ev="$(printf '%s\n' "$out" | sed -n 's/^build_evidence=//p')"
secret_hash="$(printf 'never-print-this-secret\n' | python3 -c 'import hashlib,sys;print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())')"
assert_absent "$(cat "$(dirname "$ev")/source-before.json")" "$secret_hash" "retained evidence has no brute-forceable secret hash"

mkproject flpw
mkdir -p "$TMP/flpw/fastlane/metadata/review_information" "$TMP/flpw/fastlane/review_information"
printf 'pw\n' > "$TMP/flpw/fastlane/metadata/review_information/demo_password.txt"
printf 'pw\n' > "$TMP/flpw/fastlane/review_information/Demo_Password.txt"
printf 'Ada\n' > "$TMP/flpw/fastlane/metadata/review_information/first_name.txt"
out="$(PATH="$TMP/bin:$PATH" bash "$RUN" --repo "$TMP/flpw" --out "$TMP/output" --timeout 20 --keep-build)"; st=$?
assert_eq "$st" 0 "fastlane review credentials fixture builds"
workspace="$(printf '%s\n' "$out" | sed -n 's/^build_workspace=//p')"
[[ -f "$workspace/project/fastlane/metadata/review_information/first_name.txt" ]] && echo '  ok: non-secret review metadata still copied' || { echo '  FAIL: review metadata dropped'; fails=$((fails+1)); }
[[ ! -e "$workspace/project/fastlane/metadata/review_information/demo_password.txt" && ! -e "$workspace/project/fastlane/review_information/Demo_Password.txt" ]] && echo '  ok: review password files stay out of the copy' || { echo '  FAIL: review password copied'; fails=$((fails+1)); }
rm -rf "$workspace"

section "wall-clock deadline and termination"
: > "$TMP/bin/sleep-long"; rm -f "$TMP/bin/started"
t0=$SECONDS
out="$(PATH="$TMP/bin:$PATH" bash "$RUN" --repo "$TMP/native" --out "$TMP/output" --timeout 60 --deadline 3)"; st=$?
assert_eq "$st" 3 "exhausted deadline is SKIP"
assert_contains "$out" 'build deadline exceeded' "deadline reason"
(( SECONDS - t0 < 15 )) && echo '  ok: deadline cut the 30s tool short' || { echo '  FAIL: deadline did not cap the step'; fails=$((fails+1)); }
assert_eq "$(find "$TMP/build-temp" -maxdepth 1 -name 'appstore-precheck-build.*' | wc -l | tr -d ' ')" 0 "workspace removed after deadline"
out="$(PATH="$TMP/bin:$PATH" bash "$RUN" --repo "$TMP/native" --deadline 0 2>&1)"; st=$?
assert_eq "$st" 64 "--deadline must be positive"
rm -f "$TMP/bin/started"
PATH="$TMP/bin:$PATH" bash "$RUN" --repo "$TMP/native" --out "$TMP/output" --timeout 60 > "$TMP/term.out" 2>&1 &
pid=$!
for _ in $(seq 1 100); do [[ -f "$TMP/bin/started" ]] && break; sleep 0.1; done
[[ -f "$TMP/bin/started" ]] || { echo '  FAIL: build never started'; fails=$((fails+1)); }
t0=$SECONDS
kill -TERM "$pid"; wait "$pid"; st=$?
assert_eq "$st" 143 "TERM exits 143"
(( SECONDS - t0 < 10 )) && echo '  ok: TERM handled promptly' || { echo '  FAIL: TERM was deferred'; fails=$((fails+1)); }
assert_eq "$(find "$TMP/build-temp" -maxdepth 1 -name 'appstore-precheck-build.*' | wc -l | tr -d ' ')" 0 "temp copy removed on TERM"
rm -f "$TMP/bin/sleep-long" "$TMP/bin/started"

exit "$fails"
