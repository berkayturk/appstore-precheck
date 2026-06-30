# Phase 4: Pierre deep review (22 semantic checks)

After Phase 3 (explaining every scan FAIL/WARN), Pierre runs a **read-only, project-wide
semantic review** of 22 guideline areas the static scanner cannot fully judge. This is the
**Review Simulator** layer: Pierre reads Swift, metadata, screenshots, xcstrings, paywall views,
and fetches live privacy/support URLs — then cross-checks claims against evidence.

**This phase does not change the GREEN/YELLOW/RED verdict.** Verdict counts come only from
Phases 0–2 (`FAIL:` / `WARN:` lines). Phase 4 emits `REVIEW-PASS:` or `REVIEW-FINDING:` lines
that Pierre explains in Phase 5 presentation.

## Rules

- **Read-only:** never modify project files.
- **Evidence-based:** cite `file:line`, metadata path, screenshot filename, or fetched URL text.
  If you cannot read something (private URL, missing file), say so — do not invent findings.
- **All 22 checks, every run:** report each item as `REVIEW-PASS:` or `REVIEW-FINDING:` — no skipping.
- **REVIEW-FINDING severity:** always `WARN` (advisory). Never emit `REVIEW-FINDING: … FAIL`.
  A deep-review issue informs the human; it does not block the token by itself.
- **Deepen scan hits:** when Phase 1 already flagged a guideline, Phase 4 still runs the matching
  deep check and adds semantic context (do not repeat the machine line verbatim — add what the
  scanner could not see).
- **WebFetch:** use `WebFetch` (or equivalent) on `privacy_url.txt` and `support_url.txt` when
  present. If fetch fails, `REVIEW-FINDING: … WARN — could not fetch privacy policy; verify manually`.
- **Screenshots:** read at least one PNG/JPEG per primary locale; compare visible UI/features to
  metadata claims.
- **Language:** write Pierre's 2–3 sentence explanations in the user's conversation language.

## Output format

For each of the 22 checks (in table order):

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

## The 22 checks (guideline order)

| # | Guideline | Deep question | Primary sources |
|---|-----------|---------------|-----------------|
| 1 | **1.2.1** | UGC present → is there a real report/block/moderation UI flow, not just keywords in copy? | Swift navigation, moderation views, §22 scan context |
| 2 | **1.4.1** | Health/medical/wellness claims in metadata or UI without appropriate disclaimers or HealthKit compliance? | metadata, Swift HealthKit usage, onboarding copy |
| 3 | **2.1** | Metadata/marketing claims match implemented features (AI, offline, ad-block, sync, etc.)? | metadata, description, Swift feature grep |
| 4 | **2.3.2** | Primary category plausible for app type (game vs utility vs health, etc.)? | fastlane `primary_category`, metadata tone, code structure |
| 5 | **2.3.5** | Screenshots show features the app actually ships; no misleading device frames or competitor UI? | screenshot images, metadata, Swift UI |
| 6 | **2.3.6** | Pricing/subscription language in metadata matches paywall (free vs paid, trial terms)? | metadata, paywall Swift, xcstrings |
| 7 | **2.3.11–2.3.13** | Cross-locale metadata consistent (feature lists, trial terms, support/privacy URLs, pricing claims)? | all `fastlane/metadata/*` locales |
| 8 | **3.1.1** | Digital goods sold or unlocked via external purchase links (web checkout, Stripe in WebView)? | Swift WebView/paywall, metadata, entitlements |
| 9 | **3.1.2** | Subscription/trial/auto-renew/cancel disclosures are **legible sentences**, not keyword stubs? | paywall views, xcstrings, String Catalog |
| 10 | **4.2.1–4.2.2** | App is more than a thin shell: meaningful navigation, native affordances, not a lone WebView brochure? | Swift UI structure, §12/§35 scan context |
| 11 | **4.8** | Third-party login present → Sign in with Apple offered, or a documented exempt case (enterprise, existing account, etc.)? | login Swift, SDK imports, §14 scan context |
| 12 | **5.1.1(i)** | Privacy policy text (fetched) matches data collection in code, PrivacyInfo, and App Privacy narrative? | fetch privacy URL, PrivacyInfo, SDK imports |
| 13 | **5.1.1(ii)** | Purpose strings are specific and tied to a visible feature (not empty, generic, or copy-paste)? | Info.plist, permission usage in Swift |
| 14 | **5.1.1(iii)** | Data/permission requests proportionate to stated app purpose (no obvious over-collection)? | permissions, SDKs vs metadata promise |
| 15 | **5.1.1(iv)** | Permission denial handled gracefully — no infinite re-prompt loops or hard blocks without explanation? | location/camera/notification/auth flows in Swift |
| 16 | **5.1.2** | ATT prompt, `NSUserTrackingUsageDescription`, privacy policy tracking section, and ad SDK usage align? | Info.plist, policy fetch, ad SDK imports |
| 17 | **5.1.3** | HealthKit data not used for advertising/marketing; sync paths respect health-data rules? | HealthKit + analytics/ad SDK co-use |
| 18 | **5.1.4** | Kids-audience signals → parental gate before external links/purchases/account areas? | metadata kids wording, parental gate UI |
| 19 | **5.4** | VPN/NetworkExtension → on-screen disclosure text visible in UI strings (not only Info.plist)? | Swift strings, NetworkExtension usage |
| 20 | **5.2.1–5.2.3** | Obvious third-party trademark/brand misuse in metadata, assets, or UI copy? | metadata, asset filenames, Swift strings |
| 21 | **5.3.1–5.3.3** | Contest/sweepstakes/lottery copy → official rules/eligibility/disclosure present in metadata? | description, keywords, in-app contest UI |
| 22 | **5.6.2–5.6.3** | Developer identity consistent: app name, support URL content, bundle/marketing domain match? | fetch support URL, metadata, legal/footer copy |

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

### 4 — 2.3.2 Category fit

1. Read primary category if present in fastlane or `.appstore-precheck.json`.
2. Infer app type from code (game loop, utility, reader, social).
3. Flag obvious mismatch (arcade game filed as Productivity).

### 5 — 2.3.5 Screenshots vs reality

1. Open ≥1 screenshot per primary locale.
2. List visible features (tabs, paywall, login, maps, etc.).
3. Flag screenshots showing features absent from the build or metadata.

### 6 — 2.3.6 Pricing language

1. Compare metadata "free", trial, and price claims to paywall/subscription UI strings.
2. Flag "completely free" metadata when IAP/paywall exists without clear disclosure.

### 7 — 2.3.11–2.3.13 Locale parity (semantic)

1. Beyond scan's file-presence check: compare trial terms, feature bullets, and pricing claims across locales.
2. Flag material omissions (trial mentioned in en-US only, different feature lists).

### 8 — 3.1.1 External digital purchase

1. Search for external checkout URLs, Stripe/PayPal in WebView, "subscribe on our website".
2. Flag digital unlocks that bypass StoreKit without 3.1.1(a) entitlement context.

### 9 — 3.1.2 Disclosure quality

1. Read paywall disclosure strings (Swift + xcstrings).
2. Flag if trial/auto-renew/cancel info is a single keyword, lorem, or unreadably dense.
3. Require human-readable sentences covering trial length, renewal, and cancellation path.

### 10 — 4.2.1–4.2.2 Minimum functionality (semantic)

1. Map primary user journeys (launch → core action).
2. Flag single-screen WebView brochure, template placeholder flows, or no native navigation beyond §12 minimum.

### 11 — 4.8 Sign in with Apple (context)

1. If Google/Facebook/etc. login exists, confirm `ASAuthorizationAppleID` / Sign in with Apple button.
2. If absent, assess exempt patterns (enterprise-only, password-only existing users) — flag uncertain cases for human review.

### 12 — 5.1.1(i) Privacy policy accuracy

1. Fetch privacy URL from primary locale metadata.
2. Compare policy statements to: PrivacyInfo collected types, tracking domains, location/camera/health SDK usage.
3. Flag direct contradictions ("we do not collect location" + CoreLocation).

### 13 — 5.1.1(ii) Purpose string quality

1. List every `NS*UsageDescription` in Info.plist.
2. Flag empty, placeholder, or generic strings; flag mismatch with the feature that triggers the prompt.

### 14 — 5.1.1(iii) Data minimization

1. List sensitive permissions and SDKs.
2. Compare to app category and metadata promise.
3. Flag obvious overreach (contacts + photos + location for a calculator).

### 15 — 5.1.1(iv) Permission denial UX

1. Trace location/camera/photo/notification permission flows.
2. Flag forced loops, dead-ends, or dark patterns after denial.

### 16 — 5.1.2 ATT consistency

1. If ad/attribution SDK or IDFA access: confirm ATT API usage and description text.
2. Cross-check privacy policy tracking section vs implementation.

### 17 — 5.1.3 HealthKit + ads

1. If HealthKit imported: search for analytics/ad SDK sending health-derived signals.
2. Flag health data paths combined with advertising identifiers.

### 18 — 5.1.4 Parental gate

1. If kids metadata or child-audience copy: find parental gate before web/links/IAP/account.
2. Flag child positioning without age gate UI.

### 19 — 5.4 VPN disclosure UI

1. If NetworkExtension/NEVPNManager: search UI strings for data-collection disclosure required at launch/settings.
2. Flag VPN capability with no user-visible disclosure copy.

### 20 — 5.2.1–5.2.3 IP / trademarks

1. Scan metadata and visible strings for other companies' brands used as if owned.
2. Flag likely trademark misuse (not generic descriptive use).

### 21 — 5.3.1–5.3.3 Contests

1. If sweepstakes/contest/giveaway language: check for rules, eligibility, sponsor, no-purchase-necessary.
2. Flag contest marketing without rules in metadata or in-app.

### 22 — 5.6.2–5.6.3 Developer identity

1. Fetch support URL; confirm it resolves and shows developer contact or support path.
2. Compare app name, support domain, and privacy policy domain for consistency.
3. Flag placeholder support pages or identity mismatch.

---

## Phase 5 presentation

After Phase 4, include in the final report:

1. Trilingual verdict block (from scan counts only).
2. Phase 3 commentary (every scan FAIL/WARN).
3. Phase 4 summary table: 22 checks → count of `REVIEW-FINDING` vs `REVIEW-PASS`.
4. Phase 4 detail: every `REVIEW-FINDING` with Pierre explanation; optionally list `REVIEW-PASS` lines compactly.
5. Verbatim Phase 1 scan output + verdict/token action.
