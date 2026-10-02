---
name: appstore-precheck
description: Read-only pre-submission check for an iOS app before App Store review. Scans Swift and Objective-C code, fastlane metadata, screenshots, PrivacyInfo.xcprivacy, and the paywall for 71 rejection vectors, wraps Apple's official `fastlane precheck`, watches for live App Store Review Guideline drift, has Pierre explain every FAIL and WARN, then runs 56 semantic deep-review checks across Tier A, heuristic Tier B and host vision Tier C. Emits a GREEN/YELLOW/RED verdict and a `.precheck-pass` token an upload guard can gate on. Use when preparing an iOS App Store submission (before Archive, before "Submit for Review", before TestFlight, or before any `fastlane deliver/pilot/release`), or when the user mentions App Store rejection, app review, or fastlane upload.
license: MIT
metadata:
  author: Berkay Turk
  version: 1.20.2
allowed-tools: Bash Read Grep Glob WebFetch mcp__maestro__list_devices mcp__maestro__run mcp__maestro__inspect_screen mcp__maestro__take_screenshot mcp__maestro__cheat_sheet
---

# App Store Precheck

Optional CLI tiers and build/credential boundaries: [optional-review.md](references/optional-review.md).

Coverage inventory: 93/102 leaf sections (91%); 93 touched, 2 positive-only; 71 static vectors, 56 deep-review checks, 20 dynamic checks, 5 vision checks, 9 human-only sections.

This percentage counts sections touched, not automatic verification of every requirement.

A one-command gate to run before every iOS App Store submission. It minimizes the risk of
rejection by statically scanning the most common rejection vectors, running Apple's own
metadata linter, watching for guideline drift, having Pierre explain every FAIL and WARN, and
running 56 semantic deep-review checks (Tier A, heuristic Tier B and host vision Tier C). The deep-review checklist lives in
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

`SKIP:` lines sit outside this table on purpose: they record checks that could not run, are counted
separately (`skip=` / `summary.not_audited`), and never move the verdict. They must still be
reported — see Phase 5 step 6.

When you present the verdict to the user, open with Pierre's **trilingual verdict block** (see format
below and Phase 5), then Pierre's **finding commentary** (Phase 3 — 2–3 sentences per FAIL/WARN),
then Pierre's **deep-review commentary** (Phase 4 — every `REVIEW-FINDING`), then the
machine-faithful `FAIL:`/`WARN:`/`PASS:`/`SKIP:` lines and `file:line` fixes from `scan.sh`, and
finally the mandatory **Not audited** section (Phase 5 step 6).
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

## Flow (Phases 0–5; plus an optional opt-in Phase 6)

### Phase 0: Live guideline drift check

Diff the live [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
section numbers against `guidelines-baseline.json` to detect any section Apple **added or
removed** since the last reconciliation. **Always non-blocking (WARN at most).** Drift is a gap
in *our* coverage, never a fault of the build. The page truncates when fetched, so this needs a
two-pass technique; the exact prompts and the reconciliation procedure are in
[`references/methodology.md`](references/methodology.md#phase-0-guideline-drift-check). The
baseline is **never auto-updated**. Reconciliation is a deliberate human step.

**Also scan Apple's announcements.** Section numbers and section text are not the only way a
rejection surface moves: Apple announces policy changes on
[developer.apple.com/news](https://developer.apple.com/news/) — deadlines, new required
declarations, entitlement changes — often before the guideline text catches up. Fetch that page and
report any review-relevant item **newer than the baseline's `reconciled_on` date**
(`guidelines-baseline.json`). Pay particular attention to payments, privacy, age ratings, and AI:
those moved repeatedly through 2024–2026.

- Nothing newer, or nothing review-relevant → `PASS: guideline-news none since <reconciled_on>`
- Something relevant → `WARN: guideline-news — <headline> (<date>). Assess whether it applies to
  this app; the scan does not cover it yet.` Fetch the announcement and judge applicability like any
  other check. Headlines that plainly do not apply get one line, nothing more.
- Fetch failed → `WARN: guideline-news check degraded — verify manually.`

Like the drift check this is a gap in **our** coverage, never a fault of the build: always
non-blocking, WARN at most.

The deterministic, full-page drift detector is `scripts/guideline-drift.sh` (maintainer/CI;
curl-based, so it also covers the 5.5–5.6.x tail that `WebFetch` truncates). It reports
section-number drift AND text (semantic) drift of covered sections, naming the affected
check(s). It is non-blocking and never runs in the offline user scan; the fingerprint baseline
(`guidelines-fingerprints.json`) is human-reconciled via `guideline-drift.sh --reconcile`.

### Phase 1: Static scan

Run the bundled scanner from the app repo root. `scripts/` here is relative to THIS skill's own
directory (wherever the skill is installed — a plugin dir, `.claude/skills/`, `.agents/skills/`,
`.grok/skills/`, or a clone of the source repo):

```bash
bash <skill-dir>/scripts/scan.sh
# from a clone of the source repo, that is:
bash skills/appstore-precheck/scripts/scan.sh
```

Emits `FAIL:` / `WARN:` / `PASS:` / `SKIP:` lines covering 71 rejection vectors: Privacy Manifest /
Required Reason API parity (5.1.1), purpose strings (5.1.1), ATT (5.1.2), other-platform mentions
(2.3.10), metadata limits (2.3.7), localized parity (2.3), screenshots (2.3.3), trial &
auto-renew disclosures (3.1.2), Restore/Terms/Privacy links (3.1.2), private API (2.5.1), minimum
functionality (4.2), Sign in with Apple parity (4.8), external purchase links (3.1.1(a)), an
opt-in Screen Time / FamilyControls review preparation (no numbered guideline), tracking/IDFA SDK without an ATT prompt
(5.1.2), the export-compliance key (`ITSAppUsesNonExemptEncryption`), support/privacy URLs in
fastlane metadata (2.3 / 1.5 / 5.1.1(i)), analytics SDK vs PrivacyInfo data-types (5.1.1),
placeholder/dummy metadata copy (2.1), third-party payment SDK for digital goods (3.1.1),
user-generated content without moderation (1.2), App Transport Security disabled app-wide (1.6),
recurring Apple Pay disclosure (4.9), custom App Store review prompts (5.6.1), misleading
marketing claims (2.3.1), "For Kids" wording outside the Kids Category (2.3.8), keyboard
extensions requiring full access (4.4.1), HealthKit data with an iCloud sync path (5.1.3), VPN /
NetworkExtension usage (5.4), a demo account for a login-gated app (2.1), executable-code download
/ native hot-patching (2.5.2), unused background modes (2.5.4), cryptocurrency wallet/mining
(3.1.5), thin WKWebView wrappers (4.2), remote-desktop apps (4.2.7), Safari extensions
(4.4.2), account creation without in-app deletion (5.1.1(v) Account Sign-In), kids audience with
third-party ads/analytics (5.1.4), real-money gambling copy (5.3.4), MDM signals (5.5), and
screenshot format/dimension mismatches (2.3.3), permission-priming CTA copy that steers users
toward granting access (5.1.1(iv)), trial-emphasized paywall CTAs and free-trial toggles (3.1.2),
pricing/promo language in the app name or subtitle (2.3.1), generic boilerplate purpose
strings (5.1.1(ii)), a third-party AI endpoint without a provider-naming consent string (5.1.1),
urgency/scarcity dark patterns on the paywall (3.1.2), sentiment-gated rating prompts (5.6.1),
forced login without a guest path (5.1.1(v)), a marketing-push SDK without an opt-out signal
(4.5.4), and a pre-26 Xcode `LastUpgradeCheck` against the April 2026 iOS 26 SDK upload minimum
(2.1), and exposure to a category Apple names as saturated in 4.3(b) (4.3). The IAP checks (8–10 and 53) are skipped automatically
when no in-app-purchase signals are present, and the signal-gated advisory checks (16–52) stay
silent unless their triggering signal is found. The
full check table is in
[`references/methodology.md`](references/methodology.md#phase-1-rejection-vectors).

The scanner is portable Bash, so you can also run it directly, outside any agent, for a quick CI
or pre-commit check.

A fourth line class, `SKIP:`, marks a check that **could not run** — a missing artifact, not a
clean result. It is counted separately (`skip=` in `verdict.sh`, `summary.not_audited` in JSON) and
**never changes the verdict**: a gap in coverage is not a defect in the build. It must never be
presented as a pass.

**`SKIP: framework — …`** (`framework-not-audited`) appears when the repo is React Native, Flutter
or Kotlin Multiplatform (`scripts/framework-detect.sh`, file presence only): the code-level checks
grep Swift/ObjC, so on those toolkits they under-detect rather than false-fire, and the line names
how many checks (derived from the evidence catalogue) and which. The metadata, manifest, resource
and build-setting checks still apply in full. Tell the user; the Phase 6 tier observes the built
app regardless of toolkit.

**When the scan emits `SKIP: metadata`, ask the user for the listing.** The App Store Connect
listing is a real rejection surface — roughly a fifth of the checks read it — and a repo without a
`fastlane/metadata` directory silently skips all of them. Ask for:

> app name, subtitle, description, keywords, promotional text, age rating, and the App Review
> Information fields (review notes and the demo account)

Then **re-run the scanner over what they paste — do not judge it by eye.** The verdict is
deterministic and comes only from scanner lines (Phase 5), so a finding Pierre "notices" in pasted
text cannot count; a finding the scanner emits can. Write the pasted fields into a temporary
fastlane-shaped tree outside the repo and point the scanner at it:

```bash
T="$(mktemp -d)"; mkdir -p "$T/fastlane/metadata/en-US"     # one dir per locale they pasted
# write name.txt, subtitle.txt, description.txt, keywords.txt, promotional_text.txt from the paste
printf '{"metadataDir":"%s"}' "$T/fastlane/metadata" > "$T/precheck.json"
APPSTORE_PRECHECK_CONFIG="$T/precheck.json" bash <skill-dir>/scripts/scan.sh
```

The scanner accepts an absolute `metadataDir`, so the repo is untouched (read-only holds) and the
`SKIP: metadata` line disappears because the listing checks actually ran. The resulting `FAIL:` /
`WARN:` lines are ordinary scanner output: they **count toward the verdict**, and Pierre explains
them like any other, saying they came from the pasted listing rather than the repo. Use the second
run's output as the Phase 1 result.

Age rating, review notes and the demo account have no scanner rule; judge those in Phase 4 (deep
review check 4) as advisory `REVIEW-FINDING` lines. If the user declines, or there is no user to ask
(a CI or non-interactive run), leave the listing as `SKIP` and list it under "Not audited" in
Phase 5. **Never invent metadata to audit.**

The same applies to `SKIP: 2.3.3 Screenshots` — ask what the App Store Connect screenshot set
contains, or leave it unaudited.

Every `FAIL:` / `WARN:` is followed by an indented **evidence line**:

```
FAIL: 5.1.1 camera capture API used but Info.plist is missing 'NSCameraUsageDescription' [App/CameraView.swift:42]
      evidence: source · validator-blocking · needs build verification
```

It answers what severity cannot: *which artifact this was read from*, and *who enforces it*.
`source` findings are concluded from a code grep, so dead code, `#if DEBUG`, and files excluded
from the shipping target can make them wrong; `metadata` and `manifest` findings are read from
files that ship as authored. `needs build verification` appears when a `validator-blocking` claim
rests on `source` or `build-setting` evidence — the upload validator runs against the built
product, which no repository read can see. Set `APPSTORE_PRECHECK_NO_EVIDENCE=1` to suppress the
line if you parse the text output strictly. Full rationale and the per-rule table:
[`references/methodology.md`](references/methodology.md#evidence-strength-and-confidence).

`scan.sh --format json` emits a structured findings envelope (`id`, `rule_id`, `severity`,
`guideline`, `guideline_url`, `message`, optional `file`/`line`, plus `evidence`, `confidence` and
the derived `needs_build_verification` per finding; `resolved_by`, `runtime_target` and
`build_config` are `null` until the Phase 6 tier's `dynamic.sh` reconciles a run; and a verdict
summary with a `by_confidence` roll-up) instead of the default text lines, for tooling and
measurement to consume. The `runtime` evidence class and the `RESOLVED` severity appear only in
`dynamic.sh` output; `RESOLVED` is counted by nothing. `--format sarif` carries
the same labels in each result's `properties` bag. It's read-only and additive; the default text
output gains only the evidence line above.

### Phase 2: Apple's official `fastlane precheck`

Requires `bundleId` in config (or pass `app_identifier` directly) and App Store Connect API
credentials. **This phase is optional: if no ASC credentials are available, skip it, note the
skip in the report, and continue to Phase 3 — do not stall waiting for credentials.**
**Never commit the key.** The bundled wrapper builds the ASC API key JSON from your
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

Follow [`references/finding-commentary.md`](references/finding-commentary.md) for the
complete procedure and prompt: every scanner finding verbatim, evidence strength,
pinned/live citations, and a short explanation in the user's language. Never invent
citations or claim a source grep establishes release behavior.

### Phase 4: Pierre deep review (56 semantic checks)

After Phase 3, Pierre runs the **Review Simulator**: 56 read-only, evidence-based checks the
static scanner cannot fully judge (Tier A cross-reads, Tier B heuristics and Tier C host vision).
The full checklist, per-check procedure, and output format live in
[`references/pierre-deep-review.md`](references/pierre-deep-review.md) — read it before starting
Phase 4. When screenshots are present, also run the structured screenshot vision review in
[`references/screenshot-vision-review.md`](references/screenshot-vision-review.md) (non-blocking;
host vision model; never changes the verdict).

**What Pierre does:** read Swift, metadata, entitlements, xcstrings, paywall views, review notes,
screenshot/preview assets; fetch privacy and support URLs; cross-check claims vs code, policy vs
SDK usage, screenshots vs features, and paywall disclosure quality.

**Rules (summary):**

- Run **all 56 checks every time** — report an outcome for each using the reference status definitions; missing evidence never means PASS.
- `REVIEW-FINDING:` is always **WARN** (advisory). It does **not** change FAIL/WARN counts or the verdict.
- **Tier B** is heuristic; **Tier C** needs host vision. New v4 checks report FINDING, SKIP or no signal, never PASS.
- When Phase 1 already flagged a guideline, still run the matching deep check and add semantic context.
- Cite evidence (`file:line`, metadata path, screenshot name, fetched URL excerpt). Read-only — never edit files.

The canonical 56-check table, including check 31 (4.0 design quality), is in
[`references/pierre-deep-review.md`](references/pierre-deep-review.md). Its versioned
mapping is recorded in `references/review-catalog.json`.

Use this prompt after Phase 3:

> You are **Pierre**. Phase 3 is done. Now run **Phase 4 deep review**: all 56 checks in
> [`references/pierre-deep-review.md`](references/pierre-deep-review.md), in table order. For each
> check use the reference outcome format, including NEEDS-REVIEW, UNSUPPORTED, NOT-RUN or
> evidence-backed NOT-APPLICABLE where appropriate. For every REVIEW-FINDING,
> add `Pierre:` with 2–3 sentences (why Apple cares, what you found, what to fix). Read-only.
> Write explanations in `<USER_LANGUAGE>`. Do not change the scan verdict counts. † Tier B checks
> require evidence of non-applicability; Tier C requires vision. Missing inputs mean REVIEW-SKIP.

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
4. Present **Phase 4 deep review** — summary counts for findings, no signal and missing evidence, then
   every `REVIEW-FINDING` with Pierre explanation; list historical `REVIEW-PASS` lines compactly. New v4 checks never produce PASS.
   The 5 screenshot-vision checks (S1–S5) emit the same `REVIEW-*` prefixes but count as a
   **separate "+5 vision checks" sub-block** in the summary, never inside the "of 56" denominator.
5. Present the **machine-faithful** scan output: each `FAIL:`/`WARN:` line verbatim, with its
   `evidence:` line, then for each FAIL a `file:line` reference and a suggested fix (one line each,
   surgical, not paraphrased).
6. Print `Guideline coverage this run: X/102 sections touched, Y SKIP, Z human-only` using
   `coverage_sections` from scan JSON (Y counts SKIP records, including `gaps`). List every
   `human_only_sections` entry with its reason; optional tiers stay unexecuted unless observed.
   Print a **"Not audited"** section. This is **mandatory on every run**, including a GREEN one —
   a verdict is only meaningful next to the list of what it did not cover. Two parts:

   **(a) Checks that did not run this time** — every `SKIP:` line and coverage `gaps` record, with what would close
   the gap (paste the App Store Connect listing, set `.screenshotsDir`, …). A SKIP acknowledged in
   `.precheck-ignore` is not printed by the scanner but is still in `summary.not_audited` with
   `suppressed: true`; list it here as *acknowledged* — signing for a gap does not close it. If
   there are none, say "every check ran". This list always includes the runtime gap: when Phase 6
   was not run, one line `SKIP: runtime — the Phase 6 dynamic tier did not run …` under the stable
   id **`runtime-not-audited`** (produce it with `bash scripts/dynamic.sh --not-run --findings
   <scan json>`, which derives the count of unobserved dynamic checks); when it was run, every
   `DYNAMIC-SKIP` line instead.

   **(b) What this tool cannot see at all**, regardless of input — a fixed list, never omitted and
   never implied to have been verified:
   - runtime crashes, hangs, and performance
   - whether links (support, privacy, marketing, EULA) actually resolve
   - whether Restore Purchases, sign-in, and the purchase flow really work end to end
   - OAuth / third-party login round trips
   - server-driven content, remote config, and anything that changes after review
   - the built archive itself: what actually shipped, and which SDK it was built with

   Then add the **"what this run could not establish"** note whenever any finding carries
   `needs build verification` (`summary.needs_build_verification` in `--format json` counts them):
   name the count and say those claims rest on source or build settings, not on the shipping
   archive. None of this changes the verdict — it tells the user where the verdict is silent.

   When the verdict is GREEN and anything is unaudited, say so in the same breath: a GREEN that
   never saw the store listing is a GREEN with a hole in it, and Pierre says which hole.
7. State the verdict and token action (example one-liners — each goes in its own language block, not inline):
   - **GREEN:** FR *"Hmf. Je ne trouve rien. Acceptable. Ne me faites pas regretter."* · EN *"Hmf. I find nothing. Acceptable. Do not make me regret this."* · + user-language line → write `.precheck-pass` (valid 60 min).
   - **YELLOW:** FR *"Quelques petites laideurs. Je ne rejette pas, mais j'ai remarqué."* · EN *"A few small uglinesses. I would not reject, but I noticed."* · + user-language line → ask "confirm and submit anyway?"; token only on confirmation.
   - **RED:** FR *"Non. {n} fautes. Apple en aurait trouvé moins. Suivant."* · EN *"No. {n} faults. Apple would have found fewer. Next."* · + user-language line → no token; state submission is BLOCKED.
8. Print the final manual checklist (see
   [`references/methodology.md`](references/methodology.md#pre-submit-manual-checklist)).

### Phase 6: local dynamic simulator tier (optional, opt-in — off by default)

**This phase does not run by default.** Run it ONLY when the user explicitly asks for a dynamic /
simulator check AND supplies a built app (a simulator `.app` path, or a booted simulator UDID +
bundle id). It uses `xcrun simctl` + Maestro MCP tools (`mcp__maestro__*`) to launch the app on a
disposable simulator and observe real behavior — the free/local alternative to a paid cloud device
farm.

It emits advisory `DYNAMIC-PASS:` / `DYNAMIC-FINDING:` / `DYNAMIC-SKIP:` lines, each tagged with a
rule id (`[dyn-launch]`, `[dyn-permission-prompt:NSCameraUsageDescription]`, …), and **never
changes the GREEN/YELLOW/RED verdict** (the verdict stays derived only from Phases 0–2). A check
that could not be driven is a `DYNAMIC-SKIP`, never a PASS and never an invented FINDING. It is
**no-write, but it executes your application code**: it creates its own throwaway simulator
device and never touches an existing one or the repo, but the launched app reaches its backends
and receives the demo credentials you supplied — tell the user so before the first launch. It
requires macOS + Xcode + a simulator runtime and is permanently local-only (it cannot run in CI).
It is a pre-submit local smoke signal, not a TestFlight / crash-reporter / QA replacement.
The separate `scan.sh --dynamic-blocking` opt-in requires jq; without it the scanner exits 64
with `--dynamic-blocking needs jq` before optional work.

**Getting a build without building.** Never run `xcodebuild` / `flutter build` / `gradle`. Run
`bash <skill-dir>/scripts/app-discover.sh --repo <repo> --json`: it lists the simulator `.app`
bundles the user already built (DerivedData, `build/ios/iphonesimulator`) with build time,
configuration (from the directory name: `debug` / `release` / `unknown`) and bundle id, and
recommends the newest. **Ask the user to confirm one candidate explicitly** before anything is
installed or launched. If it finds none, keep the `runtime-not-audited` gap and paste the build
command it prints for the user to run themselves.

**Observation-based checks are scripted.** `bash <skill-dir>/scripts/dynamic-run.sh --app <path>.app
--repo <repo> --out <tmp>` creates a throwaway device, runs the launch checks **three times on an
erased device** (a crash FINDING needs 3/3; a mixed result carries its ratio and never blocks),
then dark-mode / Dynamic Type layout heuristics, the installed bundle (`Info.plist` purpose
strings, `DTXcode`, `otool -L`), and hosts contacted, writing `<tmp>/transcript.txt` and
`<tmp>/run.json` (which carries the `build_config` to pass on). Add `--ipad` for the iPad pass. On
React Native without Metro on port 8081 it SKIPs the launch checks instead of reporting a false
crash; on Flutter / KMP it pre-SKIPs the selector-based checks (no accessibility semantics). Then
drive the selector-based checks (D3 paywall, D3b Restore tap, D4 prompts, D5 demo login, D6
parity) with the Maestro MCP tools — **one flow per `mcp__maestro__run` call**, labels read from
`accessibilityText` — appending `DYNAMIC-*` lines to the same transcript.

Follow [`references/simulator-dynamic-review.md`](references/simulator-dynamic-review.md) for the
setup step (D0), the full checklist (D1–D17 incl. D3b) and the output format.
Afterwards feed the transcript to [`scripts/dynamic.sh`](scripts/dynamic.sh) with the static
`--format json` output: it records every observation as `evidence: runtime` with the run's
`runtime_target` and `build_config`, and reconciles them with the static findings (a runtime
confirmation upgrades the evidence; a complete runtime contradiction marks the static finding
`RESOLVED`, which counts toward nothing; a partial one only downgrades FAIL to WARN). A **Debug or
unknown build never clears `needs build verification`**; say which configuration the `.app` came
from, and leave it `unknown` if you do not know.

## Rules

- **READ-ONLY:** never change code or assets. Only report and write the token. (The optional Phase 6
  simulator tier touches disposable simulator state only — never the user's project — but it does
  execute the user's app; see Phase 6.)
- **Speed > exhaustiveness:** `scan.sh` uses parallel grep/jq and finishes in seconds.
- **No error swallowing:** if any scan command fails, that line is reported as FAIL and the scan continues.
- **Token location:** `.precheck-pass` at the repo root; the guard tests it with an `mmin -60` filter.
- **Local-only:** designed for manual, local runs; keep it out of CI to avoid false signals.

## Known limits

- The default flow is static analysis only. Runtime crash/behavior testing is available as an
  optional, opt-in local simulator tier (Phase 6, `references/simulator-dynamic-review.md`); it is a
  pre-submit local smoke signal, not a TestFlight / crash-reporter replacement.
- Several checks are advisory WARNs gated on detected signals (Sign in with Apple 4.8,
  external-purchase 3.1.1(a), tracking/IDFA without ATT, analytics vs privacy manifest, metadata
  URLs and placeholder copy). The export-compliance key is flagged when absent, but the actual
  encryption answer still belongs in App Store Connect.
- Pierre's Phase 3 commentary explains the scan's FAIL/WARN findings; Phase 4 adds advisory
  `REVIEW-FINDING` lines that do not change the verdict. Neither phase is a guarantee of Apple's decision.
- Most accurate for native Swift / SwiftUI. The metadata, privacy-manifest, screenshots, and
  export-compliance checks apply to any iOS app, but the code-level checks read Swift source, so on
  React Native (JavaScript), Flutter (Dart) or Kotlin Multiplatform they under-detect rather than
  false-fire — and the scan now says so with a `SKIP: framework` gap record (`framework-not-audited`)
  naming the affected checks.
- iOS only.
- Phase 0 checks section-number drift and fingerprints of covered sections; it does not establish complete guideline coverage.
- Guideline citations are **pinned snapshots**, not a live fetch: offline and reproducible, but only
  as current as the last reconciliation. `guideline-cite.sh` prints the verification date and marks a
  citation `STALE` past the staleness window; `--verify-live` upgrades that to a real change check
  against the live page when the network is available, and the scheduled drift job catches it
  otherwise. Without either, an age-fresh pin on a section Apple edited yesterday will still read as
  current.
- Evidence and confidence labels are **per rule**, refined per branch where a branch is clearly
  stronger or weaker than its rule; a branch that could not run at all is a `SKIP`, not a labelled
  WARN. They describe the artifact the finding was read from and who
  enforces the guideline — not a probability that Apple will reject this particular submission.

## Optional: upload guard hook

`hooks/fastlane-guard.sh` blocks `fastlane deliver/pilot/release` unless a fresh `.precheck-pass`
token exists. In Claude Code and Grok Build it auto-wires via `hooks/hooks.json` **when installed
as a plugin** (the hook path uses `${CLAUDE_PLUGIN_ROOT}`; Grok also sets that alias alongside
`${GROK_PLUGIN_ROOT}`, and maps a `Bash` matcher onto `run_terminal_command`). The guard reads
the snake_case (`.tool_input`), camelCase (`.toolInput`), and top-level (`.command`, Cursor)
tool-use envelopes, and reports a block on both stderr and stdout, so it blocks on every host that
wires it. An `install.sh`-vendored copy gets no automatic hook. In other
environments, wire it as a pre-command check yourself, or treat the token as a manual go/no-go
signal.
