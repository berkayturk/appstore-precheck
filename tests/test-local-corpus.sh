#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
# shellcheck source=tests/_assert.sh
source tests/_assert.sh
for kind in clean broken; do
  root="tests/local/corpus/swiftui/$kind"
  assert_eq "$(find "$root" -name project.pbxproj 2>/dev/null | wc -l | tr -d ' ')" 1 "$kind has a checked-in Xcode project"
  assert_not_empty "$(cat "$root/Info.plist" 2>/dev/null)" "$kind has its own plist"
done
assert_contains "$(cat tests/local/corpus/swiftui/broken/Sources/PrecheckApp.swift 2>/dev/null)" 'fatalError' 'broken corpus has intentional launch crash'
assert_absent "$(cat tests/local/corpus/swiftui/clean/Sources/PrecheckApp.swift 2>/dev/null)" 'fatalError' 'clean corpus does not crash intentionally'
exit "$fails"
