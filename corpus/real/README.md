# Real-App Validation Panel

_Referenced by `scripts/scorecard-real.sh`. Do not edit by hand except to add apps or labels._

## Purpose

This panel measures the scanner's **real-code false-positive rate** by running it
against permissively-licensed, commit-pinned open-source iOS / React-Native apps.

It measures the FP rate on real code. **It makes no claim about Apple's actual App
Store review decisions.**

## How to run

```
bash scripts/scorecard.sh --real
```

This clones each app listed in `manifest.json` at its pinned commit into a temporary
directory, runs the scanner (`scan.sh --format json`) against the checkout, and joins
the resulting findings with the human labels in `labels.json`. It requires network
access and is slow — it is non-blocking in CI.

## The human labelling pass

Findings produced by the real panel start **UNLABELED**. A human reviewer looks at
each candidate finding and records a verdict in `labels.json`:

- `TP` — true positive: a real issue the scanner correctly flagged.
- `FP` — false positive: the scanner flagged something that is not actually a problem.

The label key format is exactly what `scorecard-real.sh` builds when joining findings
against `labels.json`:

```
"<app>|<rule_id>|<file>|<line>|<commit>": "TP" | "FP"
```

Until a finding is labelled, `scorecard-real.sh` reports it as **UNLABELED** and it
contributes to no published precision number.

Each label carries a one-line rationale in [`rationales.json`](rationales.json), keyed by
`<app>|<rule_id>`, so a verdict can be audited without re-deriving the evidence. No script
reads that file.

## Pass status (2026-08-04)

The panel is **fully labelled**: 0 UNLABELED findings across all 18 apps.

```
real-panel: tp=184 fp=122 unlabeled=0
real-panel precision (FP rate basis): 0.60
```

Two rules produce half of all false positives and are the obvious next fixes:

| Rule | FP | Why it misfires |
|------|----|-----------------|
| `screenshot-dimensions` | 47 | wikipedia-ios ships JPEG files named `.png`. The detection is factually right, but Apple accepts JPEG and App Store Connect validates by content, so 47 WARNs carry no review consequence. |
| `xcode-sdk-requirement` | 15 | `LastUpgradeCheck` records the Xcode that last ran the project upgrade check, not the SDK the app builds against. |

One FP class found in this pass is already fixed: the §2 photo-read regex matched a bare
`fetchAssets`, so any method with that name (a config loader in duckduckgo-ios, a wallpaper
manager in firefox-ios) raised a 5.1.1 FAIL. The signal is now PhotoKit-qualified, with
`tests/fixtures/fetch-assets-app` as the regression guard.

### Known limitation: key collisions

The key format has no message discriminator, so several findings from the same rule on the
same file collapse onto one key and can only carry one verdict. It happened twice here, both
on `privacy-manifest-parity` (wikipedia-ios, duckduckgo-ios), where a genuine Required Reason
API gap shares a key with a false one. Collisions are resolved conservatively: a key is `TP`
only when *every* finding under it is a true positive. Adding a message hash to the key would
fix this, at the cost of invalidating every existing label.

## Honesty

No real-panel precision figure is published until findings are labelled. Numbers above are
reported only because the pass is complete; they measure the false-positive rate on real
open-source code and make no claim about Apple's actual review decisions.

## Manifest

`manifest.json` lists 18 apps, each pinned by `{name, repo, commit, license}`. Every
app carries a permissive license (MIT, Apache-2.0, BSD-2-Clause, BSD-3-Clause, or
MPL-2.0).
