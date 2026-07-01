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
# review-prompt-app — the only StoreKit usage is a rating prompt
# (SKStoreReviewController.requestReview), no purchase API and no paywall view.
# Bare `import StoreKit` used to be enough to set iap_detected, so this app got
# false-flagged with 3.1.2 paywall FAILs it doesn't deserve. The IAP gate must
# require an actual purchase-API signal (or a paywall view) before running.
# ---------------------------------------------------------------------------
check_fixture "review-prompt-app" "StoreKit used only for a rating prompt"
assert_has "---END-OF-SCAN---"                                            "scanner ran to completion"
assert_absent "FAIL: 3.1.2"                                               "review-prompt: no paywall FAIL when StoreKit is only a rating prompt"
assert_has "PASS: 3.1.2 IAP — no in-app purchase"                         "review-prompt: IAP gate correctly skips"
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
assert_absent "WARN: 2.3.3 Screenshots — screenshots dir not found"       "no-screenshots: absent in-repo screenshots dir is not a WARN (managed in ASC)"
finish_fixture

# ---------------------------------------------------------------------------
# segmented-ui-app — a SwiftUI Picker with .pickerStyle(SegmentedPickerStyle())
# plus a UIKit UISegmentedControl(), and NO analytics SDK. The bare "Segment"
# substring in the old analytics-privacyinfo-mismatch regex matched these UI
# APIs and false-fired the §19 privacy-manifest WARN; the import/API-qualified
# regex must not.
# ---------------------------------------------------------------------------
check_fixture "segmented-ui-app" "segmented control, no analytics SDK (§19 false-positive regression)"
assert_has "---END-OF-SCAN---"                                            "scanner ran to completion"
assert_absent "WARN: 5.1.1 Privacy manifest — analytics SDK detected"     "segmented-ui: no analytics-SDK false positive"
finish_fixture

# ---------------------------------------------------------------------------
# audio-playback-app — `import AVFoundation` used ONLY for playback
# (AVAudioPlayer + AVAudioSession.setCategory(.playback)), no capture API at
# all. The old generic framework loop treated the bare import as proof of
# camera+mic use; the capture-gated §2 restructure must stay silent since
# neither a camera- nor a microphone-capture API is present.
# ---------------------------------------------------------------------------
check_fixture "audio-playback-app" "playback-only AVFoundation — no camera/mic FP"
assert_has "---END-OF-SCAN---"                                            "scanner ran to completion"
assert_absent "FAIL: 5.1.1 camera capture API"                            "no camera-capture FAIL: playback-only AVFoundation use"
assert_absent "FAIL: 5.1.1 microphone/recording API"                      "no microphone-capture FAIL: .playback category, not .record"
assert_absent "FAIL: 5.1.1 framework 'AVFoundation'"                      "legacy import-based AVFoundation FAIL is gone (generic entry removed)"
finish_fixture

# ---------------------------------------------------------------------------
# photos-picker-app — `import PhotosUI` with PhotosPicker only, no PHAsset
# read. PhotosPicker runs out-of-process and needs NO Info.plist key at all.
# The old generic framework loop treated the bare "Photos" substring match
# (present inside "PhotosUI") as proof of library access; the capture-gated
# restructure must stay silent since no PHAsset/PHFetchResult/PHImageManager
# read API and no PHAssetCreationRequest/save API is present.
# ---------------------------------------------------------------------------
check_fixture "photos-picker-app" "PhotosPicker only — no NSPhotoLibraryUsageDescription FP"
assert_has "---END-OF-SCAN---"                                            "scanner ran to completion"
assert_absent "FAIL: 5.1.1 Photos"                                        "no legacy import-based Photos FAIL (PhotosPicker needs no key)"
finish_fixture

# ---------------------------------------------------------------------------
# camera-capture-app — TP-GUARD fixture. Drives AVCaptureSession/
# AVCaptureDevice directly (real capture, not a bare import) with NO
# NSCameraUsageDescription in Info.plist. Proves the capture-gated §2
# restructure did not just get disabled: a genuine capture API without the
# purpose string must still FAIL.
# ---------------------------------------------------------------------------
check_fixture "camera-capture-app" "TP-guard: real AVCaptureSession capture without purpose string"
assert_has "---END-OF-SCAN---"                                            "scanner ran to completion"
assert_has "FAIL: 5.1.1 camera capture API used but Info.plist is missing 'NSCameraUsageDescription'" "capture-gated check still fires on a real capture API (no TP regression)"
assert_absent "FAIL: 5.1.1 microphone/recording API"                      "video-only AVCaptureDevice(for: .video) must NOT force a microphone-purpose-string requirement"
finish_fixture

# ---------------------------------------------------------------------------
# voice-recorder-app — mic TP-guard fixture. Sets AVAudioSession's category to
# .playAndRecord (the standard record+monitor category) and uses AVAudioRecorder,
# with NO NSMicrophoneUsageDescription in Info.plist. The old mic regex
# (`AVAudioSession[^;]*\.record`) does not match `.playAndRecord` — this fixture
# proves the mic-gating regex now matches the .playAndRecord category too.
# ---------------------------------------------------------------------------
check_fixture "voice-recorder-app" "TP-guard: .playAndRecord category without purpose string"
assert_has "---END-OF-SCAN---"                                            "scanner ran to completion"
assert_has "FAIL: 5.1.1 microphone/recording API used but Info.plist is missing 'NSMicrophoneUsageDescription'" "mic-gated check fires on .playAndRecord category (no TP regression)"
finish_fixture

# ---------------------------------------------------------------------------
# uikit-nav-app — navigation is pure UIKit (UITabBarController root embedded in
# a UINavigationController), with NO SwiftUI TabView/NavigationStack anywhere.
# The old §12 pattern only matched SwiftUI tokens inside the auto-detected
# $IOS_DIR, so a real multi-screen UIKit app false-flagged 4.2 Minimum
# functionality (real-panel FP). The broadened, repo-wide pattern must
# recognize UIKit's own nav-hub APIs.
# ---------------------------------------------------------------------------
check_fixture "uikit-nav-app" "pure UIKit UITabBarController/UINavigationController nav (§12 false-positive regression)"
assert_has "---END-OF-SCAN---"                                            "scanner ran to completion"
assert_absent "WARN: 4.2 Minimum functionality"                           "uikit-nav: no 4.2 FP for a UIKit UITabBarController app"
finish_fixture

check_fixture "pbxproj-generate-app" "app uses GENERATE_INFOPLIST_FILE; extension owns the only plist"
assert_has  "PASS: layout — ios='MyApp'"  "project-model picks the app dir, not the extension"
assert_absent "ios='MyWidget'"            "detection does not land on the extension dir"
finish_fixture

check_fixture "pbxproj-multiapp" "two application targets; the larger one wins"
assert_has  "ios='AppB'"                  "project-model picks the app with more sources"
finish_fixture

# ---------------------------------------------------------------------------
echo "================================================================"
if (( total_fails == 0 )); then
  echo "ALL TESTS PASSED"
else
  echo "$total_fails ASSERTION(S) FAILED"
  exit 1
fi
