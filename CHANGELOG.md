# Changelog

All notable changes to this project are documented here. Versioning follows
[SemVer](https://semver.org/). Released as git tags.

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
