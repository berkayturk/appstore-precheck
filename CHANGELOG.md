# Changelog

All notable changes to this project are documented here. Versioning follows
[SemVer](https://semver.org/). Released as git tags.

## [1.5.0] - 2026-06-30

### Added
- **Tier B v1 — 6 heuristic Pierre deep-review checks** (28 total, up from 22). New Phase 4 items
  in guideline order: **2.1** review notes / demo account quality, **2.2** beta/test language,
  **2.3.4** app preview consistency, **2.3.9** incentivized review copy, **4.5.1–4.5.3** push /
  HomeKit abuse patterns, **5.6.4–5.6.7** rating manipulation dark patterns. Marked † in docs;
  higher false-positive risk — advisory `REVIEW-FINDING: WARN` only.
- Expanded `covered_by_pierre_deep_review` in `guidelines-baseline.json` with 2.2, 2.3.4, 2.3.9,
  4.5.1–4.5.3, 5.6.4–5.6.7.

### Changed
- Phase 4 checklist 22 → **28** across `pierre-deep-review.md`, `SKILL.md`, `methodology.md`, README
  (full guideline-ordered table with † Tier B labels), plugin manifest, and social preview
  (`41 static + 28 Pierre deep checks`).

## [1.4.0] - 2026-06-30

### Added
- **Phase 4: Pierre deep review — 22 semantic checks.** After Phase 3 (explaining every scan
  FAIL/WARN), Pierre runs a read-only Review Simulator: fetches privacy/support URLs, reads
  screenshots, compares metadata claims to Swift code, validates paywall disclosure quality, and
  cross-checks permissions vs policy. Each check emits `REVIEW-PASS:` or advisory
  `REVIEW-FINDING: … WARN` (does not change GREEN/YELLOW/RED counts). Full checklist in
  [`references/pierre-deep-review.md`](skills/appstore-precheck/references/pierre-deep-review.md).
- **`covered_by_pierre_deep_review`** in `guidelines-baseline.json` (26 guideline numbers across
  the 22 checks). Consolidation moves to **Phase 5** (6 phases total: 0–5).
- [`examples/pierre-deep-review.md`](examples/pierre-deep-review.md) showing `REVIEW-FINDING` output.

### Changed
- Flow is now **6 phases (0–5)**: Phase 3 = scan commentary, Phase 4 = deep review, Phase 5 =
  verdict + token. Updated `SKILL.md`, `methodology.md`, README (static table + deep-review table
  in guideline order), examples, plugin manifest, and social preview copy (`41 static + 22 Pierre
  deep checks`).

## [1.3.1] - 2026-06-30

### Changed
- **Phase 3 (Pierre) now explains every FAIL and WARN** from Phases 0–2 in **2–3 sentences
  each** — no more random 5-guideline sampling. Pierre repeats each machine line verbatim,
  then explains why Apple cares, what the scan found, and what to fix. Updated `SKILL.md`,
  `methodology.md`, the README example, `examples/red-reject.md`, and behavioral eval
  assertions in lockstep.
- Phase 4 presentation order clarified: trilingual verdict block → Pierre commentary → verbatim
  scan lines + `file:line` fixes → verdict/token.
- **Trilingual verdict block format:** each language in its own **bold label + blockquote**, separated
  by horizontal rules (`---`) under a `### Pierre` heading — never FR/EN/user-lang compressed on one line.

## [1.3.0] - 2026-06-30

### Added
- **Eleven new signal-gated advisory checks (30 → 41 rejection vectors), all WARN-only:**
  - **2.1** a login-gated app with no demo account / credentials for App Review (fastlane
    `review_information` or `.reviewPrepNotes`).
  - **2.5.2** executable-code download / native hot-patching (JSPatch, Rollout, DynamicCocoa).
    Allowed JS-bundle OTA (React Native CodePush) is deliberately **not** flagged.
  - **2.5.4** a background mode declared in `UIBackgroundModes` with no matching API used in Swift.
  - **3.1.5(a)** a cryptocurrency wallet / exchange / mining signal.
  - **4.2.3** a thin WKWebView wrapper around a website (heuristic: WKWebView + very few Swift files).
  - **4.2.7** a remote-desktop / host-mirroring signal.
  - **4.4.2** a Safari content-blocker / web extension.
  - **5.1.1(v)** account creation offered without an in-app account-deletion path (the real
    5.1.1(v) Account Sign-In rule).
  - **5.1.4** metadata targeting a child audience while a third-party ads/analytics SDK is linked.
  - **5.3.4** real-money gambling language in metadata.
  - **5.5** a Mobile Device Management (MDM) signal.
- `tests/fixtures/risky-app-2` (advisory §31–§41 except web-wrapper) and `tests/fixtures/webview-app`
  (the 4.2.3 heuristic), with assertions in `tests/run.sh`. Both are advisory-only (no FAIL).

### Changed
- **Corrected the Required Reason API label from `5.1.1(v)` to `5.1.1`.** Apple documents the
  Required Reason API rules under 5.1.1 + the privacy-manifest developer docs; sub-item **(v)** is
  "Account Sign-In", a different rule. The `(v)` label now belongs to the new account-deletion
  check (vector 38). Updated `scan.sh` output, the methodology table, the README table, the
  examples, and the field-test notes in lockstep.
- §18 (support / privacy URL) now also cites the guidelines it satisfies: **1.5** (developer
  contact via the support URL) and **5.1.1(i)** (privacy policy link).
- Expanded `guidelines-baseline.json` `covered_by_scan` with 1.5, 2.5.2, 2.5.4, 3.1.5, 4.2.3,
  4.2.7, 4.4.2, 5.1.4, 5.3.4, and 5.5.

## [1.2.0] - 2026-06-30

### Added
- **Ten new signal-gated advisory checks (20 → 30 rejection vectors), all WARN-only:**
  - **3.1.1** third-party payment SDK (Stripe, Braintree, PayPal, Square, Adyen, …) linked for
    digital goods instead of in-app purchase.
  - **1.2** user-generated content detected without a report / block / moderation affordance.
  - **1.6** App Transport Security disabled app-wide (`NSAllowsArbitraryLoads=true`).
  - **4.9** recurring Apple Pay without the renewal / cancel disclosure.
  - **5.6.1** a direct App Store write-review link/prompt without the system `requestReview` API.
  - **2.3.1** misleading marketing claims (iOS virus / malware scanners, fake speed boosters) in metadata.
  - **2.3.8** "For Kids" / "For Children" wording outside the Kids Category.
  - **4.4.1** keyboard extension requiring full access (`RequestsOpenAccess=true`).
  - **5.1.3** HealthKit used together with an iCloud / CloudKit sync path.
  - **5.4** VPN / NetworkExtension (`NEVPNManager`) usage.
- `tests/fixtures/risky-app` plus assertions in `tests/run.sh` exercising all ten new vectors
  (advisory only — the fixture is YELLOW, never RED).

### Changed
- **YELLOW threshold raised from 3+ to 5+ WARN.** The ten new advisory checks are signal-gated
  (most apps trip only one or two), but the bump keeps a normal submission from sliding into
  YELLOW on advisory noise alone. GREEN is now 0 FAIL and ≤4 WARN; YELLOW is 0 FAIL and ≥5 WARN.
  Updated `verdict.sh`, the verdict tests, the output-contract tables, and the docs in lockstep.
- Corrected the minimum-functionality check's label from `4.0` to `4.2` (its real guideline
  number) in the scanner output, the methodology table, and the README.
- Reconciled `guidelines-baseline.json` against the live guidelines (Last Updated June 8, 2026):
  no structural section drift; expanded `covered_by_scan` to reflect every guideline the scan now
  touches (adds 1.2, 1.6, 2.1, 2.3, 2.3.8, 3.1.1, 4.4.1, 4.8, 4.9, 5.1.3, 5.4, 5.6.1; 4.0 → 4.2).

## [1.1.1] - 2026-06-30

### Changed
- **Pierre now speaks in a trilingual block.** The verdict opens with his native **French** line,
  then an **English** rendering, then a rendering in the **user's conversation language** — each an
  idiomatic, in-character re-expression in that language's own rhythm, not a literal translation.
  Collapses to two lines when the user already converses in French or English. The block stays
  flavor only; the FAIL/WARN list, `file:line` references, and fixes below it remain plain and
  machine-faithful. Updated the output contract, Phase 4 step 3, and the behavioral eval
  assertions accordingly.

### Fixed
- **Pierre no longer treats local-only files as Apple submission evidence.** The Phase 3 prompt
  now scopes reject-risk evidence to Apple-facing artifacts (fastlane metadata, paywall Swift,
  String Catalog, Info.plist, PrivacyInfo.xcprivacy). Internal/local files (`.planning/` notes,
  `reviewPrepNotes` drafts, build scripts) and Google Play / non-Apple sections are out of scope —
  cited at most as a WARN labeled "internal draft — not submitted to Apple", never REJECT-RISK. A
  REJECT risk now requires a contradiction *within* submission-facing artifacts, not an internal
  doc disagreeing with metadata. An eligibility-gated/conditional offer paired with metadata that
  mentions it is WARN at most (unless the metadata promises it unconditionally). Prevents the
  false REJECT-RISK overreach seen when dogfooding an already-approved build.
- **2.3.7 locale check no longer hard-FAILs on a config/disk mismatch.** A locale listed in
  `.appstore-precheck.json` `locales` but with no metadata folder on disk is now a WARN (with an
  actionable "add it or remove it from the config" message), not a FAIL — that locale was simply
  never submitted, so it must not turn an approved set RED. A missing *file* inside a present
  locale folder is still a FAIL.
- **2.1 placeholder check no longer false-fires on words containing "changeme".** The `changeme`
  pattern is now word-bounded (`\bchangeme\b`) in both the metadata-URL and store-copy scans, so
  legitimate copy such as the French "changement" ("change") is not flagged as unfinished.
- Added regression coverage in `tests/test-config.sh` for both fixes.
- CI: bumped `actions/checkout@v4 -> v7` and `actions/setup-node@v4 -> v6` to clear the
  GitHub Actions Node.js 20 deprecation warning (both now run natively on Node 24).

## [1.1.0] - 2026-06-28

### Added
- `npx appstore-precheck` CLI (`bin/cli.js`): run the static scan with no clone and no install.
  It scans the current directory (or `--dir <path>`), prints the scan output and the verdict
  verbatim, and exits non-zero on RED (or on YELLOW with `--fail-on YELLOW`), mirroring the
  GitHub Action. A thin wrapper over the bundled `scan.sh` / `verdict.sh`; it adds no new checks.
- Published to npm under the package name `appstore-precheck`.
- `tests/test-cli.sh`: covers the CLI's verdict mapping and exit codes (GREEN/RED/YELLOW,
  `--fail-on`, `--version`, `--help`, bad-usage), wired into the suite and `npm run lint`.

## [1.0.0] - 2026-06-28

Initial release.

### Added
- `appstore-precheck` Agent Skill: read-only iOS App Store pre-submission gate.
- `scripts/scan.sh`: portable Bash scanner for 20 rejection vectors (including advisory Sign in
  with Apple parity and external-purchase-link checks) with zero-config
  auto-detection of a standard fastlane + Xcode layout, plus `.appstore-precheck.json` overrides.
- Five more signal-gated advisory checks (15 → 20): tracking/IDFA SDK shipped without an ATT
  prompt (5.1.2, the reverse of the existing ATT check), the export-compliance key
  (`ITSAppUsesNonExemptEncryption`), support/privacy URL presence in fastlane metadata (2.3),
  analytics SDK vs `PrivacyInfo.xcprivacy` data-type declarations (5.1.1), and placeholder/dummy
  copy in store metadata (2.1). All WARN-only, with a `tracking-app` fixture that exercises them.
- `scripts/verdict.sh`: deterministic GREEN/YELLOW/RED verdict and `.precheck-pass` token
  action from the scan output, so the verdict is machine-testable, not just an agent judgement.
- 5-phase flow: guideline-drift check, static scan, Apple `fastlane precheck` wrapper,
  adversarial reviewer pass, consolidation + `.precheck-pass` token.
- Optional Claude Code upload-guard hook (`hooks/fastlane-guard.sh`) that blocks
  `fastlane deliver/pilot/release` without a fresh token.
- Cross-tool support: native `SKILL.md` for Claude Code / Codex / Cursor / Gemini CLI,
  root `AGENTS.md`, and an `install.sh` multi-host installer. Claude Code and Codex CLI runs
  verified end-to-end (`docs/cross-tool-verification.md`).
- Claude Code plugin + single-plugin marketplace manifests.
- Test suite (`tests/`): fixture scans plus unit tests for verdict thresholds, the upload-guard
  hook, config overrides, and the installer. CI runs ShellCheck, JSON validation, a
  version-consistency guard, and the full suite on every push and PR.
- Documentation: methodology reference, a how-to-add-a-check guide, an agent-portability note,
  real Phase 0 drift-check and Phase 2 `fastlane precheck` examples, and a field-test report
  from dogfooding real App Store apps (`docs/`).
- Community health files: contributing guide, security policy, code of conduct, and issue/PR
  templates.
- Behavioral eval suite (`skills/appstore-precheck/evals/`) in the Agent Skills format: RED /
  GREEN / no-IAP cases with self-contained inputs and assertions.
- Branding: logo, social preview, and **Pierre**, the French App Review critic mascot whose
  voice drives the Phase 3 adversarial review.

### Fixed
- More reliable app-target auto-detection: resolve the iOS source dir via the app entry point
  (`@main` / `AppDelegate`), not Info.plist position alone, so a Watch app, extension, or
  framework is no longer mistaken for the main target. Required-link checks now scan the whole
  paywall cluster instead of a single auto-picked file. (Found by dogfooding Pocket Casts,
  Wikipedia, and DuckDuckGo.)
- Portable empty-array handling under `set -u` on stock macOS bash 3.2 and modern bash.
