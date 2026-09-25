# Methodology: App Store Precheck

The detailed reference behind the skill. Read the section you need; you do not need to read this
whole file to run the skill.

## Contents

- [Phase 0: Guideline drift check](#phase-0-guideline-drift-check)
- [Phase 1: Rejection vectors](#phase-1-rejection-vectors)
- [Phase 3: Pierre explains every finding](#phase-3-pierre-explains-every-finding)
- [Phase 4: Pierre deep review (31 checks)](#phase-4-pierre-deep-review-31-semantic-checks)
- [Auto-detection rules](#auto-detection-rules)
- [Verdict thresholds](#verdict-thresholds)
- [Evidence strength and confidence](#evidence-strength-and-confidence)
- [Guideline citations](#guideline-citations)
- [The SKIP line class](#the-fourth-line-class-skip-not-audited)
- [SARIF output](#sarif-output---format-sarif)
- [Real App Store outcomes](#real-app-store-outcomes-corpusoutcomes)
- [Optional local dynamic simulator tier](#optional-local-dynamic-simulator-tier)
- [Guideline obligation coverage](#guideline-obligation-coverage)
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

**Automated detector:** `scripts/guideline-drift.sh` is the deterministic, curl-based counterpart
to the two-pass technique above — it runs unattended in CI (see
`.github/workflows/guideline-drift.yml`, scheduled + `workflow_dispatch`, always non-blocking) and
also covers text (semantic) drift of covered sections via `guidelines-fingerprints.json`, naming
the affected check(s) when a section's fingerprint no longer matches. Reconcile the fingerprint
baseline the same deliberate way, with `guideline-drift.sh --reconcile`.

**Category intros (`1.0`–`5.0`).** Apple cites the intro prose of each category by number
("Guideline 4.0 - Design" is its single most-cited removal reason), but the live page anchors that
prose only as the bare category id (`id="4"`; there is no `id="4.0"`, verified 2026-09-01). The
parser surfaces bare category anchors as `N.0`, so the intros are baselined, fingerprinted and
citable like any sub-section; every link and citation resolves `N.0` back to `#N`.

---

## Phase 1: Rejection vectors

`scripts/scan.sh` checks the following. Each emits `FAIL:` / `WARN:` / `PASS:` with a location.

| # | Guideline | What it checks |
|---|-----------|----------------|
| 1 | **5.1.1 Privacy Manifest** | Required Reason API usage (`UserDefaults`/`@AppStorage`, file timestamp, system boot time, disk space, active keyboard) ↔ `PrivacyInfo.xcprivacy` declaration parity. (Apple documents Required Reason APIs under 5.1.1 + the privacy-manifest docs; it is **not** sub-item (v) — that is Account Sign-In, checked in vector 38.) |
| 2 | **5.1.1 Purpose Strings** | Every imported sensitive framework (FamilyControls, CoreLocation, AVFoundation, Photos, Contacts, HealthKit) has a non-empty `NS*UsageDescription` in Info.plist |
| 3 | **5.1.2 ATT** | If `AppTrackingTransparency`/`ATTrackingManager` is used, `NSUserTrackingUsageDescription` is present |
| 4 | **2.3.10 Other platforms** | No "Android" / "Google Play" / competitor store names in store metadata |
| 5 | **2.3.7 / ASC Metadata limits** | name ≤30, subtitle ≤30, keywords ≤100, promotional_text ≤170, description ≤4000 (Unicode codepoints, matching ASC) |
| 6 | **2.3 Localized parity** | Every detected locale has name + subtitle + description + keywords |
| 7 | **2.3.3 Screenshots** | Each locale folder has at least one screenshot (warns if <3) |
| 8 | **3.1.2 Trial disclosure** | If trial wording exists, a trial→paid auto-renew disclosure key exists |
| 9 | **3.1.2 Auto-renew disclosure** | A subscription disclosure string exists and covers each locale |
| 10 | **3.1.2 Required links** | The paywall view contains Restore Purchases + Terms of Use (EULA) + Privacy Policy |
| 11 | **2.5.1 Private API** | No banned identifiers (`UIWebView`, `setSelectionIndicatorImage`, `_UIBackdropView`, `NSURLConnection`, …) |
| 12 | **4.2 Minimum functionality** | At least one navigation hub (`TabView` / `NavigationStack` / `NavigationSplitView`) |
| 13 | **Review preparation: Sensitive APIs** *(opt-in)* | If FamilyControls is used and `optionalChecks.familyControls` is on, a reviewer-notes justification exists |
| 14 | **4.8 Sign in with Apple** *(advisory)* | If a third-party social login SDK (Google, Facebook, Auth0, …) is used, Sign in with Apple is offered too |
| 15 | **3.1.1(a) External purchase link** *(advisory)* | If StoreKit External Purchase APIs or the entitlement are present, review offering, storefront, distribution and applicable agreements before determining entitlement/disclosure/reporting duties |
| 16 | **5.1.2 Tracking SDK / IDFA** *(advisory)* | If an ad / attribution SDK (AdMob, AppLovin, AppsFlyer, Adjust, Branch, ironSource, Unity Ads, Vungle, Chartboost, InMobi, Mintegral, Pangle, Singular, Kochava, Tenjin) or raw IDFA access is present but no ATT prompt is, it is flagged (the reverse of vector 3). Per-SDK coverage: [`tests/test-sdk-signals.sh`](../../../tests/test-sdk-signals.sh) |
| 17 | **Export compliance** *(advisory)* | If a checked-in Info.plist lacks `ITSAppUsesNonExemptEncryption`, set it (true/false) to skip the App Store Connect encryption-export question |
| 18 | **2.3 Support / Privacy URL** *(advisory)* | fastlane metadata has a non-empty `support_url.txt` and `privacy_url.txt` across locales, with no placeholder URLs |
| 19 | **5.1.1 Privacy manifest** *(advisory)* | If an analytics SDK (Firebase, Amplitude, Mixpanel, Sentry, Segment, Bugsnag, App Center, Datadog, PostHog, Heap, Countly, Matomo, Smartlook, Instabug, New Relic, Embrace) is linked but `PrivacyInfo.xcprivacy` declares no collected data types or tracking domains, it is flagged. Per-SDK coverage: [`tests/test-sdk-signals.sh`](../../../tests/test-sdk-signals.sh) |
| 20 | **2.1 Placeholder content** *(advisory)* | No lorem ipsum / TODO / FIXME / `example.com` / "insert X here" / changeme in store metadata |
| 21 | **3.1.1 Third-party payment SDK** *(advisory)* | If a third-party payment SDK (Stripe, Braintree, PayPal, Square, Adyen, …) is linked, review the offering, storefront, distribution and applicable 3.1.1/3.1.3 exceptions; SDK presence alone establishes no violation |
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
| 34 | **3.1.5 Cryptocurrency** *(advisory)* | A crypto wallet / exchange / mining signal (WalletConnect, web3swift, TrustWalletCore, mining libraries) with its entity/licensing and no-on-device-mining requirements |
| 35 | **4.2 Web wrapper** *(advisory)* | A `WKWebView` in a project with very few Swift files — heuristic for a thin wrapper around a website. The most false-positive-prone of the batch, so WARN/verify |
| 36 | **4.2.7 Remote desktop** *(advisory)* | A remote-desktop / host-mirroring signal (VNC/RDP libraries); host-mirroring apps must only show the owner's host and be free or use IAP |
| 37 | **4.4.2 Safari extension** *(advisory)* | A Safari content-blocker / web extension (`com.apple.Safari.*` extension point); must use the APIs as intended and not hide analytics/ads |
| 38 | **5.1.1(v) Account deletion** *(advisory)* | Account creation (`signUp`/`createUser`/`createAccount`/…) detected but no in-app account-deletion path (`deleteAccount`/`closeAccount`/…). This is the real 5.1.1(v) Account Sign-In rule |
| 39 | **5.1.4 Kids** *(advisory)* | Metadata targets a child audience **and** a third-party ads/analytics SDK is linked; Kids Category apps may not include third-party ads/analytics and need a parental gate |
| 40 | **5.3.4 Gambling** *(advisory)* | Real-money gaming language in metadata (casino, sportsbook, real money, wager); real-money gambling needs licensing, geo-restriction, and must be free on the store |
| 41 | **5.5 MDM** *(advisory)* | A Mobile Device Management signal (`DeviceManagement`, managed-app-config, `com.apple.mdm`); MDM apps need a commercial enterprise/education entity and purpose-limited data use |
| 42 | **2.3.3 Screenshot format/dimensions** *(advisory)* | Reads each in-repo screenshot's magic bytes and, for PNGs, its IHDR pixel dimensions; WARNs on a file whose content does not match its extension, a truncated PNG, or a PNG whose size matches no known App Store screenshot size (either orientation). JPEG dimensions are not parsed (format-checked only). WARN-only — never forces a RED verdict. |
| 43 | **5.1.1(iv) Permission priming** *(advisory)* | Custom pre-permission screens whose consent CTA steers users toward granting access ("Allow and continue", "Grant access to start", bare "Enable notifications" buttons) near a runtime permission request; Apple requires neutral wording ("Continue"/"Next"). Post-denial "Enable X in Settings" guidance is excluded. Source-language strings only (String Catalogs + hardcoded literals; English + common tr/de/fr/es steering patterns) |
| 44 | **3.1.2 Trial-emphasized paywall CTA** *(advisory)* | Paywall purchase buttons that promote the free trial over the billed price ("Continue with free trial", "Start your free trial") and "free-trial toggle" paywalls (a Toggle next to trial wording) — the 2026 App Review rejection wave under 3.1.2. A CTA that already shows the price is excluded; the fix is a neutral CTA ("Continue"/"Subscribe") with price + renewal term legible next to it. Source-language strings only (English + common tr/de/fr/es trial patterns, both word orders) |
| 45 | **2.3.7 Pricing language in name/subtitle** *(advisory)* | "Free", "% off", "sale", "discount", or a currency amount in `name.txt` / `subtitle.txt` (2.3.7 accurate metadata): prices vary by storefront and belong in the price field. Hyphen compounds ("ad-free") are excluded; keywords and descriptions are not scanned. The offline complement to `fastlane precheck`'s pricing rules (Phase 2 needs ASC credentials; this does not) |
| 46 | **5.1.1(ii) Generic purpose strings** *(advisory)* | Non-empty `NS*UsageDescription` values that are very short (<20 chars) or restate the permission without the user-facing feature ("This app needs camera access"). Vector 2 checks presence; this checks substance. Static complement to deep-review check 18 |
| 47 | **5.1.1 Third-party AI consent** *(advisory)* | An external AI endpoint/SDK (OpenAI, Anthropic, Gemini, Mistral, OpenRouter, Groq, Perplexity, Together) is in the code but no user-facing string names the provider — since 2026 App Review expects a consent screen naming the AI provider and what data is shared (5.1.1 / 5.1.2(i)). The endpoint URL literal itself does not count as a mention |
| 48 | **3.1.2 Paywall urgency/scarcity** *(advisory)* | Fake-urgency purchase pressure near the paywall: "limited time" / "only today" / "last chance" copy (multilingual), or a countdown timer combined with discount wording in a paywall view (3.1.2 / 2.3.1 misleading purchase pressure) |
| 49 | **5.6.1 Rating sentiment gate** *(advisory)* | "Enjoying the app?"-style copy next to a rating-prompt API — routing only happy users to the App Store review sheet is rating manipulation (5.6.1). Signal-gated on `requestReview` / `SKStoreReviewController` / a write-review link being present |
| 50 | **5.1.1(v) Forced login** *(advisory)* | A credential login UI (SecureField / Login view) with no skip / guest / continue-without-account affordance grepped anywhere — requiring login for features that are not account-based is rejected under 5.1.1(v). WARN-verify: an app whose every feature is genuinely account-based is fine |
| 51 | **4.5.4 Marketing push opt-out** *(advisory)* | A marketing-push SDK (OneSignal, Braze, CleverTap, Iterable, Airship, MoEngage) registers for notifications but no notification-preferences / opt-out signal is found; promotional push requires explicit consent and a working opt-out (4.5.4) |
| 52 | **2.1 Xcode/SDK minimum** *(advisory)* | The highest `LastUpgradeCheck` across checked-in pbxproj files is clearly pre-26 — since April 2026, App Store uploads must be built with the iOS 26 SDK (Xcode 26) or they are auto-rejected at upload. WARN-verify: the field tracks the upgrade-check, not the actual build toolchain |
| 53 | **3.1.2 EULA link in metadata** *(IAP-gated)* | Every locale’s App Store `description.txt` contains a functional Terms of Use (EULA) URL — auto-renewable-subscription apps are rejected without one in the app metadata (a custom EULA set in App Store Connect also satisfies Apple, but the description link is the checkable signal) |
| 54 | **4.3(b) Saturated category** *(advisory)* | The app name / subtitle / keywords place it in a category Apple names in 4.3(b) (dating, flashlight, sound effects, wallpaper, simple timers, fortune telling, drinking games, kama sutra, fart, burp) — exposure, not a violation; the differentiation question is deep-review check 30 |
| 55 | **2.5.5 IPv6-only** *(advisory)* | A legacy IPv4-only BSD socket API (`inet_addr`, `inet_aton`, `gethostbyname`, `sockaddr_in`, `AF_INET`) or a hardcoded IPv4 literal in source or a plist. App Review runs on an IPv6-only NAT64 network: DNS64 synthesizes hostnames, but a literal has nothing to synthesize from and the IPv4 API cannot address that network. Excludes loopback, `0.0.0.0`, `255.x` masks, CIDR ranges, version-looking values and comment lines |

Vectors 8–10 only run when in-app-purchase signals are detected (StoreKit / RevenueCat import,
or a paywall view). Otherwise the scanner emits a single PASS and skips them. Vectors 16–52, 54 and 55 (plus the IAP-gated 53) are
signal-gated advisory WARNs: each emits nothing unless its triggering signal is present.

### Screenshot format + dimensions (§7b, 2.3.3)

Vector 7 (above) checks that every locale has at least one screenshot. §7b goes one layer deeper,
purely with zero-dependency byte reads (`image-dims.sh`, pure bash + `od`/`awk`): for every
in-repo screenshot it reads the file's magic bytes to confirm the content actually matches its
extension (`.png`/`.jpg`/`.jpeg`), and for PNGs it also parses the IHDR chunk for pixel width and
height and checks that pair against a table of known App Store screenshot sizes (tried in both
orientations, sourced from Apple's [screenshot specifications
page](https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications/)).
JPEG dimensions are not parsed — JPEGs are format-checked only (magic-byte match), not size-checked.

This is **WARN-only, never FAIL**: the accepted-size table can drift as Apple adds device sizes,
and the scanner has no way to know which display slot (iPhone 6.9", iPad 13", …) a given file is
meant to target, so a size that matches nothing in the table is a prompt to verify against the
current spec, not proof of a rejection. A mismatched-format file (e.g. a renamed JPEG saved as
`.png`) or an unreadable/truncated PNG WARNs the same way. Findings surface under
`rule_id == "screenshot-dimensions"` (catalog vector 42) with messages beginning
`WARN: 2.3.3 Screenshot …`.

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

## Phase 4: Pierre deep review (31 semantic checks)

After Phase 3, Pierre runs the **Review Simulator**: 31 evidence-based checks the static scanner
cannot fully judge — **23 Tier A** (high-confidence) plus **8 Tier B v1** heuristic checks (items
**4, 5, 7, 10, 15, 29, 30, 31** in the checklist: 2.1 review notes, 2.2, 2.3.4, 3.2.2(x)/5.6.3, 2.5.1/4.5.3/4.5.4,
5.6.1/5.6.3, 4.3 differentiation, 4.0 design minimum). Full procedure, output format, and per-check steps are in
[`pierre-deep-review.md`](pierre-deep-review.md).

**Verdict impact:** none. Phase 4 uses the reference outcome definitions, separating missing evidence, unsupported inspection, unexecuted checks and evidence-backed non-applicability from PASS/FINDING.
These are advisory; FAIL/WARN counts and GREEN/YELLOW/RED come only from Phases 0–2.

**Coverage:** deepens scan hits where applicable (e.g. 5.1.1 purpose strings → 5.1.1(ii) quality;
§22 UGC keyword → 1.2 moderation UI) and adds net-new semantic areas (2.3.3 screenshots,
5.1.1(i) privacy policy fetch, 2.3 locale consistency, etc.). Guideline numbers touched
are tracked in `guidelines-baseline.json` → `covered_by_pierre_deep_review`.

**Presentation (Phase 5):** after Phase 3 commentary, show Phase 4 summary (N of 31 findings) and
every `REVIEW-FINDING` with Pierre's 2–3 sentence explanation. Tier B v1 findings are heuristic.

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

## Evidence strength and confidence

**Why:** severity says how bad a finding is. It does not say how firmly it is *established*. Apple's
automated validators run against the **built product**; this scanner reads a **repository**. A
missing purpose string found by grepping `.swift` files is a real upload blocker *if that code
ships* — and conditional compilation, `#if DEBUG`, unused targets, and files excluded from the
shipping target can all mean it does not. Reporting that identically to a missing key in a
checked-in `Info.plist` overstates the weaker of the two. Every `FAIL:`/`WARN:` therefore carries
two labels, in the text output and in `--format json` / `--format sarif`.

`scripts/evidence.sh` owns both catalogues. They are pinned per rule and gated by
`tests/test-evidence.sh`, which fails the build if any rule `scan.sh` sets is unclassified or uses a
label outside the closed vocabulary — so a new check cannot ship unlabelled.

### Evidence class — which artifact the conclusion rests on

Ordered strongest to weakest, where "strength" is how faithfully the artifact represents what
actually ships:

| Class | Read from | Why it sits here |
|---|---|---|
| `metadata` | `fastlane/metadata/**` | Uploaded to App Store Connect verbatim. |
| `manifest` | `Info.plist`, `*.entitlements`, `PrivacyInfo.xcprivacy` | Ship as authored. |
| `resource` | String Catalogs, screenshot assets | Shipped / uploaded files. |
| `build-setting` | `project.pbxproj` values | Resolved per target **and** per configuration, so a repo-level read is a proxy for what the archive was built with. |
| `source` | `.swift` / `.m` / `.mm` / `.h` greps | Weakest: presence in a file is not proof of presence in the shipping binary. |

A rule's class is the **weakest artifact its conclusion depends on**, not the strongest one it
happens to open. A parity check that reads `Info.plist` *and* greps source ("framework imported but
no purpose string") is `source`: if the grep is wrong about what ships, the conclusion is wrong,
however solid the plist read was.

**No rule reads a lockfile.** Every SDK signal (tracking, analytics, payment, AI, push) is a source
grep, not a `Podfile.lock` / `Package.resolved` read — which is why so many signal-gated checks sit
at the weakest class, and a direct explanation of where the real-panel false positives come from.

### Confidence — who acts on the finding

| Level | Meaning |
|---|---|
| `validator-blocking` | Apple's automated validation (upload or App Store Connect) blocks this. Mechanical, not a matter of opinion. |
| `review-risk` | A human reviewer rejects this pattern frequently. Well evidenced, but a person decides. |
| `judgment-call` | A heuristic signal. A reasonable reviewer could go either way, and a false positive is expected. |

A rule whose own message calls itself a heuristic is never graded above `judgment-call`.

### The derived qualifier

```
needs_build_verification = (confidence == validator-blocking)
                           AND (evidence in {source, build-setting})
```

**Derived, never stored** — so it cannot drift out of sync with the two catalogues. It means: this
*will* block the upload if it ships as-is, but the repository cannot show that it ships. Non-
validator findings never carry it; a human reviewer looks at the running app either way.

Phase 5 surfaces the count as a "what this run could not establish" note
(`summary.needs_build_verification` in JSON). It never changes the GREEN/YELLOW/RED verdict —
severity decides that, and this layer is about how the finding is *phrased*, not how it is counted.

### Per-branch refinement

A rule-level label is the honest default for the rule as a whole, but individual branches differ.
`set_evidence` and `set_confidence` refine the labels for one branch and are cleared by the next
`set_rule`:

- §2's empty-purpose-string FAIL reads `Info.plist` directly, so it is `manifest`, not the rule's
  `source` floor.
- §1's "declared but no code usage grepped" and §42's "could not read PNG dimensions" are real but
  soft findings (an over-declaration; a corrupt asset) — `judgment-call`, not the rule's
  `validator-blocking`.
- §6: only **name and description** are required by App Store Connect. An empty subtitle or
  keywords file is a `judgment-call` WARN, not the validator FAIL it used to be.
- §7: a missing per-locale screenshot folder (App Store Connect falls back to the primary locale)
  and "only N images (3–10 recommended)" are advice — `judgment-call`. Only an *empty* folder is
  the validator block.

**A check that could not run is a `SKIP`, not a labelled WARN.** §2's "Info.plist not found", §1's
"could not auto-detect iOS source dir" and §10's "no paywall view found" were first downgraded to
`judgment-call`; on reflection that was half a fix — they were still WARNs counting toward YELLOW,
inflating the verdict with a coverage gap. They are now `SKIP` under their rule (no labels, listed
under "Not audited"). §53's "no metadata dir" line was removed outright: the store-listing SKIP at
the top of the scan already names it.

Without this, a check that could not run would inherit "Apple's validator blocks this", which is
exactly the overstatement the layer exists to stop.

**Research notes behind the confidence column** (verified 2026-09-01): `ITMS-90683` fires for any
missing purpose string when the framework is *linked*, ATT included — so `att-usage` is genuinely
mechanical; `ITMS-91053` rejects a missing required-reason declaration; `ITMS-90725` enforces the
iOS 26 SDK floor at upload; App Store Connect requires a privacy-policy URL and a support URL to
submit. `export-compliance` was **downgraded** to `judgment-call`: the build is held at "Missing
Compliance" until the question is answered, which is one click — friction, not a rejection.

### §54 and the false-positive appetite

`saturated-category` WARNs on every app whose name, subtitle or keywords place it in a category
Apple names in 4.3(b) — including a genuinely good wallpaper or dating app. That is deliberate.
Apple's own text says new submissions in those categories are not accepted *unless* they offer a
meaningfully different or improved experience, so the exposure is real for every app there; the
WARN tells the team to state the differentiator in the review notes, and deep-review check 30
makes the actual judgment. A team that has done that can acknowledge the rule in `.precheck-ignore`
(`saturated-category`) — suppression is a signed acknowledgment, so the gate stays honest. Gating
the rule on "thin app" signals was considered and rejected: a substantial dating app carries the
same 4.3 exposure as a thin one.

### The fourth line class: `SKIP` (not audited)

`FAIL` / `WARN` / `PASS` all assert something about the build. A check that could not run asserts
nothing, and reporting it as a `PASS` — as the screenshots check used to, with *"assumed managed in
App Store Connect"* — turns an unexamined surface into a clean bill of health.

`SKIP:` records that state. It is counted separately (`skip=` from `verdict.sh`,
`summary.not_audited` in JSON), excluded from SARIF, and **never moves the verdict**: a missing
artifact is a gap in coverage, not a defect in the build. Phase 5 must list every SKIP under
"Not audited", so a GREEN is always read next to what it did not cover.

Two are emitted today:

- **`SKIP: metadata`** when no `fastlane/metadata` directory is found. The message names how many
  store-listing checks did not run, counted from `rules_with_evidence metadata` so the number cannot
  rot as rules are added. Both the count and the rule
  list under it are derived from `rules_with_evidence metadata`, so neither can rot. SKILL.md
  Phase 1 then asks the user to paste their App Store Connect listing, writes it into a temporary
  fastlane-shaped tree, and **re-runs the scanner** with an absolute `metadataDir` — so the findings
  are deterministic scanner lines that count toward the verdict, not a model's reading of the text.
- **`SKIP: 2.3.3 Screenshots`** when there is no in-repo screenshots directory.

**Acknowledging a gap.** Both can be silenced by id in `.precheck-ignore`
(`screenshots-per-locale`, `store-listing-not-audited`). Suppression here is a signed
acknowledgment, not a hiding place: the line leaves the text output, the record stays with
`suppressed: true`, the `suppressed` counter rises — and the gap **still counts in `not_audited`**,
because signing for a gap does not close it. `store-listing-not-audited` is a *gap record*, not a
check: it establishes nothing, carries no labels, and sits outside the catalogue and its
completeness test (`is_gap_record`, convention: ids ending in `-not-audited`).

### The full table

| § | Rule | Evidence | Confidence | Needs build verification |
|---|---|---|---|---|
| 1 | `privacy-manifest-parity` | source | validator-blocking | yes |
| 2 | `usage-description-crosscheck` | source | validator-blocking | yes |
| 3 | `att-usage` | source | validator-blocking | yes |
| 4 | `competitor-mentions` | metadata | review-risk | — |
| 5 | `metadata-char-limits` | metadata | validator-blocking | — |
| 6 | `locale-metadata-parity` | metadata | validator-blocking | — |
| 7 | `screenshots-per-locale` | resource | validator-blocking | — |
| 8 | `trial-disclosure` | resource | review-risk | — |
| 9 | `autorenew-disclosure` | resource | review-risk | — |
| 10 | `subscription-links-restore` | source | review-risk | — |
| 11 | `private-api` | source | validator-blocking | yes |
| 12 | `min-functionality-nav` | source | judgment-call | — |
| 13 | `screentime-justification` | manifest | review-risk | — |
| 14 | `siwa-parity` | source | review-risk | — |
| 15 | `external-purchase-link` | source | review-risk | — |
| 16 | `tracking-sdk-no-att` | source | review-risk | — |
| 17 | `export-compliance` | manifest | judgment-call | — |
| 18 | `support-privacy-url` | metadata | validator-blocking | — |
| 19 | `analytics-privacyinfo-mismatch` | source | review-risk | — |
| 20 | `placeholder-metadata` | metadata | review-risk | — |
| 21 | `thirdparty-payment-sdk` | source | review-risk | — |
| 22 | `ugc-no-moderation` | source | review-risk | — |
| 23 | `ats-arbitrary-loads` | manifest | review-risk | — |
| 24 | `applepay-recurring-disclosure` | source | review-risk | — |
| 25 | `custom-review-prompt` | source | review-risk | — |
| 26 | `misleading-marketing` | metadata | review-risk | — |
| 27 | `kids-wording` | metadata | review-risk | — |
| 28 | `keyboard-full-access` | manifest | review-risk | — |
| 29 | `health-icloud-sync` | source | review-risk | — |
| 30 | `vpn-networkextension` | source | review-risk | — |
| 31 | `demo-account` | source | review-risk | — |
| 32 | `executable-code-download` | source | review-risk | — |
| 33 | `background-modes-unused` | manifest | review-risk | — |
| 34 | `crypto-wallet-mining` | source | judgment-call | — |
| 35 | `webview-wrapper` | source | judgment-call | — |
| 36 | `remote-desktop` | source | judgment-call | — |
| 37 | `safari-extension` | manifest | review-risk | — |
| 38 | `account-no-delete` | source | review-risk | — |
| 39 | `kids-ads-analytics` | metadata | review-risk | — |
| 40 | `realmoney-gambling` | metadata | review-risk | — |
| 41 | `mdm` | source | judgment-call | — |
| 42 | `screenshot-dimensions` | resource | validator-blocking | — |
| 43 | `permission-priming-cta` | source | judgment-call | — |
| 44 | `paywall-trial-emphasis` | source | judgment-call | — |
| 45 | `metadata-pricing-language` | metadata | judgment-call | — |
| 46 | `generic-purpose-string` | manifest | judgment-call | — |
| 47 | `ai-provider-consent` | source | judgment-call | — |
| 48 | `paywall-urgency` | source | judgment-call | — |
| 49 | `rating-sentiment-gate` | source | judgment-call | — |
| 50 | `forced-login` | source | judgment-call | — |
| 51 | `push-marketing-optout` | source | judgment-call | — |
| 52 | `xcode-sdk-requirement` | build-setting | validator-blocking | yes |
| 53 | `subscription-eula-metadata` | metadata | review-risk | — |
| 54 | `saturated-category` | metadata | judgment-call | — |
| 55 | `ipv4-literal` | source | review-risk | — |

*Generated from `scripts/evidence.sh`; `tests/test-evidence.sh` keeps it honest.*

---

## Guideline citations

**Why:** Pierre explains every FAIL and WARN, and an explanation is only worth reading if the
guideline wording behind it is Apple's, not a plausible-sounding reconstruction. There are two ways
to get that wording:

| | Fetch the live page every run | Quote a pinned snapshot |
|---|---|---|
| Current | always | as of the last reconciliation |
| Network | required | none |
| Reproducible | no — a different extraction each run | yes |
| Coverage | truncates past ~5.4 | whatever was reconciled (curl-based, covers the tail) |
| Reviewable | no | yes — the quotes are in git |
| Wrong-quote detection | none | the drift job flags the section |

This project takes the second, because a pre-submission gate has to be reproducible and has to work
offline. `scripts/guideline-cite.sh` reads the pinned quotes out of `guidelines-fingerprints.json` —
the same file whose hashes already detect when Apple changes a section — so a quote that has gone
out of date is a **detectable condition** rather than a silent lie.

```bash
bash skills/appstore-precheck/scripts/guideline-cite.sh 5.1.1      # 5.1.1(v) and 3.1.1(a) resolve to their anchor
bash skills/appstore-precheck/scripts/guideline-cite.sh --json 2.3.3
bash skills/appstore-precheck/scripts/guideline-cite.sh --list
```

Exit codes: `0` cited · `3` no pinned citation · `64` bad usage · `66` store unreadable.

**Exit 3 is the point.** With no pinned quote the caller must say the wording could not be verified
this run — never reconstruct guideline text from memory. Phase 3 states this as a hard rule, and
`guideline_url` on every finding (JSON and SARIF) links the section so a human can always read the
source.

**Staleness, two ways.** Each quote carries `quote_verified_on`. Past `GUIDELINE_CITE_STALE_DAYS`
(default 120) the citation prints a `STALE` marker. But age is only a proxy, and a poor one in both
directions: an untouched section stays correct for years, while a section Apple edited yesterday is
wrong and still looks fresh.

`--verify-live` resolves it properly. It fetches the live page (cached per day, so a whole run costs
one request), re-hashes the section, and compares it with the pinned fingerprint — the same
comparison the scheduled drift job makes, available at explain time:

- **unchanged** → the quote is current however old the pin is, and `STALE` is withdrawn
- **changed** → exit `4` and `CHANGED`; Phase 3 then requires Pierre to say Apple's text has moved
  rather than quoting the pinned wording as current
- **any failure** (offline, fetch error, section absent) → degrades to the offline behaviour and
  never reports a verification that did not happen

This is why the shared HTML parser lives at
[`scripts/lib/guideline-text.sh`](../scripts/lib/guideline-text.sh) *inside the skill* rather than
beside the maintainer scripts: only the skill directory is packaged, and installed users need it.

**Beyond the guidelines page.** Apple also announces policy changes on
[developer.apple.com/news](https://developer.apple.com/news/) — deadlines, new required
declarations, entitlement changes — often before the guideline text catches up. Phase 0 scans it for
items newer than the baseline `reconciled_on` and WARNs on anything review-relevant. Non-blocking,
like every Phase 0 signal: it is a gap in our coverage, not a fault of the build.

**Populating the quotes** is a maintainer step, deliberately separate from reconciliation:

```bash
bash scripts/guideline-drift.sh --quotes            # fetches the live page
bash scripts/guideline-drift.sh --quotes --html saved.html
```

`--quotes` writes only `quote` and `quote_verified_on`; it never touches a fingerprint or
`reconciled_on`. A section is re-quoted **only when its live fingerprint still matches the pinned
one** — quoting a drifted section would take the new wording while the fingerprint still claims the
old, papering over exactly the change the drift check exists to surface. Drifted sections are warned
about and left alone, so a human reconciles first, then re-runs `--quotes`.

---

## SARIF output (`--format sarif`)

`scan.sh --format sarif` emits a SARIF 2.1.0 log built from the same structured findings as
`--format json` (pure `jq`, no new dependency). `results[]` contains the non-suppressed FAIL and
WARN findings (FAIL → `error`, WARN → `warning`); PASS and suppressed findings are excluded. Findings
that carry a `file`/`line` become SARIF `physicalLocation`s so GitHub can anchor PR annotations. Only
the deterministic scan findings are included — the agent-mode Pierre deep-review findings are not
(SARIF is a deterministic CI artifact). The GitHub Action uploads this via `upload-sarif` and/or
emits inline `::error`/`::warning` annotations, both opt-in.

---

### Real App Store outcomes (`corpus/outcomes/`)

Beyond the synthetic and real-panel corpora, the tool tracks real Apple review outcomes (approved /
rejected + cited guideline) in a committed, human-reviewed ledger (`corpus/outcomes/ledger.json`),
summarized in `docs/scorecard.md` by `scripts/scorecard-outcomes.sh`. It is honesty-floored: no rate
is computed below 10 records (raw tally only), and a permanent survivorship-bias caveat applies once
a rate is shown. It is a reporting layer only — it never influences the GREEN/YELLOW/RED verdict or
which rules fire. Contribute an outcome via the "App Store outcome" issue template.

---

### Optional local dynamic simulator tier

Beyond the static scan and the agent-mode deep reviews, an **opt-in** local dynamic tier
(`references/simulator-dynamic-review.md`, SKILL.md Phase 6) can run the app on a simulator
(`xcrun simctl` + Maestro MCP, with `scripts/dynamic-run.sh` driving the observation-based part)
and emit advisory `DYNAMIC-PASS:` / `DYNAMIC-FINDING:` / `DYNAMIC-SKIP:` observations — launch/crash
(three repeats on an erased device; a finding needs all three), first screen, dark-mode / Dynamic
Type / iPad layout heuristics, the installed bundle's `Info.plist` / `DTXcode` / linked frameworks,
hosts contacted vs `NSPrivacyTrackingDomains`, and the agent-driven paywall, Restore tap, permission
prompt, demo-login and screenshot-parity checks. It is off by default. Explicit
`--dynamic-blocking` can add a FAIL only for a 3/3 launch or demo-login failure. It never writes
to the user's project: `--build` builds a temporary copy, while `--app` uses a supplied artifact;
the runner creates and deletes its own simulator. The tier is permanently local-only (it
cannot run in CI). It *does* execute the app. `scripts/dynamic.sh` records every observation as
`evidence: runtime` and reconciles it with the static findings; a Debug build never clears `needs
build verification`. It is a pre-submit local smoke signal, not a TestFlight / crash-reporter / QA
replacement. When it is not run, the report carries the `runtime-not-audited` gap record; on a React
Native / Flutter / Kotlin Multiplatform repo the static scan additionally carries
`framework-not-audited`, because its code-level greps read Swift / ObjC only.

---

### Guideline obligation coverage

The generated [coverage report](../../../docs/guideline-coverage.md) counts reviewed obligations and implemented routes separately from checks that actually ran for a project. The [route guide](guideline-coverage.md) documents the opt-in build, artifact, runtime, metadata, source evidence, and attestation results. Every obligation has a route, but partial evidence and a developer attestation do not amount to automatic approval. The default scan remains offline and read-only.

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
[ ] Paywall price matches App Store Connect EXACTLY (amount + currency formatting)
[ ] Free trial is configured as an Introductory Offer in App Store Connect (not app-side only)
[ ] Updated age-rating questionnaire (13+/16+/18+ tiers) completed in App Store Connect
[ ] EU DSA trader status declared (required for EU distribution)
[ ] If user data goes to a third-party AI provider: consent screen names the provider
[ ] IPv6-only run: Internet Sharing > "Create NAT64 Network" on a Mac, every network feature works (2.5.5 — GUI-only, not automatable; §55 only greps the IPv4-literal subset)
```
