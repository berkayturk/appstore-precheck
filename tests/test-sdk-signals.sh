#!/usr/bin/env bash
# tests/test-sdk-signals.sh — per-SDK coverage for the two signal lists that go stale
# fastest: §3/§16 tracking (`tracking_sdk`) and §19 analytics (`analytics_sdk`).
#
# A missing SDK in either list is a SILENT false negative: the scan stays quiet on an
# app that will draw a 5.1.2 (ATT) or 5.1.1 (privacy manifest) rejection. A fixture per
# SDK would be unreadable, so this drives one minimal app per signal instead: the
# tracking-app fixture with its single Swift source replaced by the snippet under test.
#
# tracking-app is the right base because it already has no ATT prompt and an empty
# PrivacyInfo.xcprivacy, so a matched tracking signal must WARN and a matched analytics
# signal must WARN. Negative cases guard the FP-prone words in the lists.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/_assert.sh
source "$DIR/_assert.sh"
SCAN="$DIR/../skills/appstore-precheck/scripts/scan.sh"
FIXTURE="$DIR/fixtures/tracking-app"
SRC_REL="ios/TrackingApp/ContentView.swift"

TRACKING_WARN="WARN: 5.1.2 Tracking SDK"
ANALYTICS_WARN="WARN: 5.1.1 Privacy manifest — analytics SDK detected"

# scan_with <swift-source> — copy the fixture, replace its only Swift file with the
# given source, scan the copy, echo the combined output.
scan_with() {
  local src="$1" tmp out
  tmp="$(mktemp -d)"
  cp -R "$FIXTURE/." "$tmp/"
  # Drop every bundled source first: the fixture ships its own SDK imports, and a
  # leftover one would make the negative cases pass for the wrong reason.
  rm -f "$tmp/$(dirname "$SRC_REL")"/*.swift
  printf '%s\n' "$src" > "$tmp/$SRC_REL"
  out="$( cd "$tmp" && APPSTORE_PRECHECK_CONFIG=/nonexistent bash "$SCAN" 2>&1 )"
  rm -rf "$tmp"
  printf '%s' "$out"
}

# expect_fires <needle> <label> <swift-source>
expect_fires() { assert_contains "$(scan_with "$3")" "$1" "$2"; }
# expect_silent <needle> <label> <swift-source>
expect_silent() { assert_absent "$(scan_with "$3")" "$1" "$2"; }

# ---------------------------------------------------------------------------
# §3/§16 — ad / attribution / IDFA SDKs (5.1.2)
# Snippets use each SDK's real module or entry-point symbol, not a guessed name.
# ---------------------------------------------------------------------------
section "5.1.2 tracking-SDK signals (issue #16)"

expect_fires "$TRACKING_WARN" "raw IDFA via ASIdentifierManager" \
'import AdSupport
let idfa = ASIdentifierManager.shared().advertisingIdentifier'

expect_fires "$TRACKING_WARN" "Google AdMob (GADMobileAds)" \
'import GoogleMobileAds
func boot() { GADMobileAds.sharedInstance().start(completionHandler: nil) }'

expect_fires "$TRACKING_WARN" "AppLovin MAX (ALSdk)" \
'import AppLovinSDK
let sdk = ALSdk.shared()'

expect_fires "$TRACKING_WARN" "AppsFlyer (AppsFlyerLib)" \
'import AppsFlyerLib
func boot() { AppsFlyerLib.shared().start() }'

expect_fires "$TRACKING_WARN" "Adjust" \
'import Adjust
func boot() { Adjust.appDidLaunch(nil) }'

expect_fires "$TRACKING_WARN" "Meta Audience Network (FBAudienceNetwork)" \
'import FBAudienceNetwork
func boot() { FBAdSettings.setAdvertiserTrackingEnabled(true) }'

expect_fires "$TRACKING_WARN" "Branch (BranchSDK)" \
'import BranchSDK
func boot() { Branch.getInstance().initSession() }'

expect_fires "$TRACKING_WARN" "ironSource" \
'import IronSource
func boot() { IronSource.initWithAppKey("k") }'

expect_fires "$TRACKING_WARN" "Unity Ads" \
'import UnityAds
func boot() { UnityAds.initialize(gameId: "1234", testMode: false) }'

expect_fires "$TRACKING_WARN" "Vungle / Liftoff (VungleAdsSDK)" \
'import VungleAdsSDK
func boot() { VungleAds.initWithAppId("app") }'

expect_fires "$TRACKING_WARN" "Chartboost" \
'import ChartboostSDK
func boot() { Chartboost.start(withAppID: "id", appSignature: "sig") { _ in } }'

expect_fires "$TRACKING_WARN" "InMobi (IMSdk)" \
'import InMobiSDK
func boot() { IMSdk.initWithAccountID("acct") { _ in } }'

expect_fires "$TRACKING_WARN" "Mintegral (MTGSDK)" \
'import MTGSDK
func boot() { MTGSDK.sharedInstance().setAppID("id", apiKey: "key") }'

expect_fires "$TRACKING_WARN" "Pangle / TikTok (PAGAdSDK)" \
'import PAGAdSDK
func boot() { PAGConfig.share().appID = "id" }'

expect_fires "$TRACKING_WARN" "Pangle legacy (BUAdSDK)" \
'import BUAdSDK
func boot() { BUAdSDKManager.setAppID("id") }'

expect_fires "$TRACKING_WARN" "Singular" \
'import Singular
func boot() { Singular.start(SingularConfig(apiKey: "k", andSecret: "s")) }'

expect_fires "$TRACKING_WARN" "Kochava (KVATracker)" \
'import KochavaTracker
func boot() { KVATracker.shared.start(withAppGUIDString: "guid") }'

expect_fires "$TRACKING_WARN" "Tenjin" \
'import TenjinSDK
func boot() { TenjinSDK.getInstance("key").connect() }'

# ---------------------------------------------------------------------------
# §19 — analytics SDKs vs an empty PrivacyInfo.xcprivacy (5.1.1)
# ---------------------------------------------------------------------------
section "5.1.1 analytics-SDK signals (issue #17)"

expect_fires "$ANALYTICS_WARN" "Firebase Analytics" \
'import FirebaseAnalytics
func log() { Analytics.logEvent("open", parameters: nil) }'

expect_fires "$ANALYTICS_WARN" "Amplitude" \
'import Amplitude
let amp = Amplitude(configuration: .init(apiKey: "k"))'

expect_fires "$ANALYTICS_WARN" "Mixpanel" \
'import Mixpanel
func log() { Mixpanel.mainInstance().track(event: "open") }'

expect_fires "$ANALYTICS_WARN" "Sentry" \
'import Sentry
func boot() { SentrySDK.start { _ in } }'

expect_fires "$ANALYTICS_WARN" "Segment" \
'import Segment
let analytics = Analytics.shared()'

expect_fires "$ANALYTICS_WARN" "Bugsnag" \
'import Bugsnag
func boot() { Bugsnag.start() }'

expect_fires "$ANALYTICS_WARN" "App Center" \
'import AppCenterAnalytics
func boot() { Analytics.trackEvent("open") }'

expect_fires "$ANALYTICS_WARN" "Datadog" \
'import DatadogCore
func boot() { Datadog.initialize(with: .init(clientToken: "t", env: "prod")) }'

expect_fires "$ANALYTICS_WARN" "PostHog" \
'import PostHog
func boot() { PostHogSDK.shared.setup(PostHogConfig(apiKey: "k")) }'

expect_fires "$ANALYTICS_WARN" "Heap" \
'import Heap
func log() { Heap.track("open") }'

expect_fires "$ANALYTICS_WARN" "Countly" \
'import Countly
func boot() { Countly.sharedInstance().start(with: CountlyConfig()) }'

expect_fires "$ANALYTICS_WARN" "Matomo" \
'import MatomoTracker
let tracker = MatomoTracker(siteId: "1", baseURL: URL(string: "https://m.example")!)'

expect_fires "$ANALYTICS_WARN" "Smartlook" \
'import Smartlook
func boot() { Smartlook.instance.start() }'

expect_fires "$ANALYTICS_WARN" "Instabug" \
'import Instabug
func boot() { Instabug.start(withToken: "t", invocationEvents: []) }'

expect_fires "$ANALYTICS_WARN" "New Relic" \
'import NewRelic
func boot() { NewRelic.start(withApplicationToken: "t") }'

expect_fires "$ANALYTICS_WARN" "Embrace" \
'import EmbraceIO
func boot() { try? Embrace.setup(options: .init(appId: "id")) }'

# ---------------------------------------------------------------------------
# Negative cases — the FP-prone words in both lists. A false WARN on ordinary
# code erodes trust faster than a missed SDK (docs/adding-a-check.md).
# ---------------------------------------------------------------------------
section "no false positives on ordinary code"

expect_silent "$ANALYTICS_WARN" "a hand-rolled heap type is not the Heap SDK" \
'import SwiftUI
struct MinHeap<T: Comparable> { var storage: [T] = [] }
let heap = MinHeap<Int>()   // heap sort scratch space'

expect_silent "$TRACKING_WARN" "the word Singularity is not the Singular SDK" \
'import SwiftUI
let codename = "Singularity"'

expect_silent "$TRACKING_WARN" "adjusting a layout is not the Adjust SDK" \
'import SwiftUI
// Adjust the inset when the keyboard shows
func adjustInset() {}'

expect_silent "$ANALYTICS_WARN" "an embrace animation is not the Embrace SDK" \
'import SwiftUI
// Embrace the whitespace: no chrome on this screen
let embrace = true'

expect_silent "$TRACKING_WARN" "a plain SwiftUI screen trips no tracking signal" \
'import SwiftUI
struct ContentView: View { var body: some View { Text("Hello") } }'

exit "$fails"
