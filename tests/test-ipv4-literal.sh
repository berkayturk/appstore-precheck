#!/usr/bin/env bash
# tests/test-ipv4-literal.sh — §55 ipv4-literal (2.5.5 IPv6-only networks).
# App Review runs on an IPv6-only NAT64 network. DNS64/NAT64 rewrites hostnames
# transparently, but an IPv4 LITERAL never gets a AAAA record and the legacy
# BSD-socket IPv4 API cannot address an IPv6 network at all. Only the greppable
# subset is checked statically; the actual NAT64 run is GUI-only (manual checklist).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck source=tests/_assert.sh
source "$HERE/_assert.sh"
SCAN="$ROOT/skills/appstore-precheck/scripts/scan.sh"

run_fixture() { # run_fixture <name> [scan args]
  local d; d="$(mktemp -d)"; cp -R "$HERE/fixtures/$1/." "$d/"; shift
  ( cd "$d" && APPSTORE_PRECHECK_CONFIG=/nonexistent bash "$SCAN" "$@" 2>&1 )
  rm -rf "$d"
}
run_src() { # run_src <swift-body> -> scan output for a one-file app
  local d; d="$(mktemp -d)"; mkdir -p "$d/ios/App"
  printf '<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>x</string></dict></plist>\n' > "$d/ios/App/Info.plist"
  printf 'import SwiftUI\n@main struct A: App { var body: some Scene { WindowGroup { NavigationStack { Text("x") } } } }\n%s\n' "$1" > "$d/ios/App/App.swift"
  ( cd "$d" && APPSTORE_PRECHECK_CONFIG=/nonexistent bash "$SCAN" 2>&1 )
  rm -rf "$d"
}

section "fires on IPv4-only socket APIs and hardcoded IPv4 literals"
out="$(run_fixture ipv4-literal-app)"
assert_contains "$out" "WARN: 2.5.5 IPv6-only" "the fixture trips §55"
assert_contains "$out" "inet_addr" "the legacy API is named in the detail"
assert_contains "$out" "198.51.100.7" "the source literal is shown"
assert_contains "$out" "203.0.113.10" "the plist literal is shown too"
assert_absent   "$out" "FAIL: 2.5.5" "never a FAIL — Apple tests this on NAT64, a human rejects it"
assert_absent   "$out" "1.2.3.4" "a version string is not reported as an address"

section "each signal fires on its own"
for sig in 'let a = inet_aton("x", nil)' 'let f = AF_INET' 'var s = sockaddr_in()' 'let h = gethostbyname("x")' 'let u = "https://192.0.2.44/api"'; do
  o="$(run_src "$sig")"
  assert_contains "$o" "WARN: 2.5.5 IPv6-only" "fires for: $sig"
done

section "stays silent on the excluded forms"
out="$(run_fixture ipv4-clean-app)"
assert_absent   "$out" "WARN: 2.5.5" "loopback, 0.0.0.0, CIDR, version strings, comments, AF_INET6/sockaddr_in6 do not fire"
assert_contains "$out" "PASS: 2.5.5 IPv6-only" "and the rule says it ran"
for sig in 'let a = sockaddr_in6()' 'let f = AF_INET6' 'let h = gethostbyname2("x", AF_INET6)' '// inet_addr("1.2.3.4") in a comment' 'let v = "v1.2.3.4"' 'let n = "255.255.255.0"'; do
  o="$(run_src "$sig")"
  assert_absent "$o" "WARN: 2.5.5" "silent for: $sig"
done

section "the finding is labelled and catalogued like every other rule"
j="$(run_fixture ipv4-literal-app --format json 2>/dev/null | sed -n '/^{/,$p')"
f="$(jq -c '[.findings[]|select(.rule_id=="ipv4-literal")][0]' <<<"$j")"
assert_eq "ipv4-literal" "$(jq -r .rule_id <<<"$f")"    "rule_id set"
assert_eq "WARN"         "$(jq -r .severity <<<"$f")"   "advisory severity"
assert_eq "2.5.5"        "$(jq -r .guideline <<<"$f")"  "guideline is 2.5.5"
assert_eq "source"       "$(jq -r .evidence <<<"$f")"   "concluded from source"
assert_eq "review-risk"  "$(jq -r .confidence <<<"$f")" "a reviewer decides, no validator"
assert_eq "false"        "$(jq -r .needs_build_verification <<<"$f")" "no build qualifier on a review-risk claim"
assert_eq "https://developer.apple.com/app-store/review/guidelines/#2.5.5" "$(jq -r .guideline_url <<<"$f")" "deep link"
assert_not_empty "$(jq -r '.file // ""' <<<"$f")" "carries a file reference"

section "2.5.5 is citable and tracked for drift"
cite="$(bash "$ROOT/skills/appstore-precheck/scripts/guideline-cite.sh" 2.5.5)"; st=$?
assert_eq "$st" "0" "2.5.5 has a pinned quote"
assert_contains "$cite" "fully functional on IPv6-only networks" "the pinned quote is Apple's 2.5.5 wording"
assert_contains "$(jq -r '.covered_by_scan[]' "$ROOT/skills/appstore-precheck/guidelines-baseline.json")" \
  "2.5.5" "2.5.5 is declared covered so the drift job watches it"

exit "$fails"
