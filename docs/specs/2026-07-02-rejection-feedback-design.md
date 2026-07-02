# Rejection-outcome feedback loop

**Roadmap:** #3 (rejection-outcome feedback loop). Reporting/measurement layer only. Builds on the #1 measurement infrastructure (`corpus/`, `scripts/scorecard*.sh`, `docs/scorecard.md`).

**Date:** 2026-07-02
**Target release:** v1.11.0 (bump at release, not in-branch)

## Problem

`docs/scorecard.md` publishes two honestly-scoped measurements — synthetic intended-behaviour
fidelity and a real-panel false-positive rate — and states plainly: *"Neither measurement claims
agreement with Apple's actual review decisions."* This feature adds a **third, independently-labelled
axis**: real App Store review outcomes (approved / rejected + Apple's cited guideline), recorded in a
committed ledger and summarized in the scorecard. It closes the "we can't say anything about real
Apple decisions" gap **honestly** — raw, uninflated, never overclaiming from a tiny sample.

The value accrues with accumulated outcomes (which arrive one submission at a time, slowly), not with
code. This ships the honest plumbing — an empty jar with a clear label and a floor that refuses to
compute a rate until there is enough data to mean anything.

## Identity constraints (non-negotiable)

- **READ-ONLY** for the user's project. Writing to the tool's own `corpus/outcomes/` ledger is
  self-owned measurement state (same category as `.precheck-pass` and `guidelines-fingerprints.json`).
- **No competitor names** anywhere.
- **Honesty:** distinguish real Apple outcomes from synthetic/real-panel labels at every point;
  never compute a rate below the sample-size floor; a permanent survivorship-bias caveat once a rate
  is shown.
- **Offline / zero-dependency / byte-identical CLI:** `scan.sh`, `bin/cli.js`, `action.yml`,
  `install.sh`, `verdict.sh` are UNTOUCHED. This is a maintainer/reporting-side addition only,
  reading a committed local ledger (no network, unlike `--real`).
- **Verdict determinism untouched:** GREEN/YELLOW/RED is a pure function of the current scan; it
  never depends on historical outcome data.
- **bash 3.2**, version lockstep (bump at release).

## Resolved design decisions (the scoping draft's open questions)

1. **Storage:** in-repo public `corpus/outcomes/ledger.json` — auditability (anyone can verify the
   raw tally behind any published number) is the tool's differentiator, matching `corpus/real/`.
   Privacy via anonymized `app_ref`, no verbatim Apple Resolution Center text, no bundle id / company
   / app name unless the submitter explicitly discloses.
2. **Contribution:** maintainer-reviewed via PR (mirrors the real-panel human labelling pass). A
   GitHub issue template funnels submissions into a maintainer-reviewed PR. No telemetry. Every
   record carries `reviewed_by`.
3. **Sample-size floor = 10.** Below 10 outcomes: raw tally only, no computed rate. At/above 10: a
   directional recall estimate with caveats + a permanent survivorship-bias note.
4. **Scope: reporting only.** Feeding outcome data back into which rules exist or their severity is
   explicitly OUT of scope (a future human/roadmap decision, never automated). `verdict.sh`/`scan.sh`
   untouched.
5. **Evidence:** no verbatim Apple text in-repo. A record attests `evidence_kept_privately`
   (submitter retains off-repo evidence); the repo stores no evidence and takes on no custody.

## Approach

**Approach A** from the scoping draft: a committed ledger + a deterministic scorecard section. The
ledger is local and committed, so — unlike the network `--real` panel — the outcomes summary is fully
deterministic and offline, and therefore baked into the standard generated `docs/scorecard.md` and
covered by the existing blocking `scorecard.sh --check` (regenerate + diff). No separate non-blocking
CI job is needed.

## Components

### 1. `corpus/outcomes/ledger.json` + `corpus/outcomes/README.md`

- `ledger.json` starts as an empty array `[]` (like `corpus/real/labels.json` started `{}`).
- Each record (one per real submission outcome):
  ```jsonc
  {
    "id": "2026-07-02-appref01",              // stable id, not derived from real app identity
    "app_ref": "maintainer-app-1",            // anonymized label; never a real bundle id/company/name
    "precheck_version": "1.9.0",              // PRECHECK_VERSION at scan time
    "scan_date": "2026-06-15",
    "verdict_at_submission": "YELLOW",        // GREEN|YELLOW|RED from verdict.sh at submission time
    "findings_snapshot": [                    // from scan.sh --format json, file/line stripped
      { "rule_id": "subscription-links-restore", "severity": "WARN", "guideline": "3.1.2" }
    ],
    "submission_date": "2026-06-16",
    "apple_decision": "rejected",             // "approved" | "rejected"
    "apple_decision_date": "2026-06-19",
    "rejected_guidelines": ["3.1.2"],          // Apple's cited guideline number(s); [] if approved
    "matched_rule_ids": ["subscription-links-restore"], // human-mapped rule_id(s) for the cited guideline(s)
    "outcome_label": "predicted-and-flagged", // taxonomy below
    "evidence_kept_privately": true,
    "reviewed_by": "bt",
    "notes": "free text; mapping caveats, ambiguity, etc."
  }
  ```
- `outcome_label` taxonomy (app-level): `predicted-and-flagged` (Apple rejected for G; tool had a
  finding mapped to G), `missed` (Apple rejected for G; tool had no finding mapped to G — the most
  valuable/actionable), `approved-clean` (approved; 0 FAIL at submission),
  `approved-with-warns-unaddressed` (approved; ≥1 WARN still present — suggestive, not proof).
- `README.md` documents: the schema, the anonymization/privacy rules (no verbatim Apple text, no real
  identity), the PR + maintainer-review contribution process, the sample-size floor, and an Honesty
  section mirroring `corpus/real/README.md`.

### 2. `scripts/scorecard-outcomes.sh`

Standalone (like `scorecard-real.sh`), pure `bash`+`jq`, offline, deterministic. Reads
`corpus/outcomes/ledger.json` and prints the **markdown section** to stdout:

- `n == 0`: a section stating no outcomes are recorded yet + a pointer to `corpus/outcomes/README.md`.
- `0 < n < 10`: a raw tally table (count per `outcome_label`) + a bold line: *"n=N is too small to
  compute a meaningful rate; shown for transparency only."* No percentage.
- `n >= 10`: the tally table + a directional recall line ("flagged the cited guideline in X of Y real
  rejections — directional, not a guarantee") + a permanent survivorship-bias caveat.
- Always: a line stating these are real Apple outcomes, independently labelled, distinct from the
  synthetic/real-panel measurements, and that neither approval nor rejection here proves a finding's
  general correctness.

Floor is a documented constant (`OUTCOMES_FLOOR=10`).

### 3. `scripts/scorecard.sh`

- `render_card()` appends the outcomes section (via `bash "$ROOT/scripts/scorecard-outcomes.sh"`)
  after the "Synthetic aggregate" section; the "Methodology" text is updated from "Two corpora" to
  three measurements (adding the outcomes axis).
- A new `--outcomes` mode runs `scorecard-outcomes.sh` standalone (prints the section) for
  manual/CI use, parallel to `--real`.
- `docs/scorecard.md` is regenerated to include the `n=0` outcomes section. `--check` (regenerate +
  diff) now covers it — deterministic because the ledger is committed and read offline.

### 4. `.github/ISSUE_TEMPLATE/app-store-outcome.md`

A structured issue template prompting a contributor for the schema fields (anonymized), so the first
external contributor has a low-friction path that funnels into a maintainer-reviewed PR.

### 5. CI (`.github/workflows/ci.yml`)

Add `scripts/scorecard-outcomes.sh` + `tests/test-scorecard-outcomes.sh` to the shellcheck/test
lists and `corpus/outcomes/ledger.json` to the JSON-validation list, matching the existing pattern.
The outcomes section is covered by the existing blocking `scorecard.sh --check` (deterministic); no
new non-blocking job is required.

## Testing (TDD)

- **`tests/test-scorecard-outcomes.sh`** (registered in `tests/all.sh`): unit-test
  `scorecard-outcomes.sh` against crafted temp ledgers via an env override of the ledger path:
  - empty ledger (`[]`) → the "no outcomes yet" section, no rate.
  - a small ledger (n=3, mixed labels) → raw tally with correct per-label counts + the "too small"
    line + NO percentage anywhere.
  - a ledger at the floor (n=10, some rejections flagged/missed) → the tally + a directional recall
    line + the survivorship-bias caveat.
  - assert the section never prints a `%`/rate when n < 10.
- **`--check` determinism:** regenerating `docs/scorecard.md` with the committed empty ledger is
  stable; `scorecard.sh --check` passes.
- **Byte-identity of the scan path:** `scan.sh`/`bin/cli.js`/`action.yml` unchanged; the existing
  suites stay green.
- **JSON validity** of `ledger.json` (`[]`) in CI.

## Out of scope (v1)

- Any per-finding disposition pipeline (scoping Approach C) — deferred; Apple cites only the blocking
  reason, so most per-finding dispositions for approved apps are unknowable.
- A `record-outcome.sh` submission helper (scoping Approach B) — natural fast-follow once the schema
  is proven; not needed to ship the honest plumbing.
- Feeding outcome data into rule existence/severity or the verdict — explicitly a future human
  decision, never automated.
- Verbatim Apple Resolution Center text storage.

## Build method

superpowers subagent-driven-development: fresh implementer per task + two-stage review; final Opus
whole-branch review; `superpowers:finishing-a-development-branch`. New feature branch; merge +
release (v1.11.0) after the final review.
