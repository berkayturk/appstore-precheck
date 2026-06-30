# Changelog

All notable changes to this project are documented here. Versioning follows
[SemVer](https://semver.org/). Released as git tags.

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
