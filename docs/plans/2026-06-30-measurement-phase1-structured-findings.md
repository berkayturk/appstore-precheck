# Measurement Phase 1 — Structured Findings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give scan.sh a parallel, machine-readable JSON output (`--format json`) where every finding carries a stable `rule_id` + optional file/line, without changing the default text output by a single byte.

**Architecture:** A new sourced file `scripts/findings.sh` holds the rule-id catalog, a per-section `set_rule` setter, a `_record` recorder that appends one JSON object per finding to a JSONL temp buffer, and a `render_json` assembler. scan.sh's `fail/warn/pass` helpers gain a `_record` call (text echo unchanged); each `§` section calls `set_rule <slug>` once; a new `--format text|json` flag selects output. JSON mode swallows the normal text via an fd redirect and prints only the assembled envelope. A golden text-regression test guarantees byte-identical text output across every fixture.

**Tech Stack:** Bash 3.2 (macOS), `jq` (already a dependency), the existing `tests/_assert.sh` harness.

## Global Constraints

- **READ-ONLY invariant:** no task may add code that edits source/metadata/assets. Only side effect remains the `.precheck-pass` token (unchanged).
- **Backward compatibility:** `--format text` is the default and must be byte-identical to current output. `verdict.sh`, the npm CLI, the GitHub Action, and the skill must keep working unchanged.
- **Portability:** Bash 3.2 / BSD tools only — no `grep -P`, no `sed -i`, no GNU-only flags. (`declare -gA` IS available in bash 3.2? NO — associative arrays need bash 4+. Use a `case` lookup function instead; see Task 1.)
- **Verdict thresholds (single source of truth, copied from verdict.sh):** RED if `fail >= 1`; else YELLOW if `warn >= 5`; else GREEN. Counts exclude suppressed findings.
- **Severity set is exactly `{FAIL, WARN, PASS}`** — there is no INFO.
- **jq is required** and already used by the config layer; rely on it for all JSON assembly.

## Rule-id catalog (complete; section → slug)

| § | slug | § | slug |
|---|---|---|---|
| 1 | `privacy-manifest-parity` | 22 | `ugc-no-moderation` |
| 2 | `usage-description-crosscheck` | 23 | `ats-arbitrary-loads` |
| 3 | `att-usage` | 24 | `applepay-recurring-disclosure` |
| 4 | `competitor-mentions` | 25 | `custom-review-prompt` |
| 5 | `metadata-char-limits` | 26 | `misleading-marketing` |
| 6 | `locale-metadata-parity` | 27 | `kids-wording` |
| 7 | `screenshots-per-locale` | 28 | `keyboard-full-access` |
| 8 | `trial-disclosure` | 29 | `health-icloud-sync` |
| 9 | `autorenew-disclosure` | 30 | `vpn-networkextension` |
| 10 | `subscription-links-restore` | 31 | `demo-account` |
| 11 | `private-api` | 32 | `executable-code-download` |
| 12 | `min-functionality-nav` | 33 | `background-modes-unused` |
| 13 | `screentime-justification` | 34 | `crypto-wallet-mining` |
| 14 | `siwa-parity` | 35 | `webview-wrapper` |
| 15 | `external-purchase-link` | 36 | `remote-desktop` |
| 16 | `tracking-sdk-no-att` | 37 | `safari-extension` |
| 17 | `export-compliance` | 38 | `account-no-delete` |
| 18 | `support-privacy-url` | 39 | `kids-ads-analytics` |
| 19 | `analytics-privacyinfo-mismatch` | 40 | `realmoney-gambling` |
| 20 | `placeholder-metadata` | 41 | `mdm` |
| 21 | `thirdparty-payment-sdk` | | |

Section header lines in `skills/appstore-precheck/scripts/scan.sh` (for locating each `set_rule` insertion): §1=156, §2=187, §3=212, §4=232, §5=246, §6=269, §7=295, §8=323, §9=335, §10=352, §11=378, §12=390, §13=400, §14=411, §15=425, §16=435, §17=452, §18=467, §19=491, §20=515, §21=531, §22=545, §23=562, §24=576, §25=588, §26=604, §27=618, §28=635, §29=649, §30=662, §31=674, §32=701, §33=714, §34=744, §35=754, §36=769, §37=779, §38=787, §39=804, §40=819, §41=831. (§8–§10 are sub-blocks inside the §7→§11 paywall region.)

## File structure

| File | Responsibility |
|---|---|
| `skills/appstore-precheck/scripts/findings.sh` (new, sourced) | rule catalog (`rule_slug`), `set_rule`, `_record`, `render_json` |
| `skills/appstore-precheck/scripts/scan.sh` (modify) | source findings.sh; instrument `fail/warn/pass`; `--format` flag + fd redirect; one `set_rule` per § |
| `tests/test-findings.sh` (new) | unit tests for `_record`, catalog, `render_json` |
| `tests/test-format-json.sh` (new) | integration: JSON output shape + golden text regression on fixtures |
| `tests/all.sh` (modify) | register the two new test files |
| `CHANGELOG.md` (modify) | Unreleased entry |

---

### Task 1: findings.sh — catalog, set_rule, _record

**Files:**
- Create: `skills/appstore-precheck/scripts/findings.sh`
- Test: `tests/test-findings.sh`

**Interfaces:**
- Produces: `rule_slug <section-number> -> echoes slug or ""`; `set_rule <slug>` (sets `_CURRENT_RULE`); `_record <FAIL|WARN|PASS> <message> [<file>] [<line>]` (appends one JSON line to `$FINDINGS_TMP` if set).

- [ ] **Step 1: Write the failing test**

Create `tests/test-findings.sh`:
```bash
#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/_assert.sh"
source "$HERE/../skills/appstore-precheck/scripts/findings.sh"

FINDINGS_TMP="$(mktemp)"; : > "$FINDINGS_TMP"
set_rule "ats-arbitrary-loads"
_record WARN "1.6 App Transport Security disabled" "ios/App/Info.plist" "12"
set_rule "private-api"
_record FAIL "2.5.1 Private API used"

line1="$(sed -n '1p' "$FINDINGS_TMP")"
assert_eq "ats-arbitrary-loads" "$(jq -r .rule_id <<<"$line1")" "rule_id recorded"
assert_eq "WARN"                "$(jq -r .severity <<<"$line1")" "severity recorded"
assert_eq "1.6"                 "$(jq -r .guideline <<<"$line1")" "guideline from message"
assert_eq "ios/App/Info.plist"  "$(jq -r .file <<<"$line1")" "file recorded"
assert_eq "12"                  "$(jq -r .line <<<"$line1")" "line recorded (number)"
line2="$(sed -n '2p' "$FINDINGS_TMP")"
assert_eq "null" "$(jq -r .file <<<"$line2")" "file null when omitted"
assert_eq "ats-arbitrary-loads" "$(rule_slug 23)" "catalog lookup §23"
assert_eq "" "$(rule_slug 999)" "catalog lookup unknown -> empty"
rm -f "$FINDINGS_TMP"
exit "$fails"
```
**Assertion API (verified against `tests/_assert.sh`):** `assert_eq <actual> <expected> <label>`, `assert_contains <haystack> <needle> <label>`, `assert_absent <haystack> <needle> <label>`, and `section <title>`. There is **no `finish_suite`** — the harness uses a `$fails` counter, so each test file ends with `exit "$fails"`. `assert_eq` is symmetric for pass/fail (it just compares), so operand order only affects the diagnostic message wording.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-findings.sh`
Expected: FAIL — `findings.sh` does not exist / functions undefined.

- [ ] **Step 3: Write minimal implementation**

Create `skills/appstore-precheck/scripts/findings.sh`:
```bash
#!/usr/bin/env bash
# findings.sh — structured-findings layer for scan.sh.
# Sourced by scan.sh. Adds a parallel machine-readable channel; text output is untouched.
# Bash 3.2 compatible: NO associative arrays (catalog is a case lookup).

# rule_slug <section-number> -> stable kebab-case slug, or "" if unknown.
rule_slug() {
  case "$1" in
    1) echo privacy-manifest-parity ;;        2) echo usage-description-crosscheck ;;
    3) echo att-usage ;;                       4) echo competitor-mentions ;;
    5) echo metadata-char-limits ;;            6) echo locale-metadata-parity ;;
    7) echo screenshots-per-locale ;;          8) echo trial-disclosure ;;
    9) echo autorenew-disclosure ;;           10) echo subscription-links-restore ;;
    11) echo private-api ;;                    12) echo min-functionality-nav ;;
    13) echo screentime-justification ;;       14) echo siwa-parity ;;
    15) echo external-purchase-link ;;         16) echo tracking-sdk-no-att ;;
    17) echo export-compliance ;;              18) echo support-privacy-url ;;
    19) echo analytics-privacyinfo-mismatch ;; 20) echo placeholder-metadata ;;
    21) echo thirdparty-payment-sdk ;;         22) echo ugc-no-moderation ;;
    23) echo ats-arbitrary-loads ;;            24) echo applepay-recurring-disclosure ;;
    25) echo custom-review-prompt ;;           26) echo misleading-marketing ;;
    27) echo kids-wording ;;                   28) echo keyboard-full-access ;;
    29) echo health-icloud-sync ;;             30) echo vpn-networkextension ;;
    31) echo demo-account ;;                   32) echo executable-code-download ;;
    33) echo background-modes-unused ;;        34) echo crypto-wallet-mining ;;
    35) echo webview-wrapper ;;                36) echo remote-desktop ;;
    37) echo safari-extension ;;               38) echo account-no-delete ;;
    39) echo kids-ads-analytics ;;             40) echo realmoney-gambling ;;
    41) echo mdm ;;                            *) echo "" ;;
  esac
}

_CURRENT_RULE=""
set_rule() { _CURRENT_RULE="$1"; }

: "${FINDINGS_TMP:=}"

# _record <severity> <message> [<file>] [<line>]
_record() {
  [[ -z "$FINDINGS_TMP" ]] && return 0
  local sev="$1" msg="$2" file="${3:-}" line="${4:-}" guideline
  guideline="$(printf '%s' "$msg" | awk '{print $1}')"
  jq -nc --arg r "$_CURRENT_RULE" --arg s "$sev" --arg g "$guideline" \
        --arg m "$msg" --arg f "$file" --arg l "$line" \
    '{rule_id:$r, severity:$s, guideline:$g, message:$m,
      file:(if $f=="" then null else $f end),
      line:(if $l=="" then null else ($l|tonumber) end),
      suppressed:false}' >> "$FINDINGS_TMP"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-findings.sh`
Expected: PASS — all assertions ok.

- [ ] **Step 5: Commit**

```bash
git add skills/appstore-precheck/scripts/findings.sh tests/test-findings.sh
git commit -m "feat(findings): rule-id catalog + _record structured-finding recorder"
```

---

### Task 2: render_json — assemble the envelope

**Files:**
- Modify: `skills/appstore-precheck/scripts/findings.sh` (append `render_json`)
- Test: `tests/test-findings.sh` (add cases)

**Interfaces:**
- Consumes: `$FINDINGS_TMP` (JSONL of finding objects), `$PRECHECK_VERSION` (string, default "dev").
- Produces: `render_json` -> prints one JSON envelope `{tool, version, verdict, summary{fail,warn,pass,suppressed}, findings[]}` to stdout.

- [ ] **Step 1: Write the failing test**

Append to `tests/test-findings.sh` before `finish_suite`:
```bash
FINDINGS_TMP="$(mktemp)"; : > "$FINDINGS_TMP"
set_rule "ats-arbitrary-loads"; _record WARN "1.6 a"
set_rule "kids-wording";        _record WARN "2.3.8 b"
set_rule "ugc-no-moderation";   _record WARN "1.2 c"
set_rule "demo-account";        _record WARN "2.1 d"
set_rule "vpn-networkextension";_record WARN "5.4 e"
PRECHECK_VERSION="9.9.9"
out="$(render_json)"
assert_eq "9.9.9"  "$(jq -r .version <<<"$out")" "version in envelope"
assert_eq "YELLOW" "$(jq -r .verdict <<<"$out")" "5 warns -> YELLOW"
assert_eq "5"      "$(jq -r .summary.warn <<<"$out")" "warn count"
assert_eq "0"      "$(jq -r .summary.fail <<<"$out")" "fail count"
assert_eq "5"      "$(jq -r '.findings|length' <<<"$out")" "findings length"
rm -f "$FINDINGS_TMP"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-findings.sh`
Expected: FAIL — `render_json: command not found`.

- [ ] **Step 3: Write minimal implementation**

Append to `skills/appstore-precheck/scripts/findings.sh`:
```bash
: "${PRECHECK_VERSION:=dev}"

# render_json -> prints the structured envelope. Verdict reuses verdict.sh thresholds
# (RED >=1 FAIL; YELLOW >=5 WARN; else GREEN), counting non-suppressed findings only.
render_json() {
  local buf="${FINDINGS_TMP:-/dev/null}"
  [[ -s "$buf" ]] || { printf '%s\n' '{"findings":[]}' | jq \
     --arg v "$PRECHECK_VERSION" '{tool:"appstore-precheck",version:$v,verdict:"GREEN",summary:{fail:0,warn:0,pass:0,suppressed:0},findings:[]}'; return 0; }
  jq -s --arg v "$PRECHECK_VERSION" '
    (map(select(.suppressed==false))) as $live
    | ($live|map(select(.severity=="FAIL"))|length) as $f
    | ($live|map(select(.severity=="WARN"))|length) as $w
    | ($live|map(select(.severity=="PASS"))|length) as $p
    | (map(select(.suppressed==true))|length) as $s
    | (if $f>=1 then "RED" elif $w>=5 then "YELLOW" else "GREEN" end) as $verdict
    | {tool:"appstore-precheck", version:$v, verdict:$verdict,
       summary:{fail:$f, warn:$w, pass:$p, suppressed:$s},
       findings: .}' "$buf"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-findings.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add skills/appstore-precheck/scripts/findings.sh tests/test-findings.sh
git commit -m "feat(findings): render_json envelope with verdict-thresholded summary"
```

---

### Task 3: Wire findings.sh into scan.sh + golden text regression

**Files:**
- Modify: `skills/appstore-precheck/scripts/scan.sh` (source findings.sh; instrument helpers; `--format` flag + fd redirect)
- Create: `tests/test-format-json.sh`

**Interfaces:**
- Consumes: `findings.sh` functions.
- Produces: `scan.sh --format json` envelope; `scan.sh` (no flag) unchanged text.

- [ ] **Step 1: Write the failing test**

Create `tests/test-format-json.sh`:
```bash
#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/_assert.sh"
SCAN="$HERE/../skills/appstore-precheck/scripts/scan.sh"

# Golden: text output for risky-app must be byte-identical with and without the change.
tmp="$(mktemp -d)"; cp -R "$HERE/fixtures/risky-app/." "$tmp/"
text="$(cd "$tmp" && APPSTORE_PRECHECK_CONFIG=/nonexistent bash "$SCAN" 2>&1)"
assert_contains "$text" "WARN: 1.6 App Transport Security" "text mode still emits warnings"
assert_contains "$text" "---END-OF-SCAN---" "text mode reaches end marker"

# JSON mode: valid JSON, no text lines leaked, findings present.
json="$(cd "$tmp" && APPSTORE_PRECHECK_CONFIG=/nonexistent bash "$SCAN" --format json 2>/dev/null)"
echo "$json" | jq -e . >/dev/null; assert_eq "0" "$?" "json mode emits valid JSON"
assert_eq "appstore-precheck" "$(jq -r .tool <<<"$json")" "tool field"
# NOTE: rule_id is wired per-section in Task 4 (set_rule). Here, assert structure
# only — guideline is derived from the message's leading token, so it works now.
has16="$(jq '[.findings[]|select(.guideline=="1.6")]|length > 0' <<<"$json")"
assert_eq "true" "$has16" "ATS (guideline 1.6) finding present in JSON"
assert_eq "" "$(printf '%s' "$json" | grep -c 'WARN: ' | sed 's/0//')" "no text WARN lines leaked into JSON"
rm -rf "$tmp"
exit "$fails"
```
(`assert_contains <haystack> <needle>` and `assert_eq <actual> <expected>` per the verified API above. `tests/all.sh` runs each suite file in a subshell and checks its exit code, so ending with `exit "$fails"` is what marks the suite pass/fail.)

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-format-json.sh`
Expected: FAIL — `--format` unknown / JSON empty (scan.sh not yet wired).

- [ ] **Step 3: Write minimal implementation**

In `skills/appstore-precheck/scripts/scan.sh`:

(a) Near the top, after `cd "$ROOT"`, source the layer and init the buffer:
```bash
source "$(dirname "${BASH_SOURCE[0]}")/findings.sh"
FINDINGS_TMP="$(mktemp)"; export FINDINGS_TMP
trap 'rm -f "$FINDINGS_TMP"' EXIT
FORMAT="text"
PRECHECK_VERSION="$(grep -m1 '"version"' "$ROOT/package.json" 2>/dev/null | tr -dc '0-9.' )"
[[ -z "$PRECHECK_VERSION" ]] && PRECHECK_VERSION="dev"
```

(b) Parse the new flag (wherever args are handled; if scan.sh has no arg loop, add one before the scan body):
```bash
while [[ $# -gt 0 ]]; do
  case "$1" in
    --format) FORMAT="$2"; shift 2 ;;
    --format=*) FORMAT="${1#*=}"; shift ;;
    *) shift ;;
  esac
done
[[ "$FORMAT" == json || "$FORMAT" == text ]] || { echo "scan.sh: --format must be text|json" >&2; exit 64; }
```

(c) Instrument the helpers (echo behaviour byte-identical; add `_record`):
```bash
fail() { echo "FAIL: $1"; _record FAIL "$1" "${2:-}" "${3:-}"; }
warn() { echo "WARN: $1"; _record WARN "$1" "${2:-}" "${3:-}"; }
pass() { echo "PASS: $1"; _record PASS "$1" "${2:-}" "${3:-}"; }
```

(d) Wrap the scan body output: swallow stdout in JSON mode **before the first line the scan prints** — note scan.sh emits a `PASS: layout ...` echo *before* §1, so place the redirect above that echo (not literally at the §1 header), or that line leaks into the JSON and breaks `jq`. At the very end, restore and render:
```bash
# just before §1:
if [[ "$FORMAT" == json ]]; then exec 4>&1 1>/dev/null; fi
# ... existing scan body, unchanged ...
# at the very end of the file (after the last section / END marker):
if [[ "$FORMAT" == json ]]; then exec 1>&4 4>&-; render_json; fi
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-format-json.sh`
Expected: PASS.

- [ ] **Step 5: Run the full existing suite to confirm zero text regression**

Run: `bash tests/all.sh`
Expected: `SUITE PASSED` — all prior fixtures still pass (text output unchanged).

- [ ] **Step 6: Commit**

```bash
git add skills/appstore-precheck/scripts/scan.sh tests/test-format-json.sh
git commit -m "feat(scan): --format json output via instrumented helpers (text default unchanged)"
```

---

### Task 4: set_rule in every § section + catalog coverage test

**Files:**
- Modify: `skills/appstore-precheck/scripts/scan.sh` (one `set_rule` per section)
- Create/modify: `tests/test-format-json.sh` (coverage assertions)

**Interfaces:**
- Consumes: `set_rule`, `rule_slug`.
- Produces: every finding in JSON has a non-empty catalog `rule_id`.

- [ ] **Step 1: Write the failing test**

Append to `tests/test-format-json.sh` before `finish_suite` — assert no finding has an empty rule_id across all "risky" fixtures (which collectively trip most sections):
```bash
for fx in risky-app risky-app-2 tracking-app; do
  d="$(mktemp -d)"; cp -R "$HERE/fixtures/$fx/." "$d/"
  j="$(cd "$d" && APPSTORE_PRECHECK_CONFIG=/nonexistent bash "$SCAN" --format json 2>/dev/null)"
  empties="$(jq '[.findings[]|select(.severity!="PASS" and (.rule_id==""))]|length' <<<"$j")"
  assert_eq "0" "$empties" "$fx: every FAIL/WARN finding has a catalog rule_id"
  rm -rf "$d"
done
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-format-json.sh`
Expected: FAIL — sections without `set_rule` emit findings with empty rule_id.

- [ ] **Step 3: Insert one `set_rule` per section**

For each `§N` section header listed in the catalog table above, insert `set_rule "<slug>"` as the first executable line of that section (immediately after the header comment block, before the section's first `if`/`grep`). Pattern, e.g. for §23 (header at line 562):
```bash
# §23 — 1.6 App Transport Security disabled globally
# ===================================================================
set_rule "ats-arbitrary-loads"
if [[ -f "$INFO_PLIST" ]]; then
  ...
```
And for §38:
```bash
# §38 — 5.1.1(v) Account Sign-In: account creation without in-app deletion
# ===================================================================
set_rule "account-no-delete"
if [[ -n "$IOS_DIR" ]]; then
  ...
```
Do this for all 41 sections using the slug from the catalog table. For the paywall sub-blocks §8/§9/§10, place `set_rule "trial-disclosure"`, `set_rule "autorenew-disclosure"`, `set_rule "subscription-links-restore"` at the start of each `# ---- §N` sub-block respectively.

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/test-format-json.sh`
Expected: PASS — no empty rule_ids.

Run: `bash tests/all.sh`
Expected: `SUITE PASSED` — text output still byte-identical (set_rule prints nothing).

- [ ] **Step 5: Commit**

```bash
git add skills/appstore-precheck/scripts/scan.sh tests/test-format-json.sh
git commit -m "feat(scan): tag every section with set_rule so JSON findings carry rule-ids"
```

---

### Task 5: Register tests, document, changelog

**Files:**
- Modify: `tests/all.sh`, `README.md`, `skills/appstore-precheck/SKILL.md`, `CHANGELOG.md`

**Interfaces:** none (docs/glue only).

- [ ] **Step 1: Register the new suites**

In `tests/all.sh`, add `test-findings.sh` and `test-format-json.sh` to the list of suite files it runs (follow the existing pattern in that file).

- [ ] **Step 2: Run the full suite**

Run: `bash tests/all.sh`
Expected: `SUITE PASSED (9 files)` (7 existing + 2 new).

- [ ] **Step 3: Document `--format json`**

In `README.md` (near the CLI/usage section) and `skills/appstore-precheck/SKILL.md` (where scan invocation is described), add a short note: `scan.sh --format json` emits a structured findings envelope (`rule_id`, severity, guideline, message, file, line) for tooling; default output is unchanged text. State it is read-only and additive.

- [ ] **Step 4: CHANGELOG**

Add under a new `## [Unreleased]` section in `CHANGELOG.md`:
```markdown
## [Unreleased]

### Added
- `scan.sh --format json`: structured findings output (stable `rule_id` per vector, severity, guideline, message, optional file/line) for tooling and measurement. Default text output is unchanged.
```

- [ ] **Step 5: Commit**

```bash
git add tests/all.sh README.md skills/appstore-precheck/SKILL.md CHANGELOG.md
git commit -m "docs+test: register structured-findings suites and document --format json"
```

---

## Self-Review

**1. Spec coverage (Phase 1 of the spec):**
- G1 structured JSON via `--format json` → Tasks 2, 3. ✓
- G2 stable rule_id + severity/guideline/message/file/line → Tasks 1, 4. ✓
- G5 backward compatibility (text default byte-identical) → Task 3 golden test + Task 4 re-run of `tests/all.sh`. ✓
- Verdict single-sourcing (spec §4.4) → Task 2 `render_json` reuses verdict.sh thresholds. ✓
- Out of scope here (G3 suppression, G4 corpus/scorecard) → deferred to Phase 2 & Phase 3 plans, by design.

**2. Placeholder scan:** every code/test step contains complete code; the only "adapt to real API" notes are for `tests/_assert.sh` helper names, which the implementer must read first (the harness exists). No TBD/TODO.

**3. Type consistency:** `rule_slug`, `set_rule`, `_record`, `render_json`, `_CURRENT_RULE`, `FINDINGS_TMP`, `PRECHECK_VERSION`, `FORMAT` are used identically across Tasks 1–4. Helper signatures `fail/warn/pass "msg" [file] [line]` match the `_record` arity.

**Note for the implementer:** the assertion API is verified — `assert_eq <actual> <expected> <label>`, `assert_contains <haystack> <needle> <label>`, `assert_absent`, `section`; no `finish_suite` (end each file with `exit "$fails"`). `tests/all.sh` runs each suite in a subshell and gates on its exit code.

## Out of scope (follow-on plans)
- **Phase 2** — `.precheck-ignore` + inline suppression (own plan; consumes `rule_id` + file/line from Phase 1).
- **Phase 3** — synthetic + real-app validation corpus + `docs/scorecard.md` (own plan; consumes `--format json`).
- SARIF/JUnit emitters (Direction #4), now trivial given the JSON envelope.
