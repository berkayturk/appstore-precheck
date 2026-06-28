# Documentation index

| Doc | What's in it |
|-----|--------------|
| [methodology.md](../skills/appstore-precheck/references/methodology.md) | The detailed method behind every check: the drift mechanics, the full rejection-vector table, auto-detection rules, verdict thresholds, and the manual checklist. |
| [adding-a-check.md](adding-a-check.md) | How to add a new rejection-vector check to `scan.sh`: the output contract, fixtures, and docs to update. |
| [agent-portability.md](agent-portability.md) | How one `SKILL.md` runs across Claude Code, Codex, Cursor, and Gemini, and what each host reads. |
| [cross-tool-verification.md](cross-tool-verification.md) | Real per-host runs proving the skill triggers and runs `scan.sh` (Claude Code + Codex verified end-to-end). |
| [field-tests.md](field-tests.md) | Dogfooding the scanner on real App Store apps (DuckDuckGo, Pocket Casts, Wikipedia): bugs found and fixed. |
| [drift-check.md](../examples/drift-check.md) | A real Phase 0 guideline-drift run. |
| [fastlane-precheck.md](../examples/fastlane-precheck.md) | A real Phase 2 `fastlane precheck` run. |

New here? Start with the [top-level README](../README.md), then `methodology.md` for the
specifics behind a check.
