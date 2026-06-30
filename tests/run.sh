#!/usr/bin/env bash
# tests/run.sh — run scan.sh against each fixture project and assert key lines.
# Each fixture is copied to a temp dir OUTSIDE any git repo so scan.sh treats it
# as the root, then run with a non-existent config so auto-detection is exercised.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCAN="$REPO/skills/appstore-precheck/scripts/scan.sh"
FIXTURES="$REPO/tests/fixtures"

total_fails=0

# run_fixture <fixture-dir-name>
# Copies the fixture to a temp dir, runs the scanner there, and echoes its
# combined stdout/stderr. The caller captures the output for assertions.
run_fixture() {
  local fixture="$1" tmp
  tmp="$(mktemp -d)"
  cp -R "$FIXTURES/$fixture/." "$tmp/"
  ( cd "$tmp" && APPSTORE_PRECHECK_CONFIG=/nonexistent bash "$SCAN" 2>&1 )
  local status=$?
  rm -rf "$tmp"
  return "$status"
}

# Per-fixture assertion state. assert_has / assert_absent operate on $OUT and
# accumulate into $fails (reset by check_fixture before each fixture).
fails=0
OUT=""

assert_has() { # assert_has <substring> <why>
  if grep -qF -- "$1" <<<"$OUT"; then
    echo "  ok: $2"
  else
    echo "  FAIL: expected to find: $1  ($2)"
    fails=$((fails + 1))
  fi
}

assert_absent() { # assert_absent <substring> <why>
  if grep -qF -- "$1" <<<"$OUT"; then
    echo "  FAIL: did not expect: $1  ($2)"
    fails=$((fails + 1))
  else
    echo "  ok: $2"
  fi
}

# check_fixture <fixture-dir-name> <human-label>
# Runs the fixture, prints its output, and resets the per-fixture counter.
# Assertions for the fixture follow the call; finish with finish_fixture.
check_fixture() {
  local fixture="$1" label="$2"
  echo "================================================================"
  echo "FIXTURE: $fixture — $label"
  echo "================================================================"
  fails=0
  OUT="$(run_fixture "$fixture")"
  echo "scan output:"
  echo "$OUT" | sed 's/^/    /'
  echo "assertions:"
}

# finish_fixture — fold the per-fixture failures into the grand total.
finish_fixture() {
  if (( fails == 0 )); then
    echo "  -> PASSED"
  else
    echo "  -> $fails ASSERTION(S) FAILED"
  fi
  total_fails=$((total_fails + fails))
  echo
}

# ---------------------------------------------------------------------------
# sample-app — the original baseline: Android mention + bare paywall view.
# ---------------------------------------------------------------------------
check_fixture "sample-app" "baseline with violations"
assert_has "---END-OF-SCAN---"                                            "scanner ran to completion"
assert_has "PASS: 5.1.1 Required Reason API — 'UserDefaults' parity OK"    "PrivacyInfo parity detected"
assert_has "FAIL: 2.3.10 Other-platform mention"                          "Android mention in metadata flagged"
assert_has "FAIL: 3.1.2 Restore Purchases"                                "missing Restore Purchases flagged"
assert_has "FAIL: 3.1.2 Terms of Use"                                     "missing Terms link flagged"
assert_has "FAIL: 3.1.2 Privacy Policy"                                   "missing Privacy link flagged"
assert_has "PASS: 4.2 Minimum functionality"                              "TabView navigation hub detected"
assert_absent "FAIL: 2.5.1"                                               "no false private-API positive"
finish_fixture

# ---------------------------------------------------------------------------
# no-iap-app — no StoreKit/RevenueCat import and no paywall view: the 3.1.2
# paywall checks must be skipped, not failed.
# ---------------------------------------------------------------------------
check_fixture "no-iap-app" "no IAP signals"
assert_has "---END-OF-SCAN---"                                            "scanner ran to completion"
assert_has "PASS: 3.1.2 IAP — no in-app purchase / subscription signals detected, skipping paywall checks" "IAP gate skips paywall checks"
assert_absent "FAIL: 3.1.2"                                               "no paywall FAIL when no IAP"
finish_fixture

# ---------------------------------------------------------------------------
# root-app — Xcode source + fastlane live at the fixture ROOT (no ios/ nesting).
# Auto-detection must still resolve a non-empty iOS source dir.
# ---------------------------------------------------------------------------
check_fixture "root-app" "flat root layout"
assert_has "---END-OF-SCAN---"                                            "scanner ran to completion"
assert_has "PASS: layout — ios='.'"                                       "iOS dir auto-detected at root"
assert_absent "ios='?'"                                                   "iOS source dir is not empty"
finish_fixture

# ---------------------------------------------------------------------------
# clean-app — well-formed app: StoreKit paywall with restore + terms + privacy,
# complete metadata, declared PrivacyInfo. Expect a clean pass (zero FAILs).
# ---------------------------------------------------------------------------
check_fixture "clean-app" "clean well-formed app"
assert_has "---END-OF-SCAN---"                                            "scanner ran to completion"
assert_has "PASS: 3.1.2 Restore Purchases — present"                      "restore purchases detected"
assert_has "PASS: 3.1.2 Terms of Use (EULA) link — present"               "terms link detected"
assert_has "PASS: 3.1.2 Privacy Policy link — present"                    "privacy link detected"
assert_absent "FAIL:"                                                     "no FAIL lines at all"
assert_absent "4.8 Sign in with Apple"                                    "no 4.8 flag without third-party login"
assert_absent "3.1.1(a) External purchase"                                "no 3.1.1(a) flag without external purchase"
assert_absent "WARN: 5.1.2 Tracking SDK"                                  "no tracking-SDK flag without an ad/attribution SDK"
assert_absent "WARN: export-compliance"                                   "export-compliance key present, not flagged"
assert_absent "WARN: 2.3 Support URL"                                     "support_url present, not flagged"
assert_absent "WARN: 2.3 Privacy URL"                                     "privacy_url present, not flagged"
assert_absent "WARN: 5.1.1 Privacy manifest"                              "no analytics SDK, privacy-manifest check silent"
assert_absent "WARN: 2.1 Metadata content"                               "no placeholder text in clean metadata"
finish_fixture

# ---------------------------------------------------------------------------
# watch-app — a Watch App target carries a checked-in Info.plist and MORE Swift
# files than the main app, which has none (auto-generated). Detection must still
# resolve the main app via its entry point, not the Watch app — else IAP in the
# main app is missed. Regression test for the dogfood-found detection bug.
# ---------------------------------------------------------------------------
check_fixture "watch-app" "main app vs Watch app target"
assert_has "---END-OF-SCAN---"                                            "scanner ran to completion"
# Match the dir name without anchoring the ./ prefix (grep -r emits it on some
# platforms but not others); the trailing quote keeps it to the layout line.
assert_has "MainApp'"                                                     "entry-point app target detected, not the Watch app"
assert_absent "WatchApp'"                                                 "Watch app NOT selected as the iOS source dir"
assert_absent "no in-app purchase / subscription signals detected"        "IAP in the main app is detected (not skipped)"
assert_has "PASS: 3.1.2 Restore Purchases — present"                      "paywall links found in the main app"
finish_fixture

# ---------------------------------------------------------------------------
# social-login-app — third-party login (Google) with no Sign in with Apple, plus
# an external-purchase entitlement. Exercises the two advisory checks (4.8, 3.1.1(a)).
# ---------------------------------------------------------------------------
check_fixture "social-login-app" "third-party login + external purchase"
assert_has "---END-OF-SCAN---"                                            "scanner ran to completion"
assert_has "WARN: 4.8 Sign in with Apple"                                 "4.8 flagged: social login without Sign in with Apple"
assert_has "WARN: 3.1.1(a) External purchase link detected"               "3.1.1(a) flagged: external purchase entitlement"
assert_absent "FAIL:"                                                     "advisory only — no FAIL lines"
finish_fixture

# ---------------------------------------------------------------------------
# tracking-app — an ad SDK (AdMob) and an analytics SDK (Firebase) with no ATT
# prompt, no export-compliance key, missing support/privacy URLs, an empty privacy
# manifest, and lorem-ipsum metadata. Exercises the five signal-gated advisory WARNs
# (§16 5.1.2 tracking, §17 export compliance, §18 URLs, §19 privacy manifest, §20
# placeholder). All advisory: no FAIL.
# ---------------------------------------------------------------------------
check_fixture "tracking-app" "tracking/analytics SDKs, advisory WARNs"
assert_has "---END-OF-SCAN---"                                            "scanner ran to completion"
assert_has "WARN: 5.1.2 Tracking SDK"                                     "5.1.2 flagged: tracking SDK without ATT prompt"
assert_has "WARN: export-compliance"                                      "export-compliance flagged: ITSAppUsesNonExemptEncryption missing"
assert_has "WARN: 2.3 Support URL"                                        "2.3 flagged: support_url missing in metadata"
assert_has "WARN: 2.3 Privacy URL"                                        "2.3 flagged: privacy_url missing in metadata"
assert_has "WARN: 5.1.1 Privacy manifest"                                 "5.1.1 flagged: analytics SDK vs empty privacy manifest"
assert_has "WARN: 2.1 Metadata content"                                  "2.1 flagged: lorem-ipsum placeholder in metadata"
assert_absent "FAIL:"                                                     "advisory only — no FAIL lines"
finish_fixture

# ---------------------------------------------------------------------------
# risky-app — exercises the §21–§30 advisory checks: a third-party payment SDK
# (Stripe), UGC without moderation, ATS disabled app-wide, recurring Apple Pay
# without disclosure, a custom App Store review link, misleading + "for kids"
# metadata, a keyboard extension requiring full access, HealthKit + iCloud, and
# a VPN (NetworkExtension). All advisory: no FAIL, so the verdict is YELLOW.
# ---------------------------------------------------------------------------
check_fixture "risky-app" "advisory §21–§30 vectors"
assert_has "---END-OF-SCAN---"                                            "scanner ran to completion"
assert_has "WARN: 3.1.1 Third-party payment SDK"                         "3.1.1 flagged: Stripe payment SDK"
assert_has "WARN: 1.2 UGC"                                               "1.2 flagged: UGC without moderation"
assert_has "WARN: 1.6 App Transport Security"                            "1.6 flagged: NSAllowsArbitraryLoads=true"
assert_has "WARN: 4.9 Apple Pay"                                         "4.9 flagged: recurring Apple Pay without disclosure"
assert_has "WARN: 5.6.1 App reviews"                                     "5.6.1 flagged: custom review link without requestReview"
assert_has "WARN: 2.3.1 Misleading marketing"                            "2.3.1 flagged: virus-scanner claim in metadata"
assert_has "WARN: 2.3.8"                                                 "2.3.8 flagged: 'for kids' wording in metadata"
assert_has "WARN: 4.4.1 Keyboard extension"                              "4.4.1 flagged: keyboard requires full access"
assert_has "WARN: 5.1.3 Health data"                                     "5.1.3 flagged: HealthKit + iCloud"
assert_has "WARN: 5.4 VPN"                                               "5.4 flagged: NetworkExtension/NEVPNManager"
assert_absent "WARN: 5.1.4"                                              "5.1.4 not fired: kids wording without an ad/analytics SDK (§39 gating)"
assert_absent "FAIL:"                                                     "advisory only — no FAIL lines"
finish_fixture

# ---------------------------------------------------------------------------
# risky-app-2 — exercises the v1.3.0 advisory checks (§31–§34, §36–§41): a
# credential login with no demo account, a hot-patch framework, a background mode
# declared but unused, a crypto SDK, a remote-desktop SDK, a Safari extension,
# account creation without deletion, a kids audience with an ad SDK, real-money
# gambling copy, and an MDM signal. All advisory: no FAIL, so the verdict is YELLOW.
# Also carries a SCOPED ATS exception (NSAllowsArbitraryLoadsInWebContent) that must
# NOT trip §23, and asserts the §27↔§39 kids cross-gate (no 2.3.8 double-count).
# ---------------------------------------------------------------------------
check_fixture "risky-app-2" "advisory v1.3.0 vectors (§31–§41)"
assert_has "---END-OF-SCAN---"                                           "scanner ran to completion"
assert_has "WARN: 2.1 Demo account"                                      "2.1 flagged: credential login without demo account"
assert_has "WARN: 2.5.2 Executable code"                                 "2.5.2 flagged: hot-patch framework (JSPatch)"
assert_has "WARN: 2.5.4 Background modes"                                "2.5.4 flagged: location background mode unused"
assert_has "WARN: 3.1.5(a) Cryptocurrency"                               "3.1.5(a) flagged: crypto SDK (WalletConnect)"
assert_has "WARN: 4.2.7 Remote desktop"                                  "4.2.7 flagged: remote-desktop SDK"
assert_has "WARN: 4.4.2 Safari extension"                                "4.4.2 flagged: Safari content-blocker extension"
assert_has "WARN: 5.1.1(v) Account deletion"                             "5.1.1(v) flagged: account creation without deletion"
assert_has "WARN: 5.1.4 Kids"                                            "5.1.4 flagged: kids audience with an ad SDK"
assert_has "WARN: 5.3.4 Gambling"                                        "5.3.4 flagged: real-money gambling copy"
assert_has "WARN: 5.5 MDM"                                               "5.5 flagged: MDM signal"
assert_absent "WARN: 2.3.8"                                              "2.3.8 cross-gated: §39 (5.1.4) owns the kids signal when an ad SDK is linked — no double-count"
assert_absent "WARN: 1.6 App Transport"                                 "1.6 not fired: NSAllowsArbitraryLoadsInWebContent is scoped, not app-wide ATS off"
assert_absent "FAIL:"                                                     "advisory only — no FAIL lines"
finish_fixture

# ---------------------------------------------------------------------------
# webview-app — a thin WKWebView wrapper with a single Swift file. Exercises the
# 4.2.3 web-wrapper heuristic (§35). Advisory: no FAIL.
# ---------------------------------------------------------------------------
check_fixture "webview-app" "thin WKWebView wrapper (§35)"
assert_has "---END-OF-SCAN---"                                           "scanner ran to completion"
assert_has "WARN: 4.2.3 Minimum functionality"                           "4.2.3 flagged: thin WKWebView wrapper"
assert_absent "FAIL:"                                                     "advisory only — no FAIL lines"
finish_fixture

# ---------------------------------------------------------------------------
echo "================================================================"
if (( total_fails == 0 )); then
  echo "ALL TESTS PASSED"
else
  echo "$total_fails ASSERTION(S) FAILED"
  exit 1
fi
