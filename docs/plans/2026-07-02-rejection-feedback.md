# Rejection-Outcome Feedback Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a committed real-App-Store-outcome ledger and a deterministic, honesty-floored "Real App Store outcomes" section to `docs/scorecard.md`, without touching the scan/verdict path.

**Architecture:** A new `corpus/outcomes/ledger.json` (committed, starts `[]`) is summarized by a new standalone `scripts/scorecard-outcomes.sh` (pure bash+jq, offline, deterministic). Because the ledger is local and committed, the section is baked into the generated `docs/scorecard.md` and covered by the existing blocking `scorecard.sh --check` — no network, no new CI job.

**Tech Stack:** bash 3.2, `jq` (already required), GitHub issue templates.

## Global Constraints

- READ-ONLY for the user's project. `corpus/outcomes/` is the tool's own measurement state.
- No competitor name anywhere.
- Honesty: never compute a rate below the sample-size floor (10); distinguish real Apple outcomes from synthetic/real-panel labels; permanent survivorship-bias caveat once a rate is shown.
- Offline / zero-dependency / byte-identical CLI: `scan.sh`, `bin/cli.js`, `action.yml`, `install.sh`, `verdict.sh` UNTOUCHED. This is reporting-side only, reading a committed local ledger (no network).
- Verdict determinism untouched: never wire outcome data into `verdict.sh`/`scan.sh`.
- Sample-size floor is a documented constant `OUTCOMES_FLOOR=10`.
- bash 3.2 compatible.
- NO version bump in-branch (bump at release).
- Register any new test suite in `tests/all.sh` and new scripts/JSON in `.github/workflows/ci.yml`.

---

### Task 1: `corpus/outcomes/` — ledger + README + CI JSON validation

**Files:**
- Create: `corpus/outcomes/ledger.json`
- Create: `corpus/outcomes/README.md`
- Modify: `.github/workflows/ci.yml` (add `corpus/outcomes/ledger.json` to the "Validate JSON" list)

**Interfaces:**
- Produces: `corpus/outcomes/ledger.json` — a JSON array of outcome records (empty `[]` initially). Consumed by `scorecard-outcomes.sh` (Task 2). Record fields: `id, app_ref, precheck_version, scan_date, verdict_at_submission, findings_snapshot[], submission_date, apple_decision, apple_decision_date, rejected_guidelines[], matched_rule_ids[], outcome_label, evidence_kept_privately, reviewed_by, notes`. `outcome_label` ∈ {`predicted-and-flagged`, `missed`, `approved-clean`, `approved-with-warns-unaddressed`}.

- [ ] **Step 1: Create the empty ledger**

```bash
mkdir -p corpus/outcomes
printf '[]\n' > corpus/outcomes/ledger.json
```

- [ ] **Step 2: Verify it is valid JSON**

Run: `jq empty corpus/outcomes/ledger.json && echo "valid"`
Expected: `valid`.

- [ ] **Step 3: Create `corpus/outcomes/README.md`**

```markdown
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
```

- [ ] **Step 4: Add the ledger to CI JSON validation**

In `.github/workflows/ci.yml`, in the "Validate JSON" `for f in ... ` list, add a line after `corpus/real/labels.json \`:
```yaml
                   corpus/outcomes/ledger.json \
```

- [ ] **Step 5: Commit**

```bash
git add corpus/outcomes/ledger.json corpus/outcomes/README.md .github/workflows/ci.yml
git commit -m "feat(outcomes): committed real-outcome ledger (empty) + schema/privacy README + CI json-validate"
```

---

### Task 2: `scripts/scorecard-outcomes.sh` + unit test

**Files:**
- Create: `scripts/scorecard-outcomes.sh`
- Create: `tests/test-scorecard-outcomes.sh`
- Modify: `tests/all.sh` (add `test-scorecard-outcomes.sh` to `SUITE`)
- Modify: `.github/workflows/ci.yml` (add `scripts/scorecard-outcomes.sh` and `tests/test-scorecard-outcomes.sh` to the shellcheck file list)

**Interfaces:**
- Consumes: `corpus/outcomes/ledger.json` (Task 1); overridable via env `OUTCOMES_LEDGER` (for tests).
- Produces: `scripts/scorecard-outcomes.sh` — prints the "Real App Store outcomes (n=N)" markdown section to stdout. Consumed by `scorecard.sh` (Task 3).

- [ ] **Step 1: Write the failing unit test `tests/test-scorecard-outcomes.sh`**

```bash
#!/usr/bin/env bash
# tests/test-scorecard-outcomes.sh — scorecard-outcomes.sh section rendering + honesty floor.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/_assert.sh
source "$ROOT/tests/_assert.sh"
SO="$ROOT/scripts/scorecard-outcomes.sh"

section "empty ledger -> no outcomes section, no rate"
tmp="$(mktemp -d)"; printf '[]\n' > "$tmp/l.json"
out="$(OUTCOMES_LEDGER="$tmp/l.json" bash "$SO")"
assert_contains "$out" "Real App Store outcomes (n=0)" "empty shows n=0 heading"
assert_contains "$out" "No real App Store outcomes recorded yet" "empty shows placeholder"
assert_absent "$out" "%" "no percentage when empty"
rm -rf "$tmp"

section "small ledger (n=3) -> raw tally, too-small note, no rate"
tmp="$(mktemp -d)"
cat > "$tmp/l.json" <<'JSON'
[
 {"outcome_label":"predicted-and-flagged","apple_decision":"rejected"},
 {"outcome_label":"missed","apple_decision":"rejected"},
 {"outcome_label":"approved-clean","apple_decision":"approved"}
]
JSON
out="$(OUTCOMES_LEDGER="$tmp/l.json" bash "$SO")"
assert_contains "$out" "Real App Store outcomes (n=3)" "n=3 heading"
assert_contains "$out" "too small to compute a meaningful rate" "too-small note present"
assert_absent "$out" "%" "no percentage below the floor"
assert_absent "$out" "Survivorship-bias" "no survivorship caveat below floor (no rate shown)"
rm -rf "$tmp"

section "at floor (n=10) -> tally + directional line + survivorship caveat"
tmp="$(mktemp -d)"
{
  echo "["
  for i in $(seq 1 6); do echo "{\"outcome_label\":\"predicted-and-flagged\",\"apple_decision\":\"rejected\"},"; done
  for i in $(seq 1 3); do echo "{\"outcome_label\":\"missed\",\"apple_decision\":\"rejected\"},"; done
  echo "{\"outcome_label\":\"approved-clean\",\"apple_decision\":\"approved\"}"
  echo "]"
} > "$tmp/l.json"
jq empty "$tmp/l.json"    # sanity: valid JSON
out="$(OUTCOMES_LEDGER="$tmp/l.json" bash "$SO")"
assert_contains "$out" "Real App Store outcomes (n=10)" "n=10 heading"
assert_contains "$out" "9 real rejections" "directional line counts rejections (6 flagged + 3 missed)"
assert_contains "$out" "Survivorship-bias caveat" "survivorship caveat present at/above floor"
rm -rf "$tmp"

if (( fails == 0 )); then echo "test-scorecard-outcomes: OK"; else echo "test-scorecard-outcomes: $fails FAILURE(S)"; exit 1; fi
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/test-scorecard-outcomes.sh`
Expected: FAIL — `scripts/scorecard-outcomes.sh` does not exist.

- [ ] **Step 3: Implement `scripts/scorecard-outcomes.sh`**

```bash
#!/usr/bin/env bash
# scorecard-outcomes.sh — print the "Real App Store outcomes" markdown section from the committed
# outcomes ledger. Pure bash + jq, offline, deterministic. Because it reads a LOCAL committed ledger
# (no network, unlike --real), the section is safe to bake into the generated scorecard + --check.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LEDGER="${OUTCOMES_LEDGER:-$ROOT/corpus/outcomes/ledger.json}"
OUTCOMES_FLOOR=10

n=0
if [[ -f "$LEDGER" ]]; then
  n="$(jq 'length' "$LEDGER" 2>/dev/null || echo 0)"
  [[ "$n" =~ ^[0-9]+$ ]] || n=0
fi

echo "## Real App Store outcomes (n=$n)"
echo
echo "Real Apple review outcomes, independently labelled — distinct from the synthetic and real-panel"
echo "measurements above. Neither an approval nor a rejection here proves a finding's correctness in"
echo "general. See \`corpus/outcomes/README.md\`."
echo

if [[ "$n" -eq 0 ]]; then
  echo "_No real App Store outcomes recorded yet. This section populates as outcomes are contributed"
  echo "and reviewed (see \`corpus/outcomes/README.md\`)._"
  exit 0
fi

tally() { jq -r --arg l "$1" '[.[]|select(.outcome_label==$l)]|length' "$LEDGER"; }
pf="$(tally predicted-and-flagged)"
ms="$(tally missed)"
ac="$(tally approved-clean)"
aw="$(tally approved-with-warns-unaddressed)"

echo "| outcome | count |"
echo "|---|---|"
echo "| predicted-and-flagged (rejected; tool had flagged the cited guideline) | $pf |"
echo "| missed (rejected; tool had no finding for the cited guideline) | $ms |"
echo "| approved-clean (approved; 0 FAIL at submission) | $ac |"
echo "| approved-with-warns-unaddressed (approved; >=1 WARN present) | $aw |"
echo

if [[ "$n" -lt "$OUTCOMES_FLOOR" ]]; then
  echo "**n=$n is too small to compute a meaningful rate; shown for transparency only.**"
  exit 0
fi

rej=$((pf + ms))
echo "Across $rej real rejections, the tool had already flagged the cited guideline in **$pf** of them"
echo "(directional, not a guarantee)."
echo
echo "**Survivorship-bias caveat:** apps whose FAILs were fixed before submission never produce a"
echo "rejection record, so FAIL-severity choices cannot be validated here — only WARN/PASS-level"
echo "judgment, and only in the \"approved anyway\" direction."
```

- [ ] **Step 4: Run to verify it passes**

Run: `bash tests/test-scorecard-outcomes.sh`
Expected: PASS — `test-scorecard-outcomes: OK`.

- [ ] **Step 5: Register the suite + CI shellcheck entries**

In `tests/all.sh` `SUITE=(...)` (after `test-scorecard.sh`), add:
```bash
  "test-scorecard-outcomes.sh" # scorecard-outcomes.sh tally + honesty floor
```
In `.github/workflows/ci.yml`, in the shellcheck file list, add after `scripts/scorecard-real.sh \`:
```yaml
                     scripts/scorecard-outcomes.sh \
```
and after `tests/test-scorecard.sh \`:
```yaml
                     tests/test-scorecard-outcomes.sh \
```

- [ ] **Step 6: Run full suite + shellcheck**

Run: `bash tests/all.sh && shellcheck -x --severity=warning scripts/scorecard-outcomes.sh tests/test-scorecard-outcomes.sh`
Expected: `SUITE PASSED (17 files)`; shellcheck clean.

- [ ] **Step 7: Commit**

```bash
git add scripts/scorecard-outcomes.sh tests/test-scorecard-outcomes.sh tests/all.sh .github/workflows/ci.yml
git commit -m "feat(outcomes): scorecard-outcomes.sh — deterministic tally section with honesty floor"
```

---

### Task 3: Bake the outcomes section into `scorecard.sh` + regenerate the card

**Files:**
- Modify: `scripts/scorecard.sh` (`render_card()` appends the section; add `--outcomes` mode; update Methodology text)
- Modify: `docs/scorecard.md` (regenerated)

**Interfaces:**
- Consumes: `scripts/scorecard-outcomes.sh` (Task 2).
- Produces: `docs/scorecard.md` now contains the outcomes section; `scorecard.sh --outcomes` prints it; `scorecard.sh --check` covers it.

- [ ] **Step 1: Update the Methodology text in `render_card()`**

In `scripts/scorecard.sh`, replace the Methodology intro line `Two corpora measure two different things:` with:
```
Three independent measurements, three methodologies:
```
and add, after the `- **Real panel** ...` bullet, a third bullet:
```
- **Real App Store outcomes** (\`corpus/outcomes/\`): real Apple review decisions (approved /
  rejected + cited guideline), human-reviewed, with a sample-size floor before any rate is shown.
  Measures **correlation with actual review outcomes** (honestly, only once enough data exists).
```

- [ ] **Step 2: Append the outcomes section in `render_card()`**

In the `render_card()` heredoc, between the "## Synthetic aggregate" table (the `| **precision** | $prec |` line) and the "## Honesty" heading, insert a blank line then the command substitution:
```
| **precision**   | $prec |

$(bash "$ROOT/scripts/scorecard-outcomes.sh")

## Honesty
```
(The heredoc is unquoted, so `$(...)` expands at generation time. The ledger is committed and read
offline, so the output is deterministic.)

- [ ] **Step 3: Add the `--outcomes` mode**

In the `case "${1:-}" in` block, add a branch before the `*)` fallback:
```bash
  --outcomes)
    bash "$ROOT/scripts/scorecard-outcomes.sh" ;;
```

- [ ] **Step 4: Regenerate the card**

Run: `bash scripts/scorecard.sh` (writes `docs/scorecard.md`)
Expected: `scorecard: wrote .../docs/scorecard.md`. The card now contains a "## Real App Store outcomes (n=0)" section.

- [ ] **Step 5: Verify `--check` passes and `--outcomes` prints the section**

Run:
```bash
bash scripts/scorecard.sh --check
bash scripts/scorecard.sh --outcomes | head -1
```
Expected: `scorecard: up to date (precision ... >= 0.80)`; the `--outcomes` head prints `## Real App Store outcomes (n=0)`.

- [ ] **Step 6: Run full suite + shellcheck**

Run: `bash tests/all.sh && shellcheck -x --severity=warning scripts/scorecard.sh`
Expected: `SUITE PASSED (17 files)` (existing `test-scorecard.sh` still passes: the honesty caveat and `--check` staleness behavior are intact); shellcheck clean.

- [ ] **Step 7: Commit**

```bash
git add scripts/scorecard.sh docs/scorecard.md
git commit -m "feat(outcomes): bake the outcomes section into the scorecard + --outcomes mode"
```

---

### Task 4: Contribution issue template + methodology note

**Files:**
- Create: `.github/ISSUE_TEMPLATE/app-store-outcome.md`
- Modify: `skills/appstore-precheck/references/methodology.md` (a note pointing at the outcomes measurement)

**Interfaces:** documentation / repo-config only.

- [ ] **Step 1: Create the issue template**

```markdown
---
name: App Store outcome
about: Report a real App Store review outcome for an app you scanned with appstore-precheck (anonymized)
title: "[outcome] "
labels: outcome
---

Thanks for contributing a real outcome. A maintainer will review and add it to
`corpus/outcomes/ledger.json`. **Do not include** your real bundle id, company, or app name unless
you choose to, and **do not paste verbatim Apple Resolution Center text** — summarize instead.

- **Anonymized app ref** (any label): 
- **appstore-precheck version at scan time**: 
- **Scan date** (YYYY-MM-DD): 
- **Verdict at submission** (GREEN / YELLOW / RED): 
- **Findings at submission** (rule_id + severity + guideline, from `scan.sh --format json`, no file paths): 
- **Submission date** (YYYY-MM-DD): 
- **Apple decision** (approved / rejected): 
- **Apple decision date** (YYYY-MM-DD): 
- **Cited guideline number(s)** (if rejected, e.g. 3.1.2): 
- **Which rule_id(s), if any, matched the cited guideline(s)**: 
- **Do you retain private evidence of the decision?** (yes / no): 
- **Notes / caveats**: 
```

- [ ] **Step 2: Add a methodology note**

In `skills/appstore-precheck/references/methodology.md`, add:
```markdown
### Real App Store outcomes (`corpus/outcomes/`)

Beyond the synthetic and real-panel corpora, the tool tracks real Apple review outcomes (approved /
rejected + cited guideline) in a committed, human-reviewed ledger (`corpus/outcomes/ledger.json`),
summarized in `docs/scorecard.md` by `scripts/scorecard-outcomes.sh`. It is honesty-floored: no rate
is computed below 10 records (raw tally only), and a permanent survivorship-bias caveat applies once
a rate is shown. It is a reporting layer only — it never influences the GREEN/YELLOW/RED verdict or
which rules fire. Contribute an outcome via the "App Store outcome" issue template.
```

- [ ] **Step 3: Verify suite + versions (no bump) + issue template is valid front-matter**

Run:
```bash
bash tests/all.sh && ./scripts/check-versions.sh
head -6 .github/ISSUE_TEMPLATE/app-store-outcome.md
```
Expected: `SUITE PASSED (17 files)`; `OK: versions match (1.10.0)`; the template's YAML front-matter (`name`/`about`/`title`/`labels`) prints.

- [ ] **Step 4: Commit**

```bash
git add .github/ISSUE_TEMPLATE/app-store-outcome.md skills/appstore-precheck/references/methodology.md
git commit -m "docs(outcomes): contribution issue template + methodology note"
```

---

## Self-Review

**Spec coverage:**
- Committed ledger + README (schema/privacy/contribution/honesty/floor) → Task 1. ✓
- `scorecard-outcomes.sh` deterministic section + floor logic (n=0 / <10 / >=10) → Task 2. ✓
- Baked into `docs/scorecard.md` + `--outcomes` mode + Methodology "three measurements" → Task 3. ✓
- `--check` covers it deterministically (committed offline ledger) → Task 3 Step 5. ✓
- Contribution issue template (maintainer-reviewed PR path) → Task 4. ✓
- Storage in-repo public / no verbatim Apple text / anonymized → Task 1 README + Task 4 template. ✓
- Floor = 10 constant → Task 2 impl + test. ✓
- Scan/verdict path untouched; no version bump → no task touches scan.sh/verdict.sh; Task 4 asserts 1.10.0. ✓
- CI: shellcheck + json-validate entries → Tasks 1, 2. ✓

**Placeholder scan:** every step has full content; no TBD/TODO. ✓

**Type/name consistency:** `scorecard-outcomes.sh`, `OUTCOMES_LEDGER` (test override), `OUTCOMES_FLOOR=10`, `outcome_label` values, and the section heading `Real App Store outcomes (n=N)` are used identically across Tasks 1-4. Suite count increments 16→17 (Task 2). ✓

**Note for executor:** the outcomes section is intentionally baked into the deterministic card (unlike the network `--real` panel) because the ledger is committed and read offline — this is what lets `--check` cover it. Do NOT move it to a non-blocking network job.
