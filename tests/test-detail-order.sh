#!/usr/bin/env bash
# tests/test-detail-order.sh — findings that quote "the first hit" must not depend on
# the filesystem's directory order. APFS and ext4 list directory entries differently,
# and the additions-only golden test pins the exact finding (file, line, detail text).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck source=tests/_assert.sh
source "$HERE/_assert.sh"
SCAN="$ROOT/skills/appstore-precheck/scripts/scan.sh"

section "§40 realmoney-gambling: the quoted hit is the first in path order, not readdir order"
d="$(mktemp -d)"; mkdir -p "$d/fastlane/metadata/en-US"
printf 'Spin the casino wheel.\n' > "$d/fastlane/metadata/en-US/keywords.txt"
printf 'Real money sportsbook with live wagering.\n' > "$d/fastlane/metadata/en-US/description.txt"
printf 'Bet Now\n' > "$d/fastlane/metadata/en-US/name.txt"
j="$(cd "$d" && APPSTORE_PRECHECK_CONFIG=/nonexistent bash "$SCAN" --format json 2>/dev/null)"
f="$(jq -c '.findings[]|select(.rule_id=="realmoney-gambling")' <<<"$j")"
assert_eq "WARN" "$(jq -r .severity <<<"$f")" "gambling language fires"
assert_eq "./fastlane/metadata/en-US/description.txt" "$(jq -r .file <<<"$f")" "description.txt sorts before keywords.txt and is the quoted file"
t="$(cd "$d" && APPSTORE_PRECHECK_CONFIG=/nonexistent bash "$SCAN" 2>/dev/null)"
det="$(printf '%s\n' "$t" | awk '/^WARN: 5.3.4/{f=1; next} f && /^      evidence:/{next} f && /^      \.\//{print; next} f{exit}' | sed 's/^      //')"
assert_eq "$det" "$(printf '%s\n' "$det" | LC_ALL=C sort -t: -k1,1 -k2,2n -k3)" "detail lines are sorted by path then line"
rm -rf "$d"

exit "$fails"
