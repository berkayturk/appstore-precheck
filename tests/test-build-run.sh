#!/usr/bin/env bash
# Portable command-plan and source-isolation fixtures for the opt-in build runner.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
source "$HERE/_assert.sh"
RUN="$ROOT/skills/appstore-precheck/scripts/build-run.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

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
  printf '{"project":{"schemes":["App"]}}\n'
  exit 0
fi
if [[ -e .env || -e .appstore-precheck.json || -e dev-asc-key-1.json || -e .git/sentinel || -e node_modules/sentinel || -e Pods/sentinel || -e build/sentinel || -e DerivedData/sentinel ]]; then exit 98; fi
printf 'never-print-this-secret\n'
if [[ -f "$(dirname "$0")/missing-sdk" ]]; then printf 'SDK iphonesimulator not found\n'; exit 65; fi
if [[ -f "$(dirname "$0")/sleep-build" ]]; then sleep 2; fi
printf 'tool ran\n' > tool-wrote-here
dd=''; cfg=''
while [[ $# -gt 0 ]]; do
  case "$1" in -derivedDataPath) dd="$2"; shift 2;; -configuration) cfg="$2"; shift 2;; *) shift;; esac
done
if [[ "$cfg" == Release && -f "$(dirname "$0")/fail-release" ]]; then exit 65; fi
mkdir -p "$dd/Build/Products/$cfg-iphonesimulator/App.app"
printf '<?xml version="1.0"?><plist><dict><key>CFBundleIdentifier</key><string>test.app</string></dict></plist>\n' > "$dd/Build/Products/$cfg-iphonesimulator/App.app/Info.plist"
SH
chmod +x "$TMP/bin/xcodebuild"
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
assert_absent "$(cat "$workspace/build-events.jsonl")" 'never-print-this-secret' "persistent event log contains no credential"
rm -rf "$workspace"

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

exit "$fails"
