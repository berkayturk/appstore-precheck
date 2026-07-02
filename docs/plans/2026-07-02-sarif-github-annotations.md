# SARIF Output + GitHub PR Annotations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `scan.sh --format sarif` output and an opt-in GitHub Action path that surfaces deterministic scan findings as SARIF (code-scanning) and inline PR annotations — read-only, no auto-fix, default behavior unchanged.

**Architecture:** A new sourced `sarif.sh` `render_sarif()` (pure jq over the existing findings buffer) mirrors `findings.sh`'s `render_json()`; `scan.sh` gains `--format sarif`; `bin/cli.js` exposes `--format`; `action.yml` gains two opt-in inputs (`sarif`, `annotations`) that upload SARIF and/or emit workflow-command annotations, both defaulting off.

**Tech Stack:** bash 3.2, `jq` (already required), GitHub Actions composite action, `github/codeql-action/upload-sarif@v3`.

## Global Constraints

- READ-ONLY: the scanner writes only to stdout; no auto-fix; no writes to the user's tracked source. The Action redirecting SARIF to a workspace file is a CI artifact, not a project write.
- No competitor name anywhere.
- Offline, zero-dependency, deterministic: SARIF is generated with `jq` (already required). No new runtime dependency. `scan.sh --format sarif` is fully offline/deterministic.
- Opt-in / byte-identical default: new Action inputs default off; `--format text` and `--format json` outputs stay byte-identical.
- bash 3.2 compatible.
- SARIF covers deterministic scan findings only (Pierre agent-mode findings are out of scope). Results = non-suppressed FAIL + WARN; PASS and suppressed excluded.
- NO version bump in-branch (bump at release across the 4 manifests).
- Register every new test suite in `tests/all.sh`.

---

### Task 1: `sarif.sh` — `render_sarif()` + unit tests

**Files:**
- Create: `skills/appstore-precheck/scripts/sarif.sh`
- Create: `tests/test-sarif.sh`
- Modify: `tests/all.sh` (add `test-sarif.sh` to `SUITE`)

**Interfaces:**
- Consumes: the `FINDINGS_TMP` JSONL buffer written by `findings.sh` `_record` (each line: `{rule_id, severity, guideline, message, file, line, suppressed}`), and `PRECHECK_VERSION`.
- Produces: `render_sarif()` — prints a SARIF 2.1.0 JSON document to stdout.

- [ ] **Step 1: Write the failing unit test `tests/test-sarif.sh`**

```bash
#!/usr/bin/env bash
# tests/test-sarif.sh — unit tests for sarif.sh render_sarif (SARIF 2.1.0 from findings buffer).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/_assert.sh
source "$HERE/_assert.sh"
# shellcheck source=skills/appstore-precheck/scripts/findings.sh
source "$HERE/../skills/appstore-precheck/scripts/findings.sh"
# shellcheck source=skills/appstore-precheck/scripts/sarif.sh
source "$HERE/../skills/appstore-precheck/scripts/sarif.sh"
PRECHECK_VERSION="9.9.9"

section "empty buffer -> valid empty SARIF"
FINDINGS_TMP="$(mktemp)"; : > "$FINDINGS_TMP"
out="$(render_sarif)"
assert_eq "2.1.0" "$(jq -r .version <<<"$out")" "version 2.1.0"
assert_eq "appstore-precheck" "$(jq -r '.runs[0].tool.driver.name' <<<"$out")" "driver name"
assert_eq "9.9.9" "$(jq -r '.runs[0].tool.driver.version' <<<"$out")" "driver version"
assert_eq "0" "$(jq -r '.runs[0].results|length' <<<"$out")" "no results when empty"
assert_eq "true" "$(jq -e 'has("$schema")' <<<"$out")" "schema present"
rm -f "$FINDINGS_TMP"

section "FAIL/WARN mapped; PASS + suppressed excluded; locations"
FINDINGS_TMP="$(mktemp)"; : > "$FINDINGS_TMP"
set_rule "private-api";          _record FAIL "2.5.1 Private API used" "ios/App/A.swift" "7"
set_rule "ats-arbitrary-loads";  _record WARN "1.6 ATS disabled" "ios/App/Info.plist" "12"
set_rule "min-functionality-nav";_record WARN "4.2 No nav"      # no file/line
set_rule "screenshots-per-locale"; _record PASS "2.3.3 Screenshots ok"
# a suppressed finding
_record_suppressed WARN "2.3.10 suppressed thing" "x" "1"
out="$(render_sarif)"
assert_eq "2" "$(jq -r '.runs[0].results|length' <<<"$out")" "only 2 issues (FAIL+WARN, no PASS/suppressed)"
assert_eq "error" "$(jq -r '.runs[0].results[]|select(.ruleId=="private-api").level' <<<"$out")" "FAIL -> error"
assert_eq "warning" "$(jq -r '.runs[0].results[]|select(.ruleId=="ats-arbitrary-loads").level' <<<"$out")" "WARN -> warning"
assert_eq "ios/App/A.swift" "$(jq -r '.runs[0].results[]|select(.ruleId=="private-api").locations[0].physicalLocation.artifactLocation.uri' <<<"$out")" "located finding uri"
assert_eq "7" "$(jq -r '.runs[0].results[]|select(.ruleId=="private-api").locations[0].physicalLocation.region.startLine' <<<"$out")" "located finding startLine"
assert_eq "0" "$(jq -r '.runs[0].results[]|select(.ruleId=="min-functionality-nav").locations|length' <<<"$out")" "unlocated finding -> empty locations"
assert_eq "true" "$(jq -e '.runs[0].tool.driver.rules|map(.id)|index("private-api")!=null' <<<"$out")" "rule metadata for private-api present"
assert_eq "2.5.1" "$(jq -r '.runs[0].tool.driver.rules[]|select(.id=="private-api").shortDescription.text' <<<"$out")" "rule shortDescription = guideline"
rm -f "$FINDINGS_TMP"

echo
if (( fails == 0 )); then echo "[test-sarif.sh] OK"; else echo "[test-sarif.sh] $fails FAILED"; fi
exit "$fails"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/test-sarif.sh`
Expected: FAIL — `sarif.sh` does not exist / `render_sarif` undefined.

- [ ] **Step 3: Implement `skills/appstore-precheck/scripts/sarif.sh`**

```bash
#!/usr/bin/env bash
# sarif.sh — SARIF 2.1.0 output layer for scan.sh. Sourced; pure jq over the
# findings buffer. No side effects, no output on load. bash 3.2 compatible.

: "${PRECHECK_VERSION:=dev}"

# render_sarif -> prints a SARIF 2.1.0 log built from the FINDINGS_TMP buffer.
# results[] = non-suppressed FAIL/WARN only (PASS + suppressed excluded);
# level: FAIL->error, WARN->warning. rules[] = distinct non-empty ruleIds present.
render_sarif() {
  local buf="${FINDINGS_TMP:-/dev/null}"
  local uri="https://github.com/berkayturk/appstore-precheck"
  local help="https://github.com/berkayturk/appstore-precheck/blob/main/skills/appstore-precheck/references/methodology.md"
  if [[ ! -s "$buf" ]]; then
    jq -nc --arg v "$PRECHECK_VERSION" --arg u "$uri" '
      {"$schema":"https://json.schemastore.org/sarif-2.1.0.json", "version":"2.1.0",
       "runs":[{"tool":{"driver":{"name":"appstore-precheck","version":$v,"informationUri":$u,"rules":[]}},"results":[]}]}'
    return 0
  fi
  jq -s --arg v "$PRECHECK_VERSION" --arg u "$uri" --arg help "$help" '
    (map(select(.suppressed==false and (.severity=="FAIL" or .severity=="WARN")))) as $issues
    | ($issues
        | map({id:.rule_id, text:.guideline})
        | map(select(.id != "" and .id != null))
        | unique_by(.id)
        | map({id:.id, name:.id, shortDescription:{text:.text}, helpUri:$help})) as $rules
    | ($issues | map(
        ( (if (.rule_id // "") == "" then {} else {ruleId:.rule_id} end)
          + {level:(if .severity=="FAIL" then "error" else "warning" end),
             message:{text:.message}}
          + (if .file != null
               then {locations:[{physicalLocation:(
                       {artifactLocation:{uri:.file}}
                       + (if .line != null then {region:{startLine:.line}} else {} end))}]}
               else {locations:[]} end) )
      )) as $results
    | {"$schema":"https://json.schemastore.org/sarif-2.1.0.json", "version":"2.1.0",
       "runs":[{"tool":{"driver":{"name":"appstore-precheck","version":$v,"informationUri":$u,"rules":$rules}},"results":$results}]}
  ' "$buf"
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/test-sarif.sh`
Expected: PASS — `[test-sarif.sh] OK`, exit 0.

- [ ] **Step 5: Register the suite in `tests/all.sh`**

In the `SUITE=(...)` array (after `test-image-dims.sh`), add:
```bash
  "test-sarif.sh"     # sarif.sh render_sarif SARIF 2.1.0 output
```

- [ ] **Step 6: Run full suite + shellcheck**

Run: `bash tests/all.sh && shellcheck -x --severity=warning skills/appstore-precheck/scripts/sarif.sh tests/test-sarif.sh`
Expected: `SUITE PASSED (15 files)`; shellcheck clean.

- [ ] **Step 7: Commit**

```bash
git add skills/appstore-precheck/scripts/sarif.sh tests/test-sarif.sh tests/all.sh
git commit -m "feat(sarif): render_sarif — SARIF 2.1.0 output from the findings buffer"
```

---

### Task 2: `scan.sh --format sarif` wiring + validation + end-to-end test

**Files:**
- Modify: `skills/appstore-precheck/scripts/scan.sh` (source sarif.sh ~line 17; `--format needs a value` message ~line 31; validation ~line 37; output-swallow ~line 205; render dispatch ~line 1014)
- Modify: `tests/test-sarif.sh` (append an end-to-end `scan.sh --format sarif` block + a bad-value exit-64 check)

**Interfaces:**
- Consumes: `render_sarif` (Task 1).
- Produces: `scan.sh --format sarif` prints a SARIF document; `--format` accepts `text|json|sarif`.

- [ ] **Step 1: Append the failing end-to-end assertions to `tests/test-sarif.sh`**

Add before the final `echo`/exit block:
```bash
section "scan.sh --format sarif end-to-end"
SCAN="$HERE/../skills/appstore-precheck/scripts/scan.sh"
tmp="$(mktemp -d)"; cp -R "$HERE/fixtures/sample-app/." "$tmp/"
e2e="$(cd "$tmp" && APPSTORE_PRECHECK_CONFIG=/nonexistent bash "$SCAN" --format sarif 2>/dev/null)"
rm -rf "$tmp"
assert_eq "2.1.0" "$(jq -r .version <<<"$e2e")" "e2e: valid SARIF version"
assert_eq "true" "$(jq -e '.runs[0].results|length > 0' <<<"$e2e")" "e2e: sample-app produces results"
assert_eq "true" "$(jq -e '[.runs[0].results[].level]|any(.=="error" or .=="warning")' <<<"$e2e")" "e2e: results carry error/warning levels"

section "scan.sh --format bad value -> exit 64"
tmp="$(mktemp -d)"; cp -R "$HERE/fixtures/clean-app/." "$tmp/"
( cd "$tmp" && APPSTORE_PRECHECK_CONFIG=/nonexistent bash "$SCAN" --format xml >/dev/null 2>&1 ); code=$?
rm -rf "$tmp"
assert_eq "64" "$code" "invalid --format exits 64"
```

- [ ] **Step 2: Run to verify the new assertions fail**

Run: `bash tests/test-sarif.sh`
Expected: the two new sections FAIL (`--format sarif` not yet accepted; currently exits 64 for sarif).

- [ ] **Step 3: Source `sarif.sh` in `scan.sh`**

After the `source ".../image-dims.sh"` line (added in the screenshot-vision feature, ~line 18), add:
```bash
source "$(dirname "${BASH_SOURCE[0]}")/sarif.sh"
```

- [ ] **Step 4: Update the `--format` value-missing message and the validation line**

Change the missing-value message (in the `--format)` case):
```bash
      if [[ $# -lt 2 ]]; then echo "scan.sh: --format needs a value (text|json|sarif)" >&2; exit 64; fi
```
Change the validation line (currently `[[ "$FORMAT" == json || "$FORMAT" == text ]] || {...}`):
```bash
[[ "$FORMAT" == json || "$FORMAT" == text || "$FORMAT" == sarif ]] || { echo "scan.sh: --format must be text|json|sarif" >&2; exit 64; }
```

- [ ] **Step 5: Generalize the output-swallow line (~205)**

Change:
```bash
if [[ "$FORMAT" == json ]]; then exec 4>&1 1>/dev/null; fi
```
to:
```bash
if [[ "$FORMAT" != text ]]; then exec 4>&1 1>/dev/null; fi
```

- [ ] **Step 6: Add the sarif dispatch at the render line (~1014)**

Change:
```bash
if [[ "$FORMAT" == json ]]; then exec 1>&4 4>&-; render_json; fi
```
to:
```bash
if [[ "$FORMAT" == json ]]; then exec 1>&4 4>&-; render_json;
elif [[ "$FORMAT" == sarif ]]; then exec 1>&4 4>&-; render_sarif; fi
```

- [ ] **Step 7: Run to verify the new assertions pass**

Run: `bash tests/test-sarif.sh`
Expected: PASS — `[test-sarif.sh] OK`.

- [ ] **Step 8: Verify text/json byte-identity + full suite + shellcheck**

Run:
```bash
bash tests/run.sh > /tmp/sarif-after.txt 2>&1
git stash push -- skills/appstore-precheck/scripts/scan.sh
bash tests/run.sh > /tmp/sarif-base.txt 2>&1
git stash pop
diff /tmp/sarif-base.txt /tmp/sarif-after.txt && echo "TEXT OUTPUT BYTE-IDENTICAL"
bash tests/all.sh && shellcheck -x --severity=warning skills/appstore-precheck/scripts/scan.sh
```
Expected: `TEXT OUTPUT BYTE-IDENTICAL`; `SUITE PASSED (15 files)`; shellcheck clean. (run.sh exercises `--format text`; json parity is covered by the unchanged `test-format-json.sh`.)

- [ ] **Step 9: Commit**

```bash
git add skills/appstore-precheck/scripts/scan.sh tests/test-sarif.sh
git commit -m "feat(sarif): scan.sh --format sarif (text output byte-identical)"
```

---

### Task 3: `bin/cli.js` — expose `--format`

**Files:**
- Modify: `bin/cli.js` (`parseArgs` add `--format`; `printHelp` add the flag; `main` skip verdict for non-text formats)
- Modify: `tests/test-cli.sh` (add `--format sarif` passthrough + bad-value assertions)

**Interfaces:**
- Consumes: `scan.sh --format` (Task 2).
- Produces: `npx appstore-precheck --format text|json|sarif`.

- [ ] **Step 1: Add failing CLI assertions to `tests/test-cli.sh`**

Append near the other sections:
```bash
section "clean-app --format sarif -> SARIF doc, exit 0"
run_cli "clean-app" --format sarif
assert_contains "$OUT" '"version": "2.1.0"' "cli passes --format sarif through to the scanner"
assert_eq "$CODE" "0" "non-text format exits 0"

section "--format bad value -> exit 64"
run_cli "clean-app" --format xml
assert_eq "$CODE" "64" "invalid --format exits 64"
```

- [ ] **Step 2: Run to verify the new assertions fail**

Run: `bash tests/test-cli.sh`
Expected: the two new sections FAIL (`--format` is an unknown option today → exit 64 for BOTH, so the sarif section fails on output/exit).

- [ ] **Step 3: Add `--format` to `parseArgs` in `bin/cli.js`**

In `parseArgs`, initialize and handle the flag. Change the opts initializer:
```javascript
  const opts = { dir: process.cwd(), failOn: 'RED', format: 'text' };
```
Add this handler before the final `fail(...)` line in the loop:
```javascript
    if (a === '--format') {
      const v = (argv[++i] || '').toLowerCase();
      if (v !== 'text' && v !== 'json' && v !== 'sarif') fail('--format must be text, json, or sarif', 64);
      opts.format = v;
      continue;
    }
```

- [ ] **Step 4: Pass the format through and skip verdict for non-text in `main`**

In `main`, change the scan invocation to pass the format:
```javascript
  const scanArgs = opts.format === 'text' ? [SCAN] : [SCAN, '--format', opts.format];
  const scan = spawnSync('bash', scanArgs, {
    cwd: opts.dir,
    encoding: 'utf8',
    maxBuffer: 32 * 1024 * 1024,
  });
```
After `process.stdout.write(scanOut);`, short-circuit non-text formats (they have no text `VERDICT:` line and should not be followed by the verdict block):
```javascript
  if (opts.format !== 'text') {
    process.exit(scan.status === 0 ? 0 : (scan.status || 0));
  }
```
(Leave the existing verdict/summary/fail-on logic below for the text path.)

- [ ] **Step 5: Update `printHelp`**

Add a line to the help text (next to `--fail-on`):
```javascript
    `  --format <fmt>      Output format: text (default), json, or sarif\n` +
```

- [ ] **Step 6: Run to verify the new assertions pass + full CLI suite**

Run: `bash tests/test-cli.sh`
Expected: PASS (all sections). If `node` is absent the suite self-skips (pre-existing behavior).

- [ ] **Step 7: Run full suite**

Run: `bash tests/all.sh`
Expected: `SUITE PASSED (15 files)`.

- [ ] **Step 8: Commit**

```bash
git add bin/cli.js tests/test-cli.sh
git commit -m "feat(sarif): expose --format text|json|sarif in the npx CLI"
```

---

### Task 4: `action.yml` — opt-in `sarif` + `annotations` inputs (default off)

**Files:**
- Modify: `action.yml` (2 new inputs; 2 conditional steps; pass via env)
- Create: `tests/test-action-sarif.sh` (structural assertions on action.yml defaults)
- Modify: `tests/all.sh` (add `test-action-sarif.sh`)

**Interfaces:**
- Consumes: `scan.sh --format sarif` and `scan.sh --format json` (Tasks 1-2).
- Produces: opt-in Action behavior; defaults preserve current byte-identical output.

- [ ] **Step 1: Write the failing structural test `tests/test-action-sarif.sh`**

```bash
#!/usr/bin/env bash
# tests/test-action-sarif.sh — structural guard: the new Action inputs are opt-in
# (default off) so default Action behavior is unchanged. The network upload step
# is not executed here (documented; validated by integration, not unit tests).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/_assert.sh
source "$HERE/_assert.sh"
A="$HERE/../action.yml"

body="$(cat "$A")"
section "opt-in inputs default off"
assert_contains "$body" "sarif:" "action declares a 'sarif' input"
assert_contains "$body" "annotations:" "action declares an 'annotations' input"
# both defaults must be the string false (opt-in)
assert_eq "2" "$(grep -cE 'default:[[:space:]]*"false"' "$A")" "both new inputs default to \"false\""
section "sarif upload + annotation wiring present"
assert_contains "$body" "github/codeql-action/upload-sarif" "uses upload-sarif for SARIF"
assert_contains "$body" "--format sarif" "produces SARIF via scan.sh --format sarif"
assert_contains "$body" "::warning" "emits warning annotations"
assert_contains "$body" "::error" "emits error annotations"

echo
if (( fails == 0 )); then echo "[test-action-sarif.sh] OK"; else echo "[test-action-sarif.sh] $fails FAILED"; fi
exit "$fails"
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/test-action-sarif.sh`
Expected: FAIL (inputs/steps not present yet).

- [ ] **Step 3: Add the two inputs to `action.yml`**

In the `inputs:` block (after `fail-on:`), add:
```yaml
  sarif:
    description: "Emit a SARIF file and upload it to GitHub code-scanning (needs permissions: security-events: write)."
    required: false
    default: "false"
  annotations:
    description: "Emit inline PR annotations (::error/::warning) for each FAIL/WARN finding."
    required: false
    default: "false"
```

- [ ] **Step 4: Add the SARIF + annotation steps to `action.yml`**

After the existing "Run appstore-precheck scan" step, add these steps (composite actions support step-level `if:` and `uses:`). Pass inputs via env, matching the existing injection-safe pattern:
```yaml
    - name: Generate SARIF
      if: ${{ inputs.sarif == 'true' }}
      shell: bash
      env:
        APC_WORKDIR: ${{ inputs.working-directory }}
        APC_ACTION_PATH: ${{ github.action_path }}
      run: |
        set -euo pipefail
        scan="$APC_ACTION_PATH/skills/appstore-precheck/scripts/scan.sh"
        cd "$APC_WORKDIR"
        bash "$scan" --format sarif > "$GITHUB_WORKSPACE/appstore-precheck.sarif"
    - name: Upload SARIF
      if: ${{ inputs.sarif == 'true' }}
      uses: github/codeql-action/upload-sarif@v3
      with:
        sarif_file: appstore-precheck.sarif
    - name: Emit PR annotations
      if: ${{ inputs.annotations == 'true' }}
      shell: bash
      env:
        APC_WORKDIR: ${{ inputs.working-directory }}
        APC_ACTION_PATH: ${{ github.action_path }}
      run: |
        set -euo pipefail
        scan="$APC_ACTION_PATH/skills/appstore-precheck/scripts/scan.sh"
        cd "$APC_WORKDIR"
        bash "$scan" --format json \
          | jq -r '.findings[]
                   | select(.suppressed==false and (.severity=="FAIL" or .severity=="WARN"))
                   | (if .severity=="FAIL" then "error" else "warning" end) as $lvl
                   | "::\($lvl)"
                     + (if .file then " file=\(.file)" + (if .line then ",line=\(.line)" else "" end) else "" end)
                     + "::\(.message)"'
```

- [ ] **Step 5: Run structural test + verify default behavior unchanged**

Run:
```bash
bash tests/test-action-sarif.sh
python3 -c "import yaml,sys; yaml.safe_load(open('action.yml')); print('action.yml valid YAML')"
```
Expected: `[test-action-sarif.sh] OK`; `action.yml valid YAML`. (The default `scan`+`verdict`+`step summary`+`fail-on` step is untouched, so a run with both inputs off behaves exactly as before.)

- [ ] **Step 6: Register the suite + run full suite + shellcheck**

Add to `tests/all.sh` `SUITE` (after `test-sarif.sh`):
```bash
  "test-action-sarif.sh" # action.yml opt-in SARIF/annotation inputs default off
```
Run: `bash tests/all.sh && shellcheck -x --severity=warning tests/test-action-sarif.sh`
Expected: `SUITE PASSED (16 files)`; shellcheck clean.

- [ ] **Step 7: Commit**

```bash
git add action.yml tests/test-action-sarif.sh tests/all.sh
git commit -m "feat(sarif): opt-in Action inputs — SARIF upload + inline PR annotations (default off)"
```

---

### Task 5: Documentation — README opt-in example + methodology note

**Files:**
- Modify: `README.md` (add an opt-in SARIF/annotations Action usage example + a bullet under checks/CI)
- Modify: `skills/appstore-precheck/references/methodology.md` (document the SARIF output + its scope)

**Interfaces:** documentation only.

- [ ] **Step 1: Add a README section**

In `README.md`, near the GitHub Action usage section, add:
````markdown
### SARIF & PR annotations (opt-in)

The Action can surface findings as GitHub code-scanning results and inline PR annotations. Both are
off by default; enable either or both:

```yaml
permissions:
  contents: read
  security-events: write   # required for SARIF upload
jobs:
  precheck:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: berkayturk/appstore-precheck@v1
        with:
          sarif: true         # upload SARIF to the Security tab + PR annotations
          annotations: true   # also emit inline ::error/::warning annotations
```

Locally / via npx: `npx appstore-precheck --format sarif > results.sarif`. The scan stays read-only;
nothing is auto-fixed.
````

- [ ] **Step 2: Add a methodology note**

In `references/methodology.md`, add:
```markdown
### SARIF output (`--format sarif`)

`scan.sh --format sarif` emits a SARIF 2.1.0 log built from the same structured findings as
`--format json` (pure `jq`, no new dependency). `results[]` contains the non-suppressed FAIL and
WARN findings (FAIL → `error`, WARN → `warning`); PASS and suppressed findings are excluded. Findings
that carry a `file`/`line` become SARIF `physicalLocation`s so GitHub can anchor PR annotations. Only
the deterministic scan findings are included — the agent-mode Pierre deep-review findings are not
(SARIF is a deterministic CI artifact). The GitHub Action uploads this via `upload-sarif` and/or
emits inline `::error`/`::warning` annotations, both opt-in.
```

- [ ] **Step 3: Verify suite + versions (no bump in-branch)**

Run: `bash tests/all.sh && ./scripts/check-versions.sh`
Expected: `SUITE PASSED (16 files)`; `OK: versions match (1.9.0)`.

- [ ] **Step 4: Commit**

```bash
git add README.md skills/appstore-precheck/references/methodology.md
git commit -m "docs(sarif): document --format sarif + opt-in Action SARIF/annotations"
```

---

## Self-Review

**Spec coverage:**
- `scan.sh --format sarif` core → Tasks 1 + 2. ✓
- New `sarif.sh` render_sarif (pure jq, mirrors render_json) → Task 1. ✓
- SARIF shape (schema/version/driver/rules/results), FAIL→error/WARN→warning, PASS+suppressed excluded, locations for file/line, empty→valid empty → Task 1 test + impl. ✓
- Scope = deterministic findings only → render_sarif reads only the findings buffer (Pierre lines never enter it). ✓
- `bin/cli.js --format` passthrough → Task 3. ✓
- Action opt-in `sarif` (upload-sarif) + `annotations` (workflow commands), default off/byte-identical → Task 4. ✓
- Tests registered in all.sh (test-sarif, test-action-sarif) → Tasks 1, 4. ✓
- Byte-identity text/json + Action default → Task 2 Step 8 (text) + Task 4 (defaults off) + unchanged test-format-json.sh. ✓
- Docs (README opt-in example w/ security-events: write, methodology) → Task 5. ✓
- No version bump in-branch → Task 5 Step 3 asserts 1.9.0. ✓

**Placeholder scan:** every step contains full code/commands; the `::error`/`::warning`/`TODO`-free content is real. No TBD. ✓

**Type/name consistency:** `render_sarif`, `sarif.sh`, `--format sarif`, opts.format, inputs `sarif`/`annotations` used identically across tasks. SARIF field names (`ruleId`, `level`, `physicalLocation`, `artifactLocation`, `region.startLine`, `shortDescription`) consistent between the Task 1 test and impl. Suite counts increment consistently: 14→15 (Task 1) →16 (Task 4). ✓

**Note for executor:** `render_sarif`'s jq builds keys like `"$schema"` as literal strings (jq does not interpolate `$` inside plain double-quoted object keys — only `\(...)` interpolates), so the SARIF `$schema` property is emitted literally. Do not "fix" it to a jq variable.
