# Design — Suppression & Scorecard (Direction #1, Phases 2–3)

- **Date:** 2026-07-01
- **Status:** Approved (implementation design)
- **Author:** Berkay Turk
- **Extends:** [`2026-06-30-measurement-structured-findings-design.md`](./2026-06-30-measurement-structured-findings-design.md)

This is the implementation-level design for **Phase 2 (suppression)** and **Phase 3
(validation corpus + scorecard)**, resolving the decisions the original design left open
once Phase 1 landed on `main` (PR #12). It supersedes §5 and §6 of the parent design where
they conflict.

## 0. State after Phase 1 (facts that drive this design)

- `scan.sh` routes every finding through `pass()`/`warn()`/`fail()`. Phase 1 gave them the
  signature `<msg> [<file>] [<line>]` and each appends a JSONL record to `$FINDINGS_TMP`.
- Every `§` section is tagged with `set_rule "<slug>"`; `_CURRENT_RULE` carries the rule-id
  into `_record`. The 41-slug catalog lives in `scripts/findings.sh`.
- `render_json` already filters `suppressed==false` for the summary counts but emits **all**
  findings in `findings[]` — so suppression only needs to **flip the `suppressed` flag**.
- **Gap found:** none of the 78 `fail/warn/pass` call sites currently pass `file`/`line` —
  every finding has `file:null, line:null`. Path-scoped and inline suppression need location
  data, so file/line plumbing is prerequisite work (see §1.4).
- The text verdict is computed by `verdict.sh`, which counts anchored `^FAIL:`/`^WARN:` lines
  from `scan.sh`'s stdout. **Consequence:** for suppression to affect the text verdict, a
  suppressed finding's line must be **absent from stdout** — retroactive un-printing is
  impossible, so suppression must be decided *at emit time* inside the helpers (§1.1).
- Exactly **7 evidence lines** print after a finding via `echo "$var" | sed 's/^/      /'`
  (lines 266, 421, 530, 572, 665, 683, 892). Suppressing a finding must also drop its
  evidence, or the text output gets orphaned indented blocks (§1.2).

## 1. Phase 2 — Suppression

### 1.1 Emit-time suppression in the helpers (keystone)

The helpers decide suppression before echoing:

```sh
fail() {                            # $1=msg  $2=file  $3=line
  if is_suppressed "$_CURRENT_RULE" "${2:-}" "${3:-}"; then
    _record_suppressed FAIL "$1" "${2:-}" "${3:-}"    # JSONL suppressed:true; bump counter; _LAST_SUPPRESSED=1
  else
    echo "FAIL: $1"; _record FAIL "$1" "${2:-}" "${3:-}"; _LAST_SUPPRESSED=0
  fi
}
# warn()/pass() identical, swapping the severity token and prefix.
```

Properties:
- A suppressed FAIL never prints `FAIL:` → `verdict.sh` never counts it → **a suppressed FAIL
  no longer forces RED**. Same for WARN vs the YELLOW threshold.
- The JSON path is unchanged: `render_json` already counts `suppressed==false` and lists all.
- **Byte-identity:** with no `.precheck-ignore` and no inline markers, `is_suppressed` is
  always false, nothing is dropped, no footer prints → output is byte-for-byte today's.

### 1.2 Evidence lines

Add one helper and migrate the 7 sites:

```sh
detail() { [[ "${_LAST_SUPPRESSED:-0}" == 1 ]] || printf '%s\n' "$1" | sed 's/^/      /'; }
```

`echo "$banned_hits" | sed 's/^/      /'` → `detail "$banned_hits"`. When the preceding
finding was suppressed, its evidence is skipped; otherwise output is identical.

### 1.3 `scripts/suppress.sh` (new, sourced)

Bash 3.2 compatible — **no associative arrays**; parsed rules live in newline-delimited string
vars (or temp files).

- `load_precheck_ignore [root]` — read `<root>/.precheck-ignore`. Per non-blank, non-comment
  line, strip any trailing `# comment`, then split into `token1 [token2]`:
  - `token1` **is a catalog rule-id** and no `token2` → suppress that rule everywhere
    (append to `_SUPP_RULES`).
  - `token1` is a rule-id **and** `token2` present → path-scoped (append
    `rule<TAB>glob` to `_SUPP_RULE_PATH`).
  - `token1` is **not** a rule-id (a path glob) → exclude that path from scanning
    (append to `_SUPP_PATHS`).
- `precheck_prune_globs` — echo `_SUPP_PATHS` so `scan.sh` appends them to its `find` PRUNE
  array and `grep --exclude-dir` list (pre-filter; those paths are never scanned).
- `is_suppressed <rule> <file> <line>` → exit 0 (suppressed) and set `_SUPP_REASON` when:
  1. `rule` ∈ `_SUPP_RULES`, **or**
  2. a `(rule, glob)` in `_SUPP_RULE_PATH` matches `file` (fnmatch via `case`), **or**
  3. **inline:** `file` and `line` are non-empty and the source at `file:line` — or the line
     directly above it — contains a real comment opener (`//`, `#`, `<!--`) followed by
     `precheck:ignore` optionally then `<rule>`. A bare `precheck:ignore` matches any rule;
     `precheck:ignore <rule>` matches only that rule. Prose merely mentioning the string
     (not after a comment opener) is **not** a directive.

Unknown catalog rule-ids in `.precheck-ignore` are reported (one stderr note), not silently
ignored — a misspelled rule-id that suppresses nothing should be visible.

### 1.4 file/line plumbing (prerequisite; implemented first)

Thread `<file> [<line>]` into the checks with a clear single location so path-scoped and
inline suppression have data to match. Examples: §11 private-api (grep emits `file:line:` —
extract the first), §1 privacy-manifest & §2 usage-description & §23 ATS (Info.plist /
`PrivacyInfo.xcprivacy` path), metadata char-limit / placeholder / misleading-marketing
checks (the offending metadata file). Roughly 15–25 checks get a location; genuinely
location-less advisory checks keep `""`/null (valid per parent §3.1).

- **Byte-identity:** `file`/`line` are extra args; the text branch prints only `$1`, so text
  output does not change. A golden test asserts this.
- A test asserts every check that *should* carry a location does (guards against regressions).

### 1.5 Transparency (no silent caps)

- `_SUPPRESSED_COUNT` is incremented by `_record_suppressed`.
- **Text mode:** after all checks, if `_SUPPRESSED_COUNT > 0`, print one footer line, e.g.
  `(N finding(s) suppressed via .precheck-ignore)`. It is not `^FAIL/WARN/PASS`, so
  `verdict.sh` ignores it. When `N == 0` no footer prints (byte-identity).
- **JSON mode:** `summary.suppressed` already reports `N`; each finding keeps its
  `suppressed` boolean. Suppressed findings are **never** dropped from `findings[]`.

## 2. Phase 3 — Validation corpus + scorecard

### 2.1 Synthetic corpus (`corpus/synthetic/labels.json`)

Deterministic; reuses the 11 `tests/fixtures/*`. One entry per fixture:

```json
{
  "risky-app": { "expect_fire": ["private-api", "ats-arbitrary-loads"],
                 "expect_absent": ["realmoney-gambling", "mdm"] },
  "clean-app": { "expect_fire": [], "expect_absent": ["private-api", "..."] }
}
```

Harness runs `scan.sh --format json` in each fixture and, per rule-id:
- **TP** = in `expect_fire` and fired; **FN** = in `expect_fire` and did not fire;
- **FP** = in `expect_absent` and fired; **TN** = in `expect_absent` and did not fire.

### 2.2 Real panel (`corpus/real/`)

- `manifest.json` — 10–20 permissively-licensed (MIT / Apache-2.0 / BSD / MPL-2.0) open-source
  iOS / React-Native apps, each pinned: `{ "name", "repo", "commit", "license" }`. Candidate
  set (final list confirmed with per-repo license verification during planning): Wikipedia-iOS
  (MIT), DuckDuckGo/iOS (Apache-2.0), Kickstarter/ios-oss (Apache-2.0), firefox-ios (MPL-2.0),
  pocket-casts-ios (MPL-2.0), plus MIT React-Native sample apps.
- `labels.json` — each finding keyed by `{rule_id, file, line, commit}` → `"TP"|"FP"`.
  Candidate labels are generated by running the scanner; a one-time **human pass** finalizes
  them (the label is a human judgement, not the tool's).

### 2.3 `scripts/scorecard.sh` (new)

- **default** — run the synthetic corpus, compute per-rule and aggregate
  precision = TP/(TP+FP) and recall = TP/(TP+FN), regenerate `docs/scorecard.md`.
- `--real` — shallow-clone each `manifest.json` app at its pinned commit, run the scanner,
  join findings with `labels.json`, report real-code precision / false-positive rate. Recall
  on the real panel is bounded by labeled known issues and reported as such.
- `--check` — regenerate the synthetic scorecard to a temp file and diff against
  `docs/scorecard.md`; **fail** if stale, or if aggregate synthetic precision drops below a
  declared floor. Deterministic and network-free.

### 2.4 `docs/scorecard.md` (generated)

Methodology; corpus description (synthetic vs real, N apps, commit pins); a per-rule table;
aggregate numbers; and a mandatory **honesty section**:

> Synthetic measures intended-behavior fidelity. Real-panel precision measures the
> false-positive rate on real open-source code. **Neither claims agreement with Apple's
> actual review decisions.** Recall is bounded by labeled known issues and is not exhaustive.

A CI lint asserts this caveat text is present (guards against over-claiming edits).

### 2.5 CI

- **Blocking (PR CI):** `scripts/scorecard.sh --check` on the synthetic corpus — fast,
  deterministic, no network.
- **Non-blocking / scheduled:** a separate job runs the real panel (network clones) so PR CI
  stays fast and reproducible.

## 3. Files

| File | Role |
|---|---|
| `skills/appstore-precheck/scripts/scan.sh` | helpers gain emit-time suppression + `detail()`; source `suppress.sh`; PRUNE gets `precheck_prune_globs`; file/line threaded into locatable checks; text footer when `N>0` |
| `skills/appstore-precheck/scripts/findings.sh` | add `_record_suppressed` + `_SUPPRESSED_COUNT` (render_json unchanged) |
| `skills/appstore-precheck/scripts/suppress.sh` (new, sourced) | `.precheck-ignore` + inline parsing & `is_suppressed` |
| `scripts/scorecard.sh` (new) | corpus runner, metrics, regenerate `docs/scorecard.md`; `--real`, `--check` |
| `corpus/synthetic/labels.json` (new) | per-fixture expected fire/absent rule-ids |
| `corpus/real/manifest.json` + `labels.json` (new) | pinned real apps + human TP/FP labels |
| `docs/scorecard.md` (new, generated) | published precision/recall scorecard |
| `tests/test-suppress.sh`, `tests/test-scorecard.sh` (new); `tests/test-findings.sh` (extended) | TDD coverage |

## 4. Testing (TDD)

- **suppress:** rule-id line removes the finding and increments `suppressed`; rule+path scoped
  match; inline marker on-line and line-above both work; path-only line prevents scanning that
  path; a suppressed FAIL no longer forces RED; **byte-identity** with no `.precheck-ignore`;
  suppressed count equals findings removed (nothing silently dropped); prose mention of the
  marker is **not** a directive; unknown rule-id in the ignore file is reported.
- **file/line:** locatable checks carry `file`/`line`; text output byte-identical (golden).
- **scorecard:** metric math on a tiny known corpus; `--check` detects a stale scorecard and a
  precision regression below the floor; the honesty caveat text is present.

## 5. Invariants preserved

- **READ-ONLY** — suppression and scorecard code never edit code/metadata/assets; the only
  side effect remains `verdict.sh --apply`'s `.precheck-pass` token.
- **No competitor name** anywhere (repo / PR / commit / file).
- **Text default byte-identical** — guaranteed by emit-time suppression + null-safe file/line +
  footer-only-when-`N>0`, all covered by golden tests.
- **Version lockstep + TDD** — tests first; version bump handled at release per repo process.

## 6. Sequencing

1. file/line plumbing + golden byte-identity test.
2. `suppress.sh` + helper integration + `.precheck-ignore` (rule-id, path-scoped, path-exclude)
   + inline + footer; `test-suppress.sh`.
3. Synthetic corpus + `scorecard.sh` (default + `--check`) + `docs/scorecard.md` + CI blocking
   job; `test-scorecard.sh`.
4. Real panel: `manifest.json` (license-verified) + candidate `labels.json` + `--real` +
   non-blocking CI job. Human label review before publishing real numbers.
5. Whole-branch Opus review → PR.
