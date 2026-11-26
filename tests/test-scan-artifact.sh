#!/usr/bin/env bash
# tests/test-scan-artifact.sh — `scan.sh --artifact <.app|.ipa|.xcarchive>`: the nine
# read-only artifact-review checks join the scan output as catalogued rules, with
# `artifact` evidence, without executing the bundle. Without the flag nothing changes.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck source=tests/_assert.sh
source "$HERE/_assert.sh"
SCAN="$ROOT/skills/appstore-precheck/scripts/scan.sh"
APP="$HERE/fixtures/dynamic-bundle/Installed.app"
REPO="$HERE/fixtures/dynamic-bundle/repo"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
run() { APPSTORE_PRECHECK_CONFIG=/nonexistent bash "$SCAN" "$@" 2>/dev/null; }
count_artifact() { printf '%s\n' "$1" | grep -cE '^(FAIL|WARN|PASS|SKIP): [0-9.]+ artifact-[a-z-]+ — '; }

section "without --artifact the scan is unchanged"
out="$(run --dir "$REPO")"
assert_eq "$(count_artifact "$out")" "0" "no artifact lines without the flag"

section "--artifact <.app> adds the nine artifact checks"
out="$(run --dir "$REPO" --artifact "$APP")"
assert_eq "$(count_artifact "$out")" "9" "nine artifact lines"
assert_contains "$out" " 1.6 artifact-ats — " "ATS check is filed under 1.6"
assert_contains "$out" " 2.5.1 artifact-private-api — " "private framework linkage is filed under 2.5.1"
assert_contains "$out" " 5.1.1 artifact-reason-api — " "required-reason API check is filed under 5.1.1"
assert_absent "$out" "^FAIL: [0-9.]+ artifact-" "artifact checks never FAIL on their own"

section "--ipa <.ipa> reads the Payload app"
( cd "$T" && mkdir -p Payload && cp -R "$APP" Payload/ && python3 - <<'PY'
import zipfile, pathlib
with zipfile.ZipFile('app.ipa', 'w') as z:
    for p in sorted(pathlib.Path('Payload').rglob('*')):
        z.write(p, str(p))
PY
)
out="$(run --dir "$REPO" --ipa "$T/app.ipa")"
assert_eq "$(count_artifact "$out")" "9" "nine artifact lines from the IPA"

section "a missing artifact is nine honest SKIPs"
out="$(run --dir "$REPO" --artifact "$T/nope.ipa")"
assert_eq "$(printf '%s\n' "$out" | grep -cE '^SKIP: [0-9.]+ artifact-')" "9" "every artifact check reports a gap"

section "JSON carries the artifact evidence class"
json="$(run --dir "$REPO" --artifact "$APP" --format json)"
assert_eq "$(jq -r '[.findings[] | select(.rule_id | startswith("artifact-"))] | length' <<<"$json")" "9" "nine artifact findings in JSON"
assert_eq "$(jq -r '[.findings[] | select((.rule_id | startswith("artifact-")) and .severity != "SKIP") | .evidence] | unique | join(",")' <<<"$json")" "artifact" "evidence class is artifact on every PASS/WARN"
assert_eq "$(jq -r '[.findings[] | select((.rule_id | startswith("artifact-")) and .severity != "SKIP")] | length > 0' <<<"$json")" "true" "at least one artifact check actually ran on the fixture"

section "a relative --artifact path is resolved from the caller's directory"
out="$( cd "$HERE" && APPSTORE_PRECHECK_CONFIG=/nonexistent bash "$SCAN" --dir fixtures/dynamic-bundle/repo --artifact fixtures/dynamic-bundle/Installed.app 2>/dev/null )"
assert_eq "$(printf '%s\n' "$out" | grep -cE '^SKIP: [0-9.]+ artifact-')" "$(printf '%s\n' "$(run --dir "$REPO" --artifact "$APP")" | grep -cE '^SKIP: [0-9.]+ artifact-')" "same SKIP count as the absolute path"
assert_eq "$(count_artifact "$out")" "9" "nine artifact lines from a relative path"

exit "$fails"
