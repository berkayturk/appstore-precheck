---
name: appstore-precheck
description: Read-only pre-submission check for an iOS app before App Store review. Scans Swift code, fastlane metadata, screenshots, PrivacyInfo.xcprivacy, and the paywall for 41 rejection vectors, wraps Apple's official `fastlane precheck`, watches for live App Store Review Guideline drift, and has Pierre explain every FAIL and WARN in plain language. Emits a GREEN/YELLOW/RED verdict and a `.precheck-pass` token an upload guard can gate on. Use when preparing an iOS App Store submission (before Archive, before "Submit for Review", before TestFlight, or before any `fastlane deliver/pilot/release`), or when the user mentions App Store rejection, app review, or fastlane upload.
license: MIT
metadata:
  author: Berkay Turk
  version: 1.3.1
allowed-tools: Bash Read Grep Glob WebFetch
---

# App Store Precheck

A one-command gate to run before every iOS App Store submission. It minimizes the risk of
rejection by statically scanning the most common rejection vectors, running Apple's own
metadata linter, watching for guideline drift, and having Pierre explain every FAIL and WARN.

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

When you present the verdict to the user, open with Pierre's **trilingual one-liner** (see Phase 4),
then Pierre's **finding commentary** (Phase 3 — 2–3 sentences per FAIL/WARN), then the machine-faithful
`FAIL:`/`WARN:`/`PASS:` lines and `file:line` fixes from `scan.sh`. **Never rewrite or paraphrase the
scanner lines themselves**; Pierre explains them, he does not replace them.

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
  Pierre's dry critic register). The Phase 4 trilingual one-liner stays separate.

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

1. Gather Phase 0–3 output; tally FAIL + WARN + PASS into the output-contract table (counts come
   from Phase 1 + Phase 0/2 findings only — Pierre's prose does not add new FAIL/WARN lines).
2. Open with Pierre's **trilingual one-liner** — French, then English, then the user's conversation
   language (collapse to two lines if the user already speaks French or English). Keep each line short.
3. Present **Phase 3 commentary** — Pierre's 2–3 sentence explanation for every FAIL and WARN.
4. Present the **machine-faithful** scan output: each `FAIL:`/`WARN:` line verbatim, then for each
   FAIL a `file:line` reference and a suggested fix (one line each, surgical, not paraphrased).
5. State the verdict and token action:
   - **GREEN:** e.g. FR *"Hmf. Je ne trouve rien. Acceptable. Ne me faites pas regretter."* /
     EN *"Hmf. I find nothing. Acceptable. Do not make me regret this."* / + the user-language line,
     then `date +%s > .precheck-pass && echo "token written"` (valid 60 min).
   - **YELLOW:** e.g. FR *"Quelques petites laideurs. Je ne rejette pas, mais j'ai remarqué."* /
     EN *"A few small uglinesses. I would not reject, but I noticed."* / + the user-language line.
     List the WARNs plainly, ask the user "confirm and submit anyway?", write the token only on confirmation.
   - **RED:** e.g. FR *"Non. {n} fautes. Apple en aurait trouvé moins. Suivant."* /
     EN *"No. {n} faults. Apple would have found fewer. Next."* / + the user-language line.
     No token; state plainly that submission is BLOCKED.
6. Print the final manual checklist (see
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
- Pierre's commentary explains the scan's FAIL/WARN findings; it does not replace them and
  does not invent new ones. It is not a guarantee of Apple's decision.
- Most accurate for native Swift / SwiftUI. The metadata, privacy-manifest, screenshots, and
  export-compliance checks apply to any iOS app, but the code-level checks read Swift source, so on
  React Native (JavaScript) or Flutter (Dart) they under-detect rather than false-fire.
- iOS only.
- Phase 0 detects only **structural** drift (added/removed section numbers); see the reference for why.

## Optional: upload guard hook

`hooks/fastlane-guard.sh` blocks `fastlane deliver/pilot/release` unless a fresh `.precheck-pass`
token exists. In Claude Code it auto-wires via `hooks/hooks.json`. In other environments, wire it
as a pre-command check yourself, or treat the token as a manual go/no-go signal.
