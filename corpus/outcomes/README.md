# Real App Store Outcomes

_Referenced by `scripts/scorecard-outcomes.sh`. Do not edit by hand except to add reviewed records._

## Purpose

This ledger records **real App Store review outcomes** (approved / rejected + Apple's cited
guideline) for apps that were scanned by this tool before submission. It is a third, independent
measurement axis alongside the synthetic and real-panel corpora. It makes no claim beyond the raw,
reviewed records it contains, and computes no rate until there are enough of them to mean anything.

## Why it starts empty

Synthetic and real-panel data exist in bulk on day one. Real Apple outcomes cannot be manufactured —
they arrive one submission at a time, over weeks. `ledger.json` seeds `[]` and grows only as reviewed
outcomes are contributed.

## Record schema

Each element of `ledger.json` is one outcome record:

| field | meaning |
|---|---|
| `id` | stable id, e.g. `2026-07-02-appref01` — never derived from real app identity |
| `app_ref` | anonymized label; NEVER a real bundle id, company, or app name unless the submitter explicitly discloses it |
| `precheck_version` | `PRECHECK_VERSION` at scan time |
| `scan_date` | ISO date the scan was run |
| `verdict_at_submission` | `GREEN` / `YELLOW` / `RED` from `verdict.sh` at submission time |
| `findings_snapshot` | array of `{rule_id, severity, guideline}` from `scan.sh --format json`, **file/line stripped** |
| `submission_date` | ISO date submitted to App Store review |
| `apple_decision` | `approved` or `rejected` |
| `apple_decision_date` | ISO date of Apple's decision |
| `rejected_guidelines` | Apple's cited guideline number(s), e.g. `["3.1.2"]`; `[]` if approved |
| `matched_rule_ids` | human-mapped rule_id(s) that correspond to the cited guideline(s) |
| `outcome_label` | one of the four labels below |
| `evidence_kept_privately` | `true`/`false` — the submitter attests they retain off-repo evidence |
| `reviewed_by` | maintainer who reviewed the record before merge |
| `notes` | free text: mapping caveats, ambiguity |

### `outcome_label` taxonomy (app-level)

- `predicted-and-flagged` — Apple rejected for guideline G; the tool had already FAILed/WARNed on a rule mapped to G.
- `missed` — Apple rejected for guideline G; the tool had no finding mapped to G (a real recall gap; the most valuable record).
- `approved-clean` — app approved; the tool had 0 FAIL at submission.
- `approved-with-warns-unaddressed` — app approved; the tool had ≥1 WARN still present (suggestive, not proof, that the WARN wasn't blocking).

## Privacy & anonymization

- No real bundle id, company, or app name unless the submitter explicitly opts in.
- **No verbatim Apple Resolution Center text** is stored — `notes` is a free-text summary only.
- The repo stores no evidence; `evidence_kept_privately` records that the submitter retains it off-repo.

## Contribution

Contribute via a GitHub issue (template: "App Store outcome") with the anonymized fields, which a
maintainer reviews and merges into `ledger.json` as a PR. There is no telemetry; every record is
human-reviewed before merge and carries `reviewed_by`.

## Honesty

`scorecard-outcomes.sh` computes **no rate** below a sample-size floor of 10 records — it shows only
a raw tally. Once at/above the floor, it may show a directional recall estimate with a permanent
survivorship-bias caveat: apps whose FAILs were fixed before submission never produce a rejection
record, so FAIL-severity choices cannot be validated against real rejections.
