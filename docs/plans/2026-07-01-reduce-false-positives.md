# False-Positive Reduction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Cut real-code false positives in five scanner checks (analytics, IAP gate, usage-description, min-functionality-nav, screenshots) without regressing true positives, driven by the measured 18-app panel.

**Architecture:** Each fix is a localized change in `skills/appstore-precheck/scripts/scan.sh` (a regex or a small block), paired with a fixture that reproduces the FP (must NOT fire) and preserved coverage where the concern is real (must still fire). Design: `docs/specs/2026-07-01-reduce-false-positives-design.md`.

**Tech Stack:** Bash 3.2, `jq`, POSIX grep/sed/awk. Tests under `tests/`.

## Global Constraints

- **READ-ONLY** — no writes into a scanned project.
- **Behavior intentionally changes** — default text output is NOT byte-identical for fixtures that exercise a fixed check. Update the affected `tests/run.sh` asserts, `corpus/synthetic/labels.json`, and regenerate `docs/scorecard.md` in the SAME task as the fix.
- **No TP regression** — every fix keeps firing where the concern is real (guard with a fixture that SHOULD trip it).
- **Bash 3.2** (no associative arrays / `mapfile` / `${x^^}`), **no competitor name**, **TDD**, **rule-ids from the `findings.sh` catalog only**.
- Do not bump versions inside these tasks (release process handles it).

`SCAN=skills/appstore-precheck/scripts`. Anchor edits by the check's `set_rule "<slug>"` marker, not absolute line numbers.

---

## Task 1: `analytics-privacyinfo-mismatch` — kill the `Segment` substring (pilot)

**Files:** Modify `$SCAN/scan.sh` (block at `set_rule "analytics-privacyinfo-mismatch"`); add a fixture + `tests/run.sh` assert.

**Interfaces:** Consumes `$IOS_DIR`, `$PRIVACY_FILE`. Produces: analytics detection that no longer matches `UISegmentedControl`/`SegmentedPickerStyle`.

- [ ] **Step 1: Write the failing test** — create `tests/fixtures/segmented-ui-app/` = a minimal app whose only "Segment" token is a SwiftUI/UIKit segmented control, with NO analytics SDK. Minimum: an `App/ContentView.swift` containing `Picker("x", selection: $s) { }.pickerStyle(SegmentedPickerStyle())` and a `let seg = UISegmentedControl()`, plus an `App/Info.plist` and a `PrivacyInfo.xcprivacy` with no collected-data. In `tests/run.sh`, add a block that runs the scanner on this fixture and asserts:

```bash
assert_absent "WARN: 5.1.1 Privacy manifest — analytics SDK detected" "segmented-ui: no analytics-SDK false positive"
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/run.sh` (or the focused fixture runner)
Expected: FAIL — the `Segment` substring matches `SegmentedPickerStyle`, so the WARN fires.

- [ ] **Step 3: Implement the regex fix** — in the `set_rule "analytics-privacyinfo-mismatch"` block, replace the `analytics_sdk=$(grep ...)` pattern with import/API-qualified tokens:

```sh
analytics_sdk=$(grep -rlE 'FirebaseAnalytics|import Firebase|import Amplitude|Amplitude\(|import Mixpanel|Mixpanel\.|import Sentry|SentrySDK|import Segment|SEGAnalytics|Analytics\.shared\(|import Bugsnag|Bugsnag\.|AppCenterAnalytics|import Datadog|DatadogCore' "$IOS_DIR" --include="*.swift" 2>/dev/null | head -1)
```

- [ ] **Step 4: Run to verify it passes**

Run: `bash tests/run.sh`
Expected: PASS — segmented-ui fixture no longer trips the analytics WARN.

- [ ] **Step 5: Verify no TP regression + reconcile corpus** — confirm any fixture that SHOULD detect an analytics SDK still does (e.g. `tracking-app` if it imports one; if none exists, the `tracking-app` fixture already exercises §16/§19 — verify its expected asserts still hold). If any fixture's firing changed, update `tests/run.sh` and `corpus/synthetic/labels.json`, then:

Run: `bash scripts/scorecard.sh && bash scripts/scorecard.sh --check && npm test`
Expected: `--check` passes; suite green.

- [ ] **Step 6: Shellcheck + commit**

```bash
shellcheck -x --severity=warning skills/appstore-precheck/scripts/scan.sh
git add skills/appstore-precheck/scripts/scan.sh tests/fixtures/segmented-ui-app tests/run.sh corpus/synthetic/labels.json docs/scorecard.md
git commit -m "fix(scan): analytics detection requires import/API form, not bare Segment substring"
```

---

## Task 2: IAP detection — require a real purchase API

**Files:** Modify `$SCAN/scan.sh` (the `iap_detected=` block before the §8–§10 gate); add a fixture + assert.

**Interfaces:** Consumes `$IOS_DIR`, `$SUB_VIEW`. Produces: `iap_detected` that ignores rating-prompt / ad-attribution / custom-namespace StoreKit usage.

- [ ] **Step 1: Write the failing test** — create `tests/fixtures/review-prompt-app/` = an app whose only StoreKit usage is a rating prompt: `App/ContentView.swift` with `import StoreKit` and `SKStoreReviewController.requestReview(in: scene)`, no purchase API, no paywall view. Add to `tests/run.sh`:

```bash
assert_absent "FAIL: 3.1.2" "review-prompt: no paywall FAIL when StoreKit is only a rating prompt"
assert_present "PASS: 3.1.2 IAP — no in-app purchase" "review-prompt: IAP gate correctly skips"
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/run.sh`
Expected: FAIL — `import StoreKit` currently sets `iap_detected`, so the paywall checks run and 3.1.2 links FAIL.

- [ ] **Step 3: Implement the detection fix** — replace the first `iap_detected` grep line:

```sh
grep -rqE 'SKPaymentQueue|SKProduct|SKMutablePayment|Product\.products|Product\(for:|Product\(id:|\.purchase\(|Transaction\.currentEntitlements|Transaction\.updates|RevenueCat|Purchases\.(shared|configure|logIn|getProducts)|Adapty|Glassfy|import Qonversion' "$IOS_DIR" --include="*.swift" 2>/dev/null && iap_detected=1
```

(Leave the next line `[[ -n "$SUB_VIEW" ]] && iap_detected=1` unchanged — a real paywall view still gates in.)

- [ ] **Step 4: Run to verify it passes**

Run: `bash tests/run.sh`
Expected: PASS — review-prompt-app hits the IAP-skip PASS; no 3.1.2 FAIL.

- [ ] **Step 5: No TP regression + reconcile** — the `sample-app` fixture is designed to trip 3.1.2 (`subscription-links-restore` in `corpus/synthetic/labels.json`). Confirm it STILL detects IAP (it has a paywall view `$SUB_VIEW` and/or a real purchase API). If sample-app relied only on bare `import StoreKit`, add a real purchase API line to it so intent is preserved. Update `tests/run.sh`/`labels.json` only if firing changed; then:

Run: `bash scripts/scorecard.sh --check && npm test`
Expected: `--check` passes; suite green (sample-app still fires 3.1.2).

- [ ] **Step 6: Shellcheck + commit**

```bash
shellcheck -x --severity=warning skills/appstore-precheck/scripts/scan.sh
git add skills/appstore-precheck/scripts/scan.sh tests/fixtures/review-prompt-app tests/run.sh corpus/synthetic/labels.json docs/scorecard.md tests/fixtures/sample-app
git commit -m "fix(scan): IAP gate requires a purchase API, ignores rating-prompt/ad-attribution StoreKit"
```

---

## Task 3: `usage-description-crosscheck` — capture-gated camera/mic + Photos-aware

**Files:** Modify `$SCAN/scan.sh` (the framework loop under `set_rule "usage-description-crosscheck"`); add fixtures + asserts.

**Interfaces:** Consumes `$IOS_DIR`, `$INFO_PLIST`. Produces: camera/mic/photo-library requirements gated on real capture/read APIs, not bare imports.

- [ ] **Step 1: Write the failing tests** — add two fixtures:
  - `tests/fixtures/audio-playback-app/`: `import AVFoundation` used only for `AVAudioPlayer`/`AVAudioSession.sharedInstance().setCategory(.playback)`; `Info.plist` has NO camera/mic keys.
  - `tests/fixtures/photos-picker-app/`: `import PhotosUI` with `PhotosPicker(...)` only (no `PHAsset` read); `Info.plist` has NO `NSPhotoLibraryUsageDescription`.

In `tests/run.sh`:

```bash
assert_absent "FAIL: 5.1.1 framework 'AVFoundation'" "audio-playback: no camera/mic FP for playback-only AVFoundation"
assert_absent "FAIL: 5.1.1 framework 'Photos'"       "photos-picker: no NSPhotoLibraryUsageDescription FP for PhotosPicker"
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/run.sh`
Expected: FAIL — both fixtures trip the import-based FAILs today.

- [ ] **Step 3: Implement capture-gating** — in the framework loop, KEEP the generic entries for `FamilyControls`, `CoreLocation`, `Contacts`, `HealthKit`. REMOVE the `AVFoundation:...` and `Photos:...` generic entries and replace them, after the loop, with dedicated checks:

```sh
# Camera: purpose string required only when a capture API is actually used.
if grep -rqE 'AVCaptureDevice|AVCaptureSession|UIImagePickerController' "$IOS_DIR" --include="*.swift" 2>/dev/null; then
  grep -qE 'NSCameraUsageDescription' "$INFO_PLIST" 2>/dev/null || \
    fail "5.1.1 camera capture API used but Info.plist is missing 'NSCameraUsageDescription'" "$INFO_PLIST"
fi
# Microphone: required only for recording/capture, not playback.
if grep -rqE 'AVAudioRecorder|AVCaptureDevice|installTap\(|AVAudioSession[^;]*\.record' "$IOS_DIR" --include="*.swift" 2>/dev/null; then
  grep -qE 'NSMicrophoneUsageDescription' "$INFO_PLIST" 2>/dev/null || \
    fail "5.1.1 microphone/recording API used but Info.plist is missing 'NSMicrophoneUsageDescription'" "$INFO_PLIST"
fi
# Photo library READ: PhotosPicker/PHPicker need no key; only true read/fetch APIs do.
if grep -rqE 'PHAsset\b|PHFetchResult|PHImageManager|fetchAssets|PHAssetCollection' "$IOS_DIR" --include="*.swift" 2>/dev/null; then
  grep -qE 'NSPhotoLibraryUsageDescription' "$INFO_PLIST" 2>/dev/null || \
    fail "5.1.1 Photos read API used but Info.plist is missing 'NSPhotoLibraryUsageDescription'" "$INFO_PLIST"
elif grep -rqE 'PHAssetCreationRequest|UIImageWriteToSavedPhotosAlbum|performChanges' "$IOS_DIR" --include="*.swift" 2>/dev/null; then
  # Add-only save: covered by the add-only key.
  grep -qE 'NSPhotoLibraryAddUsageDescription' "$INFO_PLIST" 2>/dev/null || \
    fail "5.1.1 Photos add-only API used but Info.plist is missing 'NSPhotoLibraryAddUsageDescription'" "$INFO_PLIST"
fi
```

- [ ] **Step 4: Run to verify it passes**

Run: `bash tests/run.sh`
Expected: PASS — playback-only and PhotosPicker fixtures no longer FAIL.

- [ ] **Step 5: No TP regression + reconcile** — add or confirm a fixture where a real capture API IS used without the key so the check STILL fails there (e.g. extend an existing fixture with `AVCaptureSession()` + no `NSCameraUsageDescription` → asserts FAIL present). Update `tests/run.sh`, `corpus/synthetic/labels.json`, regenerate scorecard if any fixture firing changed; then:

Run: `bash scripts/scorecard.sh --check && npm test`
Expected: `--check` passes; suite green.

- [ ] **Step 6: Shellcheck + commit**

```bash
shellcheck -x --severity=warning skills/appstore-precheck/scripts/scan.sh
git add skills/appstore-precheck/scripts/scan.sh tests/fixtures/audio-playback-app tests/fixtures/photos-picker-app tests/run.sh corpus/synthetic/labels.json docs/scorecard.md
git commit -m "fix(scan): usage-description gated on real capture/read APIs, not bare imports"
```

---

## Task 4: `min-functionality-nav` — UIKit + React-Navigation, repo-wide

**Files:** Modify `$SCAN/scan.sh` (block at `set_rule "min-functionality-nav"`); add a fixture + assert.

**Interfaces:** Consumes `$GREP_PRUNE` (the repo-wide prune array). Produces: nav-hub detection across UIKit/RN and outside the auto-detected `$IOS_DIR`.

- [ ] **Step 1: Write the failing test** — create `tests/fixtures/uikit-nav-app/` = an app whose navigation is pure UIKit: `App/RootViewController.swift` with `class Root: UITabBarController {}` and a `UINavigationController(rootViewController:)`, and NO SwiftUI `TabView`. Add to `tests/run.sh`:

```bash
assert_absent "WARN: 4.2 Minimum functionality" "uikit-nav: no 4.2 FP for a UIKit UITabBarController app"
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/run.sh`
Expected: FAIL — the SwiftUI-only pattern finds nothing, so 4.2 WARN fires.

- [ ] **Step 3: Implement the broadened, repo-wide detection** — replace the `tab_count=$(...)` line:

```sh
tab_count=$(grep -rcE 'TabView|NavigationStack|NavigationSplitView|NavigationView|UITabBarController|UINavigationController|createBottomTabNavigator|createStackNavigator|createNativeStackNavigator' . "${GREP_PRUNE[@]}" --include='*.swift' --include='*.m' --include='*.js' --include='*.jsx' --include='*.ts' --include='*.tsx' 2>/dev/null | awk -F: '{sum+=$2} END {print sum+0}')
```

- [ ] **Step 4: Run to verify it passes**

Run: `bash tests/run.sh`
Expected: PASS — UIKit fixture is recognized as having a nav hub.

- [ ] **Step 5: No TP regression + reconcile** — confirm a fixture with genuinely no navigation still trips 4.2 (if none exists, the check simply won't fire on any real fixture — acceptable; note it). Update `tests/run.sh`/`labels.json` if firing changed; then:

Run: `bash scripts/scorecard.sh --check && npm test`
Expected: `--check` passes; suite green.

- [ ] **Step 6: Shellcheck + commit**

```bash
shellcheck -x --severity=warning skills/appstore-precheck/scripts/scan.sh
git add skills/appstore-precheck/scripts/scan.sh tests/fixtures/uikit-nav-app tests/run.sh corpus/synthetic/labels.json docs/scorecard.md
git commit -m "fix(scan): min-functionality-nav detects UIKit/React-Navigation repo-wide"
```

---

## Task 5: `screenshots-per-locale` — no in-repo dir is not a defect

**Files:** Modify `$SCAN/scan.sh` (the `else` branch of the `set_rule "screenshots-per-locale"` block); update asserts.

**Interfaces:** Consumes `$SCREEN_DIR`. Produces: a non-firing advisory when no in-repo screenshots dir exists.

- [ ] **Step 1: Write the failing test** — pick/confirm a fixture with NO `fastlane/screenshots` dir (e.g. `tests/fixtures/root-app` or a minimal one). Add to `tests/run.sh`:

```bash
assert_absent "WARN: 2.3.3 Screenshots — screenshots dir not found" "no-screenshots: absent in-repo screenshots dir is not a WARN"
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/run.sh`
Expected: FAIL — the `else` branch currently WARNs.

- [ ] **Step 3: Implement** — replace the `else` branch warn (`warn "2.3.3 Screenshots — screenshots dir not found ..."`) with:

```sh
else
  pass "2.3.3 Screenshots — no in-repo screenshots dir; assumed managed in App Store Connect (set .screenshotsDir to check in-repo)"
fi
```

(Leave the dir-exists loop, including the per-locale `warn "2.3.3 Screenshots — no folder for $loc"`, unchanged.)

- [ ] **Step 4: Run to verify it passes**

Run: `bash tests/run.sh`
Expected: PASS — no-screenshots fixture no longer WARNs.

- [ ] **Step 5: No TP regression + reconcile** — confirm a fixture WITH a screenshots dir but a missing locale still WARNs (`config-app`/`sample-app` if applicable). Update `tests/run.sh`/`labels.json` for any fixture whose WARN count changed (this may shift a fixture from N to N-1 WARNs; update any `assert`/verdict expectation). Then:

Run: `bash scripts/scorecard.sh --check && npm test`
Expected: `--check` passes; suite green.

- [ ] **Step 6: Shellcheck + commit**

```bash
shellcheck -x --severity=warning skills/appstore-precheck/scripts/scan.sh
git add skills/appstore-precheck/scripts/scan.sh tests/run.sh corpus/synthetic/labels.json docs/scorecard.md
git commit -m "fix(scan): no in-repo screenshots dir is advisory, not a WARN (managed in ASC)"
```

---

## Task 6: Remeasure the real panel + report + whole-branch review

**Files:** Create `docs/fp-reduction-report.md` (before/after). No scanner change.

- [ ] **Step 1: Full suite + synthetic gate**

Run: `npm test && bash scripts/scorecard.sh --check`
Expected: all green.

- [ ] **Step 2: Remeasure the panel** — re-run the scanner over the 18 pinned apps (reuse the candidate `corpus/real/labels.json`) and recompute aggregate + per-rule precision. Use `bash scripts/scorecard.sh --real` (or the same clone+scan+join the panel used). Capture the new per-rule TP/FP and the new aggregate (raw and char-limit-excluded).

- [ ] **Step 3: Write `docs/fp-reduction-report.md`** — a before/after table: per-rule precision before (from the baseline labels) vs after (fixed scanner), the aggregate move, and the honest caveat (candidate labels; char-limit-excluded number is the headline). Note which FP clusters were eliminated and which remain (IOS_DIR-rooted, demo-account) as deferred follow-ups.

- [ ] **Step 4: Commit**

```bash
git add docs/fp-reduction-report.md
git commit -m "docs: false-positive reduction before/after measurement report"
```

- [ ] **Step 5: Whole-branch review** — dispatch a code-reviewer over `git diff <merge-base>...HEAD`: verify each regex fix can't over-narrow (dropping real TPs), no competitor name, Bash 3.2, READ-ONLY, and that every fixture change is a real behavior improvement (not a test loosened to pass).

---

## Self-Review

**Spec coverage:** Fix 1 → Task 1; Fix 2 → Task 2; Fix 3 → Task 3; Fix 4 → Task 4; Fix 5 → Task 5; remeasure §5 → Task 6. Deferred items (IOS_DIR, demo-account, private-api) explicitly out of scope. Covered.

**Placeholders:** none — every regex and fixture is concrete.

**Type/name consistency:** `iap_detected`, `analytics_sdk`, `tab_count`, `GREP_PRUNE`, `SCREEN_DIR`, `INFO_PLIST`, `IOS_DIR`, `PRIVACY_FILE` match `scan.sh`. Fixture names (`segmented-ui-app`, `review-prompt-app`, `audio-playback-app`, `photos-picker-app`, `uikit-nav-app`) are used consistently across their tasks.
