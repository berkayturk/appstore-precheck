#!/usr/bin/env bash
# tests/test-framework-detect.sh — framework-detect.sh (file presence only) and the
# framework-not-audited gap record scan.sh emits from it.
#
# Why this matters: every code-level check greps Swift / ObjC (SRC_INC). On React
# Native, Flutter and Kotlin Multiplatform the app logic lives in JS / Dart / Kotlin,
# so those checks UNDER-DETECT rather than false-fire — and until now the scan said
# nothing about it. A repo could look clean on ground the scanner never read. The gap
# record names the cost, with the count derived from the evidence catalogue.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck source=tests/_assert.sh
source "$HERE/_assert.sh"
S="$ROOT/skills/appstore-precheck/scripts"
FD="$S/framework-detect.sh"
SCAN="$S/scan.sh"
FX="$HERE/fixtures"

section "one word per framework, from file presence alone"
assert_eq "rn"      "$(bash "$FD" --root "$FX/rn-app")"      "package.json with react-native -> rn"
assert_eq "flutter" "$(bash "$FD" --root "$FX/flutter-app")" "pubspec.yaml + ios/Runner.xcodeproj -> flutter"
assert_eq "kmp"     "$(bash "$FD" --root "$FX/kmp-app")"     "build.gradle.kts + iosApp/ -> kmp"
assert_eq "native"  "$(bash "$FD" --root "$FX/clean-app")"   "a plain Xcode layout -> native"
assert_eq "native"  "$(bash "$FD" --root "$FX/risky-app")"   "another native fixture -> native"

section "--json carries the word and the signals that decided it"
j="$(bash "$FD" --root "$FX/rn-app" --json)"
assert_eq "rn" "$(jq -r .framework <<<"$j")" "json.framework"
assert_contains "$(jq -r '.signals[]' <<<"$j")" "package.json" "json.signals names the deciding file"
j="$(bash "$FD" --root "$FX/flutter-app" --json)"
assert_contains "$(jq -r '.signals[]' <<<"$j")" "pubspec.yaml" "flutter signal named"
assert_contains "$(jq -r '.signals[]' <<<"$j")" "Runner.xcodeproj" "…and the iOS runner"
j="$(bash "$FD" --root "$FX/kmp-app" --json)"
assert_contains "$(jq -r '.signals[]' <<<"$j")" "iosApp" "kmp signal names iosApp/"
j="$(bash "$FD" --root "$FX/clean-app" --json)"
assert_eq "0" "$(jq -r '.signals|length' <<<"$j")" "native has no framework signal"

section "a package.json that merely mentions react-native in prose is not rn"
d="$(mktemp -d)"; mkdir -p "$d/ios/App"
printf '{"name":"x","description":"not react-native, a native app","dependencies":{"lodash":"4"}}' > "$d/package.json"
printf 'import UIKit\n@main class AppDelegate: UIResponder {}\n' > "$d/ios/App/AppDelegate.swift"
assert_eq "native" "$(bash "$FD" --root "$d")" "react-native must be a dependency, not a word in the description"
rm -rf "$d"

section "pubspec without an iOS runner is not enough for flutter (a Dart package, not an app)"
d="$(mktemp -d)"; printf 'name: pkg\n' > "$d/pubspec.yaml"
assert_eq "native" "$(bash "$FD" --root "$d")" "pubspec.yaml alone -> native (nothing to under-detect)"
rm -rf "$d"

section "sourceable: detect_framework <root> is the same function scan.sh uses"
# shellcheck source=skills/appstore-precheck/scripts/framework-detect.sh
source "$FD"
assert_eq "flutter" "$(detect_framework "$FX/flutter-app")" "function form agrees with the CLI"
assert_eq "native"  "$(detect_framework "$FX/clean-app")"   "…for native too"

section "scan.sh: a non-native repo gets a framework-not-audited gap record"
# shellcheck source=skills/appstore-precheck/scripts/findings.sh
source "$S/findings.sh"
# shellcheck source=skills/appstore-precheck/scripts/evidence.sh
source "$S/evidence.sh"
src_n="$(rules_with_evidence source 55 | grep -c .)"
assert_gt "$src_n" "20" "(precondition) the source-evidence class is the largest"
for fx in rn-app flutter-app kmp-app; do
  d="$(mktemp -d)"; cp -R "$FX/$fx/." "$d/"
  out="$(cd "$d" && APPSTORE_PRECHECK_CONFIG=/nonexistent bash "$SCAN" 2>&1)"
  assert_contains "$out" "SKIP: framework — $src_n code-level checks under-detect on" "$fx: the SKIP names the derived count"
  assert_contains "$out" "source greps read Swift/ObjC only" "$fx: and says why"
  assert_contains "$out" "ipv4-literal" "$fx: the skipped rule ids are listed (newest source rule included)"
  assert_absent   "$out" "FAIL: framework" "$fx: a coverage gap is never a FAIL"
  j="$(cd "$d" && APPSTORE_PRECHECK_CONFIG=/nonexistent bash "$SCAN" --format json 2>/dev/null)"
  g="$(jq -c '[.findings[]|select(.rule_id=="framework-not-audited")][0]' <<<"$j")"
  assert_eq "SKIP" "$(jq -r .severity <<<"$g")" "$fx: recorded as SKIP under its stable id"
  assert_eq "null" "$(jq -r .evidence <<<"$g")" "$fx: a gap record carries no evidence class"
  assert_eq "null" "$(jq -r .confidence <<<"$g")" "$fx: …nor a confidence"
  assert_gt "$(jq -r .summary.not_audited <<<"$j")" "0" "$fx: counted as not audited"
  rm -rf "$d"
done
d="$(mktemp -d)"; cp -R "$FX/rn-app/." "$d/"
out="$(cd "$d" && APPSTORE_PRECHECK_CONFIG=/nonexistent bash "$SCAN" 2>&1)"
assert_contains "$out" "under-detect on rn" "the framework word is in the line"
rm -rf "$d"

section "scan.sh: a native repo does NOT get the gap record"
d="$(mktemp -d)"; cp -R "$FX/clean-app/." "$d/"
out="$(cd "$d" && APPSTORE_PRECHECK_CONFIG=/nonexistent bash "$SCAN" 2>&1)"
assert_absent "$out" "SKIP: framework" "native -> no framework SKIP"
rm -rf "$d"

section "the gap can be acknowledged in .precheck-ignore, never erased"
d="$(mktemp -d)"; cp -R "$FX/rn-app/." "$d/"
printf 'framework-not-audited\n' > "$d/.precheck-ignore"
out="$(cd "$d" && APPSTORE_PRECHECK_CONFIG=/nonexistent bash "$SCAN" 2>&1)"
assert_absent "$out" "SKIP: framework" "acknowledged -> not re-printed"
j="$(cd "$d" && APPSTORE_PRECHECK_CONFIG=/nonexistent bash "$SCAN" --format json 2>/dev/null)"
assert_eq "true" "$(jq -r '[.findings[]|select(.rule_id=="framework-not-audited")][0].suppressed' <<<"$j")" "recorded as suppressed"
assert_gt "$(jq -r .summary.not_audited <<<"$j")" "0" "still counted as not audited"
assert_eq "true" "$(is_gap_record framework-not-audited && echo true || echo false)" "framework-not-audited is a gap record by convention"
rm -rf "$d"

section "the detector is file presence only: it runs no toolchain"
shim="$(mktemp -d)"; marker="$shim/ran"
for t in xcodebuild flutter gradle node npm npx pod; do
  printf '#!/bin/sh\necho %s >> "%s"\n' "$t" "$marker" > "$shim/$t"; chmod +x "$shim/$t"
done
PATH="$shim:$PATH" bash "$FD" --root "$FX/rn-app" >/dev/null
PATH="$shim:$PATH" bash "$FD" --root "$FX/flutter-app" >/dev/null
PATH="$shim:$PATH" bash "$FD" --root "$FX/kmp-app" >/dev/null
[[ -e "$marker" ]] && { echo "  FAIL: a toolchain was invoked: $(cat "$marker")"; fails=$((fails+1)); } || echo "  ok: no toolchain invoked"
rm -rf "$shim"

exit "$fails"
