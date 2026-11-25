#!/usr/bin/env bash
# tests/test-xcode-sdk-paths.sh — §51 xcode-sdk-requirement (2.1) path handling.
# The rule reads LastUpgradeCheck out of every checked-in project.pbxproj. It must
# survive the two things real repositories do: put spaces in directory names, and
# carry more than a handful of generated .xcodeproj bundles that have no
# LastUpgradeCheck at all (Tuist / XcodeGen / SwiftPM wrappers) in front of the
# one hand-maintained project that does.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck source=tests/_assert.sh
source "$HERE/_assert.sh"
SCAN="$ROOT/skills/appstore-precheck/scripts/scan.sh"
FX="$HERE/fixtures/old-xcode-app"

run_in() { ( cd "$1" && APPSTORE_PRECHECK_CONFIG=/nonexistent bash "$SCAN" 2>&1 ); }

section "a space in the project path does not hide an old LastUpgradeCheck"
d="$(mktemp -d)"
mkdir -p "$d/My App"
cp -R "$FX/." "$d/My App/"
o="$(run_in "$d")"
assert_contains "$o" "WARN: 2.1 Xcode/SDK minimum" "the pre-26 project is still found behind a space"
assert_contains "$o" "LastUpgradeCheck=1520" "and its value is reported"
rm -rf "$d"

section "more than five pbxproj files: the old one is read wherever find lists it"
d="$(mktemp -d)"
cp -R "$FX/." "$d/"
# Six generated projects with no LastUpgradeCheck. APFS lists directory entries in
# hash order, not by name, so rename the hand-maintained project until find lists it
# LAST: a head-N cap over the find output would then drop the one file with the signal.
for i in 1 2 3 4 5 6; do
  mkdir -p "$d/gen-$i/Gen.xcodeproj"
  printf '// !$*UTF8*$!\n{ objects = { }; rootObject = 1; }\n' > "$d/gen-$i/Gen.xcodeproj/project.pbxproj"
done
placed=""; cur="$d/OldApp.xcodeproj"
for n in $(seq 1 80); do
  mv "$cur" "$d/OldApp$n.xcodeproj"; cur="$d/OldApp$n.xcodeproj"
  last="$(cd "$d" && find . -name project.pbxproj -type f | tail -1)"
  if [[ "$last" == *"OldApp$n.xcodeproj"* ]]; then placed=1; break; fi
done
assert_eq "$placed" "1" "test setup: OldApp.xcodeproj is listed last by find"
o="$(run_in "$d")"
assert_contains "$o" "WARN: 2.1 Xcode/SDK minimum" "the seventh pbxproj is still read"
assert_contains "$o" "LastUpgradeCheck=1520" "and its value is reported"
rm -rf "$d"

exit "$fails"
