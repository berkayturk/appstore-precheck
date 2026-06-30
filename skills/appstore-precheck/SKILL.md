---
name: appstore-precheck
description: Read-only pre-submission check for an iOS app before App Store review. Scans Swift code, fastlane metadata, screenshots, PrivacyInfo.xcprivacy, and the paywall for 30 rejection vectors, wraps Apple's official `fastlane precheck`, watches for live App Store Review Guideline drift, and runs an adversarial reviewer pass. Emits a GREEN/YELLOW/RED verdict and a `.precheck-pass` token an upload guard can gate on. Use when preparing an iOS App Store submission (before Archive, before "Submit for Review", before TestFlight, or before any `fastlane deliver/pilot/release`), or when the user mentions App Store rejection, app review, or fastlane upload.
license: MIT
metadata:
  author: Berkay Turk
  version: 1.2.0
allowed-tools: Bash Read Grep Glob WebFetch
---

# App Store Precheck

A one-command gate to run before every iOS App Store submission. It minimizes the risk of
rejection by statically scanning the most common rejection vectors, running Apple's own
metadata linter, watching for guideline drift, and simulating an adversarial review pass.

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

When you present the verdict to the user, open with Pierre's verdict (the French App Review
critic, see Phase 3) as a short **trilingual block**: his native **French** line first, then an
**English** rendering, then the **user's conversation language** rendering. Each is an
*idiomatic, in-character* re-expression in that language's own rhythm — his deadpan French-critic
register carried across, never a flat word-for-word translation. Collapse to two lines if the
user already converses in French or English (no duplicate line). Then drop straight into the
plain, surgical breakdown. The voice is a thin wrapper. The data underneath, the FAIL/WARN list,
`file:line` references, and fixes, stays clean and machine-faithful. **Never rewrite or paraphrase
`scan.sh` output**, and keep the Pierre block to these short one-per-language lines.

## Flow (5 phases: 0–4)

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

Emits `FAIL:` / `WARN:` / `PASS:` lines covering 30 rejection vectors: Privacy Manifest parity
(5.1.1(v)), purpose strings (5.1.1), ATT (5.1.2), other-platform mentions (2.3.10), metadata
limits (2.3.1), localized parity (2.3.7), screenshots (2.3.3), trial & auto-renew disclosures
(3.1.2), Restore/Terms/Privacy links (3.1.2), private API (2.5.1), minimum functionality (4.2),
Sign in with Apple parity (4.8), external purchase links (3.1.1(a)), an opt-in Screen Time /
FamilyControls justification (5.1.5), tracking/IDFA SDK without an ATT prompt (5.1.2), the
export-compliance key (`ITSAppUsesNonExemptEncryption`), support/privacy URLs in fastlane
metadata (2.3), analytics SDK vs PrivacyInfo data-types (5.1.1), placeholder/dummy metadata
copy (2.1), third-party payment SDK for digital goods (3.1.1), user-generated content without
moderation (1.2), App Transport Security disabled app-wide (1.6), recurring Apple Pay disclosure
(4.9), custom App Store review prompts (5.6.1), misleading marketing claims (2.3.1), "For Kids"
wording outside the Kids Category (2.3.8), keyboard extensions requiring full access (4.4.1),
HealthKit data with an iCloud sync path (5.1.3), and VPN / NetworkExtension usage (5.4). The IAP
checks (8–10) are skipped automatically when no in-app-purchase signals are present, and the
signal-gated advisory checks (16–30) stay silent unless their triggering signal is found. The
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

### Phase 3: Adversarial review (most important)

Dispatch a subagent that role-plays **Pierre**, a skeptical Apple App Reviewer with the exacting
palate of a French critic. Use this prompt verbatim, filling in the app's specifics:

> You are **Pierre**, a veteran Apple App Reviewer who critiques like a French critic. You have
> seen ten thousand rejections and are impressed by none of them. A new submission just landed on
> your desk. Your job is to **realistically try to reject it**, with no approval bias. Pick **5 random
> guideline items** with a spread across sections (one 2.x, two 3.x weighted toward paywall,
> one 4.x, one 5.x); choose a different combination each run (include a seed line so reruns
> vary). For each item: (Pass A) grep the relevant files for at least 2 concrete pieces of
> evidence: metadata for 2.3.x; the paywall view + String Catalog for 3.1.x; Core/navigation
> for 4.x; Info.plist + PrivacyInfo for 5.1.x. **Scope of evidence:** only Apple-facing
> submission artifacts count toward a reject risk — fastlane metadata, the paywall Swift, the
> String Catalog, Info.plist, and PrivacyInfo.xcprivacy. Internal or local-only files (anything
> under `.planning/`, design notes, build scripts, and `reviewPrepNotes` drafts — which are *not*
> auto-submitted to App Store Connect) and any Google Play / non-Apple sections are **out of
> scope**: cite them at most as a WARN labeled "internal draft — not submitted to Apple", never as
> REJECT-CERTAIN/REJECT-RISK. A REJECT risk requires a contradiction *within* submission-facing
> artifacts (e.g. metadata vs the paywall), not an internal doc disagreeing with metadata. An
> eligibility-gated / conditional offer (e.g. a free trial shown only to eligible users) paired
> with metadata that mentions the offer is **WARN at most**, unless the metadata promises it
> unconditionally to all users. (Pass B) ask "as a reviewer, on what basis would
> I flag this?" (Pass C) write a rejection draft in Apple's real voice (Guideline X.Y.Z –
> Category / We noticed… / Specifically… / Next Steps… / Resources…). Assign each item a risk:
> REJECT-CERTAIN / REJECT-RISK / WARN / PASS. End with a submit recommendation (HOLD / SUBMIT
> WITH WARNINGS / GO) and the single most critical fix. Read-only: never modify files; if you
> can't find evidence, say so rather than inventing it. Keep it under 500 words. Include at
> least one PASS and at least one risk-bearing item, to give a realistic distribution.

### Phase 4: Consolidation + token

The GREEN/YELLOW/RED decision and token action are **deterministic**, derived purely from the
FAIL/WARN counts. [`scripts/verdict.sh`](scripts/verdict.sh) computes them so the verdict is
machine-testable, not just an agent judgement; pipe the scan into it:

```bash
bash skills/appstore-precheck/scripts/verdict.sh < scan-output.txt   # prints VERDICT / COUNTS / TOKEN
```

It exits 0 GREEN / 1 RED / 2 YELLOW, and with `--apply` writes or removes `.precheck-pass`
accordingly (YELLOW holds the token for explicit human confirmation). Phase 0–3 still produce the
narrative; verdict.sh just pins the threshold arithmetic.

1. Gather Phase 0–3 output; tally FAIL + WARN + PASS into the output-contract table.
2. For each FAIL, give a `file:line` reference and a suggested fix.
3. Open the verdict with Pierre's **trilingual block** — French, then English, then the user's
   conversation language — then drop into the plain breakdown. Each line is an idiomatic,
   in-character rendering (not a literal translation), carrying his deadpan French-critic register
   into that language's own rhythm. Collapse to two lines if the user already converses in French
   or English. Vary the wording each run; keep each line short. Decide:
   - **GREEN:** e.g. FR *"Hmf. Je ne trouve rien. Acceptable. Ne me faites pas regretter."* /
     EN *"Hmf. I find nothing. Acceptable. Do not make me regret this."* / + the user-language line,
     then `date +%s > .precheck-pass && echo "token written"` (valid 60 min).
   - **YELLOW:** e.g. FR *"Quelques petites laideurs. Je ne rejette pas, mais j'ai remarqué."* /
     EN *"A few small uglinesses. I would not reject, but I noticed."* / + the user-language line.
     List the WARNs plainly, ask the user "confirm and submit anyway?", write the token only on confirmation.
   - **RED:** e.g. FR *"Non. {n} fautes. Apple en aurait trouvé moins. Suivant."* /
     EN *"No. {n} faults. Apple would have found fewer. Next."* / + the user-language line.
     No token; then the plain FAIL list with `file:line` + fixes, and state plainly that submission is BLOCKED.
   The Pierre block is flavor only. The FAIL/WARN list, `file:line`, and fixes below it stay plain
   and surgical, never paraphrased.
4. Print the final manual checklist (see
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
- The adversarial reviewer is a heuristic simulation, not a guarantee of Apple's decision.
- Most accurate for native Swift / SwiftUI. The metadata, privacy-manifest, screenshots, and
  export-compliance checks apply to any iOS app, but the code-level checks read Swift source, so on
  React Native (JavaScript) or Flutter (Dart) they under-detect rather than false-fire.
- iOS only.
- Phase 0 detects only **structural** drift (added/removed section numbers); see the reference for why.

## Optional: upload guard hook

`hooks/fastlane-guard.sh` blocks `fastlane deliver/pilot/release` unless a fresh `.precheck-pass`
token exists. In Claude Code it auto-wires via `hooks/hooks.json`. In other environments, wire it
as a pre-command check yourself, or treat the token as a manual go/no-go signal.
