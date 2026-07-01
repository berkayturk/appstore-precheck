# Design — Measurement & Structured Findings (Direction #1)

- **Date:** 2026-06-30
- **Status:** Draft (awaiting review)
- **Author:** Berkay Turk

## 1. Context & motivation

appstore-precheck (v1.5.2) is a pile of **unmeasured heuristics**: 41 static vectors (grep/awk)
plus 28 LLM "Pierre" deep-review checks. Its entire credibility rests on heuristics whose real
precision/recall nobody has measured — the positioning is honestly "static heuristic, n=1." We hit
the ceiling of the heuristic-accretion path this very cycle: three false positives were fixed in a
single session (§23 ATS, §27 kids double-count, §35 thin-wrapper noted).

An internal review of the landscape confirmed two things:
1. **No comparable tool publishes accuracy data.** Measuring and publishing precision/recall is
   open ground and a first-mover, defensible differentiator that aligns with our honesty brand.
2. **Config + inline suppression is table stakes.** Comparable tools ship a config file plus an
   inline `ignore` directive; we lack both. A suppression mechanism is parity, not a nice-to-have.

**Keystone insight:** scan.sh routes every finding through three central helpers — `pass()`,
`warn()`, `fail()`. Enhancing those helpers to also record a **structured finding** gives us
machine-readable output almost for free, without rewriting all 41 checks. That one change unlocks:
measurement (score per rule), suppression (suppress by rule-id), and later SARIF/JUnit (#4).

## 2. Goals / non-goals

### Goals
- G1. scan.sh can emit **structured findings as JSON** (`--format json`), in addition to today's text.
- G2. Every finding carries a **stable `rule_id`**, severity, guideline, message, and optional file/line.
- G3. A **`.precheck-ignore`** file + inline `# precheck:ignore` suppress findings transparently
  (suppressed count is always reported; never silently hidden).
- G4. A **validation corpus** (synthetic + real open-source apps) and a generated **scorecard**
  publish per-rule and aggregate precision/recall, with explicit honesty caveats.
- G5. **Backward compatibility:** text output stays the default and byte-compatible; all existing
  tests, `verdict.sh`, the npm CLI, the GitHub Action, and the skill keep working unchanged.

### Non-goals (explicitly out of scope here)
- SARIF / JUnit emitters (Direction #4 — Phase 1 here makes them trivial later).
- Vision on screenshots, AST analysis, IPA inspection (Direction #2).
- Local dynamic simulator tier (Direction #5).
- Rejection-outcome feedback loop (Direction #3).
- Confidence scoring per finding (candidate Phase 4; not built now).
- Any change to the READ-ONLY invariant.

## 3. Invariants

- **READ-ONLY preserved.** Suppression and scorecard code never edit code/metadata/assets. The
  only side effect remains the `.precheck-pass` token written by `verdict.sh --apply`.
- **TDD.** Tests for JSON shape, suppression behavior, and metric computation are written first.
- **Modularity** (per coding-style: many small files). New logic lives in dedicated sourced files,
  not bolted onto the already-835-line scan.sh.
- **Honesty.** The scorecard must never imply agreement with Apple's actual review decisions.

## 4. Phase 1 — Structured findings core

### 4.1 Mechanism
- The central `pass()`/`warn()`/`fail()` helpers (today: `fail() { echo "FAIL: $1"; }`, severity
  set is exactly `{FAIL, WARN, PASS}` — there is no INFO) get a new signature:
  `fail <rule_id> <message> [<file>] [<line>]` (and likewise for `warn`/`pass`). The text print is
  unchanged — they still emit `FAIL: <message>` from `$2`. Each call also appends one JSON object to
  a temp **JSONL** buffer (`$FINDINGS_TMP`) with `rule_id`, severity, `message`, and optional
  `file`/`line`. `guideline` is derived from the leading token of the message (e.g. `1.6`).
- At end of scan, a renderer assembles the final output:
  - `--format text` (default): exactly today's output — no change.
  - `--format json`: `jq` slurps the JSONL buffer into the envelope below. (`jq` is already a
    dependency used by the config layer.)

### 4.2 JSON envelope
```json
{
  "tool": "appstore-precheck",
  "version": "1.5.2",
  "verdict": "GREEN|YELLOW|RED",
  "summary": { "fail": 0, "warn": 2, "pass": 39, "suppressed": 1 },
  "findings": [
    {
      "rule_id": "ats-arbitrary-loads",
      "severity": "WARN",
      "guideline": "1.6",
      "message": "1.6 App Transport Security — NSAllowsArbitraryLoads=true ...",
      "file": "ios/App/Info.plist",
      "line": 12,
      "suppressed": false
    }
  ]
}
```
`file`/`line` are `null` when a check has no location (many advisory checks). The verdict in JSON
is computed by the same logic as `verdict.sh` (single source of truth; see 4.4).

### 4.3 Rule-id catalog
- Each `§1–§41` vector gets a stable kebab-case slug, defined once in `scripts/findings.sh`
  (e.g. `private-api`, `ats-arbitrary-loads`, `kids-ads-analytics`, `account-no-delete`,
  `siwa-parity`). The catalog is the contract for suppression, scorecard, and future SARIF rule IDs.
- A test asserts: every `warn/fail/pass` call site passes a rule-id that exists in the catalog, and
  rule-ids are unique. (Migrating all 41 call sites is mechanical; checks with no location pass `""`.)
- Deep-review (Pierre) checks are **out of scope for rule-ids in v1** — they are LLM-emitted, not
  scanner-emitted. The catalog covers the deterministic scanner only.

### 4.4 Verdict single-sourcing
- Today `verdict.sh` recomputes the verdict by counting `^FAIL:`/`^WARN:` text lines. To avoid two
  divergent verdict models (a real bug class), the JSON renderer computes
  counts from the structured buffer and applies the **same thresholds** (RED ≥1 FAIL; YELLOW ≥5 WARN;
  else GREEN). `verdict.sh`'s text path is unchanged; a follow-up may let it consume JSON, but that
  is not required for this spec.

## 5. Phase 2 — Suppression

### 5.1 `.precheck-ignore` (repo root, flat, greppable)
```
# comment
account-no-delete                 # suppress this rule everywhere
ats-arbitrary-loads  ios/Legacy/  # suppress this rule under a path
vendor/                           # ignore a path entirely (not scanned)
Pods/
```
Grammar per non-blank, non-comment line:
- `<rule-id>` → suppress that rule in all files.
- `<rule-id> <path-glob>` → suppress that rule for findings whose `file` matches the glob.
- `<path-glob>` (no rule-id) → exclude the path from scanning entirely (pre-filter).

### 5.2 Inline
- `# precheck:ignore` (bare) or `# precheck:ignore <rule-id>` on the flagged line, or on the line
  directly above it. Swift/ObjC use `//`; plist/XML use `<!-- -->`. Prose merely mentioning the
  marker is not a directive (must be a real comment opener).

### 5.3 Application point & transparency
- Suppression is applied in the structured layer, **after** collection and **before** rendering and
  before verdict counting: a suppressed finding does not count toward YELLOW/RED.
- The summary always reports `suppressed: N`. In text mode, a one-line footer notes `N suppressed`.
  Suppressed findings are never silently dropped (anti-pattern guard, mirrors `no silent caps`).
- Implemented in `scripts/suppress.sh`; depends on Phase 1 rule-ids and file/line.

## 6. Phase 3 — Validation corpus + scorecard

### 6.1 Corpus = synthetic + real (chosen strategy)
- **Synthetic** (`corpus/synthetic/`): reuse `tests/fixtures/*` plus a `labels.json` per fixture
  declaring `expect_fire: [rule_id...]` (true positives) and `expect_absent: [rule_id...]` (true
  negatives). Deterministic; measures **intended-behavior fidelity**.
- **Real panel** (`corpus/real/`): `manifest.json` lists 10–20 permissively-licensed open-source
  iOS / RN apps, each pinned by `{name, repo, commit, license}`. A harness clones each at its commit,
  runs the scanner, and a one-time human pass labels each finding `TP|FP` in `labels.json`
  (keyed by `rule_id` + `file` + `line` + `commit`). Measures **real-code precision (FP rate)** —
  the credible headline number.

### 6.2 Metrics
- Per-rule and aggregate **precision** = TP / (TP + FP).
- **Recall** = TP / (TP + FN), where FN = `expect_fire` rule-ids that did not fire. Meaningful for
  synthetic (ground truth is complete); for the real panel recall is bounded by labeled known issues
  and reported as such (not exhaustive).
- **False-positive rate** on the real panel as the marketing-credible figure.

### 6.3 Scorecard
- `scripts/scorecard.sh` runs the corpus, computes metrics, and regenerates **`docs/scorecard.md`**:
  methodology, corpus description (synthetic vs real, N apps, commit pins), a per-rule table, and
  aggregate numbers — with an explicit **honesty section**: "Synthetic measures intended-behavior
  fidelity; real-panel precision measures false-positive rate on real code; **neither claims
  agreement with Apple's actual review decisions**; recall is bounded by labeled known issues."
- A README badge/section links to the scorecard.

### 6.4 CI guard
- `scripts/scorecard.sh --check` fails CI if `docs/scorecard.md` is stale (regenerate against the
  synthetic corpus and diff) or if aggregate synthetic precision regresses below a floor. The real
  panel (network clones) runs in a separate, non-blocking or scheduled job to keep PR CI fast and
  deterministic.

## 7. Architecture / files

| File | Role |
|---|---|
| `skills/appstore-precheck/scripts/scan.sh` | helper signature gains `rule_id` + optional `file:line`; `--format` flag; sources `findings.sh`/`suppress.sh` |
| `scripts/findings.sh` (new, sourced) | rule-id catalog + JSONL buffer + JSON renderer |
| `scripts/suppress.sh` (new, sourced) | `.precheck-ignore` + inline parsing & filtering |
| `scripts/scorecard.sh` (new) | corpus runner, metrics, regenerates `docs/scorecard.md` |
| `corpus/synthetic/labels.json` (new) | per-fixture expected fire/absent rule-ids |
| `corpus/real/manifest.json` + `labels.json` (new) | pinned real apps + human TP/FP labels |
| `docs/scorecard.md` (new, generated) | published precision/recall scorecard |
| `tests/test-findings.sh`, `tests/test-suppress.sh`, `tests/test-scorecard.sh` (new) | TDD coverage |

## 8. Testing strategy (TDD)
- **findings:** JSON validates as JSON; envelope has required keys; every finding has a catalog
  rule-id; rule-ids unique; text output is byte-identical to pre-change (golden test).
- **suppress:** a `.precheck-ignore` rule removes the expected finding and increments `suppressed`;
  inline marker on-line and line-above both work; a suppressed FAIL no longer forces RED; nothing is
  silently dropped (suppressed count matches).
- **scorecard:** metric math on a tiny known corpus; `--check` detects a stale scorecard.

## 9. Risks & mitigations
- **Threading rule-id/file/line through 41 checks is tedious** → do the helpers + catalog first;
  migrate call sites incrementally; checks without a location pass `""`/null (valid).
- **Bash structured-data fragility** → use a JSONL temp file + `jq`, never bash associative arrays.
- **Two divergent verdict models** (the divergent-verdict bug class) → JSON verdict reuses the exact thresholds;
  one source of truth.
- **Real-app panel drift** (apps change) → pin every app to a commit; labels keyed to that commit.
- **Over-claiming in the scorecard** → mandatory honesty section; CI lint that the caveat text exists.

## 10. Sequencing
Phase 1 (structured findings) → Phase 2 (suppression) → Phase 3 (corpus + scorecard). Phases 1–2 are
small and unlock SARIF (#4) later; Phase 3 is the larger differentiator. Each phase is independently
shippable behind the unchanged text default.
