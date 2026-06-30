# Methodology: App Store Precheck

The detailed reference behind the skill. Read the section you need; you do not need to read this
whole file to run the skill.

## Contents

- [Phase 0: Guideline drift check](#phase-0-guideline-drift-check)
- [Phase 1: Rejection vectors](#phase-1-rejection-vectors)
- [Phase 3: Pierre explains every finding](#phase-3-pierre-explains-every-finding)
- [Phase 4: Pierre deep review (22 checks)](#phase-4-pierre-deep-review-22-semantic-checks)
- [Auto-detection rules](#auto-detection-rules)
- [Verdict thresholds](#verdict-thresholds)
- [Pre-submit manual checklist](#pre-submit-manual-checklist)

---

## Phase 0: Guideline drift check

**Why:** the scanner's checks and `fastlane precheck`'s rule engine are static and hand-maintained.
Apple changes the [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
without notice. This phase flags whether any guideline **section number was added or removed**
since the last reconciliation, catching drift without manual upkeep. It is **always
non-blocking (WARN at most)**: drift is a gap in *our* coverage, never a fault of the build.

**Mechanics.** Read `guidelines-baseline.json`, then fetch the live page and diff its section
numbers against `all_sections`. The fetcher's sub-model truncates this single long page after
~5.4, so do **two focused passes**, each embedding only the relevant slice of `all_sections`:

- **Pass A (Sections 1–3):** "Report ONLY (NEW) section numbers present on the live page but
  missing from this list, and (REMOVED) numbers in the list but absent. Ignore parenthetical
  (a)/(b) suffixes. If nothing differs, output NO DRIFT."
- **Pass B (Section 4 + 5.1–5.4):** same, plus "The page reliably truncates after ~5.4, that is
  EXPECTED; do NOT report 5.5/5.6.x as removed and do NOT output TRUNCATED for the tail."
- **Tail 5.5–5.6.x** can't be fetched reliably and is structurally the most stable section
  (Developer Code of Conduct); review it by hand during reconciliation.

**Interpretation (always WARN at most):**

- `NO DRIFT` → `PASS: guideline-drift none (baseline reconciled <reconciled_on>)`
- NEW/REMOVED → `WARN: guideline-drift — NEW: <…> / REMOVED: <…>. Review the live page; add a
  check to scan.sh if relevant, then reconcile the baseline.`
- fetch failed/truncated → `WARN: guideline-drift-check degraded — verify manually.`

**Reconciliation (a deliberate human step):** review the drift, optionally add a scan check for a
newly relevant section, then update `guidelines-baseline.json`, add/remove the section numbers
in `all_sections` and set `reconciled_on` to today. **Never auto-update the baseline:** doing so
would silently swallow the warning and defeat the entire purpose of drift detection.

**Limit:** this detects only *structural* drift (the set of section numbers). A section whose
number is unchanged but whose *text* changed is not caught here, but is partly covered by
Phase 2 (Apple's own rule engine) and Phase 3 (Pierre explains every FAIL/WARN). Apple does not expose a
machine-readable "last updated" date in the page DOM, so the section-number set is the signal.

---

## Phase 1: Rejection vectors

`scripts/scan.sh` checks the following. Each emits `FAIL:` / `WARN:` / `PASS:` with a location.

| # | Guideline | What it checks |
|---|-----------|----------------|
| 1 | **5.1.1 Privacy Manifest** | Required Reason API usage (`UserDefaults`/`@AppStorage`, file timestamp, system boot time, disk space, active keyboard) ↔ `PrivacyInfo.xcprivacy` declaration parity. (Apple documents Required Reason APIs under 5.1.1 + the privacy-manifest docs; it is **not** sub-item (v) — that is Account Sign-In, checked in vector 38.) |
| 2 | **5.1.1 Purpose Strings** | Every imported sensitive framework (FamilyControls, CoreLocation, AVFoundation, Photos, Contacts, HealthKit) has a non-empty `NS*UsageDescription` in Info.plist |
| 3 | **5.1.2 ATT** | If `AppTrackingTransparency`/`ATTrackingManager` is used, `NSUserTrackingUsageDescription` is present |
| 4 | **2.3.10 Other platforms** | No "Android" / "Google Play" / competitor store names in store metadata |
| 5 | **2.3.1 Metadata limits** | name ≤30, subtitle ≤30, keywords ≤100, promotional_text ≤170, description ≤4000 (Unicode codepoints, matching ASC) |
| 6 | **2.3.7 Localized parity** | Every detected locale has name + subtitle + description + keywords |
| 7 | **2.3.3 Screenshots** | Each locale folder has at least one screenshot (warns if <3) |
| 8 | **3.1.2 Trial disclosure** | If trial wording exists, a trial→paid auto-renew disclosure key exists |
| 9 | **3.1.2 Auto-renew disclosure** | A subscription disclosure string exists and covers each locale |
| 10 | **3.1.2 Required links** | The paywall view contains Restore Purchases + Terms of Use (EULA) + Privacy Policy |
| 11 | **2.5.1 Private API** | No banned identifiers (`UIWebView`, `setSelectionIndicatorImage`, `_UIBackdropView`, `NSURLConnection`, …) |
| 12 | **4.2 Minimum functionality** | At least one navigation hub (`TabView` / `NavigationStack` / `NavigationSplitView`) |
| 13 | **5.1.5 Sensitive APIs** *(opt-in)* | If FamilyControls is used and `optionalChecks.familyControls` is on, a reviewer-notes justification exists |
| 14 | **4.8 Sign in with Apple** *(advisory)* | If a third-party social login SDK (Google, Facebook, Auth0, …) is used, Sign in with Apple is offered too |
| 15 | **3.1.1(a) External purchase link** *(advisory)* | If StoreKit External Purchase APIs or the entitlement are present, the 3.1.1(a) disclosure/reporting requirements are flagged |
| 16 | **5.1.2 Tracking SDK / IDFA** *(advisory)* | If an ad / attribution SDK (AdMob, AppLovin, AppsFlyer, Adjust, Branch, IronSource) or raw IDFA access is present but no ATT prompt is, it is flagged (the reverse of vector 3) |
| 17 | **Export compliance** *(advisory)* | If a checked-in Info.plist lacks `ITSAppUsesNonExemptEncryption`, set it (true/false) to skip the App Store Connect encryption-export question |
| 18 | **2.3 Support / Privacy URL** *(advisory)* | fastlane metadata has a non-empty `support_url.txt` and `privacy_url.txt` across locales, with no placeholder URLs |
| 19 | **5.1.1 Privacy manifest** *(advisory)* | If an analytics SDK (Firebase, Amplitude, Mixpanel, Sentry, Segment, Bugsnag, App Center, Datadog) is linked but `PrivacyInfo.xcprivacy` declares no collected data types or tracking domains, it is flagged |
| 20 | **2.1 Placeholder content** *(advisory)* | No lorem ipsum / TODO / FIXME / `example.com` / "insert X here" / changeme in store metadata |
| 21 | **3.1.1 Third-party payment SDK** *(advisory)* | If a third-party payment SDK (Stripe, Braintree, PayPal, Square, Adyen, …) is linked, flag it: digital goods/services must use in-app purchase (allowed only for physical goods/services) |
| 22 | **1.2 UGC moderation** *(advisory)* | If user-generated-content signals (post/comment/upload, chat SDKs) are present but no report/block/moderation affordance is found, flag the missing 1.2 safety controls |
| 23 | **1.6 App Transport Security** *(advisory)* | `NSAllowsArbitraryLoads=true` in Info.plist disables ATS app-wide |
| 24 | **4.9 Apple Pay recurring** *(advisory)* | If the recurring Apple Pay API (`PKRecurringPaymentRequest`) is used: verify the renewal term, what's provided, charges, and cancel disclosure |
| 25 | **5.6.1 Custom review prompt** *(advisory)* | If a direct App Store write-review link/prompt exists but no system `requestReview` / `SKStoreReviewController` call |
| 26 | **2.3.1 Misleading marketing** *(advisory)* | Claims iOS apps can't deliver (virus/malware scanners, fake speed boosters) in store metadata |
| 27 | **2.3.8 "For Kids" wording** *(advisory)* | Terms implying a child audience in metadata, reserved for the Kids Category |
| 28 | **4.4.1 Keyboard full access** *(advisory)* | A keyboard extension (`com.apple.keyboard-service`) with `RequestsOpenAccess=true` |
| 29 | **5.1.3 Health + iCloud** *(advisory)* | If HealthKit and iCloud/CloudKit are both used: health data must not be stored in iCloud |
| 30 | **5.4 VPN** *(advisory)* | If NetworkExtension / `NEVPNManager` is used: org-account, on-screen data disclosure, and no data sale/sharing requirements |
| 31 | **2.1 Demo account** *(advisory)* | If a credential login (`SecureField` / a Login/SignIn view) is present but no demo account/credentials for App Review are found (fastlane `review_information` or `.reviewPrepNotes`) |
| 32 | **2.5.2 Executable code** *(advisory)* | A native hot-patch / remote-code framework (JSPatch, Rollout, DynamicCocoa) that downloads code which changes features. Allowed JS-bundle OTA (React Native CodePush) is not flagged |
| 33 | **2.5.4 Background modes** *(advisory)* | A mode declared in `UIBackgroundModes` (location, audio, voip, fetch, processing, bluetooth, remote-notification) with no matching API used in Swift |
| 34 | **3.1.5(a) Cryptocurrency** *(advisory)* | A crypto wallet / exchange / mining signal (WalletConnect, web3swift, TrustWalletCore, mining libraries) with its entity/licensing and no-on-device-mining requirements |
| 35 | **4.2.3 Web wrapper** *(advisory)* | A `WKWebView` in a project with very few Swift files — heuristic for a thin wrapper around a website. The most false-positive-prone of the batch, so WARN/verify |
| 36 | **4.2.7 Remote desktop** *(advisory)* | A remote-desktop / host-mirroring signal (VNC/RDP libraries); host-mirroring apps must only show the owner's host and be free or use IAP |
| 37 | **4.4.2 Safari extension** *(advisory)* | A Safari content-blocker / web extension (`com.apple.Safari.*` extension point); must use the APIs as intended and not hide analytics/ads |
| 38 | **5.1.1(v) Account deletion** *(advisory)* | Account creation (`signUp`/`createUser`/`createAccount`/…) detected but no in-app account-deletion path (`deleteAccount`/`closeAccount`/…). This is the real 5.1.1(v) Account Sign-In rule |
| 39 | **5.1.4 Kids** *(advisory)* | Metadata targets a child audience **and** a third-party ads/analytics SDK is linked; Kids Category apps may not include third-party ads/analytics and need a parental gate |
| 40 | **5.3.4 Gambling** *(advisory)* | Real-money gaming language in metadata (casino, sportsbook, real money, wager); real-money gambling needs licensing, geo-restriction, and must be free on the store |
| 41 | **5.5 MDM** *(advisory)* | A Mobile Device Management signal (`DeviceManagement`, managed-app-config, `com.apple.mdm`); MDM apps need a commercial enterprise/education entity and purpose-limited data use |

Vectors 8–10 only run when in-app-purchase signals are detected (StoreKit / RevenueCat import,
or a paywall view). Otherwise the scanner emits a single PASS and skips them. Vectors 16–41 are
signal-gated advisory WARNs: each emits nothing unless its triggering signal is present.

**Scope by app type.** The metadata, privacy-manifest, screenshots, and export-compliance checks
apply to any iOS app regardless of how it is built. The code-level checks grep the app's Swift
source (`*.swift`, plus `*.m`/`*.h` and `*.entitlements` where relevant), so they are most accurate
for native Swift / SwiftUI. On React Native (JavaScript) or Flutter (Dart) apps that logic is not in
Swift, so the code-level checks under-detect rather than misfire. iOS only.

---

## Phase 3: Pierre explains every finding

After Phases 0–2, **Pierre** (the French critic reviewer persona) explains **every FAIL and WARN**
the pipeline emitted — no random sampling, no new hunts.

**Sources to explain (all lines, in order):**

1. Phase 0 — any `WARN: guideline-drift` (or degraded drift-check) line.
2. Phase 1 — every `FAIL:` and `WARN:` from `scan.sh` (including multi-line detail blocks
   indented under a parent line — explain the parent once, cite the paths in the explanation).
3. Phase 2 — every `fastlane precheck` violation, if Phase 2 ran (treat as FAIL-level).

**Per finding:** repeat the line verbatim, then **2–3 sentences** from Pierre: why Apple cares
about that guideline, what the scan found, what to fix or verify. Write explanations in the user's
conversation language; keep the Phase 5 trilingual verdict block separate (bold label + blockquote
per language, `---` between — see SKILL.md Output contract).

**Trilingual verdict block:** `### Pierre` heading; each language on its own — **bold label**, blank
line, `> *italic one-liner*`; horizontal rules between languages; never FR/EN/user-lang on one line.

**If zero FAIL and zero WARN:** Pierre gives a brief all-clear (2–3 sentences). Do not invent issues.

**What Phase 3 is not:** it does not add FAIL/WARN lines to the verdict count, does not paraphrase
the machine lines (those stay verbatim in Phase 5), and does not re-run detection. The scanner
finds; Pierre explains.

---

## Phase 4: Pierre deep review (22 semantic checks)

After Phase 3, Pierre runs the **Review Simulator**: 22 evidence-based checks the static scanner
cannot fully judge. Full procedure, output format, and per-check steps are in
[`pierre-deep-review.md`](pierre-deep-review.md).

**Verdict impact:** none. Phase 4 emits `REVIEW-PASS:` or `REVIEW-FINDING: <guideline> WARN — …`.
These are advisory; FAIL/WARN counts and GREEN/YELLOW/RED come only from Phases 0–2.

**Coverage:** deepens scan hits where applicable (e.g. 5.1.1 purpose strings → 5.1.1(ii) quality;
§22 UGC keyword → 1.2.1 moderation UI) and adds net-new semantic areas (2.3.5 screenshots,
5.1.1(i) privacy policy fetch, 2.3.11–13 locale consistency, etc.). Guideline numbers touched
are tracked in `guidelines-baseline.json` → `covered_by_pierre_deep_review`.

**Presentation (Phase 5):** after Phase 3 commentary, show Phase 4 summary (N of 22 findings) and
every `REVIEW-FINDING` with Pierre's 2–3 sentence explanation.

---

## Auto-detection rules

When `.appstore-precheck.json` does not pin a path, the scanner derives it:

- **iOS source dir**: the `Info.plist` directory (excluding `.git`, Pods, Carthage, `.build`,
  `build`, DerivedData, SwiftPM `SourcePackages`/`checkouts`/`.swiftmp`, `.claude`/`worktrees`,
  `node_modules`, `vendor`) that holds the most Swift files. This is the app target, not a dependency.
- **metadata / screenshots dir**: the shallowest `**/fastlane/metadata` and `**/fastlane/screenshots`.
- **String Catalog**: the first `Localizable.xcstrings`, else the first `*.xcstrings`.
- **Paywall view**: first file matching `*SubscriptionView*`, `*PaywallView*`, `*Paywall*`,
  `*…View.swift` (override with `paywallGlobs`).
- **Locales**: the directory names under `metadataDir` (override with a `locales` array).

All path matching prunes the dependency/build/worktree trees above and prefers the shallowest
match, so a vendored SwiftPM checkout is never mistaken for the app.

---

## Verdict thresholds

| State | Rule |
|-------|------|
| **GREEN** | 0 FAIL and ≤4 WARN → write `.precheck-pass` (valid 60 min) |
| **YELLOW** | 0 FAIL and ≥5 WARN → no token; require explicit user confirmation to proceed |
| **RED** | ≥1 FAIL → no token; submission blocked until fixed |

The guideline-drift WARN from Phase 0 counts toward the same WARN threshold; on its own it never
blocks, but it can be the fifth WARN that tips GREEN into YELLOW.

---

## Pre-submit manual checklist

Things the scanner cannot verify; confirm by hand before you submit:

```
[ ] App Privacy Nutrition Labels in App Store Connect match PrivacyInfo.xcprivacy
[ ] ASC App Review Information: demo account / notes filled in
[ ] Sandbox tester: at least 1 purchase + 1 restore tested end to end
[ ] TestFlight crash-free over the last 24h > 99.5%
[ ] Build number incremented from the previous submission
[ ] Export compliance (encryption) answered
[ ] If using "Sign in with Apple" alongside other social logins, it is offered
```
