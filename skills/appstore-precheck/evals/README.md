# Evals

Behavioral evaluations for the `appstore-precheck` skill, in the
[Agent Skills eval format](https://agentskills.io/skill-creation/evaluating-skills)
([`evals.json`](evals.json) + self-contained inputs under [`files/`](files/)).

These test the **agent-behavior layer**: given a realistic submission-intent prompt and a throwaway
iOS project, does the agent invoke the skill, run the scanner, reach the correct **GREEN/YELLOW/RED**
verdict, and present it faithfully: Pierre's trilingual one-liner, then **2–3 sentences explaining
each FAIL and WARN**, then the scan's `FAIL`/`WARN`/`PASS` lines verbatim (never paraphrased). Each case carries `assertions` describing what a correct run must
contain.

| # | Case | Input | Expected |
|---|------|-------|----------|
| 1 | `red-blocks-submission` | `files/red-app` (Android mention + paywall missing links) | **RED**, no token |
| 2 | `green-allows-submission` | `files/green-app` (clean + full paywall) | **GREEN**, token written |
| 3 | `no-iap-skips-paywall-checks` | `files/no-iap-app` (no StoreKit) | 3.1.2 skipped, not RED |

## Running them

The official [`skill-creator`](https://code.claude.com/docs/en/skills#run-evals-with-skill-creator)
plugin runs `evals.json` by spawning an isolated subagent per case (with-skill vs without-skill),
capturing assertion pass/fail evidence into `grading.json` and aggregate stats into `benchmark.json`.

You can also sanity-check the **mechanical** expectations directly: copy an input out of the repo
(so the scanner treats it as its own project root) and run the scan + deterministic verdict:

```bash
tmp=$(mktemp -d); cp -R skills/appstore-precheck/evals/files/red-app/. "$tmp/"
( cd "$tmp" && bash "$OLDPWD/skills/appstore-precheck/scripts/scan.sh" \
    | bash "$OLDPWD/skills/appstore-precheck/scripts/verdict.sh" )
# → VERDICT: RED   (green-app → GREEN; no-iap-app → GREEN with paywall checks skipped)
```

## Scope

Evals cover agent behavior; they complement, not replace, the deterministic scanner suite in
[`tests/`](../../../tests/) (verdict thresholds, the upload-guard hook, config overrides, the
installer) and the live cross-host runs in
[`docs/cross-tool-verification.md`](../../../docs/cross-tool-verification.md).
