# SARIF output + GitHub PR annotations

**Roadmap:** #4 (SARIF / GitHub PR-annotation integration). Follows #2 (smarter analysis: screenshot-vision, AST↔IOS_DIR, semantic guideline drift). Read-only, opt-in, **no auto-fix** — the READ-ONLY identity is preserved.

**Date:** 2026-07-02
**Target release:** v1.10.0 (bump at release, not in-branch)

## Problem

The scanner already emits structured findings (`scan.sh --format json`): an envelope
`{tool, version, verdict, summary{fail,warn,pass,suppressed}, findings[{rule_id, severity, guideline, message, file, line, suppressed}]}`.
CI/PR consumers cannot yet surface these findings as native GitHub code-scanning results or inline
PR annotations. This item adds a **SARIF 2.1.0** output and an **opt-in** GitHub Action path that
turns findings into PR annotations — without changing any default behavior and without ever
modifying the user's project (no auto-fix).

## Identity constraints (non-negotiable)

- **READ-ONLY** preserved. The scanner writes only to stdout; the Action redirects SARIF to a file
  in the CI workspace (a build artifact), never into the user's tracked project source. No auto-fix.
- **No competitor names** anywhere.
- **Offline, zero-dependency, deterministic:** SARIF is generated with `jq` (already required). No
  new runtime dependency. `scan.sh --format sarif` is fully offline and deterministic.
- **Opt-in / byte-identical default:** the new Action inputs default to off, so the Action's default
  output is unchanged. `--format text` and `--format json` output stay byte-identical.
- **bash 3.2** compatible.
- **Version lockstep**; bump at release across the 4 manifests. No in-branch bump.

## Scope

SARIF covers the **deterministic scan findings only** (the structured `findings[]`). Pierre
deep-review `REVIEW-FINDING` lines are agent-mode, not in the structured buffer, and
non-deterministic — they are **out of scope** for SARIF (SARIF is a deterministic CI artifact).

Included SARIF results: **non-suppressed FAIL and WARN** findings. PASS findings are not issues and
are excluded from `results[]`. Suppressed findings are excluded (consistent with the JSON envelope's
live-only verdict counting).

## Components

### 1. `scan.sh --format sarif` (core, reused by the Action and npx)

- Extend the `--format` accepted values from `text|json` to `text|json|sarif` (arg validation + the
  `--format=` form). Invalid value → the existing usage error (exit 64), message updated to list
  `text|json|sarif`.
- New sourced helper **`skills/appstore-precheck/scripts/sarif.sh`** with `render_sarif()`, mirroring
  `findings.sh`'s `render_json()` (pure `jq` over the `FINDINGS_TMP` buffer). Kept as its own file so
  `findings.sh` stays focused (coding-style: small focused files).
- In `scan.sh`, the existing json branch (`exec 4>&1 1>/dev/null` at ~line 205; `render_json` at
  ~line 1014) is generalized so `sarif` also suppresses text output and calls `render_sarif` at the
  end. (Both non-text formats swallow the human text and print their document to fd 4.)

**SARIF 2.1.0 document shape** (`render_sarif`, jq):
```
{
  "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
  "version": "2.1.0",
  "runs": [{
    "tool": { "driver": {
      "name": "appstore-precheck",
      "version": <tool version>,
      "informationUri": "https://github.com/berkayturk/appstore-precheck",
      "rules": [ <one per distinct ruleId present in results>:
        { "id": <rule_id slug>,
          "name": <rule_id slug>,
          "shortDescription": { "text": <guideline, e.g. "2.3.3"> },
          "helpUri": "https://github.com/berkayturk/appstore-precheck/blob/main/skills/appstore-precheck/references/methodology.md" } ]
    }},
    "results": [ <one per non-suppressed FAIL/WARN finding>:
      { "ruleId": <rule_id slug>,
        "level": <"error" for FAIL, "warning" for WARN>,
        "message": { "text": <finding message> },
        "locations": [ <present only when the finding has a file>:
          { "physicalLocation": {
              "artifactLocation": { "uri": <file> },
              "region": { "startLine": <line> } } } ] }
    ]
  }]
}
```

- A finding with no `file` → a result with an **empty `locations`** array (valid SARIF; GitHub shows
  it at the run level). A finding with `file` but no `line` → `artifactLocation` with no `region`.
- `ruleId` uses the finding's `rule_id`. Findings whose `rule_id` is empty (uncatalogued) still
  produce a result with `ruleId` omitted and no matching `rules[]` entry (valid SARIF).
- Empty findings buffer → a valid SARIF document with `results: []` and `rules: []`.

### 2. GitHub Action (`action.yml`) — two opt-in inputs, default off

- New input `sarif` (default `"false"`). When `true`:
  - run `scan.sh --format sarif > appstore-precheck.sarif` (in the workspace),
  - add a step `uses: github/codeql-action/upload-sarif@v3` with
    `sarif_file: appstore-precheck.sarif` (composite actions support `uses:` steps). GitHub renders
    the results as inline PR annotations + Security-tab entries. The consumer's workflow must grant
    `permissions: security-events: write` — documented in the README example.
- New input `annotations` (default `"false"`). When `true`:
  - the Action runs `scan.sh --format json`, iterates `findings[]` with `jq`, and emits a workflow
    command per non-suppressed FAIL/WARN: `::error file=<f>,line=<l>::<message>` /
    `::warning file=<f>,line=<l>::<message>` (omit `file=`/`line=` when absent). This gives inline
    PR annotations with no code-scanning setup required.
- Both inputs default off → the Action's existing behavior (scan + verdict + step summary + fail-on)
  is unchanged and byte-identical for current users. The two features are independent and can be
  enabled separately or together.
- Inputs are passed via env (never interpolated into the shell), matching the existing injection-safe
  pattern in `action.yml`.

### 3. `bin/cli.js` — expose `--format`

- Add a `--format text|json|sarif` passthrough (currently `bin/cli.js` does not expose `--format`).
  Validate the value (bad value → exit 64, matching scan.sh), pass it through to `scan.sh`. When a
  non-text format is requested, print the scanner's document verbatim (do not also run the text
  verdict rendering). Update `--help`. So `npx appstore-precheck --format sarif` works.

## Testing (TDD)

- **New suite `tests/test-sarif.sh`** (registered in `tests/all.sh`, shellcheck lint, CI): unit-test
  `render_sarif` by feeding a crafted `FINDINGS_TMP` buffer (reusing the `test-findings.sh` pattern of
  writing JSONL records) and asserting with `jq`:
  - top-level `version == "2.1.0"`, `$schema` present, `runs` length 1, driver name/version.
  - a FAIL record → a result with `level == "error"`; a WARN → `level == "warning"`.
  - a located finding → `results[].locations[0].physicalLocation.artifactLocation.uri` and
    `region.startLine` match; an unlocated finding → empty `locations`.
  - a suppressed record and a PASS record → **absent** from `results`.
  - distinct `rules[]` entries for the ruleIds present, each with `id`/`shortDescription`.
  - empty buffer → valid doc with `results == []`.
- **`--format` validation:** extend the existing format-arg test to accept `sarif` and reject an
  invalid value with exit 64.
- **End-to-end:** run `scan.sh --format sarif` on an existing fixture that produces a known FAIL/WARN
  and assert the SARIF contains the expected `ruleId` + `level` (jq).
- **Byte-identity:** `--format text` and `--format json` outputs unchanged across fixtures; the
  Action's default path (both new inputs off) unchanged.
- **CLI:** extend `tests/test-cli.sh` to cover `--format sarif` passthrough and bad-value exit 64.
- The Action's opt-in steps are validated structurally (YAML present, inputs default off); the
  `upload-sarif` network step is not executed in unit tests (documented, like other Action network
  steps).

## Out of scope (v1)

- SARIF for Pierre agent-mode deep-review findings (non-deterministic; not in the structured buffer).
- Any auto-fix or project mutation.
- SARIF `suppressions[]` modelling of `.precheck-ignore` (suppressed findings are simply excluded;
  revisit if consumers want suppressed findings surfaced as SARIF suppressions).
- Changing the GREEN/YELLOW/RED verdict or thresholds.

## Build method

superpowers subagent-driven-development: fresh implementer per task + two-stage review (spec +
quality); final Opus whole-branch review; `superpowers:finishing-a-development-branch`. New feature
branch; no direct commits to main; merge + release (v1.10.0) after the final review.
