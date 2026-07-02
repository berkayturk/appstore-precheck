# Phase 4: Pierre deep review (28 semantic checks)

After Phase 3 (explaining every scan FAIL/WARN), Pierre runs a **read-only, project-wide
semantic review** of 28 guideline areas the static scanner cannot fully judge. The **22 Tier A**
checks (all 28 except the Tier B items below) are high-confidence; the **6 Tier B v1** checks
**4, 5, 7, 10, 15, and 28** are heuristic advisory (higher false-positive risk, still useful
pre-submit signals).

This is the **Review Simulator** layer: Pierre reads Swift, metadata, entitlements, screenshots,
xcstrings, paywall views, review notes, and fetches live privacy/support URLs — then cross-checks
claims against evidence.

**This phase does not change the GREEN/YELLOW/RED verdict.** Verdict counts come only from
Phases 0–2 (`FAIL:` / `WARN:` lines). Phase 4 emits `REVIEW-PASS:` or `REVIEW-FINDING:` lines
that Pierre explains in Phase 5 presentation.

## Rules

- **Read-only:** never modify project files.
- **Evidence-based:** cite `file:line`, metadata path, screenshot filename, or fetched URL text.
  If you cannot read something (private URL, missing file), say so — do not invent findings.
- **All 28 checks, every run:** report each item as `REVIEW-PASS:` or `REVIEW-FINDING:` — no skipping.
- **REVIEW-FINDING severity:** always `WARN` (advisory). Never emit `REVIEW-FINDING: … FAIL`.
  A deep-review issue informs the human; it does not block the token by itself.
- **Tier B checks (4, 5, 7, 10, 15, 28):** prefer `REVIEW-PASS: … — not applicable` when the signal is absent;
  when flagging, use cautious language ("may trigger review questions") — these are heuristics.
- **Deepen scan hits:** when Phase 1 already flagged a guideline, Phase 4 still runs the matching
  deep check and adds semantic context (do not repeat the machine line verbatim — add what the
  scanner could not see).
- **WebFetch:** use `WebFetch` (or equivalent) on `privacy_url.txt` and `support_url.txt` when
  present. If fetch fails, `REVIEW-FINDING: … WARN — could not fetch privacy policy; verify manually`.
- **Screenshots:** read at least one PNG/JPEG per primary locale; compare visible UI/features to
  metadata claims.
- **Language:** write Pierre's 2–3 sentence explanations in the user's conversation language.

## Output format

For each of the 28 checks (in table order):

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
REVIEW-PASS: <guideline> — not applicable (<reason>)
```

---

## The 28 checks (guideline order)

| # | Guideline | Deep question | Primary sources |
|---|-----------|---------------|-----------------|
| 1 | **1.2.1** | UGC present → is there a real report/block/moderation UI flow, not just keywords in copy? | Swift navigation, moderation views, §22 scan context |
| 2 | **1.4.1** | Health/medical/wellness claims in metadata or UI without appropriate disclaimers or HealthKit compliance? | metadata, Swift HealthKit usage, onboarding copy |
| 3 | **2.1** | Metadata/marketing claims match implemented features (AI, offline, ad-block, sync, etc.)? | metadata, description, Swift feature grep |
| 4 | **2.1** | Login-gated app → App Review demo account / notes **actionable** (credentials, steps, not placeholder)? | `review_information/`, `.reviewPrepNotes`, §31 scan context |
| 5 | **2.2** | Store-facing copy or UI still says beta / test / preview / work-in-progress? | metadata, release_notes, Swift UI strings |
| 6 | **2.3.2** | Primary category plausible for app type (game vs utility vs health, etc.)? | fastlane `primary_category`, metadata tone, code structure |
| 7 | **2.3.4** | App preview assets present → features shown match the shipped app and metadata? | preview video paths, metadata, Swift UI |
| 8 | **2.3.5** | Screenshots show features the app actually ships; no misleading device frames or competitor UI? | screenshot images, metadata, Swift UI |
| 9 | **2.3.6** | Pricing/subscription language in metadata matches paywall (free vs paid, trial terms)? | metadata, paywall Swift, xcstrings |
| 10 | **2.3.9** | Incentivized review copy ("rate 5 stars", "review for reward") in metadata or UI? | metadata, onboarding, paywall, §25 scan context |
| 11 | **2.3.11–2.3.13** | Cross-locale metadata consistent (feature lists, trial terms, support/privacy URLs, pricing claims)? | all `fastlane/metadata/*` locales |
| 12 | **3.1.1** | Digital goods sold or unlocked via external purchase links (web checkout, Stripe in WebView)? | Swift WebView/paywall, metadata, entitlements |
| 13 | **3.1.2** | Subscription/trial/auto-renew/cancel disclosures are **legible sentences**, not keyword stubs? | paywall views, xcstrings, String Catalog |
| 14 | **4.2.1–4.2.2** | App is more than a thin shell: meaningful navigation, native affordances, not a lone WebView brochure? | Swift UI structure, §12/§35 scan context |
| 15 | **4.5.1–4.5.3** | Push or HomeKit entitlement → used as intended (no spam-push promises; HomeKit without home UI)? | entitlements, Info.plist, metadata, Swift |
| 16 | **4.8** | Third-party login present → Sign in with Apple offered, or a documented exempt case (enterprise, existing account, etc.)? | login Swift, SDK imports, §14 scan context |
| 17 | **5.1.1(i)** | Privacy policy text (fetched) matches data collection in code, PrivacyInfo, and App Privacy narrative? | fetch privacy URL, PrivacyInfo, SDK imports |
| 18 | **5.1.1(ii)** | Purpose strings are specific and tied to a visible feature (not empty, generic, or copy-paste)? | Info.plist, permission usage in Swift |
| 19 | **5.1.1(iii)** | Data/permission requests proportionate to stated app purpose (no obvious over-collection)? | permissions, SDKs vs metadata promise |
| 20 | **5.1.1(iv)** | Permission denial handled gracefully — no infinite re-prompt loops or hard blocks without explanation? | location/camera/notification/auth flows in Swift |
| 21 | **5.1.2** | ATT prompt, `NSUserTrackingUsageDescription`, privacy policy tracking section, and ad SDK usage align? | Info.plist, policy fetch, ad SDK imports |
| 22 | **5.1.3** | HealthKit data not used for advertising/marketing; sync paths respect health-data rules? | HealthKit + analytics/ad SDK co-use |
| 23 | **5.1.4** | Kids-audience signals → parental gate before external links/purchases/account areas? | metadata kids wording, parental gate UI |
| 24 | **5.4** | VPN/NetworkExtension → on-screen disclosure text visible in UI strings (not only Info.plist)? | Swift strings, NetworkExtension usage |
| 25 | **5.2.1–5.2.3** | Obvious third-party trademark/brand misuse in metadata, assets, or UI copy? | metadata, asset filenames, Swift strings |
| 26 | **5.3.1–5.3.3** | Contest/sweepstakes/lottery copy → official rules/eligibility/disclosure present in metadata? | description, keywords, in-app contest UI |
| 27 | **5.6.2–5.6.3** | Developer identity consistent: app name, support URL content, bundle/marketing domain match? | fetch support URL, metadata, legal/footer copy |
| 28 | **5.6.1 / 5.6.3** | Rating/review manipulation dark patterns (withhold features until 5 stars, direct write-review links without `requestReview`)? | Swift, metadata, §25 scan context |

---

## Per-check procedure (detail)

### 1 — 1.2.1 UGC moderation UI

1. If no UGC signals (posts, comments, chat, uploads), mark not applicable.
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

### 6 — 2.3.2 Category fit

1. Read primary category if present in fastlane or `.appstore-precheck.json`.
2. Infer app type from code (game loop, utility, reader, social).
3. Flag obvious mismatch (arcade game filed as Productivity).

### 7 — 2.3.4 App preview consistency *(Tier B v1)*

1. Look for app preview assets under `fastlane/metadata/*/preview*` or `*.mov` / `*.mp4` in metadata trees.
2. If no preview assets in-repo, mark not applicable (previews may live only in App Store Connect).
3. If previews exist: compare visible features/captions to metadata and Swift UI; flag previews
   showing features absent from the build.

### 8 — 2.3.5 Screenshots vs reality

1. Open ≥1 screenshot per primary locale.
2. List visible features (tabs, paywall, login, maps, etc.).
3. Flag screenshots showing features absent from the build or metadata.
4. For the full structured screenshot vision review (placeholder/empty-state, text overflow,
   wrong device frame, misleading marketing, metadata mismatch), follow
   `references/screenshot-vision-review.md`.

### 9 — 2.3.6 Pricing language

1. Compare metadata "free", trial, and price claims to paywall/subscription UI strings.
2. Flag "completely free" metadata when IAP/paywall exists without clear disclosure.

### 10 — 2.3.9 Incentivized review *(Tier B v1)*

1. Grep metadata, onboarding, and paywall strings for: `rate us`, `leave a review`, `5 star`,
   `five star`, `review and get`, `gift card`, `reward for review`, `write a review to unlock`.
2. Cross-check scan §25 (custom review prompt) — Phase 4 adds semantic context if §25 passed.
3. Flag quid-pro-quo review incentives or star-rating manipulation copy.

### 11 — 2.3.11–2.3.13 Locale parity (semantic)

1. Beyond scan's file-presence check: compare trial terms, feature bullets, and pricing claims across locales.
2. Flag material omissions (trial mentioned in en-US only, different feature lists).

### 12 — 3.1.1 External digital purchase

1. Search for external checkout URLs, Stripe/PayPal in WebView, "subscribe on our website".
2. Flag digital unlocks that bypass StoreKit without 3.1.1(a) entitlement context.

### 13 — 3.1.2 Disclosure quality

1. Read paywall disclosure strings (Swift + xcstrings).
2. Flag if trial/auto-renew/cancel info is a single keyword, lorem, or unreadably dense.
3. Require human-readable sentences covering trial length, renewal, and cancellation path.

### 14 — 4.2.1–4.2.2 Minimum functionality (semantic)

1. Map primary user journeys (launch → core action).
2. Flag single-screen WebView brochure, template placeholder flows, or no native navigation beyond §12 minimum.

### 15 — 4.5.1–4.5.3 Push / HomeKit abuse *(Tier B v1)*

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
3. Flag direct contradictions ("we do not collect location" + CoreLocation).

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

### 21 — 5.1.2 ATT consistency

1. If ad/attribution SDK or IDFA access: confirm ATT API usage and description text.
2. Cross-check privacy policy tracking section vs implementation.

### 22 — 5.1.3 HealthKit + ads

1. If HealthKit imported: search for analytics/ad SDK sending health-derived signals.
2. Flag health data paths combined with advertising identifiers.

### 23 — 5.1.4 Parental gate

1. If kids metadata or child-audience copy: find parental gate before web/links/IAP/account.
2. Flag child positioning without age gate UI.

### 24 — 5.4 VPN disclosure UI

1. If NetworkExtension/NEVPNManager: search UI strings for data-collection disclosure required at launch/settings.
2. Flag VPN capability with no user-visible disclosure copy.

### 25 — 5.2.1–5.2.3 IP / trademarks

1. Scan metadata and visible strings for other companies' brands used as if owned.
2. Flag likely trademark misuse (not generic descriptive use).

### 26 — 5.3.1–5.3.3 Contests

1. If sweepstakes/contest/giveaway language: check for rules, eligibility, sponsor, no-purchase-necessary.
2. Flag contest marketing without rules in metadata or in-app.

### 27 — 5.6.2–5.6.3 Developer identity

1. Fetch support URL; confirm it resolves and shows developer contact or support path.
2. Compare app name, support domain, and privacy policy domain for consistency.
3. Flag placeholder support pages or identity mismatch.

### 28 — 5.6.1 / 5.6.3 Rating/review manipulation *(Tier B v1)*

1. Grep Swift and metadata for: `itms-apps://` write-review URLs, `apps.apple.com/.../write-review`,
   "rate 5 stars", "only enable after review", custom star-rating UI tied to App Store review.
2. Compare to system `requestReview` / `SKStoreReviewController` usage (scan §25).
3. Flag dark patterns that manipulate ratings or bypass Apple's review prompt API.

---

## Phase 5 presentation

After Phase 4, include in the final report:

1. Trilingual verdict block (from scan counts only).
2. Phase 3 commentary (every scan FAIL/WARN).
3. Phase 4 summary table: 28 checks → count of `REVIEW-FINDING` vs `REVIEW-PASS` (note Tier B items 4, 5, 7, 10, 15, 28 if any fired).
4. Phase 4 detail: every `REVIEW-FINDING` with Pierre explanation; optionally list `REVIEW-PASS` lines compactly.
5. Verbatim Phase 1 scan output + verdict/token action.
