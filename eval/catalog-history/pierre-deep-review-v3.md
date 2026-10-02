# Phase 4: Pierre deep review (31 semantic checks)

After Phase 3 (explaining every scan FAIL/WARN), Pierre runs a **read-only, project-wide
semantic review** of 31 guideline areas the static scanner cannot fully judge. The **23 Tier A**
checks (all 31 except the Tier B items below) are high-confidence; the **8 Tier B v1** checks
**4, 5, 7, 10, 15, 29, 30, and 31** are heuristic advisory (higher false-positive risk, still useful
pre-submit signals).

This is the **Review Simulator** layer: Pierre reads Swift, metadata, entitlements, screenshots,
xcstrings, paywall views, review notes, and fetches live privacy/support URLs — then cross-checks
claims against evidence.

**This phase does not change the GREEN/YELLOW/RED verdict.** Verdict counts come only from
Phases 0–2 (`FAIL:` / `WARN:` lines). Phase 4 emits `REVIEW-PASS:` or `REVIEW-FINDING:` lines
that Pierre explains in Phase 5 presentation.

## Rules

**Optional TypeSafe/Jev support:** when the user enables semantic assistance, follow
[`typesafe.md`](typesafe.md) for bounded typed judgments, evidence bundles and uncertainty
handoffs. Keep full Pierre review during shadow evaluation; Jev cannot inspect images.
Use stable identities from [`review-catalog.json`](review-catalog.json). Neither the
typed judgments nor their advisory output changes the scanner verdict or upload token.

- **Read-only:** never modify project files.
- **Evidence-based:** cite `file:line`, metadata path, screenshot filename, or fetched URL text.
  If you cannot read something (private URL, missing file), say so — do not invent findings.
- **All 31 checks, every run:** report an outcome for every item. Missing evidence is `REVIEW-NEEDS-REVIEW`, unsupported inspection is `REVIEW-UNSUPPORTED`, and unexecuted checks are `REVIEW-NOT-RUN`; none is PASS.
- **REVIEW-FINDING severity:** always `WARN` (advisory). Never emit `REVIEW-FINDING: … FAIL`.
  A deep-review issue informs the human; it does not block the token by itself.
- **Tier B checks (4, 5, 7, 10, 15, 29, 30, 31):** require affirmative applicability evidence; absent repository signals alone do not prove non-applicability;
  when flagging, use cautious language ("may trigger review questions") — these are heuristics.
- **Deepen scan hits:** when Phase 1 already flagged a guideline, Phase 4 still runs the matching
  deep check and adds semantic context (do not repeat the machine line verbatim — add what the
  scanner could not see).
- **WebFetch:** use `WebFetch` (or equivalent) on `privacy_url.txt` and `support_url.txt` when
  present. If fetch fails, `REVIEW-NEEDS-REVIEW: … — privacy policy unavailable`.
- **Screenshots:** read at least one PNG/JPEG per primary locale; compare visible UI/features to
  metadata claims.
- **Language:** write Pierre's 2–3 sentence explanations in the user's conversation language.

## Output format

For each of the 31 checks (in table order), preserve the legacy PASS/FINDING forms
for supported conclusions. Use REVIEW-NEEDS-REVIEW, REVIEW-NOT-RUN, REVIEW-UNSUPPORTED
or REVIEW-NOT-APPLICABLE when inspection is blocked, unexecuted or provably outside
the applicable scope. Report those counts separately from PASS and FINDING;
missing evidence never establishes compliance.


```
REVIEW-PASS: <guideline> — <one-line why it looks OK, with evidence pointer>
```

or

```
REVIEW-FINDING: <guideline> WARN — <one-line concrete mismatch or gap, with evidence pointer>
Pierre: <2–3 sentences: why Apple cares, what you found, what to fix or verify>
```

If a check is **not applicable** (e.g. no HealthKit, no VPN, no contest copy), still report:

```
REVIEW-NOT-APPLICABLE: <guideline> — <evidence-backed reason>
```

"Not applicable" requires sufficiently complete scope and evidence that the subject is absent
or an explicit platform/distribution predicate excludes it. A missing repository signal is insufficient. When the
material a check inspects exists and is clean — release notes present but free of beta
language, a review prompt present but using the system API — report a plain
`REVIEW-PASS` with the evidence pointer, not "not applicable".

---

## The 31 checks (guideline order)

| # | Guideline | Deep question | Primary sources |
|---|---|---|---|
| 1 | **1.2** | UGC present → is there a real report/block/moderation UI flow, not just keywords in copy? | Swift navigation, moderation views, §22 scan context |
| 2 | **1.4.1** | Health/medical/wellness claims in metadata or UI without appropriate disclaimers or HealthKit compliance? | metadata, Swift HealthKit usage, onboarding copy |
| 3 | **2.1** | Metadata/marketing claims match implemented features (AI, offline, ad-block, sync, etc.)? | metadata, description, Swift feature grep |
| 4 | **2.1** | Login-gated app → App Review demo account / notes **actionable** (credentials, steps, not placeholder)? | `review_information/`, `.reviewPrepNotes`, §31 scan context |
| 5 | **2.2** | Store-facing copy or UI still says beta / test / preview / work-in-progress? | metadata, release_notes, Swift UI strings |
| 6 | **2.3.5** | Primary category plausible for app type (game vs utility vs health, etc.)? | fastlane `primary_category`, metadata tone, code structure |
| 7 | **2.3.4** | App preview assets present → features shown match the shipped app and metadata? | preview video paths, metadata, Swift UI |
| 8 | **2.3.3 / 2.3.1(a)** | Screenshots show features the app actually ships; no misleading device frames or competitor UI? | screenshot images, metadata, Swift UI |
| 9 | **2.3.2 / 3.1.2(c)** | Pricing/subscription language in metadata matches paywall (free vs paid, trial terms)? | metadata, paywall Swift, xcstrings |
| 10 | **3.2.2(x) / 5.6.3** | Incentivized review copy ("rate 5 stars", "review for reward") in metadata or UI? | metadata, onboarding, paywall, §25 scan context |
| 11 | **2.3** | Cross-locale metadata consistent (feature lists, trial terms, support/privacy URLs, pricing claims)? | all `fastlane/metadata/*` locales |
| 12 | **3.1.1** | Digital goods sold or unlocked via external purchase links (web checkout, Stripe in WebView)? | Swift WebView/paywall, metadata, entitlements |
| 13 | **3.1.2** | Subscription/trial/auto-renew/cancel disclosures are **legible sentences**, not keyword stubs? | paywall views, xcstrings, String Catalog |
| 14 | **4.2 / 4.2.2** | App is more than a thin shell: meaningful navigation, native affordances, not a lone WebView brochure? | Swift UI structure, §12/§35 scan context |
| 15 | **2.5.1 / 4.5.3 / 4.5.4** | Push or HomeKit entitlement → used as intended (no spam-push promises; HomeKit without home UI)? | entitlements, Info.plist, metadata, Swift |
| 16 | **4.8** | Third-party login present → Sign in with Apple offered, or a documented exempt case (enterprise, existing account, etc.)? | login Swift, SDK imports, §14 scan context |
| 17 | **5.1.1(i)** | Privacy policy text (fetched) matches data collection in code, PrivacyInfo, and App Privacy narrative? | fetch privacy URL, PrivacyInfo, SDK imports |
| 18 | **5.1.1(ii)** | Purpose strings are specific and tied to a visible feature (not empty, generic, or copy-paste)? | Info.plist, permission usage in Swift |
| 19 | **5.1.1(iii)** | Data/permission requests proportionate to stated app purpose (no obvious over-collection)? | permissions, SDKs vs metadata promise |
| 20 | **5.1.1(iv)** | Permission denial handled gracefully — no infinite re-prompt loops or hard blocks without explanation? | location/camera/notification/auth flows in Swift |
| 21 | **5.1.1(iv)** | Custom pre-permission priming screens use neutral CTA copy ("Continue"/"Next") — no steering toward Allow/Grant/Enable? | priming/onboarding views, xcstrings CTA strings, §42 scan context |
| 22 | **5.1.2** | ATT prompt, `NSUserTrackingUsageDescription`, privacy policy tracking section, and ad SDK usage align? | Info.plist, policy fetch, ad SDK imports |
| 23 | **5.1.3** | HealthKit data not used for advertising/marketing; sync paths respect health-data rules? | HealthKit + analytics/ad SDK co-use |
| 24 | **1.3 / 5.1.4** | Kids-audience signals → parental gate before external links/purchases/account areas? | metadata kids wording, parental gate UI |
| 25 | **5.4** | VPN/NetworkExtension → on-screen disclosure text visible in UI strings (not only Info.plist)? | Swift strings, NetworkExtension usage |
| 26 | **5.2.1** | Obvious third-party trademark/brand misuse in metadata, assets, or UI copy? | metadata, asset filenames, Swift strings |
| 27 | **5.3.1 / 5.3.2** | Contest/sweepstakes/lottery copy → official rules/eligibility/disclosure present in metadata? | description, keywords, in-app contest UI |
| 28 | **1.5 / 5.6.2** | Developer identity consistent: app name, support URL content, bundle/marketing domain match? | fetch support URL, metadata, legal/footer copy |
| 29 | **5.6.1 / 5.6.3** | Rating/review manipulation dark patterns (withhold features until 5 stars, direct write-review links without `requestReview`)? | Swift, metadata, §25 scan context |
| 30 | **4.3** | In a category Apple names as saturated (4.3(b)), is the app meaningfully different from the incumbents, and free of 4.3(a) per-variant bundle ids? | entry point, main views, `project.pbxproj` targets, §54 scan context |
| 31 | **4.0** | Would the app pass Apple's minimum design bar: usable iPad / large-text layout, no clipped, overlapping or placeholder UI, no degraded or non-functional screens? | SwiftUI/UIKit layout code, `Info.plist` device family + orientations, screenshot assets |

---

## Per-check procedure (detail)

### 1 — 1.2 UGC moderation UI

1. Establish UGC scope (posts, comments, chat, uploads) from feature and runtime evidence. Mark not applicable only when sufficient evidence excludes UGC.
2. Search Swift for report/block/flag/moderate flows and screens reachable from content.
3. Compare to metadata promises ("community", "share", "chat").
4. Flag if UGC exists but moderation is only mentioned in text, not implemented in UI.

### 2 — 1.4.1 Health / medical claims

1. Scan metadata and onboarding for diagnose, treat, cure, clinical, FDA, blood pressure, etc.
2. If HealthKit present, check disclaimers ("not a medical device") where claims exist.
3. Flag unsubstantiated treatment claims without appropriate health disclaimers.

### 3 — 2.1 Claims ↔ code

1. Extract feature claims from name, subtitle, description, keywords (AI, ML, offline, block ads, VPN, etc.).
2. Grep Swift / imports for matching implementation.
3. Flag prominent metadata claims with no code evidence.

### 4 — 2.1 Review notes / demo account quality *(Tier B v1)*

1. If the app is login-gated (`SecureField`, Login/SignIn views) or scan §31 flagged missing demo:
   read `fastlane/metadata/*/review_information/` (username, password, notes) and
   `.appstore-precheck.json` → `reviewPrepNotes` if set.
2. Flag empty notes, placeholder credentials (`test`, `demo`, `changeme`, `TBD`), or notes that
   do not explain how to reach core features (subscription paywall, Screen Time blocking, etc.).
3. If the app is not login-gated and has no account wall, mark not applicable.

### 5 — 2.2 Beta / test language *(Tier B v1)*

1. Grep store metadata, `release_notes.txt`, and user-visible Swift strings (not code comments) for:
   `beta`, `testflight`, `test flight`, `preview`, `pre-release`, `work in progress`, `WIP`,
   `under development`, `not final`, `experimental`.
2. Exclude legitimate internal keys and developer log strings not shown to users.
3. Flag any store-facing copy implying the App Store build is unfinished or a beta.

### 6 — 2.3.5 Category fit

1. Read primary category if present in fastlane or `.appstore-precheck.json`.
2. Infer app type from code (game loop, utility, reader, social).
3. Flag obvious mismatch (arcade game filed as Productivity).

### 7 — 2.3.4 App preview consistency *(Tier B v1)*

1. Look for app preview assets under `fastlane/metadata/*/preview*` or `*.mov` / `*.mp4` in metadata trees.
2. If no preview assets in-repo, report REVIEW-NEEDS-REVIEW until the ASC asset inventory establishes whether previews exist.
3. If previews exist: compare visible features/captions to metadata and Swift UI; flag previews
   showing features absent from the build.

### 8 — 2.3.3 Screenshots vs reality

1. Open ≥1 screenshot per primary locale.
2. List visible features (tabs, paywall, login, maps, etc.).
3. Flag screenshots showing features absent from the build or metadata.
4. For the full structured screenshot vision review (placeholder/empty-state, text overflow,
   wrong device frame, misleading marketing, metadata mismatch), follow
   `screenshot-vision-review.md` (sibling file in this same `references/` directory).

### 9 — 2.3.2 / 3.1.2(c) Pricing language

1. Compare metadata "free", trial, and price claims to paywall/subscription UI strings.
2. Flag "completely free" metadata when IAP/paywall exists without clear disclosure.

### 10 — 3.2.2(x) / 5.6.3 Incentivized review *(Tier B v1)*

1. Grep metadata, onboarding, and paywall strings for: `rate us`, `leave a review`, `5 star`,
   `five star`, `review and get`, `gift card`, `reward for review`, `write a review to unlock`.
2. Cross-check scan §25 (custom review prompt) — Phase 4 adds semantic context if §25 passed.
3. Flag quid-pro-quo review incentives or star-rating manipulation copy.

### 11 — 2.3 Locale parity (semantic)

1. Beyond scan's file-presence check: compare trial terms, feature bullets, and pricing claims across locales.
2. Flag material omissions (trial mentioned in en-US only, different feature lists).

### 12 — 3.1.1 External digital purchase

1. Search for external checkout URLs, Stripe/PayPal in WebView, "subscribe on our website".
2. Establish the offering, storefront, distribution and applicable 3.1.1(a)/3.1.3 exception with dated evidence. US links do not universally require entitlements. Missing context is REVIEW-NEEDS-REVIEW; a payment SDK alone is not a violation.

### 13 — 3.1.2 Disclosure quality

1. Read paywall disclosure strings (Swift + xcstrings).
2. Flag if trial/auto-renew/cancel info is a single keyword, lorem, or unreadably dense.
3. Require human-readable sentences covering trial length, renewal, and cancellation path.

### 14 — 4.2 / 4.2.2 Minimum functionality (semantic)

1. Map primary user journeys (launch → core action).
2. Flag single-screen WebView brochure, template placeholder flows, or no native navigation beyond §12 minimum.

### 15 — 2.5.1 / 4.5.3 / 4.5.4 Push / HomeKit abuse *(Tier B v1)*

1. Read entitlements and Info.plist for push notifications and HomeKit.
2. **Push:** if push entitlement present, scan metadata/UI for spam patterns ("notify every hour",
   "unlimited reminders") unrelated to user-initiated alerts.
3. **HomeKit:** if HomeKit framework imported, confirm home-automation UI exists; flag HomeKit
   import with no home-related features (possible misuse).
4. If neither push nor HomeKit signals, mark not applicable.

### 16 — 4.8 Sign in with Apple (context)

1. If Google/Facebook/etc. login exists, confirm `ASAuthorizationAppleID` / Sign in with Apple button.
2. If absent, assess exempt patterns (enterprise-only, password-only existing users) — flag uncertain cases for human review.

### 17 — 5.1.1(i) Privacy policy accuracy

1. Fetch privacy URL from primary locale metadata.
2. Compare policy statements to: PrivacyInfo collected types, tracking domains, location/camera/health SDK usage.
3. Flag a contradiction only with verified location collection/sharing evidence; a CoreLocation import alone cannot establish collection.

### 18 — 5.1.1(ii) Purpose string quality

1. List every `NS*UsageDescription` in Info.plist.
2. Flag empty, placeholder, or generic strings; flag mismatch with the feature that triggers the prompt.

### 19 — 5.1.1(iii) Data minimization

1. List sensitive permissions and SDKs.
2. Compare to app category and metadata promise.
3. Flag obvious overreach (contacts + photos + location for a calculator).

### 20 — 5.1.1(iv) Permission denial UX

1. Trace location/camera/photo/notification permission flows.
2. Flag forced loops, dead-ends, or dark patterns after denial.

### 21 — 5.1.1(iv) Permission-priming CTA neutrality

1. Find custom pre-permission ("priming") screens: views that explain an upcoming permission
   request and whose button triggers `requestAccess` / `requestAuthorization` /
   `requestRecordPermission`.
2. Read the consent CTA copy on those screens (xcstrings source-language values and hardcoded
   button titles).
3. Flag steering wording on the gate button — "Allow …", "Grant …", "Enable …", "Turn on …" —
   Apple requires neutral wording like "Continue" or "Next"; the grant/deny decision belongs to
   the system alert. Body copy explaining *why* the permission helps is fine; post-denial
   "Enable X in Settings" guidance is Apple's own recommended pattern and is fine.
4. Cross-check scan §42 (`permission-priming-cta`) — Phase 4 adds semantic judgement the static
   regex cannot: is the flagged string really on a consent gate, and does the flow stay usable
   if the user declines (ties into check 20)?

### 22 — 5.1.2 ATT consistency

1. If ad/attribution SDK or IDFA access: confirm ATT API usage and description text.
2. Cross-check privacy policy tracking section vs implementation.

### 23 — 5.1.3 HealthKit + ads

1. If HealthKit imported: search for analytics/ad SDK sending health-derived signals.
2. Flag health data paths combined with advertising identifiers.

### 24 — 5.1.4 Parental gate

1. If kids metadata or child-audience copy: find parental gate before web/links/IAP/account.
2. Flag child positioning without age gate UI.

### 25 — 5.4 VPN disclosure UI

1. If NetworkExtension/NEVPNManager: search UI strings for data-collection disclosure required at launch/settings.
2. Flag VPN capability with no user-visible disclosure copy.

### 26 — 5.2.1 IP / trademarks

1. Scan metadata and visible strings for other companies' brands used as if owned.
2. Flag likely trademark misuse (not generic descriptive use).

### 27 — 5.3.1 / 5.3.2 Contests

1. If sweepstakes/contest/giveaway language: check for rules, eligibility, sponsor, no-purchase-necessary.
2. Flag contest marketing without rules in metadata or in-app.

### 28 — 1.5 / 5.6.2 Developer identity

1. Fetch support URL; confirm it resolves and shows developer contact or support path.
2. Compare app name, support domain, and privacy policy domain for consistency.
3. Flag placeholder support pages or identity mismatch.

### 29 — 5.6.1 / 5.6.3 Rating/review manipulation *(Tier B v1)*

1. Grep Swift and metadata for: `itms-apps://` write-review URLs, `apps.apple.com/.../write-review`,
   "rate 5 stars", "only enable after review", custom star-rating UI tied to App Store review.
2. Compare to system `requestReview` / `SKStoreReviewController` usage (scan §25).
3. Flag dark patterns that manipulate ratings or bypass Apple's review prompt API.

### 30 — 4.3 Differentiation in a saturated category *(Tier B v1)*

Scan §54 flags *exposure* — the app name/subtitle/keywords put this in a category Apple names in
4.3(b). It cannot judge the thing that actually decides the rejection: whether this app offers, in
Apple's words, a "meaningfully different or improved experience". That is this check.

Run it when **either** §54 fired **or** the app is a thin single-purpose utility, whatever its
category. Skip it (report not applicable) for apps with a substantial, differentiated feature set.

1. Read what the app actually does: entry point, main views, the feature set implied by the source —
   not the description's claims about it.
2. Compare against what the category's incumbents already do. Name the specific capability, data,
   integration, or workflow that this app has and a generic member of the category does not.
3. Check 4.3(a) too: multiple app targets or bundle identifiers that are variants of one app
   (per-city, per-team, per-school builds) instead of one app with in-app selection. Look at
   `project.pbxproj` targets and `PRODUCT_BUNDLE_IDENTIFIER` values.
4. If the honest answer is "nothing meaningful", **say so plainly**. This is a judgment call and must
   be labelled as one — but a vague reassurance here is worse than no check, because 4.3 rejections
   arrive after the build has already passed everything mechanical.
5. Recommend stating the differentiator explicitly in the App Review notes when the category is one
   Apple names.

Quote Apple's 4.3 wording via `guideline-cite.sh 4.3` rather than paraphrasing the bar.

### 31 — 4.0 Design minimum standards *(Tier B v1)*

Guideline 4.0 is the intro prose of the Design section, and it is Apple's **single most-cited
removal reason** (42,252 removals in the 2024 App Store Transparency Report, ahead of every
numbered sub-section). It rejects apps that are not "simple, refined, innovative, and easy to use"
or that "stop working or offer a degraded experience". No grep can judge that; this check reads
the layout code with the reviewer's eyes. Heuristic by nature — report missing runtime or visual evidence as
`REVIEW-NEEDS-REVIEW`; a clean source read alone does not establish design compliance.

1. **iPad and large-text layout.** If `UIDeviceFamily` includes iPad (or the app does not opt
   out), look for iPad-hostile layouts: hardcoded frame widths, `UIScreen.main.bounds`
   arithmetic, single-column phone layouts with no `NavigationSplitView` / size-class handling,
   `.fixedSize()` on user text. Look for `Text` with `.lineLimit(1)` + `.minimumScaleFactor` on
   copy that grows under Dynamic Type — a common source of clipped labels at accessibility sizes.
2. **Placeholder and degraded UI.** Views that render "Coming soon", "TODO", lorem ipsum, empty
   tabs, or buttons wired to no action (`Button {} label:`, `action: {}`); screens that only show
   a spinner with no timeout or error state.
3. **Consistency with screenshots.** Where check 8 found screenshots, the shipped UI should not
   look obviously less finished than what is marketed (empty states, missing icons).
4. Flag as `REVIEW-FINDING: 4.0 WARN — …` only with a concrete `file:line`; otherwise
   report `REVIEW-NEEDS-REVIEW: 4.0 — runtime/visual evidence required` unless sufficient
   evidence supports PASS. Quote Apple's own wording via
   `guideline-cite.sh 4.0` (the page anchors it as `#4`, not `#4.0`).

What this check cannot do: see the running app. iPad rotation, real Dynamic Type rendering and
actual crashes belong to Phase 6 (the local simulator tier), not to a source read.

---

## Phase 5 presentation

After Phase 4, include in the final report:

1. Trilingual verdict block (from scan counts only).
2. Phase 3 commentary (every scan FAIL/WARN).
3. Phase 4 summary table: 31 checks → separate counts for PASS, FINDING, NEEDS-REVIEW, UNSUPPORTED, NOT-RUN and NOT-APPLICABLE (note Tier B items 4, 5, 7, 10, 15, 29, 30, 31 if any fired). The 5 screenshot-vision checks (S1–S5) report as a separate "+5 vision checks" sub-block, outside the "of 31" count.
4. Phase 4 detail: every `REVIEW-FINDING` with Pierre explanation; optionally list `REVIEW-PASS` lines compactly.
5. Verbatim Phase 1 scan output + verdict/token action.
