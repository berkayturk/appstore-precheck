#!/usr/bin/env bash
# tests/test-config.sh — asserts scan.sh honors .appstore-precheck.json overrides.
# The config-app fixture has a deliberately non-standard layout (sources under
# custom/src with a decoy Info.plist dir that has MORE Swift files, metadata under
# custom/meta which is NOT a fastlane/metadata path, a custom subscription disclosure
# key, and an opt-in FamilyControls check). Auto-detection alone gets it wrong; the
# config makes the scan resolve the real layout.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/_assert.sh
source "$DIR/_assert.sh"
SCAN="$DIR/../skills/appstore-precheck/scripts/scan.sh"
FIXTURE="$DIR/fixtures/config-app"

TMP="$(mktemp -d)"
cp -R "$FIXTURE/." "$TMP/"

# Run with and without the config; both from inside the copied fixture.
with_cfg="$( cd "$TMP" && APPSTORE_PRECHECK_CONFIG="$TMP/precheck-config.json" bash "$SCAN" 2>&1 )"
no_cfg="$(  cd "$TMP" && APPSTORE_PRECHECK_CONFIG=/nonexistent          bash "$SCAN" 2>&1 )"

section "config overrides the layout"
assert_contains "$with_cfg" "ios='custom/src'"        "iosSourceDir honored"
assert_contains "$with_cfg" "metadata='custom/meta'"  "metadataDir honored"
assert_contains "$with_cfg" "locales=2"               "locales array honored (en-US, de-DE)"

section "config overrides the subscription disclosure key"
assert_contains "$with_cfg" "subscription disclosure key 'my_sub_key' present" \
  "disclosureKeys.subscription honored"

section "opt-in FamilyControls check runs with reviewer notes"
assert_contains "$with_cfg" "5.1.5 Screen Time API — reviewer-prep justification note present" \
  "optionalChecks.familyControls + reviewPrepNotes honored"

section "config-driven layout produces no FAIL"
assert_absent "$with_cfg" "FAIL:" "well-formed config-app has zero FAILs"

# Contrast: WITHOUT the config, the scan resolves a DIFFERENT layout — proving the
# overrides are doing real work, not coinciding with what auto-detection would find.
# Comparing the two layout lines is platform-independent (it doesn't assume which dir
# auto-detection lands on, which varies with find/bash version).
section "without config, the resolved layout differs (overrides are load-bearing)"
layout_with="$(grep -m1 '^PASS: layout' <<<"$with_cfg")"
layout_no="$(grep -m1 '^PASS: layout' <<<"$no_cfg")"
if [[ -n "$layout_with" && "$layout_with" != "$layout_no" ]]; then
  echo "  ok: config changes the resolved layout"
else
  echo "  FAIL: layout did not change with config"
  echo "        with: $layout_with"
  echo "        no  : $layout_no"
  fails=$((fails + 1))
fi
assert_absent  "$no_cfg" "key 'my_sub_key' present" "custom disclosure key not used without config"
assert_absent  "$no_cfg" "5.1.5 Screen Time"        "FamilyControls check off by default"

# Regression: without config, auto-detection lands on decoy/ (see layout_no
# above), yet the TabView nav hub lives under custom/src/ — OUTSIDE the
# auto-detected iOS dir. §12 (4.2 Minimum functionality) must still find it
# because the grep is repo-wide (`.` + GREP_PRUNE), not scoped to $IOS_DIR. If
# a future change reverts the grep target back to "$IOS_DIR", this fails.
section "nav hub found repo-wide, outside auto-detected iOS dir (locks scope-widening)"
assert_contains "$no_cfg" "PASS: 4.2 Minimum functionality" \
  "config-app: nav hub found repo-wide, outside auto-detected iOS dir (locks scope-widening)"

# Regression: the no-config path has 0 locales; the scan must still complete (it used
# to crash on empty-array expansion under bash 3.2 set -u).
section "no-config scan completes (empty-LOCALES regression)"
assert_contains "$no_cfg" "---END-OF-SCAN---" "scan runs to completion with 0 locales"

rm -rf "$TMP"

# ---------------------------------------------------------------------------
# Regression: a locale listed in config but absent on disk WARNs (not FAILs),
# and a legitimate word that merely contains "changeme" (e.g. French
# "changement") is not flagged as placeholder copy.
# ---------------------------------------------------------------------------
TMP2="$(mktemp -d)"
mkdir -p "$TMP2/fastlane/metadata/en-US"
printf 'Focus App'                                  > "$TMP2/fastlane/metadata/en-US/name.txt"
printf 'Block distractions'                         > "$TMP2/fastlane/metadata/en-US/subtitle.txt"
printf 'Structured programs for real changement.\n' > "$TMP2/fastlane/metadata/en-US/description.txt"
printf 'focus,habits'                               > "$TMP2/fastlane/metadata/en-US/keywords.txt"
# Config lists en-US (present) + ru (NO folder on disk).
cat > "$TMP2/precheck-config.json" <<'JSON'
{ "metadataDir": "fastlane/metadata", "locales": ["en-US", "ru"] }
JSON

out2="$( cd "$TMP2" && APPSTORE_PRECHECK_CONFIG="$TMP2/precheck-config.json" bash "$SCAN" 2>&1 )"

section "config locale absent on disk warns, never fails (option A)"
assert_contains "$out2" "2.3.7 Locale 'ru' is in" "missing config locale is reported"
assert_contains "$out2" "WARN: 2.3.7 Locale 'ru'" "missing config locale is a WARN"
assert_absent   "$out2" "2.3.7 Locale missing — " "missing config locale is not a hard FAIL"

section "legitimate word containing 'changeme' is not placeholder copy"
assert_absent   "$out2" "2.1 Metadata content" "French 'changement' does not trip the 2.1 placeholder check"

rm -rf "$TMP2"
echo
if (( fails == 0 )); then echo "test-config: ALL PASSED"; else echo "test-config: $fails FAILED"; fi
exit "$fails"
