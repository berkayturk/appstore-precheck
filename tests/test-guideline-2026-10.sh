#!/usr/bin/env bash
# tests/test-guideline-2026-10.sh — the October 16, 2026 App Review Guidelines update:
#   §22 (1.2)      AI content-creation signals join the UGC signal list; WARN names NCII + Code of Conduct.
#   §50 (4.5.3)    Live Activities (ActivityKit / NSSupportsLiveActivities) ride on the push vector.
#   §15 (3.1.1(a)) WARN speaks Apple's "permitted destination" language.
# One minimal app per signal, built from an existing fixture with its sources replaced.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/_assert.sh
source "$DIR/_assert.sh"
SCAN="$DIR/../skills/appstore-precheck/scripts/scan.sh"

# scan_with <fixture> <src-rel-path> <swift-source> [plist-fragment]
# Copies the fixture, replaces every Swift file with the snippet, optionally injects a
# plist fragment before the closing </dict>, scans the copy and echoes the output.
scan_with() {
  local fixture="$1" src_rel="$2" src="$3" plist_extra="${4:-}" tmp out
  tmp="$(mktemp -d)"
  cp -R "$DIR/fixtures/$fixture/." "$tmp/"
  rm -f "$tmp/$(dirname "$src_rel")"/*.swift
  printf '%s\n' "$src" > "$tmp/$src_rel"
  if [[ -n "$plist_extra" ]]; then
    local plist; plist="$(find "$tmp" -name Info.plist | head -1)"
    python3 - "$plist" "$plist_extra" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); t = p.read_text()
i = t.rfind('</dict>'); p.write_text(t[:i] + sys.argv[2] + '\n' + t[i:])
PY
  fi
  out="$( cd "$tmp" && APPSTORE_PRECHECK_CONFIG=/nonexistent bash "$SCAN" 2>&1 )"
  rm -rf "$tmp"
  printf '%s' "$out"
}

UGC_SRC="ios/TrackingApp/ContentView.swift"
UGC_WARN="WARN: 1.2 UGC"
UGC_PASS="PASS: 1.2 UGC"

section "§22 — 1.2 AI content creation counts as user-generated content"

out="$(scan_with tracking-app "$UGC_SRC" 'let url = URL(string: "https://api.openai.com/v1/images/generations")!')"
assert_contains "$out" "$UGC_WARN" "OpenAI image-generation endpoint fires the UGC check"
assert_contains "$out" "AI content creation apps" "WARN names AI content creation apps"
assert_contains "$out" "nonconsensual intimate imagery" "WARN names nonconsensual intimate imagery"
assert_contains "$out" "Developer Code of Conduct" "WARN names the Code of Conduct consequence"

out="$(scan_with tracking-app "$UGC_SRC" 'import ImagePlayground
struct Studio: View { @State var show = false; var body: some View { Text("Art").imagePlaygroundSheet(isPresented: $show) { _ in } } }')"
assert_contains "$out" "$UGC_WARN" "ImagePlayground import fires the UGC check"

for sig in 'let base = "https://api.replicate.com/v1/predictions"' \
           'let base = "https://fal.run/fal-ai/flux"' \
           'let base = "https://api.stability.ai/v2beta/stable-image/generate"' \
           'let base = "https://api.dev.runwayml.com/v1/image_to_video"' \
           'func generateImage(prompt: String) async throws -> UIImage { fatalError() }' \
           'let pipeline = StableDiffusionPipeline(resourcesAt: url)'; do
  out="$(scan_with tracking-app "$UGC_SRC" "$sig")"
  assert_contains "$out" "$UGC_WARN" "generation signal fires: ${sig:0:60}"
done

out="$(scan_with tracking-app "$UGC_SRC" 'func generateImage(prompt: String) {}
func reportContent(_ id: String) {}
func blockUser(_ id: String) {}')"
assert_contains "$out" "$UGC_PASS" "generation + report/block affordances passes"

for neg in 'let thumb = generateImageThumbnail(for: asset)' \
           'let image = UIImage(named: "hero")' \
           'let caption = "Generated with love by our team"'; do
  out="$(scan_with tracking-app "$UGC_SRC" "$neg")"
  assert_absent "$out" "1.2 UGC" "no UGC line for: $neg"
done

section "§50 — 4.5.3 Live Activities signal on the push vector"

PUSH_SRC="ios/PushApp/AppDelegate.swift"
MKT='import UIKit
import OneSignal
import ActivityKit
class AppDelegate: UIResponder, UIApplicationDelegate {
  func boot() { OneSignal.initialize("app-id", withLaunchOptions: nil); UIApplication.shared.registerForRemoteNotifications() }
  func start() { let _ = try? Activity<DeliveryAttributes>.request(attributes: DeliveryAttributes(), content: .init(state: .init(), staleDate: nil)) }
}'
out="$(scan_with push-marketing-app "$PUSH_SRC" "$MKT")"
assert_contains "$out" "WARN: 4.5.3 Live Activities" "ActivityKit + marketing-push SDK warns"
assert_contains "$out" "push-to-start" "WARN points at push-to-start Live Activities"
assert_contains "$out" "WARN: 4.5.4 Marketing push" "the 4.5.4 check still runs alongside"

PLAIN='import UIKit
import ActivityKit
struct DeliveryAttributes: ActivityAttributes { struct ContentState: Codable, Hashable {} }'
out="$(scan_with push-marketing-app "$PUSH_SRC" "$PLAIN")"
assert_contains "$out" "PASS: 4.5.3 Live Activities" "ActivityKit without a marketing SDK is a PASS note"
assert_absent "$out" "WARN: 4.5.3" "no 4.5.3 WARN without a marketing SDK"

out="$(scan_with push-marketing-app "$PUSH_SRC" 'import UIKit
class AppDelegate: UIResponder {}' '<key>NSSupportsLiveActivities</key><true/>')"
assert_contains "$out" "4.5.3 Live Activities" "NSSupportsLiveActivities=true alone is a signal"

out="$(scan_with push-marketing-app "$PUSH_SRC" 'import UIKit
class AppDelegate: UIResponder {}')"
assert_absent "$out" "4.5.3 Live Activities" "no Live Activities line without ActivityKit or the plist key"

section "§15 — 3.1.1(a) permitted-destination language"

tmp="$(mktemp -d)"; cp -R "$DIR/fixtures/social-login-app/." "$tmp/"
out="$( cd "$tmp" && APPSTORE_PRECHECK_CONFIG=/nonexistent bash "$SCAN" 2>&1 )"; rm -rf "$tmp"
assert_contains "$out" "WARN: 3.1.1(a) External purchase link detected" "3.1.1(a) still flagged"
assert_contains "$out" "permitted destination" "WARN uses Apple's permitted-destination wording"
assert_contains "$out" "approved destinations vary by region" "WARN notes regional variation"
assert_absent "$out" "developer owns or maintains" "old website-ownership wording is gone"

exit "$fails"
