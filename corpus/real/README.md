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

## Honesty

No real-panel precision figure is published until findings are labelled. `labels.json`
currently seeds `{}` — it is populated only as reviewers label findings.

## Manifest

`manifest.json` lists 18 apps, each pinned by `{name, repo, commit, license}`. Every
app carries a permissive license (MIT, Apache-2.0, BSD-2-Clause, BSD-3-Clause, or
MPL-2.0).
