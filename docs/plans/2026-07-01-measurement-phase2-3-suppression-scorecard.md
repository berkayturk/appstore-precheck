# Suppression & Scorecard (Phases 2–3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add transparent `.precheck-ignore` + inline suppression and a measured
precision/recall scorecard to appstore-precheck, without changing the default text output.

**Architecture:** Suppression is decided *at emit time* inside the `pass/warn/fail` helpers so a
suppressed finding never reaches stdout (keeping `verdict.sh`'s line-counting verdict correct)
and never reaches the JSON summary counts. A new sourced `suppress.sh` parses `.precheck-ignore`
and inline markers. A new `scorecard.sh` runs a synthetic fixture corpus plus a pinned real-app
panel and regenerates `docs/scorecard.md`.

**Tech Stack:** Bash 3.2 (macOS default — **no associative arrays**), `jq` (already a
dependency), `git`, POSIX `grep`/`sed`/`awk`. Tests are plain bash under `tests/`.

## Global Constraints

- **READ-ONLY.** No task may write/edit code, metadata, or assets in a scanned project. The only
  permitted side effect anywhere remains `verdict.sh --apply`'s `.precheck-pass` token.
- **Text output byte-identical by default.** With no `.precheck-ignore` and no inline markers,
  `scan.sh` (text mode) output must be byte-for-byte what it is today. Enforced by golden tests.
- **No competitor name** in any repo/PR/commit/file/branch — ever.
- **Bash 3.2 compatible.** No associative arrays, no `mapfile`/`readarray`, no `${x^^}`.
- **TDD.** Every behavioral change gets a failing test first.
- **Rule-ids come from the catalog** in `skills/appstore-precheck/scripts/findings.sh`
  (`rule_slug 1..41`). Suppression and scorecard must only reference catalog slugs.
- **Version lockstep** is handled at release time by the existing process; do not bump versions
  inside these tasks.

Paths in this plan are relative to the repo root `/Users/bt/claude/appstore-precheck`.
`SCAN=skills/appstore-precheck/scripts` for brevity.

---

## File Structure

| File | Responsibility |
|---|---|
| `$SCAN/scan.sh` (modify) | thread file/line into locatable checks; source `suppress.sh`; emit-time suppression in helpers; `detail()` for evidence; PRUNE from ignore globs; text footer |
| `$SCAN/findings.sh` (modify) | `_record_suppressed` + `_SUPPRESSED_COUNT` (render_json already handles the flag) |
| `$SCAN/suppress.sh` (create) | `.precheck-ignore` + inline parsing: `load_precheck_ignore`, `precheck_prune_globs`, `is_suppressed` |
| `scripts/scorecard.sh` (create) | synthetic + real corpus runner, metrics, regenerate `docs/scorecard.md`; `--real`, `--check` |
| `corpus/synthetic/labels.json` (create) | per-fixture `expect_fire`/`expect_absent` rule-ids |
| `corpus/real/manifest.json` (create) | pinned real apps `{name,repo,commit,license}` |
| `corpus/real/labels.json` (create) | per-finding `TP`/`FP` labels keyed by rule_id+file+line+commit |
| `docs/scorecard.md` (create, generated) | published scorecard |
| `tests/test-suppress.sh` (create) | suppression unit + integration tests |
| `tests/test-scorecard.sh` (create) | metric math + `--check` staleness test |
| `tests/test-findings.sh` (modify) | assert locatable checks carry file/line |
| `.github/workflows/ci.yml` (modify) | shellcheck new scripts; register new tests; blocking `scorecard --check`; non-blocking real-panel job |
| `tests/all.sh`, `tests/run.sh` (modify) | register `test-suppress.sh`, `test-scorecard.sh` |
| `README.md` (modify) | scorecard section/badge; `.precheck-ignore` docs |

---

## Task 1: file/line plumbing into locatable checks

**Why first:** path-scoped and inline suppression (Task 3) need findings to carry a `file`
(and, for inline, a `line`). Today all 78 call sites pass only a message. This task adds
locations without changing any text output.

**Files:**
- Modify: `$SCAN/scan.sh` (locatable check blocks — anchor by their `set_rule "<slug>"` line)
- Modify: `tests/test-findings.sh`

**Interfaces:**
- Consumes: existing helpers `fail <msg> [<file>] [<line>]`, `warn ...`, `pass ...` (Phase 1).
- Produces: findings whose `file`/`line` are populated for locatable checks; the JSON contract
  gains real `file`/`line` values that Task 3 matches against.

**Locatable-check map** (slug → location to pass). Pass `$file` as `$2`; pass a line as `$3`
only when a single line is known (grep `-n` hits), else omit `$3`:

| slug | file to pass | line? |
|---|---|---|
| `private-api` (§11) | first path from `banned_hits` (`grep -rEnI` → `file:line:`) | yes (parse `:line:`) |
| `privacy-manifest-parity` (§1) | `$PRIVACY_MANIFEST` if set else `$INFO_PLIST` | no |
| `usage-description-crosscheck` (§2) | `$INFO_PLIST` | no |
| `att-usage` (§3) | `$INFO_PLIST` | no |
| `ats-arbitrary-loads` (§23) | `$INFO_PLIST` | no |
| `export-compliance` (§17) | `$INFO_PLIST` | no |
| `background-modes-unused` (§33) | `$INFO_PLIST` | no |
| `metadata-char-limits` (§5) | the offending metadata file (`$f`/`$META_DIR/...`) | no |
| `placeholder-metadata` (§20) | the offending metadata file | no |
| `misleading-marketing` (§26) | the offending metadata file | no |
| `kids-wording` (§27) | the offending metadata file | no |
| `realmoney-gambling` (§40) | first path from `gamble_hits` | yes if `-n` |
| `analytics-privacyinfo-mismatch` (§19) | `$PRIVACY_MANIFEST` | no |
| `support-privacy-url` (§18) | the metadata url file when known | no |

All other checks keep the current 1-arg call (file/line stay null — valid).

- [ ] **Step 1: Write the failing test** — append to `tests/test-findings.sh`, before its final
  summary/exit. It runs the scanner on the `risky-app` fixture in JSON mode and asserts the
  `private-api` finding carries a non-null `file` and integer `line`:

```bash
# --- file/line plumbing (Task 1) ---
fx="$ROOT/tests/fixtures/risky-app"
out="$(cd "$fx" && PRECHECK_VERSION=test bash "$ROOT/$SCAN/scan.sh" --format json 2>/dev/null)"
pa="$(printf '%s' "$out" | jq -c '.findings[] | select(.rule_id=="private-api")')"
assert_not_empty "$pa" "private-api finding present in risky-app json"
assert_eq "$(printf '%s' "$pa" | jq -r '.file != null')" "true" "private-api carries a file"
assert_eq "$(printf '%s' "$pa" | jq -r '(.line|type)')" "number" "private-api carries a line"
```

(Use the assert helpers already sourced by `tests/test-findings.sh`; `$ROOT` and `$SCAN` are set
at the top of that file — if `$SCAN` is not defined there, define
`SCAN="skills/appstore-precheck/scripts"` near the top.)

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-findings.sh`
Expected: FAIL — `private-api carries a file` (file is currently null).

- [ ] **Step 3: Add a golden byte-identity guard test** — still in `tests/test-findings.sh`,
  assert text output is unchanged by the plumbing. Capture the current text output of one fixture
  into a golden string and compare (the plumbing must not alter it):

```bash
# text output must not change when file/line are threaded (byte-identity)
txt_before="$(cd "$fx" && bash "$ROOT/$SCAN/scan.sh" 2>/dev/null | grep -cE '^(FAIL|WARN|PASS):')"
assert_gt "$txt_before" "0" "risky-app emits verdict lines in text mode"
```

(A full golden file is added in Task 3 Step for suppression; here we only assert the plumbing
does not drop/duplicate verdict lines. `assert_gt` — if not present in `tests/_assert.sh`, add a
2-line numeric-greater assertion there.)

- [ ] **Step 4: Implement §11 private-api location** — in `$SCAN/scan.sh`, find the
  `set_rule "private-api"` block:

```sh
if [[ -n "$banned_hits" ]]; then
  pa_first="$(printf '%s\n' "$banned_hits" | head -1)"   # "path:line:match"
  pa_file="${pa_first%%:*}"
  pa_rest="${pa_first#*:}"; pa_line="${pa_rest%%:*}"
  fail "2.5.1 Private/Deprecated API:" "$pa_file" "$pa_line"
  detail "$banned_hits"                                  # detail() added in Task 3; until then keep the echo
else
  pass "2.5.1 Private API — clean"
fi
```

Note: `detail` does not exist until Task 3. For Task 1, keep the existing
`echo "$banned_hits" | sed 's/^/      /'` line unchanged and only add the `fail ... "$pa_file"
"$pa_line"` arguments. The `detail` migration happens in Task 3.

- [ ] **Step 5: Implement the plist-backed checks** — for each slug in the map whose location is
  `$INFO_PLIST` / `$PRIVACY_MANIFEST`, add the file as `$2` on its `fail`/`warn` call. Example
  (§23 ATS):

```sh
# was: warn "1.6 App Transport Security — NSAllowsArbitraryLoads=true ..."
warn "1.6 App Transport Security — NSAllowsArbitraryLoads=true ..." "$INFO_PLIST"
```

Repeat for `usage-description-crosscheck`, `att-usage`, `export-compliance`,
`background-modes-unused`, `privacy-manifest-parity`, `analytics-privacyinfo-mismatch`
(use `$PRIVACY_MANIFEST` where that variable exists, else `$INFO_PLIST`). Only add the file
argument to the `fail`/`warn` lines; leave `pass` lines 1-arg unless the location is meaningful.

- [ ] **Step 6: Implement the metadata-file checks** — for `metadata-char-limits`,
  `placeholder-metadata`, `misleading-marketing`, `kids-wording`, pass the offending metadata
  file path that each block already computes (e.g. the `$f` / `"$d/$f"` variable in scope) as
  `$2`. Where the block loops files, pass the specific file that triggered the finding.

- [ ] **Step 7: Run tests to verify they pass**

Run: `bash tests/test-findings.sh && bash tests/test-format-json.sh`
Expected: PASS (private-api carries file+line; JSON still validates).

- [ ] **Step 8: Verify byte-identity across all fixtures** — no `.precheck-ignore` exists yet, so
  text output must be unchanged. Run the existing fixture suite:

Run: `npm test`
Expected: PASS — all existing fixture tests green (text output unchanged).

- [ ] **Step 9: Shellcheck**

Run: `shellcheck -x --severity=warning $SCAN/scan.sh`
Expected: no new warnings.

- [ ] **Step 10: Commit**

```bash
git add skills/appstore-precheck/scripts/scan.sh tests/test-findings.sh tests/_assert.sh
git commit -m "feat(scan): thread file/line into locatable checks (text output unchanged)"
```

---

## Task 2: `suppress.sh` parsing library (pure, unit-tested)

Build the suppression library as standalone functions with no `scan.sh` wiring yet, so it can be
unit-tested in isolation.

**Files:**
- Create: `$SCAN/suppress.sh`
- Create: `tests/test-suppress.sh`

**Interfaces:**
- Consumes: `rule_slug <n>` from `findings.sh` (sourced before `suppress.sh`) to validate that a
  token is a catalog rule-id.
- Produces:
  - `load_precheck_ignore [root]` — parses `<root>/.precheck-ignore`, populating globals
    `_SUPP_RULES` (newline list of rule-ids), `_SUPP_RULE_PATH` (newline list of
    `rule<TAB>glob`), `_SUPP_PATHS` (newline list of path globs). Resets them each call.
  - `precheck_prune_globs` — prints `_SUPP_PATHS` (one glob per line, trailing `/` stripped).
  - `is_suppressed <rule> <file> <line>` — exit 0 if suppressed, sets `_SUPP_REASON`; else exit 1.

- [ ] **Step 1: Write the failing test** — `tests/test-suppress.sh`:

```bash
#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCAN="skills/appstore-precheck/scripts"
# shellcheck source=tests/_assert.sh
source "$ROOT/tests/_assert.sh"
# shellcheck source=skills/appstore-precheck/scripts/findings.sh
source "$ROOT/$SCAN/findings.sh"
# shellcheck source=skills/appstore-precheck/scripts/suppress.sh
source "$ROOT/$SCAN/suppress.sh"

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

# --- rule-id everywhere ---
cat > "$work/.precheck-ignore" <<'EOF'
# comment line ignored
account-no-delete            # suppress this rule everywhere
ats-arbitrary-loads  ios/Legacy/
vendor/
EOF
load_precheck_ignore "$work"

is_suppressed "account-no-delete" "" ""            && r=0 || r=1
assert_eq "$r" "0" "rule-id suppressed everywhere"

is_suppressed "private-api" "" ""                  && r=0 || r=1
assert_eq "$r" "1" "unlisted rule not suppressed"

# --- rule + path scoped ---
is_suppressed "ats-arbitrary-loads" "ios/Legacy/Info.plist" "" && r=0 || r=1
assert_eq "$r" "0" "rule suppressed under matching path"
is_suppressed "ats-arbitrary-loads" "ios/App/Info.plist" ""    && r=0 || r=1
assert_eq "$r" "1" "rule not suppressed outside path"

# --- path exclusion collected ---
assert_eq "$(precheck_prune_globs | tr '\n' ' ' | grep -c vendor)" "1" "vendor path glob collected"

# --- unknown rule-id reported, not treated as rule ---
cat > "$work/.precheck-ignore" <<'EOF'
not-a-real-rule
EOF
err="$(load_precheck_ignore "$work" 2>&1 >/dev/null)"
assert_contains "$err" "unknown rule-id" "unknown rule-id reported on stderr"

# --- inline: on-line and line-above ---
src="$work/Sample.swift"
printf '%s\n' \
  'let a = 1 // precheck:ignore private-api' \
  '// precheck:ignore' \
  'let b = 2' \
  'let c = UIWebView()   // just mentions precheck:ignore in prose after code' > "$src"
_SUPP_RULES=""; _SUPP_RULE_PATH=""; _SUPP_PATHS=""      # inline path is independent of file rules
is_suppressed "private-api" "$src" "1" && r=0 || r=1
assert_eq "$r" "0" "inline scoped marker on the flagged line"
is_suppressed "anything" "$src" "3" && r=0 || r=1
assert_eq "$r" "0" "bare inline marker on the line above"
is_suppressed "kids-wording" "$src" "1" && r=0 || r=1
assert_eq "$r" "1" "scoped inline marker does not suppress a different rule"

echo "test-suppress: OK"
```

(If `assert_contains` / `assert_not_empty` are missing from `tests/_assert.sh`, add them —
each is a 2–3 line grep-based assertion mirroring the existing `assert_eq`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-suppress.sh`
Expected: FAIL — `suppress.sh` does not exist / functions undefined.

- [ ] **Step 3: Implement `$SCAN/suppress.sh`**

```sh
#!/usr/bin/env bash
# suppress.sh — .precheck-ignore + inline suppression for scan.sh.
# Sourced by scan.sh AFTER findings.sh (needs rule_slug). Bash 3.2: no associative arrays.

_SUPP_RULES=""        # rule-ids suppressed everywhere, one per line
_SUPP_RULE_PATH=""    # "rule<TAB>glob" per line
_SUPP_PATHS=""        # path globs excluded from scanning, one per line (trailing / stripped)
_SUPP_REASON=""       # set by is_suppressed on a hit

# _is_catalog_rule <token> -> 0 if token is a known rule slug.
_is_catalog_rule() {
  local n s
  n=1
  while [[ $n -le 41 ]]; do
    s="$(rule_slug "$n")"
    [[ "$s" == "$1" ]] && return 0
    n=$((n + 1))
  done
  return 1
}

# load_precheck_ignore [root]
load_precheck_ignore() {
  local root="${1:-.}" file line t1 t2
  file="$root/.precheck-ignore"
  _SUPP_RULES=""; _SUPP_RULE_PATH=""; _SUPP_PATHS=""
  [[ -f "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"                                   # strip trailing comment
    line="$(printf '%s' "$line" | awk '{$1=$1;print}')"  # trim ends, collapse ws
    [[ -z "$line" ]] && continue
    t1="$(printf '%s' "$line" | awk '{print $1}')"
    t2="$(printf '%s' "$line" | awk '{print $2}')"
    if _is_catalog_rule "$t1"; then
      if [[ -n "$t2" ]]; then
        _SUPP_RULE_PATH="${_SUPP_RULE_PATH}${t1}	${t2%/}
"
      else
        _SUPP_RULES="${_SUPP_RULES}${t1}
"
      fi
    elif [[ "$t1" == */* || "$t1" == *.* || "$t1" == *"*"* ]]; then
      _SUPP_PATHS="${_SUPP_PATHS}${t1%/}
"
    else
      printf 'suppress: unknown rule-id %s in .precheck-ignore (ignored)\n' "$t1" >&2
    fi
  done < "$file"
}

# precheck_prune_globs -> one path glob per line (for scan.sh PRUNE/GREP_PRUNE).
precheck_prune_globs() { printf '%s' "$_SUPP_PATHS"; }

# _inline_marker <line-text> <rule> -> 0 if a real comment marker suppresses <rule>.
_inline_marker() {
  local text="$1" rule="$2" spec
  printf '%s' "$text" | grep -qE '(//|#|<!--)[[:space:]]*precheck:ignore' || return 1
  spec="$(printf '%s' "$text" | sed -nE 's/.*precheck:ignore[[:space:]]*([a-z][a-z0-9-]*).*/\1/p')"
  [[ -z "$spec" ]] && return 0        # bare marker suppresses any rule
  [[ "$spec" == "$rule" ]]            # scoped marker must match
}

# is_suppressed <rule> <file> <line> -> 0 if suppressed (+ _SUPP_REASON), else 1.
is_suppressed() {
  local rule="$1" file="${2:-}" line="${3:-}" r g target
  _SUPP_REASON=""
  if [[ -n "$rule" ]] && printf '%s\n' "$_SUPP_RULES" | grep -qxF "$rule"; then
    _SUPP_REASON="rule:$rule"; return 0
  fi
  if [[ -n "$rule" && -n "$file" && -n "$_SUPP_RULE_PATH" ]]; then
    while IFS='	' read -r r g; do
      [[ -z "$r" ]] && continue
      if [[ "$r" == "$rule" ]]; then
        case "$file" in
          $g|*/$g|$g/*|*/$g/*) _SUPP_REASON="rule-path:$rule:$g"; return 0 ;;
        esac
      fi
    done <<INNER
$_SUPP_RULE_PATH
INNER
  fi
  if [[ -n "$file" && -n "$line" && -f "$file" ]]; then
    target="$(sed -n "${line}p" "$file" 2>/dev/null)"
    if _inline_marker "$target" "$rule"; then _SUPP_REASON="inline"; return 0; fi
    if [[ "$line" -gt 1 ]]; then
      target="$(sed -n "$((line - 1))p" "$file" 2>/dev/null)"
      if _inline_marker "$target" "$rule"; then _SUPP_REASON="inline-above"; return 0; fi
    fi
  fi
  return 1
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-suppress.sh`
Expected: PASS — `test-suppress: OK`.

- [ ] **Step 5: Shellcheck**

Run: `shellcheck -x --severity=warning $SCAN/suppress.sh tests/test-suppress.sh`
Expected: no warnings. (The `case "$file" in $g)` intentionally uses an unquoted glob — add
`# shellcheck disable=SC2254` on that line if flagged.)

- [ ] **Step 6: Commit**

```bash
git add skills/appstore-precheck/scripts/suppress.sh tests/test-suppress.sh tests/_assert.sh
git commit -m "feat(suppress): .precheck-ignore + inline parsing library (unit-tested)"
```

---

## Task 3: wire suppression into `scan.sh` (emit-time) + transparency footer

**Files:**
- Modify: `$SCAN/findings.sh` (add `_record_suppressed`, `_SUPPRESSED_COUNT`)
- Modify: `$SCAN/scan.sh` (source suppress.sh; helper gating; `detail()`; PRUNE; footer)
- Modify: `tests/test-suppress.sh` (add integration cases)
- Modify: `.github/workflows/ci.yml`, `tests/all.sh`, `tests/run.sh` (register)

**Interfaces:**
- Consumes: `is_suppressed`, `load_precheck_ignore`, `precheck_prune_globs` (Task 2);
  `_record` (Phase 1).
- Produces: emit-time-suppressing `fail/warn/pass`; `detail <text>`; `_SUPPRESSED_COUNT`;
  a text footer line `(N finding(s) suppressed via .precheck-ignore)` when `N>0`.

- [ ] **Step 1: Write the failing integration test** — append to `tests/test-suppress.sh`:

```bash
# --- integration: .precheck-ignore suppresses a real finding ---
app="$(mktemp -d)"; trap 'rm -rf "$work" "$app"' EXIT
mkdir -p "$app/App"
cat > "$app/App/ContentView.swift" <<'EOF'
import SwiftUI
let legacy = UIWebView()   // triggers private-api §11
EOF
cat > "$app/App/Info.plist" <<'EOF'
<?xml version="1.0"?><plist><dict></dict></plist>
EOF

run_scan() { (cd "$app" && PRECHECK_VERSION=test bash "$ROOT/$SCAN/scan.sh" "$@" 2>/dev/null); }

base_json="$(run_scan --format json)"
assert_eq "$(printf '%s' "$base_json" | jq '[.findings[]|select(.rule_id=="private-api" and .severity=="FAIL")]|length')" "1" "private-api fails without ignore"
assert_eq "$(printf '%s' "$base_json" | jq -r .verdict)" "RED" "verdict RED without ignore"

printf 'private-api\n' > "$app/.precheck-ignore"
supp_json="$(run_scan --format json)"
assert_eq "$(printf '%s' "$supp_json" | jq '.summary.suppressed')" "1" "suppressed count is 1"
assert_eq "$(printf '%s' "$supp_json" | jq '[.findings[]|select(.rule_id=="private-api" and .suppressed==false)]|length')" "0" "no live private-api finding"
assert_eq "$(printf '%s' "$supp_json" | jq -r .verdict)" "GREEN" "suppressed FAIL no longer forces RED"

# text mode: the FAIL line is gone, footer present, verdict via verdict.sh flips
supp_txt="$(run_scan)"
assert_eq "$(printf '%s' "$supp_txt" | grep -cE '^FAIL:.*Private')" "0" "suppressed FAIL absent from text"
assert_contains "$supp_txt" "suppressed via .precheck-ignore" "text footer reports suppression"
vtxt="$(printf '%s' "$supp_txt" | bash "$ROOT/$SCAN/verdict.sh" | grep '^VERDICT:')"
assert_contains "$vtxt" "GREEN" "verdict.sh sees GREEN after suppression"

# byte-identity: remove ignore -> output identical to a clean run
rm -f "$app/.precheck-ignore"
a="$(run_scan)"; b="$(run_scan)"
assert_eq "$a" "$b" "text output stable and footer-free with no ignore file"
assert_eq "$(printf '%s' "$a" | grep -c 'suppressed via')" "0" "no footer when nothing suppressed"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-suppress.sh`
Expected: FAIL — suppression not wired; `suppressed` stays 0, verdict stays RED.

- [ ] **Step 3: Add `_record_suppressed` + counter to `findings.sh`** — after `_record`:

```sh
: "${_SUPPRESSED_COUNT:=0}"

# _record_suppressed <severity> <message> [<file>] [<line>]
# Same JSONL record as _record but suppressed:true, and bumps the counter.
_record_suppressed() {
  [[ -z "$FINDINGS_TMP" ]] && { _SUPPRESSED_COUNT=$((_SUPPRESSED_COUNT + 1)); return 0; }
  local sev="$1" msg="$2" file="${3:-}" line="${4:-}" guideline
  guideline="$(printf '%s' "$msg" | awk '{print $1}')"
  jq -nc --arg r "$_CURRENT_RULE" --arg s "$sev" --arg g "$guideline" \
        --arg m "$msg" --arg f "$file" --arg l "$line" \
    '{rule_id:$r, severity:$s, guideline:$g, message:$m,
      file:(if $f=="" then null else $f end),
      line:(if $l=="" then null else ($l|tonumber) end),
      suppressed:true}' >> "$FINDINGS_TMP"
  _SUPPRESSED_COUNT=$((_SUPPRESSED_COUNT + 1))
}
```

- [ ] **Step 4: Source suppress.sh and gate the helpers in `scan.sh`** — after the
  `source ".../findings.sh"` line add:

```sh
source "$(dirname "${BASH_SOURCE[0]}")/suppress.sh"
```

Replace the three helpers (currently lines ~56–58) with:

```sh
_LAST_SUPPRESSED=0
fail() { if is_suppressed "$_CURRENT_RULE" "${2:-}" "${3:-}"; then _record_suppressed FAIL "$1" "${2:-}" "${3:-}"; _LAST_SUPPRESSED=1; else echo "FAIL: $1"; _record FAIL "$1" "${2:-}" "${3:-}"; _LAST_SUPPRESSED=0; fi; }
warn() { if is_suppressed "$_CURRENT_RULE" "${2:-}" "${3:-}"; then _record_suppressed WARN "$1" "${2:-}" "${3:-}"; _LAST_SUPPRESSED=1; else echo "WARN: $1"; _record WARN "$1" "${2:-}" "${3:-}"; _LAST_SUPPRESSED=0; fi; }
pass() { if is_suppressed "$_CURRENT_RULE" "${2:-}" "${3:-}"; then _record_suppressed PASS "$1" "${2:-}" "${3:-}"; _LAST_SUPPRESSED=1; else echo "PASS: $1"; _record PASS "$1" "${2:-}" "${3:-}"; _LAST_SUPPRESSED=0; fi; }

# detail <text> — indented evidence under the previous finding; skipped when it was suppressed.
detail() { [[ "${_LAST_SUPPRESSED:-0}" == 1 ]] || printf '%s\n' "$1" | sed 's/^/      /'; }
```

- [ ] **Step 5: Load the ignore file and extend PRUNE** — after the `cd "$ROOT"` and after PRUNE
  / GREP_PRUNE are defined (they are defined ~line 65–77), add:

```sh
load_precheck_ignore "$ROOT"
while IFS= read -r _g; do
  [[ -z "$_g" ]] && continue
  PRUNE+=( -not -path "*/$_g/*" -not -path "$_g/*" )
  GREP_PRUNE+=( --exclude-dir="${_g##*/}" )
done <<PRUNE_GLOBS
$(precheck_prune_globs)
PRUNE_GLOBS
```

(Place this after both arrays exist so the appends land. `load_precheck_ignore` needs `$ROOT`,
which is set near the top; if PRUNE is defined before `$ROOT`, move the `load_precheck_ignore`
call down to just before this loop.)

- [ ] **Step 6: Migrate the 7 evidence lines to `detail`** — replace each
  `echo "$VAR" | sed 's/^/      /'` (lines ~266, 421, 530, 572, 665, 683, 892) with
  `detail "$VAR"` (same variable). Example: `echo "$banned_hits" | sed 's/^/      /'` →
  `detail "$banned_hits"`.

- [ ] **Step 7: Add the text footer** — just before the final
  `if [[ "$FORMAT" == json ]]; then ... render_json; fi` line, add:

```sh
if [[ "$FORMAT" == text && "${_SUPPRESSED_COUNT:-0}" -gt 0 ]]; then
  printf '(%s finding(s) suppressed via .precheck-ignore)\n' "$_SUPPRESSED_COUNT"
fi
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `bash tests/test-suppress.sh && bash tests/test-findings.sh && bash tests/test-format-json.sh`
Expected: PASS.

- [ ] **Step 9: Full fixture suite (byte-identity regression)**

Run: `npm test`
Expected: PASS — no fixture has a `.precheck-ignore`, so all text output is unchanged.

- [ ] **Step 10: Register the test + shellcheck in CI and runners** — in `tests/all.sh` and
  `tests/run.sh` add `test-suppress.sh` to the executed list (mirror how `test-findings.sh` is
  listed). In `.github/workflows/ci.yml` add `$SCAN/suppress.sh` and `tests/test-suppress.sh` to
  the shellcheck file list, and `tests/test-suppress.sh` to the test invocation.

- [ ] **Step 11: Shellcheck everything touched**

Run: `shellcheck -x --severity=warning $SCAN/scan.sh $SCAN/findings.sh $SCAN/suppress.sh tests/test-suppress.sh`
Expected: no new warnings.

- [ ] **Step 12: Commit**

```bash
git add skills/appstore-precheck/scripts/scan.sh skills/appstore-precheck/scripts/findings.sh tests/test-suppress.sh tests/all.sh tests/run.sh .github/workflows/ci.yml
git commit -m "feat(scan): emit-time .precheck-ignore + inline suppression with transparent footer"
```

---

## Task 4: synthetic corpus + `scorecard.sh` (default + `--check`) + CI gate

**Files:**
- Create: `corpus/synthetic/labels.json`
- Create: `scripts/scorecard.sh`
- Create: `docs/scorecard.md` (generated by the script)
- Create: `tests/test-scorecard.sh`
- Modify: `.github/workflows/ci.yml` (blocking `scorecard.sh --check`)

**Interfaces:**
- Consumes: `scan.sh --format json` output (`.findings[].rule_id`, `.severity`).
- Produces: `scorecard.sh` with `--check` and a default regenerate mode; `docs/scorecard.md`.

- [ ] **Step 1: Author `corpus/synthetic/labels.json`** — one entry per fixture in
  `tests/fixtures/`. Determine each fixture's real firing rule-ids first:

```bash
for fx in tests/fixtures/*/; do
  echo "== $fx =="
  (cd "$fx" && PRECHECK_VERSION=test bash "$OLDPWD/skills/appstore-precheck/scripts/scan.sh" --format json 2>/dev/null \
     | jq -r '.findings[]|select(.severity!="PASS" and .suppressed==false)|.rule_id' | sort -u)
done
```

Then write `labels.json` with `expect_fire` = the rule-ids each fixture is *designed* to trip,
and `expect_absent` = a few rule-ids that must stay silent for that fixture. Shape:

```json
{
  "risky-app":  { "expect_fire": ["private-api"], "expect_absent": ["realmoney-gambling", "mdm"] },
  "clean-app":  { "expect_fire": [], "expect_absent": ["private-api", "ats-arbitrary-loads"] },
  "webview-app":{ "expect_fire": ["webview-wrapper"], "expect_absent": ["private-api"] }
}
```

(Fill an entry for every fixture directory. `expect_fire` reflects the fixture's intent — verify
against the actual run above; if a designed rule does not fire, that is a real recall gap the
scorecard should surface, so keep it in `expect_fire`.)

- [ ] **Step 2: Write the failing test** — `tests/test-scorecard.sh`:

```bash
#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/_assert.sh
source "$ROOT/tests/_assert.sh"

# metric math on a tiny known corpus
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/corpus/synthetic"
# a 2-fixture stub with a deterministic scanner stub is overkill; instead test the
# pure metric function directly via scorecard.sh's --selftest hook:
out="$(bash "$ROOT/scripts/scorecard.sh" --selftest)"
assert_contains "$out" "precision=1.00" "selftest precision computed"
assert_contains "$out" "recall=0.50" "selftest recall computed"

# --check detects a stale scorecard
cp "$ROOT/docs/scorecard.md" "$tmp/good.md"
printf '\nstale-marker\n' >> "$ROOT/docs/scorecard.md"
if bash "$ROOT/scripts/scorecard.sh" --check >/dev/null 2>&1; then rc=0; else rc=1; fi
cp "$tmp/good.md" "$ROOT/docs/scorecard.md"     # restore
assert_eq "$rc" "1" "--check fails on a stale scorecard"

# honesty caveat present
assert_contains "$(cat "$ROOT/docs/scorecard.md")" "Apple's actual review decisions" "honesty caveat present"
echo "test-scorecard: OK"
```

- [ ] **Step 3: Run test to verify it fails**

Run: `bash tests/test-scorecard.sh`
Expected: FAIL — `scripts/scorecard.sh` does not exist.

- [ ] **Step 4: Implement `scripts/scorecard.sh`**

```sh
#!/usr/bin/env bash
# scorecard.sh — run the validation corpus, compute precision/recall, regenerate docs/scorecard.md.
#   (default)     regenerate docs/scorecard.md from the synthetic corpus
#   --check       fail if docs/scorecard.md is stale or synthetic precision < floor
#   --real        clone + score the pinned real-app panel (network; non-blocking CI)
#   --selftest    print metric math on a fixed toy corpus (for tests)
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCAN="$ROOT/skills/appstore-precheck/scripts/scan.sh"
SYN="$ROOT/corpus/synthetic/labels.json"
CARD="$ROOT/docs/scorecard.md"
FLOOR="0.80"

# _metrics <tp> <fp> <fn> -> "precision=<p> recall=<r>" (2dp, guard div0)
_metrics() {
  awk -v tp="$1" -v fp="$2" -v fn="$3" 'BEGIN{
    p = (tp+fp>0)? tp/(tp+fp) : 1;
    r = (tp+fn>0)? tp/(tp+fn) : 1;
    printf "precision=%.2f recall=%.2f", p, r;
  }'
}

if [[ "${1:-}" == "--selftest" ]]; then
  # toy: tp=2 fp=0 fn=2 -> precision 1.00, recall 0.50
  _metrics 2 0 2; echo; exit 0
fi

# run the synthetic corpus -> aggregate tp/fp/fn and a per-rule TSV in $ROWS
run_synthetic() {
  local fx name fired want absent rid tp=0 fp=0 fn=0
  ROWS=""
  for fx in "$ROOT"/tests/fixtures/*/; do
    name="$(basename "$fx")"
    jq -e --arg n "$name" 'has($n)' "$SYN" >/dev/null 2>&1 || continue
    fired="$(cd "$fx" && PRECHECK_VERSION=scorecard bash "$SCAN" --format json 2>/dev/null \
             | jq -r '.findings[]|select(.severity!="PASS" and .suppressed==false)|.rule_id' | sort -u)"
    want="$(jq -r --arg n "$name" '.[$n].expect_fire[]?' "$SYN")"
    absent="$(jq -r --arg n "$name" '.[$n].expect_absent[]?' "$SYN")"
    for rid in $want; do
      if printf '%s\n' "$fired" | grep -qxF "$rid"; then tp=$((tp+1)); else fn=$((fn+1)); fi
    done
    for rid in $absent; do
      if printf '%s\n' "$fired" | grep -qxF "$rid"; then fp=$((fp+1)); fi
    done
  done
  SYN_TP=$tp; SYN_FP=$fp; SYN_FN=$fn
}

render_card() {
  run_synthetic
  local m; m="$(_metrics "$SYN_TP" "$SYN_FP" "$SYN_FN")"
  local prec="${m#precision=}"; prec="${prec%% *}"
  cat <<EOF
# appstore-precheck — Validation Scorecard

_Generated by \`scripts/scorecard.sh\`. Do not edit by hand._

## Methodology

Two corpora measure two different things:

- **Synthetic** (\`corpus/synthetic/\`): the project's own fixtures, each labelled with the
  rule-ids it is designed to trip (\`expect_fire\`) and rule-ids that must stay silent
  (\`expect_absent\`). Measures **intended-behaviour fidelity**.
- **Real panel** (\`corpus/real/\`): permissively-licensed open-source iOS / React-Native apps
  pinned to a commit, with a one-time human TP/FP labelling pass. Measures **real-code
  false-positive rate**. Run with \`scorecard.sh --real\`.

## Synthetic aggregate

| metric | value |
|---|---|
| true positives  | $SYN_TP |
| false positives | $SYN_FP |
| false negatives | $SYN_FN |
| **precision**   | ${m#precision=} |

## Honesty

Synthetic measures intended-behaviour fidelity. Real-panel precision measures the
false-positive rate on real open-source code. **Neither claims agreement with Apple's actual
review decisions.** Recall is bounded by labelled known issues and is not exhaustive.
EOF
}

case "${1:-}" in
  --check)
    tmp="$(mktemp)"; render_card > "$tmp"
    if ! diff -q "$tmp" "$CARD" >/dev/null 2>&1; then
      echo "scorecard: docs/scorecard.md is stale — run scripts/scorecard.sh" >&2
      diff "$CARD" "$tmp" >&2 || true; rm -f "$tmp"; exit 1
    fi
    rm -f "$tmp"
    run_synthetic
    prec="$(_metrics "$SYN_TP" "$SYN_FP" "$SYN_FN")"; prec="${prec#precision=}"; prec="${prec%% *}"
    awk -v p="$prec" -v f="$FLOOR" 'BEGIN{exit !(p+0 >= f+0)}' || {
      echo "scorecard: synthetic precision $prec below floor $FLOOR" >&2; exit 1; }
    echo "scorecard: up to date (precision $prec >= $FLOOR)"
    ;;
  --real)
    bash "$ROOT/scripts/scorecard-real.sh" ;;   # created in Task 5
  ""|--write)
    render_card > "$CARD"; echo "scorecard: wrote $CARD" ;;
  *) echo "scorecard.sh: unknown arg '$1'" >&2; exit 64 ;;
esac
```

- [ ] **Step 5: Generate the scorecard**

Run: `bash scripts/scorecard.sh && bash tests/test-scorecard.sh`
Expected: writes `docs/scorecard.md`; test prints `test-scorecard: OK`.

- [ ] **Step 6: Add the blocking CI job** — in `.github/workflows/ci.yml`, add a step after the
  fixture tests:

```yaml
      - name: Scorecard up to date (synthetic)
        run: bash scripts/scorecard.sh --check
```

Also add `scripts/scorecard.sh` and `tests/test-scorecard.sh` to the shellcheck file list and
`tests/test-scorecard.sh` to the test runner list (and to `tests/all.sh`/`tests/run.sh`).

- [ ] **Step 7: Shellcheck**

Run: `shellcheck -x --severity=warning scripts/scorecard.sh tests/test-scorecard.sh`
Expected: no warnings.

- [ ] **Step 8: Commit**

```bash
git add corpus/synthetic/labels.json scripts/scorecard.sh docs/scorecard.md tests/test-scorecard.sh tests/all.sh tests/run.sh .github/workflows/ci.yml
git commit -m "feat(scorecard): synthetic corpus + precision/recall scorecard with CI staleness gate"
```

---

## Task 5: real-app panel (`--real`) + candidate labels + non-blocking CI + README

**Files:**
- Create: `corpus/real/manifest.json`
- Create: `corpus/real/labels.json`
- Create: `scripts/scorecard-real.sh`
- Modify: `.github/workflows/ci.yml` (non-blocking real-panel job)
- Modify: `README.md`

**Interfaces:**
- Consumes: `manifest.json` `{name,repo,commit,license}`; `scan.sh --format json`.
- Produces: `scorecard-real.sh` (clone+scan+join); real precision/FP numbers appended to output.

- [ ] **Step 1: Author `corpus/real/manifest.json`** — verify each repo's license from its
  `LICENSE`/`COPYING` before adding (MIT / Apache-2.0 / BSD / MPL-2.0 only). Pin each to a real
  commit SHA (resolve with `git ls-remote <repo> HEAD` at authoring time and record the SHA):

```json
{
  "apps": [
    { "name": "wikipedia-ios",  "repo": "https://github.com/wikimedia/wikipedia-ios", "commit": "<SHA>", "license": "MIT" },
    { "name": "ios-oss",        "repo": "https://github.com/kickstarter/ios-oss",     "commit": "<SHA>", "license": "Apache-2.0" },
    { "name": "duckduckgo-ios", "repo": "https://github.com/duckduckgo/iOS",          "commit": "<SHA>", "license": "Apache-2.0" }
  ]
}
```

Add 10–20 entries total, license-verified. Do **not** invent SHAs — resolve each.

- [ ] **Step 2: Implement `scripts/scorecard-real.sh`**

```sh
#!/usr/bin/env bash
# scorecard-real.sh — clone the pinned real-app panel, scan each, join with human TP/FP labels.
# Network + slow; run via `scorecard.sh --real`, non-blocking in CI.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCAN="$ROOT/skills/appstore-precheck/scripts/scan.sh"
MAN="$ROOT/corpus/real/manifest.json"
LAB="$ROOT/corpus/real/labels.json"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

tp=0; fp=0; unlabeled=0
count="$(jq '.apps|length' "$MAN")"
i=0
while [[ $i -lt $count ]]; do
  name="$(jq -r ".apps[$i].name" "$MAN")"
  repo="$(jq -r ".apps[$i].repo" "$MAN")"
  commit="$(jq -r ".apps[$i].commit" "$MAN")"
  i=$((i+1))
  dir="$WORK/$name"
  git clone --quiet --filter=blob:none "$repo" "$dir" 2>/dev/null || { echo "clone failed: $name" >&2; continue; }
  git -C "$dir" checkout --quiet "$commit" 2>/dev/null || { echo "checkout failed: $name@$commit" >&2; continue; }
  findings="$(cd "$dir" && PRECHECK_VERSION=scorecard bash "$SCAN" --format json 2>/dev/null \
              | jq -c --arg app "$name" '.findings[]|select(.severity!="PASS" and .suppressed==false)|{app:$app, rule_id, file, line}')"
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    key="$(printf '%s' "$f" | jq -r '"\(.app)|\(.rule_id)|\(.file)|\(.line)|'"$commit"'"')"
    label="$(jq -r --arg k "$key" '.[$k] // "UNLABELED"' "$LAB")"
    case "$label" in
      TP) tp=$((tp+1)) ;;
      FP) fp=$((fp+1)) ;;
      *)  unlabeled=$((unlabeled+1)) ;;
    esac
  done <<< "$findings"
done

echo "real-panel: tp=$tp fp=$fp unlabeled=$unlabeled"
awk -v tp="$tp" -v fp="$fp" 'BEGIN{ p=(tp+fp>0)?tp/(tp+fp):1; printf "real-panel precision (FP rate basis): %.2f\n", p }'
[[ $unlabeled -gt 0 ]] && echo "note: $unlabeled finding(s) UNLABELED — run the human labelling pass (see corpus/real/README)."
exit 0
```

- [ ] **Step 3: Generate candidate labels (human-in-the-loop)** — run the panel once to emit the
  finding keys, seed `corpus/real/labels.json` with candidate values, then a human confirms:

```bash
bash scripts/scorecard.sh --real 2>&1 | tee /tmp/real-run.txt
# then hand-build corpus/real/labels.json mapping each "app|rule_id|file|line|commit" -> "TP"|"FP"
```

Seed the file as `{}` if labels are not yet reviewed; `scorecard-real.sh` reports everything as
`UNLABELED` until a human fills it, so no unreviewed number is ever published.

- [ ] **Step 4: Add a non-blocking CI job** — in `.github/workflows/ci.yml`, a separate job that
  does not gate the PR:

```yaml
  real-panel:
    runs-on: ubuntu-latest
    continue-on-error: true
    steps:
      - uses: actions/checkout@v4
      - name: Real-app panel (informational)
        run: bash scripts/scorecard.sh --real
```

- [ ] **Step 5: README section** — add a "Measured accuracy" subsection linking to
  `docs/scorecard.md`, stating the synthetic precision is a CI-gated floor and the real-panel
  number is a false-positive-rate measurement that makes **no** claim about Apple's decisions.
  Add a `.precheck-ignore` usage subsection documenting the three grammar forms and the inline
  `# precheck:ignore [rule-id]` marker, noting suppressed findings are always counted.

- [ ] **Step 6: Shellcheck**

Run: `shellcheck -x --severity=warning scripts/scorecard-real.sh`
Expected: no warnings.

- [ ] **Step 7: Commit**

```bash
git add corpus/real/manifest.json corpus/real/labels.json scripts/scorecard-real.sh .github/workflows/ci.yml README.md
git commit -m "feat(scorecard): pinned real-app panel with human TP/FP labels (non-blocking CI)"
```

---

## Task 6: whole-branch review + PR

- [ ] **Step 1: Full test sweep**

Run: `npm test && bash tests/test-suppress.sh && bash tests/test-scorecard.sh && bash tests/test-findings.sh && bash tests/test-format-json.sh`
Expected: all PASS.

- [ ] **Step 2: Byte-identity spot check** — confirm a fixture with no `.precheck-ignore`
  produces identical output before/after the branch:

```bash
git stash; a="$(cd tests/fixtures/risky-app && bash "$OLDPWD/skills/appstore-precheck/scripts/scan.sh")"; git stash pop
b="$(cd tests/fixtures/risky-app && bash "$OLDPWD/skills/appstore-precheck/scripts/scan.sh")"
[ "$a" = "$b" ] && echo IDENTICAL || echo DIFF
```

Expected: `IDENTICAL`.

- [ ] **Step 3: Whole-branch Opus review** — dispatch a code-reviewer over
  `git diff main...HEAD`, focused on: READ-ONLY invariant, byte-identity, no competitor name,
  bash 3.2 compatibility, suppression transparency (nothing silently dropped).

- [ ] **Step 4: Open the PR**

```bash
git push -u origin feat/measurement-suppression-scorecard
gh pr create --title "feat: suppression (.precheck-ignore + inline) and measured scorecard (Phases 2–3)" \
  --body "Implements Direction #1 Phases 2–3 per docs/specs/2026-07-01-…-design.md. Adds transparent .precheck-ignore + inline suppression (emit-time; text output byte-identical by default) and a synthetic+real precision/recall scorecard with a CI staleness gate. READ-ONLY preserved."
```

---

## Self-Review

**Spec coverage:** §1 emit-time suppression → Task 3; §1.2 evidence → Task 3 Step 6; §1.3
suppress.sh → Task 2; §1.4 file/line → Task 1; §1.5 footer/transparency → Task 3 Steps 7,1;
§2.1 synthetic → Task 4; §2.2 real panel → Task 5; §2.3 scorecard.sh → Tasks 4–5; §2.4
scorecard.md + honesty → Task 4 Step 4; §2.5 CI → Task 4 Step 6 (blocking) + Task 5 Step 4
(non-blocking); §4 tests → Tasks 2–5; §5 invariants → Global Constraints + Task 6. Covered.

**Placeholders:** the only intentional `<SHA>` is in Task 5 Step 1, explicitly instructed to be
resolved with `git ls-remote` (not a plan placeholder — it is runtime data the implementer
must fetch). No TBD/TODO elsewhere.

**Type consistency:** `is_suppressed <rule> <file> <line>`, `_record_suppressed`,
`_SUPPRESSED_COUNT`, `detail`, `precheck_prune_globs`, `load_precheck_ignore`, `_metrics`,
`run_synthetic` names are used identically across tasks.
