#!/usr/bin/env bash
# tests/test-saturated.sh — §54 saturated-category (4.3(b)).
# Apple NAMES the saturated categories in 4.3(b); this rule matches that list against
# the app name, subtitle and keywords — the fields that say what the app IS — and
# never against the description, where the same words appear as ordinary features.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck source=tests/_assert.sh
source "$HERE/_assert.sh"
SCAN="$ROOT/skills/appstore-precheck/scripts/scan.sh"

run_meta() { # run_meta <name> <subtitle> <keywords> <description>
  local d; d="$(mktemp -d)"; mkdir -p "$d/fastlane/metadata/en-US"
  printf '%s' "$1" > "$d/fastlane/metadata/en-US/name.txt"
  printf '%s' "$2" > "$d/fastlane/metadata/en-US/subtitle.txt"
  printf '%s' "$3" > "$d/fastlane/metadata/en-US/keywords.txt"
  printf '%s' "$4" > "$d/fastlane/metadata/en-US/description.txt"
  ( cd "$d" && APPSTORE_PRECHECK_CONFIG=/nonexistent bash "$SCAN" 2>&1 )
  rm -rf "$d"
}

section "fires on the categories Apple names in 4.3(b)"
out="$(run_meta 'Flashlight Pro' 'Simple torch' 'flashlight,torch' 'A bright light.')"
assert_contains "$out" "WARN: 4.3 Saturated category" "flashlight is named in 4.3(b)"
assert_contains "$out" "flashlight" "the matched term is shown"
assert_contains "$out" "meaningfully different" "quotes Apple's own bar for acceptance"

for pair in "Dating Now:dating" "Live Wallpaper HD:wallpaper" "Fortune Teller:fortune telling" \
            "Sound Effects Box:sound effects" "Drinking Games Party:drinking game"; do
  n="${pair%%:*}"; term="${pair##*:}"
  o="$(run_meta "$n" 'An app' 'fun' 'Something.')"
  assert_contains "$o" "WARN: 4.3 Saturated category" "fires for '$n' ($term)"
done

section "does not fire on unrelated apps"
o="$(run_meta 'Budget Tracker' 'Track your spending' 'budget,money' 'Track expenses.')"
assert_absent "$o" "WARN: 4.3 Saturated category" "an ordinary app is not flagged"
assert_contains "$o" "PASS: 4.3" "and says so explicitly"

section "the description is NOT matched (feature mentions are not category claims)"
# A camera app that merely mentions a flashlight feature is not a flashlight app.
o="$(run_meta 'Night Camera' 'Low-light photography' 'camera,photo' \
     'Shoot in the dark. Includes a flashlight and a self timer for group shots.')"
assert_absent "$o" "WARN: 4.3 Saturated category" "description-only mentions do not fire"

section "word boundaries hold"
# 'fart' must not match inside 'farther'; 'dating' must not match 'updating'.
o="$(run_meta 'Go Farther' 'Updating your run log' 'running,fitness' 'Track runs.')"
assert_absent "$o" "WARN: 4.3 Saturated category" "substring matches do not fire"

section "the finding is labelled and catalogued like every other rule"
d="$(mktemp -d)"; cp -R "$HERE/fixtures/saturated-app/." "$d/"
j="$(cd "$d" && APPSTORE_PRECHECK_CONFIG=/nonexistent bash "$SCAN" --format json 2>/dev/null)"
f="$(jq -c '[.findings[]|select(.rule_id=="saturated-category")][0]' <<<"$j")"
assert_eq "saturated-category" "$(jq -r .rule_id <<<"$f")" "rule_id set"
assert_eq "4.3"           "$(jq -r .guideline <<<"$f")"  "guideline is 4.3"
assert_eq "metadata"      "$(jq -r .evidence <<<"$f")"   "read from the store listing"
assert_eq "judgment-call" "$(jq -r .confidence <<<"$f")" "exposure, not a mechanical block"
assert_eq "https://developer.apple.com/app-store/review/guidelines/#4.3" \
  "$(jq -r .guideline_url <<<"$f")" "deep link to 4.3"
rm -rf "$d"

section "4.3 is citable and tracked for drift"
cite="$(bash "$ROOT/skills/appstore-precheck/scripts/guideline-cite.sh" 4.3)"; st=$?
assert_eq "$st" "0" "4.3 has a pinned quote"
assert_contains "$cite" "indistinguishable from" "the pinned quote is Apple's 4.3(b) wording"
assert_contains "$(jq -r '.covered_by_scan[]' "$ROOT/skills/appstore-precheck/guidelines-baseline.json")" \
  "4.3" "4.3 is declared covered so the drift job watches it"

exit "$fails"
