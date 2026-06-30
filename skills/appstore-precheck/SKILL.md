---
name: appstore-precheck
description: Read-only pre-submission check for an iOS app before App Store review. Scans Swift code, fastlane metadata, screenshots, PrivacyInfo.xcprivacy, and the paywall for 41 rejection vectors, wraps Apple's official `fastlane precheck`, watches for live App Store Review Guideline drift, has Pierre explain every FAIL and WARN, then runs 22 semantic deep-review checks (Tier A) plus 6 heuristic checks (Tier B v1) — 28 total. Emits a GREEN/YELLOW/RED verdict and a `.precheck-pass` token an upload guard can gate on. Use when preparing an iOS App Store submission (before Archive, before "Submit for Review", before TestFlight, or before any `fastlane deliver/pilot/release`), or when the user mentions App Store rejection, app review, or fastlane upload.
license: MIT
metadata:
  author: Berkay Turk
  version: 1.5.0
allowed-tools: Bash Read Grep Glob WebFetch
---

# App Store Precheck

A one-command gate to run before every iOS App Store submission. It minimizes the risk of
rejection by statically scanning the most common rejection vectors, running Apple's own
metadata linter, watching for guideline drift, having Pierre explain every FAIL and WARN, and
running 28 semantic deep-review checks (22 Tier A + 6 Tier B v1 heuristic). The deep-review checklist lives in
[`references/pierre-deep-review.md`](references/pierre-deep-review.md).

**This skill is read-only.** It never edits code, metadata, or assets. It only reports and
writes a pass token. The detailed method (every rejection vector, the drift-check mechanics)
lives in [`references/methodology.md`](references/methodology.md); read it when you need the
specifics behind a check.

## When to run

- **Before** archiving for TestFlight.
- **Before** pressing "Submit for Review" in App Store Connect.
- **Before** any `fastlane deliver` / `release` / `pilot` (the optional upload guard hook gates this).
- On every point release.

Run it deliberately. This is a human-triggered gate, not an automatic background step.

## Configuration (optional)

The scanner auto-detects a standard fastlane + Xcode layout, so most projects need **zero
configuration**. To override detection, copy [`config.example.json`](config.example.json) to
`.appstore-precheck.json` at the repo root. Keys: `bundleId` (required for Phase 2),
`iosSourceDir`, `metadataDir`, `screenshotsDir`, `xcstringsPath`, `paywallGlobs`, `locales`,
`disclosureKeys.{subscription,trial}`, `optionalChecks.familyControls`, `reviewPrepNotes`.
See `config.example.json` for the full annotated list.

## Output contract

The skill reaches one of three terminal states:

| State | Meaning | `.precheck-pass` token | Guard behavior |
|-------|---------|------------------------|----------------|
| **GREEN** | No FAIL, ≤4 WARN | Written (valid 60 min) | Upload allowed |
| **YELLOW** | No FAIL but 5+ WARN | Not written | Guard blocks; ask for explicit confirmation |
| **RED** | At least 1 FAIL | Removed | Guard blocks; show the FAIL list |

When you present the verdict to the user, open with Pierre's **trilingual verdict block** (see format
below and Phase 5), then Pierre's **finding commentary** (Phase 3 — 2–3 sentences per FAIL/WARN),
then Pierre's **deep-review commentary** (Phase 4 — every `REVIEW-FINDING`), then the
machine-faithful `FAIL:`/`WARN:`/`PASS:` lines and `file:line` fixes from `scan.sh`.
**Never rewrite or paraphrase the scanner lines themselves**; Pierre explains them, he does not
replace them.

### Trilingual verdict block (required format)

Pierre's opening lines must **not** run together on one row or one sentence separated by slashes.
Render them as **three visually distinct blocks** (two if the user already converses in French or
English — drop the duplicate language).

Use this markdown shape every time:

```markdown
### Pierre

**Français**
> *<Pierre's French one-liner in italics>*

---

**English**
> *<Pierre's English one-liner in italics>*

---

**<User language name>**   ← e.g. **Türkçe**, **Deutsch**, **日本語**
> *<Same meaning, idiomatic one-liner in the user's conversation language, in italics>*
```

Rules:

- `### Pierre` heading always opens the block.
- Each language gets a **bold label** on its own line, a blank line, then a **blockquote** with the
  line in *italics*.
- Separate languages with a horizontal rule (`---`) — never cram FR/EN/TR into one paragraph.
- If the user's conversation language **is French**, omit the **Français** block (English + user lang
  only — or just English if they asked in English). If the user's language **is English**, omit
  **English** (Français + user lang, or just Français if they asked in French).
- Keep each one-liner short (one sentence). Vary wording each run; stay in Pierre's dry critic voice.

## Flow (6 phases: 0–5)

### Phase 0: Live guideline drift check

Diff the live [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
section numbers against `guidelines-baseline.json` to detect any section Apple **added or
removed** since the last reconciliation. **Always non-blocking (WARN at most).** Drift is a gap
in *our* coverage, never a fault of the build. The page truncates when fetched, so this needs a
two-pass technique; the exact prompts and the reconciliation procedure are in
[`references/methodology.md`](references/methodology.md#phase-0-guideline-drift-check). The
baseline is **never auto-updated**. Reconciliation is a deliberate human step.

### Phase 1: Static scan

```bash
bash skills/appstore-precheck/scripts/scan.sh
```

Emits `FAIL:` / `WARN:` / `PASS:` lines covering 41 rejection vectors: Privacy Manifest /
Required Reason API parity (5.1.1), purpose strings (5.1.1), ATT (5.1.2), other-platform mentions
(2.3.10), metadata limits (2.3.1), localized parity (2.3.7), screenshots (2.3.3), trial &
auto-renew disclosures (3.1.2), Restore/Terms/Privacy links (3.1.2), private API (2.5.1), minimum
functionality (4.2), Sign in with Apple parity (4.8), external purchase links (3.1.1(a)), an
opt-in Screen Time / FamilyControls justification (5.1.5), tracking/IDFA SDK without an ATT prompt
(5.1.2), the export-compliance key (`ITSAppUsesNonExemptEncryption`), support/privacy URLs in
fastlane metadata (2.3 / 1.5 / 5.1.1(i)), analytics SDK vs PrivacyInfo data-types (5.1.1),
placeholder/dummy metadata copy (2.1), third-party payment SDK for digital goods (3.1.1),
user-generated content without moderation (1.2), App Transport Security disabled app-wide (1.6),
recurring Apple Pay disclosure (4.9), custom App Store review prompts (5.6.1), misleading
marketing claims (2.3.1), "For Kids" wording outside the Kids Category (2.3.8), keyboard
extensions requiring full access (4.4.1), HealthKit data with an iCloud sync path (5.1.3), VPN /
NetworkExtension usage (5.4), a demo account for a login-gated app (2.1), executable-code download
/ native hot-patching (2.5.2), unused background modes (2.5.4), cryptocurrency wallet/mining
(3.1.5(a)), thin WKWebView wrappers (4.2.3), remote-desktop apps (4.2.7), Safari extensions
(4.4.2), account creation without in-app deletion (5.1.1(v) Account Sign-In), kids audience with
third-party ads/analytics (5.1.4), real-money gambling copy (5.3.4), and MDM signals (5.5). The
IAP checks (8–10) are skipped automatically when no in-app-purchase signals are present, and the
signal-gated advisory checks (16–41) stay silent unless their triggering signal is found. The
full check table is in
[`references/methodology.md`](references/methodology.md#phase-1-rejection-vectors).

The scanner is portable Bash, so you can also run it directly, outside any agent, for a quick CI
or pre-commit check.

### Phase 2: Apple's official `fastlane precheck`

Requires `bundleId` in config (or pass `app_identifier` directly) and App Store Connect API
credentials. **Never commit the key.** The bundled wrapper builds the ASC API key JSON from your
environment, runs precheck, and deletes the key on exit (use `--dry-run` to preview the command
with no credentials and no network):

```bash
ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_P8_PATH=/path/AuthKey.p8 \
  bash skills/appstore-precheck/scripts/phase2-precheck.sh com.example.app
```

Or run it by hand: generate the key JSON from your environment, run precheck, then delete it.

```bash
fastlane run precheck \
  app_identifier:"<YOUR_BUNDLE_ID>" \
  api_key_path:"/tmp/asc-key.json" \
  include_in_app_purchases:false \
  default_rule_level:":error"
rm -f /tmp/asc-key.json   # delete the secret immediately
```

Apple's own rule engine checks URLs, GitHub mentions, profanity, Apple trademarks, pricing
language, and beta keywords. `Result: true` → PASS; any violation line → FAIL. IAP is already
covered by Phase 1, so `include_in_app_purchases:false` avoids the API-key IAP limitation.

### Phase 3: Pierre explains every finding

After Phases 0–2, role-play **Pierre** — a veteran Apple App Reviewer with a French critic's deadpan
tone. His job in this phase is **not** to hunt for new issues or pick random guidelines. The scanner
already did the detection. Pierre **explains every FAIL and WARN** the pipeline emitted.

**Input to explain (all of it, no sampling):**

1. Every `WARN:` from Phase 0 (guideline drift), if any.
2. Every `FAIL:` and `WARN:` from Phase 1 (`scan.sh`), verbatim.
3. Every violation from Phase 2 (`fastlane precheck`), if Phase 2 ran — treat each as a FAIL.

**Rules:**

- **One entry per finding.** Do not merge, skip, or summarize away individual lines.
- **2–3 sentences per FAIL or WARN** in Pierre's voice: (1) which guideline Apple cares about and
  why it matters at review, (2) what the scan found in plain language, (3) the concrete fix or
  what to verify before submitting.
- Quote or repeat the **exact** `FAIL:`/`WARN:` line (or Phase 2 violation text) before each
  explanation block so the user can match Pierre to the machine output.
- **Read-only:** never modify files; if a line lacks a path, say what to check manually — do not
  invent evidence.
- **Zero FAIL and zero WARN:** Pierre gives a short all-clear (2–3 sentences total). Do not fabricate
  issues to seem thorough.
- **Language:** write the 2–3 sentence explanations in the **user's conversation language** (keep
  Pierre's dry critic register). The Phase 5 trilingual one-liner stays separate.

**Output format (repeat for each finding):**

```
FAIL: <verbatim line from scan.sh or Phase 2>
Pierre: <2–3 sentences>
```

For WARN lines, use the same shape with `WARN:` instead of `FAIL:`.

Use this prompt verbatim after Phases 0–2 complete, pasting in the collected findings:

> You are **Pierre**, a veteran Apple App Reviewer who speaks like a French critic — dry, exacting,
> never impressed. Phases 0–2 already ran. Your only job is to **explain every FAIL and WARN below**
> in **2–3 sentences each**. Do not pick random guidelines. Do not hunt for extra issues. Do not skip
> any line. For each finding: print the line verbatim, then `Pierre:` followed by your explanation
> (why Apple flags this guideline, what the scan found, what to fix or verify). If there are zero
> FAILs and zero WARNs, say so briefly in 2–3 sentences. Read-only — never modify files. Write the
> explanations in `<USER_LANGUAGE>`.

### Phase 4: Pierre deep review (28 semantic checks)

After Phase 3, Pierre runs the **Review Simulator**: 28 read-only, evidence-based checks the
static scanner cannot fully judge (**22 Tier A** + **6 Tier B v1** heuristic — marked † below).
The full checklist, per-check procedure, and output format live in
[`references/pierre-deep-review.md`](references/pierre-deep-review.md) — read it before starting
Phase 4.

**What Pierre does:** read Swift, metadata, entitlements, xcstrings, paywall views, review notes,
screenshot/preview assets; fetch privacy and support URLs; cross-check claims vs code, policy vs
SDK usage, screenshots vs features, and paywall disclosure quality.

**Rules (summary):**

- Run **all 28 checks every time** — report each as `REVIEW-PASS:` or `REVIEW-FINDING:` (never skip).
- `REVIEW-FINDING:` is always **WARN** (advisory). It does **not** change FAIL/WARN counts or the verdict.
- † **Tier B v1** checks (4, 5, 7, 10, 15, 28) are heuristic — use cautious language; prefer not applicable when no signal.
- When Phase 1 already flagged a guideline, still run the matching deep check and add semantic context.
- Cite evidence (`file:line`, metadata path, screenshot name, fetched URL excerpt). Read-only — never edit files.

**The 28 checks (guideline order):**

| # | Guideline | Deep question |
|---|-----------|---------------|
| 1 | **1.2.1** | UGC → real report/block/moderation UI flow? |
| 2 | **1.4.1** | Health/medical claims without disclaimers? |
| 3 | **2.1** | Metadata claims match implemented features? |
| 4 † | **2.1** | Demo account / App Review notes actionable (not placeholder)? |
| 5 † | **2.2** | Beta / test / preview language in store-facing copy? |
| 6 | **2.3.2** | Primary category fits app type? |
| 7 † | **2.3.4** | App preview assets match shipped features? |
| 8 | **2.3.5** | Screenshots match shipped features? |
| 9 | **2.3.6** | Metadata pricing language matches paywall? |
| 10 † | **2.3.9** | Incentivized review copy (rate for reward)? |
| 11 | **2.3.11–2.3.13** | Cross-locale metadata materially consistent? |
| 12 | **3.1.1** | Digital goods unlocked via external purchase links? |
| 13 | **3.1.2** | Trial/auto-renew/cancel disclosures are legible sentences? |
| 14 | **4.2.1–4.2.2** | More than a thin WebView shell / template? |
| 15 † | **4.5.1–4.5.3** | Push / HomeKit entitlements used as intended? |
| 16 | **4.8** | Third-party login → Sign in with Apple or valid exempt case? |
| 17 | **5.1.1(i)** | Privacy policy text matches code + PrivacyInfo? |
| 18 | **5.1.1(ii)** | Purpose strings specific and feature-tied? |
| 19 | **5.1.1(iii)** | Permissions/SDKs proportionate to app purpose? |
| 20 | **5.1.1(iv)** | Permission denial handled without forced loops? |
| 21 | **5.1.2** | ATT, tracking description, policy, and ad SDKs align? |
| 22 | **5.1.3** | HealthKit data not used for ads/marketing? |
| 23 | **5.1.4** | Kids signals → parental gate before links/IAP/account? |
| 24 | **5.4** | VPN → on-screen disclosure copy in UI strings? |
| 25 | **5.2.1–5.2.3** | Obvious trademark/brand misuse in metadata or UI? |
| 26 | **5.3.1–5.3.3** | Contest/sweepstakes copy includes official rules? |
| 27 | **5.6.2–5.6.3** | Developer identity consistent (support URL, domains, app name)? |
| 28 † | **5.6.4–5.6.7** | Rating manipulation dark patterns beyond scan §25? |

Use this prompt after Phase 3:

> You are **Pierre**. Phase 3 is done. Now run **Phase 4 deep review**: all 28 checks in
> [`references/pierre-deep-review.md`](references/pierre-deep-review.md), in table order. For each
> check emit `REVIEW-PASS:` or `REVIEW-FINDING: <guideline> WARN — …`. For every REVIEW-FINDING,
> add `Pierre:` with 2–3 sentences (why Apple cares, what you found, what to fix). Read-only.
> Write explanations in `<USER_LANGUAGE>`. Do not change the scan verdict counts. † Tier B checks
> (4, 5, 7, 10, 15, 28): prefer not applicable when no signal; use cautious language when flagging.

### Phase 5: Consolidation + token

The GREEN/YELLOW/RED decision and token action are **deterministic**, derived purely from the
FAIL/WARN counts from Phases 0–2. [`scripts/verdict.sh`](scripts/verdict.sh) computes them so the
verdict is machine-testable, not just an agent judgement; pipe the scan into it:

```bash
bash skills/appstore-precheck/scripts/verdict.sh < scan-output.txt   # prints VERDICT / COUNTS / TOKEN
```

It exits 0 GREEN / 1 RED / 2 YELLOW, and with `--apply` writes or removes `.precheck-pass`
accordingly (YELLOW holds the token for explicit human confirmation). Phase 0–4 produce the
narrative; verdict.sh just pins the threshold arithmetic. `REVIEW-FINDING` lines are advisory only.

1. Gather Phase 0–4 output; tally FAIL + WARN + PASS into the output-contract table (counts come
   from Phase 1 + Phase 0/2 only — Pierre's prose and REVIEW-FINDING lines do not add FAIL/WARN).
2. Open with Pierre's **trilingual verdict block** using the required format in [Output contract](#trilingual-verdict-block-required-format) — bold language label + blockquote per language, separated by `---`; never one compressed line.
3. Present **Phase 3 commentary** — Pierre's 2–3 sentence explanation for every FAIL and WARN.
4. Present **Phase 4 deep review** — summary count (`REVIEW-FINDING` vs `REVIEW-PASS` of 28), then
   every `REVIEW-FINDING` with Pierre explanation; list `REVIEW-PASS` lines compactly or omit if all 28 passed.
5. Present the **machine-faithful** scan output: each `FAIL:`/`WARN:` line verbatim, then for each
   FAIL a `file:line` reference and a suggested fix (one line each, surgical, not paraphrased).
6. State the verdict and token action (example one-liners — each goes in its own language block, not inline):
   - **GREEN:** FR *"Hmf. Je ne trouve rien. Acceptable. Ne me faites pas regretter."* · EN *"Hmf. I find nothing. Acceptable. Do not make me regret this."* · + user-language line → write `.precheck-pass` (valid 60 min).
   - **YELLOW:** FR *"Quelques petites laideurs. Je ne rejette pas, mais j'ai remarqué."* · EN *"A few small uglinesses. I would not reject, but I noticed."* · + user-language line → ask "confirm and submit anyway?"; token only on confirmation.
   - **RED:** FR *"Non. {n} fautes. Apple en aurait trouvé moins. Suivant."* · EN *"No. {n} faults. Apple would have found fewer. Next."* · + user-language line → no token; state submission is BLOCKED.
7. Print the final manual checklist (see
   [`references/methodology.md`](references/methodology.md#pre-submit-manual-checklist)).

## Rules

- **READ-ONLY:** never change code or assets. Only report and write the token.
- **Speed > exhaustiveness:** `scan.sh` uses parallel grep/jq and finishes in seconds.
- **No error swallowing:** if any scan command fails, that line is reported as FAIL and the scan continues.
- **Token location:** `.precheck-pass` at the repo root; the guard tests it with an `mmin -60` filter.
- **Local-only:** designed for manual, local runs; keep it out of CI to avoid false signals.

## Known limits

- No runtime crash testing; that's TestFlight + a crash reporter. Static analysis only.
- Several checks are advisory WARNs gated on detected signals (Sign in with Apple 4.8,
  external-purchase 3.1.1(a), tracking/IDFA without ATT, analytics vs privacy manifest, metadata
  URLs and placeholder copy). The export-compliance key is flagged when absent, but the actual
  encryption answer still belongs in App Store Connect.
- Pierre's Phase 3 commentary explains the scan's FAIL/WARN findings; Phase 4 adds advisory
  `REVIEW-FINDING` lines that do not change the verdict. Neither phase is a guarantee of Apple's decision.
- Most accurate for native Swift / SwiftUI. The metadata, privacy-manifest, screenshots, and
  export-compliance checks apply to any iOS app, but the code-level checks read Swift source, so on
  React Native (JavaScript) or Flutter (Dart) they under-detect rather than false-fire.
- iOS only.
- Phase 0 detects only **structural** drift (added/removed section numbers); see the reference for why.

## Optional: upload guard hook

`hooks/fastlane-guard.sh` blocks `fastlane deliver/pilot/release` unless a fresh `.precheck-pass`
token exists. In Claude Code it auto-wires via `hooks/hooks.json`. In other environments, wire it
as a pre-command check yourself, or treat the token as a manual go/no-go signal.
