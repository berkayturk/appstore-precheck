#!/usr/bin/env bash
# Argument planning runs on every CI host, without Xcode or Maestro.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/_assert.sh
source "$ROOT/tests/_assert.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/repo" "$T/App with spaces.app"
cp "$ROOT/tests/fixtures/dynamic-bundle/Installed.app/Info.plist" "$T/App with spaces.app/"
printf '%s\n' '{"selectors":["Settings"]}' > "$T/navigation file.json"
RUN="$ROOT/tests/local/run-dynamic.sh"
# Deliberately omit xcrun and uname, including on a Mac with Xcode installed.
mkdir "$T/bin"
for tool in bash dirname jq python3 cat sort tee tr date cut mkdir rm mktemp awk grep head sed basename find comm wc tail; do
  ln -s "$(command -v "$tool")" "$T/bin/$tool"
done
export PATH="$T/bin"
command -v xcrun >/dev/null 2>&1; status=$?
assert_eq "$status" 1 'xcrun is absent from the test PATH'
tx="$(bash "$RUN" --repo "$T/repo" --app "$T/App with spaces.app" --dry-run --explore \
  --authorized-navigation "$T/navigation file.json" --demo-login --window 7 --repeats 4 --ipad --pktap 2>&1)"; status=$?
assert_eq "$status" 0 'dry-run arguments work without platform prerequisites'
for flag in --explore --authorized-navigation --demo-login --window --repeats --ipad --pktap; do
  assert_contains "$tx" "$flag" "forwarded $flag"
done
assert_contains "$tx" 'navigation\ file.json' 'navigation path is one quoted argument'
assert_contains "$tx" 'PLAN: sleep 7' 'window reaches runner'
assert_eq "$(grep -c 'PLAN: xcrun simctl erase' <<<"$tx")" 4 'repeat count reaches runner'
assert_contains "$tx" 'iPad layout not observed' 'iPad flag reaches runner'
assert_contains "$tx" 'PLAN: sudo tcpdump' 'pktap flag reaches runner'
for flag in --unknown --window --authorized-navigation --repo --app; do
  tx="$(bash "$RUN" "$flag" 2>&1)"; status=$?
  assert_eq "$status" 64 "invalid or missing argument: $flag"
  assert_contains "$tx" 'Usage:' 'usage is shown'
done
exit "$fails"
