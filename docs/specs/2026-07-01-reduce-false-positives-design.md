# Design — Real-Code False-Positive Reduction (measurement-driven)

- **Date:** 2026-07-01
- **Status:** Approved (scope #1–5)
- **Author:** Berkay Turk
- **Driver:** The Phase-3 real-app panel (18 apps, `corpus/real/labels.json` candidate labels)
  measured aggregate precision **0.74**, but **0.37** once openfoodfacts-ios's 146 real
  `metadata-char-limits` hits are excluded. 62 false positives cluster into a few root causes.
  This is the measurement paying off: concrete, ranked fix targets.

## 1. Scope

Fix the five highest-ROI, low/medium-risk false-positive sources (≈49 of 62 FPs). **Deferred to a
follow-up** (higher risk / inherently static-limited): the `IOS_DIR` auto-detection rework
(lands on thin app-shell / vendored dirs / custom-named plists — a cross-cutting cause of
several FPs), `demo-account` (5 FP — can't tell statically if login gates core functionality),
and `private-api` comment-line skipping (1 FP).

## 2. Invariants for THIS round (differs from the scorecard round)

- **READ-ONLY** preserved.
- **Behavior intentionally changes.** Unlike the suppression round, these fixes deliberately
  change what the scanner emits on affected inputs. Therefore **default text output is NOT
  byte-identical** for fixtures that exercise a fixed check. Each fix updates the affected
  fixture expectations (`tests/run.sh` asserts), the synthetic `corpus/synthetic/labels.json`,
  and regenerates `docs/scorecard.md` — all under TDD.
- **No regressions on true positives.** Every fix must keep firing on inputs where the concern is
  real (guarded by a fixture that SHOULD trip the check).
- **Bash 3.2**, **no competitor name**, **TDD**, **version lockstep** unchanged.

## 3. The five fixes (grounded in current `scan.sh`)

### Fix 1 — `analytics-privacyinfo-mismatch` (§19, scan.sh:563): kill the `Segment` substring
- **Now:** `grep -rlE 'FirebaseAnalytics|import Firebase|Amplitude|Mixpanel|import Sentry|Segment|Bugsnag|AppCenterAnalytics|Datadog'`. Bare `Segment` matches `UISegmentedControl`, `SegmentedPickerStyle()`, `segmentSpacing`, `SegmentedControlAccessory` — 7 FPs.
- **Fix:** make every token import- or API-qualified so a UIKit/SwiftUI segmented control can't match:
  `FirebaseAnalytics|import Firebase|import Amplitude|Amplitude\(|import Mixpanel|Mixpanel\.|import Sentry|SentrySDK|import Segment|SEGAnalytics|Analytics\.shared\(|import Bugsnag|Bugsnag\.|AppCenterAnalytics|import Datadog|DatadogCore'`
- **Net:** the only functional change is `Segment` → `import Segment|SEGAnalytics|Analytics\.shared\(` (and hardening the others to import/API forms). Kills all 7 Segment FPs; keeps real Firebase/Sentry/etc. detection.

### Fix 2 — IAP detection (scan.sh:362-364): require real purchase APIs
- **Now:** `grep -rqE 'import StoreKit|RevenueCat|Purchases\.|Product\(for:|AppStore\.|SKProduct|StoreKit2'`. `import StoreKit` fires on rating-prompt (`SKStoreReviewController`) and ad-attribution (`SKAdNetwork`) only apps; `AppStore.` matches a custom namespace (`AppStore.AppPackage`) — 8 FPs across §9/§10.
- **Fix:** drop bare `import StoreKit` and `AppStore.`; require a purchase-specific API:
  `SKPaymentQueue|SKProduct|SKMutablePayment|Product\.products|Product\(for:|Product\(id:|\.purchase\(|Transaction\.currentEntitlements|Transaction\.updates|RevenueCat|Purchases\.(shared|configure|logIn|getProducts)|Adapty|Glassfy|import Qonversion'`
  This never matches `SKStoreReviewController` / `SKAdNetwork` / `SKOverlay`. The second signal
  (`[[ -n "$SUB_VIEW" ]] && iap_detected=1`, a detected paywall-view file) is unchanged, so an
  app with a real paywall view is still gated in.
- **Net:** apps whose only StoreKit use is a rating prompt or ad attribution no longer run the
  3.1.2 paywall checks. Keeps real IAP/subscription apps (RevenueCat, StoreKit2 `Product`/
  `Transaction`, paywall view).

### Fix 3 — `usage-description-crosscheck` (§2, scan.sh:236-249): capture-gated, Photos-aware
- **Now:** a generic `framework:key` loop; `AVFoundation ⇒ NSCamera+NSMicrophone` and
  `Photos ⇒ NSPhotoLibraryUsageDescription` fire on the mere *import*. FPs: playback-only
  AVFoundation (`AVAudioPlayer`/`AVPlayer`/`AVAudioSession(.playback)`) needs neither key;
  `PhotosPicker`/`PHPickerViewController` need no key; add-only Photos
  (`PHAssetCreationRequest`/`UIImageWriteToSavedPhotosAlbum`) is covered by
  `NSPhotoLibraryAddUsageDescription` — 10 FPs.
- **Fix:** keep the generic loop for `FamilyControls`, `CoreLocation`, `Contacts`, `HealthKit`
  (import→key is reasonable there). Replace the AVFoundation and Photos rows with capture-gated
  checks:
  - **Camera:** require `NSCameraUsageDescription` only if `grep -rqE 'AVCaptureDevice|AVCaptureSession|UIImagePickerController'`.
  - **Microphone:** require `NSMicrophoneUsageDescription` only if `grep -rqE 'AVAudioRecorder|AVCaptureDevice|installTap\(|AVAudioSession[^;]*\.record'`.
  - **Photo library (read):** require `NSPhotoLibraryUsageDescription` only if a read/fetch API is
    used — `grep -rqE 'PHAsset\b|PHFetchResult|PHImageManager|fetchAssets|PHAssetCollection'` — and
    it is NOT satisfied by a picker. `PhotosPicker`/`PHPickerViewController` alone → no key.
  - **Photo library (add-only):** if only `PHAssetCreationRequest|UIImageWriteToSavedPhotosAlbum|performChanges` is used (no read API), require `NSPhotoLibraryAddUsageDescription` instead.
- **Note:** wikipedia-ios's usage-description FP is rooted in `IOS_DIR` picking the wrong
  (custom-named) plist — that is the deferred detection issue, so it is NOT fully cleared by this
  fix. This fix clears the AVFoundation/Photos import-heuristic FPs (asspp, achnbrowserui, ehpanda,
  swift-chat).

### Fix 4 — `min-functionality-nav` (§12, scan.sh:448-454): UIKit + RN, repo-wide
- **Now:** `grep -rcE 'TabView|NavigationStack|NavigationSplitView' "$IOS_DIR" --include="*.swift"`.
  Misses UIKit (`UITabBarController`/`UINavigationController`), pre-iOS16 SwiftUI (`NavigationView`),
  React-Navigation, and — because it only searches the auto-detected `$IOS_DIR` — SPM feature
  modules that live outside the thin app-shell target. 9 FPs (every one a real multi-screen app).
- **Fix:** broaden the pattern and search repo-wide with the existing prune set:
  `tab_count=$(grep -rcE 'TabView|NavigationStack|NavigationSplitView|NavigationView|UITabBarController|UINavigationController|createBottomTabNavigator|createStackNavigator|createNativeStackNavigator' . "${GREP_PRUNE[@]}" --include='*.swift' --include='*.m' --include='*.js' --include='*.jsx' --include='*.ts' --include='*.tsx' 2>/dev/null | awk -F: '{sum+=$2} END {print sum+0}')`
- **Net:** the 4.2 WARN now fires only for apps with genuinely no navigation hub of any kind.

### Fix 5 — `screenshots-per-locale` (§7, scan.sh:355-357): no in-repo dir is not a defect
- **Now:** the `else` branch (no `$SCREEN_DIR`) emits `warn "2.3.3 Screenshots — screenshots dir
  not found ..."`. Real apps manage screenshots in App Store Connect / CI, not in git → 15 FPs.
- **Fix:** turn that `else` into a non-firing advisory PASS:
  `pass "2.3.3 Screenshots — no in-repo screenshots dir; assumed managed in App Store Connect (set .screenshotsDir to check in-repo)"`.
  The dir-exists-but-locale-missing path (scan.sh:344-352) is unchanged — those remain real
  findings (e.g. controldopamine's `ru`/`zh-Hans` gaps).

## 4. Test & corpus impact (per fix, TDD)

For each fix:
1. **Add/point a fixture that reproduces the FP** (a scenario where the check must NOT fire) and
   assert absence; keep/verify a fixture where the concern IS real still fires (no TP regression).
   Prefer extending existing fixtures (`tests/fixtures/*`) and `tests/run.sh` asserts.
2. **Update `tests/run.sh`** expectations for any fixture whose output legitimately changes.
3. **Update `corpus/synthetic/labels.json`** if a fixture's `expect_fire`/`expect_absent` changes,
   and regenerate `docs/scorecard.md`; `scripts/scorecard.sh --check` must pass.
4. Run the full suite + shellcheck.

## 5. Remeasurement (final task)

Re-run the real-app panel against the fixed scanner (reuse `corpus/real/labels.json` candidate
labels): findings that were FP and are now fixed no longer fire, so they drop out of the join and
precision rises. Report before/after per-rule precision. Because the labels are keyed by
`rule_id+file+line`, a fixed FP simply disappears from the scan output; the remaining joined
findings give the improved number. Publish the before/after in the measurement report (still
candidate-labelled; no over-claim).

## 6. Files

| File | Change |
|---|---|
| `skills/appstore-precheck/scripts/scan.sh` | Fixes 1–5 (analytics regex, IAP regex, usage-description capture-gating, min-nav pattern+scope, screenshots else-branch) |
| `tests/fixtures/*`, `tests/run.sh` | reproduce FPs + update changed expectations |
| `corpus/synthetic/labels.json`, `docs/scorecard.md` | update + regenerate if fixture firing changes |
| `corpus/real/labels.json` | candidate baseline (already committed on this branch) — reused for remeasurement |

## 7. Sequencing
Fix 1 (analytics) → Fix 2 (IAP) → Fix 3 (usage-description) → Fix 4 (min-nav) → Fix 5
(screenshots) → remeasure + synthetic-corpus reconcile + whole-branch review. Fix 1 is the
cleanest and doubles as the pilot for the fixture→fix→synthetic-update→panel-remeasure flow.
