# Documentation index

| Doc | What's in it |
|-----|--------------|
| [methodology.md](../skills/appstore-precheck/references/methodology.md) | The detailed method behind every check: the drift mechanics, the full rejection-vector table, auto-detection rules, verdict thresholds, and the manual checklist. |
| [pierre-deep-review.md](../skills/appstore-precheck/references/pierre-deep-review.md) | The 28 semantic deep-review checks Pierre runs in Phase 4 (22 Tier A + 6 Tier B). |
| [simulator-dynamic-review.md](../skills/appstore-precheck/references/simulator-dynamic-review.md) | The opt-in Phase 6 local dynamic simulator tier: 6 advisory smoke checks via Maestro + `xcrun simctl`. |
| [adding-a-check.md](adding-a-check.md) | How to add a new rejection-vector check to `scan.sh`: the output contract, fixtures, and docs to update. |
| [scorecard.md](scorecard.md) | Generated validation scorecard: synthetic precision (CI-gated), real-panel FP rate, real App Store outcomes. |
| [fp-reduction-report.md](fp-reduction-report.md) | The false-positive reduction pass: what was measured and what changed. |
| [agent-portability.md](agent-portability.md) | How one `SKILL.md` runs across Claude Code, Codex, Cursor, and Gemini, and what each host reads. |
| [cross-tool-verification.md](cross-tool-verification.md) | Real per-host runs proving the skill triggers and runs `scan.sh` (all four hosts verified end-to-end: Claude Code, Codex, Gemini, Cursor). |
| [publishing-plugins.md](publishing-plugins.md) | Maintainer notes for plugin-marketplace submission per host. |
| [field-tests.md](field-tests.md) | Dogfooding the scanner on real App Store apps (DuckDuckGo, Pocket Casts, Wikipedia): bugs found and fixed. |
| [drift-check.md](../examples/drift-check.md) | A real Phase 0 guideline-drift run. |
| [fastlane-precheck.md](../examples/fastlane-precheck.md) | A real Phase 2 `fastlane precheck` run. |

New here? Start with the [top-level README](../README.md), then `methodology.md` for the
specifics behind a check.
