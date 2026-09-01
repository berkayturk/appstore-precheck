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
    41) echo mdm ;;                            42) echo screenshot-dimensions ;;
    43) echo permission-priming-cta ;;      44) echo paywall-trial-emphasis ;;
    45) echo metadata-pricing-language ;;   46) echo generic-purpose-string ;;
    47) echo ai-provider-consent ;;         48) echo paywall-urgency ;;
    49) echo rating-sentiment-gate ;;       50) echo forced-login ;;
    51) echo push-marketing-optout ;;       52) echo xcode-sdk-requirement ;;
    53) echo subscription-eula-metadata ;;  54) echo saturated-category ;;
    55) echo ipv4-literal ;;
    *) echo "" ;;
  esac
}

_CURRENT_RULE=""
_EVIDENCE_OVERRIDE=""
_CONFIDENCE_OVERRIDE=""
# set_rule also clears any per-finding overrides, so a refinement made for one
# branch can never leak into the next rule.
set_rule() { _CURRENT_RULE="$1"; _EVIDENCE_OVERRIDE=""; _CONFIDENCE_OVERRIDE=""; }

# set_evidence <class> / set_confidence <level> — refine the labels for the NEXT
# finding(s) of the current rule. A rule-level label is the honest default for the
# rule as a whole, but individual branches differ: §2 concludes its empty-purpose-
# string FAIL from Info.plist rather than a source grep (stronger evidence), while
# its "Info.plist not found" branch is an advisory, not the upload blocker the rule
# is otherwise about (weaker confidence). Without these, a degraded-read branch
# would inherit "validator-blocking" and overstate exactly what this layer exists
# to stop. Both are cleared by the next set_rule; inside a `| while read` subshell
# they scope themselves automatically.
set_evidence()   { _EVIDENCE_OVERRIDE="$1"; }
set_confidence() { _CONFIDENCE_OVERRIDE="$1"; }

# Resolvers degrade to empty when evidence.sh is not sourced (findings.sh is used
# standalone in tests), so an unclassified finding is reported as such, never guessed.
# A SKIP reached no conclusion, so it has no evidence class and no confidence: the
# rule it sits under (e.g. screenshots-per-locale) would otherwise leak
# "validator-blocking" onto a line that established nothing. Both resolvers take the
# severity so they can blank themselves for SKIP.
_evidence_of() {
  [[ "${1:-}" == "SKIP" ]] && { printf ''; return; }
  [[ -n "$_EVIDENCE_OVERRIDE" ]] && { printf '%s' "$_EVIDENCE_OVERRIDE"; return; }
  command -v rule_evidence >/dev/null 2>&1 && rule_evidence "$_CURRENT_RULE" || printf ''
}
_confidence_of() {
  [[ "${1:-}" == "SKIP" ]] && { printf ''; return; }
  [[ -n "$_CONFIDENCE_OVERRIDE" ]] && { printf '%s' "$_CONFIDENCE_OVERRIDE"; return; }
  command -v rule_confidence >/dev/null 2>&1 && rule_confidence "$_CURRENT_RULE" || printf ''
}
# _needs_build_of <severity> — the qualifier is a statement about an UNESTABLISHED
# violation ("this blocks the upload if it ships as-is"), so it is meaningless on a
# PASS: nothing is being claimed against the build. Evidence and confidence stay on
# a PASS — they still say how the rule reached its conclusion — but the qualifier
# does not. For runtime evidence the run's build_config decides (evidence.sh).
_needs_build_of() {
  # PASS asserts no violation; SKIP asserts nothing at all; RESOLVED has been
  # withdrawn. None can need a build to confirm a claim it no longer makes.
  case "${1:-}" in PASS|SKIP|RESOLVED) printf 'false'; return ;; esac
  command -v needs_build_verification >/dev/null 2>&1 \
    && needs_build_verification "$(_evidence_of)" "$(_confidence_of)" "${_BUILD_CONFIG:-unknown}" || printf 'false'
}
_guideline_url_of() {
  command -v guideline_url >/dev/null 2>&1 && guideline_url "$1" || printf ''
}

# --- Runtime provenance (Phase 6 dynamic tier, via dynamic.sh) -------------------
# Run-wide, not per rule, so set_rule does not clear them. Empty means "no runtime
# observation touched this record" and renders as null. A SKIP observed nothing, so
# it never carries a target or a build config (see _runtime_field_of).
: "${_RUNTIME_TARGET:=}"
: "${_BUILD_CONFIG:=}"
: "${_RESOLVED_BY:=}"
# set_runtime <target|""> <build_config|""> — declare where the observations come from.
set_runtime() { _RUNTIME_TARGET="${1:-}"; _BUILD_CONFIG="${2:-}"; }
_runtime_field_of() { # <severity> <value>
  [[ "${1:-}" == "SKIP" ]] && { printf ''; return; }
  printf '%s' "${2:-}"
}

# _finding_id <rule> <file> <line> <message> — a stable identity for one finding:
# the first 16 hex digits of sha256 over the four fields. Lets a later run (or the
# dynamic tier's reconciliation) refer to "this finding" without re-matching text.
# The message is part of it on purpose: a rewritten message is a different claim.
# The one deliberate exception: dynamic.sh reconciliation APPENDS a runtime
# observation to a static record's message and keeps the original id, so the id
# stays a handle for the same finding across the static and reconciled outputs.
# The hasher is resolved once at source time (this runs for every record).
if command -v shasum >/dev/null 2>&1; then _HASH_CMD="shasum -a 256"
elif command -v sha256sum >/dev/null 2>&1; then _HASH_CMD="sha256sum"
else _HASH_CMD=""; fi
_finding_id() {
  [[ -n "$_HASH_CMD" ]] || { printf ''; return; }
  local key="${1:-}|${2:-}|${3:-}|${4:-}" out
  out="$(printf '%s' "$key" | $_HASH_CMD)"
  printf '%s' "${out:0:16}"
}

# _emit <severity> <message> <file> <line> <suppressed:true|false>
# The single writer of the JSONL shape; _record and _record_suppressed wrap it.
# Severity is one of FAIL / WARN / PASS / SKIP / RESOLVED. RESOLVED (set only by
# dynamic.sh reconciliation) is structurally inert: render_json, sarif.sh and
# verdict.sh select by string equality on the other four, so a RESOLVED record is
# kept for the reader and counted by nothing. It is NOT suppressed:true — that
# field means a human signed for the finding in .precheck-ignore.
_emit() {
  local sev="$1" msg="$2" file="${3:-}" line="${4:-}" sup="${5:-false}" guideline
  guideline="$(printf '%s' "$msg" | awk '{print $1}')"
  jq -nc --arg r "$_CURRENT_RULE" --arg s "$sev" --arg g "$guideline" \
        --arg m "$msg" --arg f "$file" --arg l "$line" \
        --arg id "$(_finding_id "$_CURRENT_RULE" "$file" "$line" "$msg")" \
        --arg ev "$(_evidence_of "$sev")" --arg cf "$(_confidence_of "$sev")" \
        --arg nb "$(_needs_build_of "$sev")" --arg gu "$(_guideline_url_of "$guideline")" \
        --arg rb "$(_runtime_field_of "$sev" "$_RESOLVED_BY")" \
        --arg rt "$(_runtime_field_of "$sev" "$_RUNTIME_TARGET")" \
        --arg bc "$(_runtime_field_of "$sev" "$_BUILD_CONFIG")" \
        --argjson sup "$sup" \
    '{id:(if $id=="" then null else $id end),
      rule_id:$r, severity:$s, guideline:$g, message:$m,
      file:(if $f=="" then null else $f end),
      line:(if $l=="" then null else ($l|tonumber) end),
      evidence:(if $ev=="" then null else $ev end),
      confidence:(if $cf=="" then null else $cf end),
      needs_build_verification:($nb=="true"),
      guideline_url:(if $gu=="" then null else $gu end),
      resolved_by:(if $rb=="" then null else $rb end),
      runtime_target:(if $rt=="" then null else $rt end),
      build_config:(if $bc=="" then null else $bc end),
      suppressed:$sup}' >> "$FINDINGS_TMP"
}

: "${FINDINGS_TMP:=}"

# _record <severity> <message> [<file>] [<line>]
_record() {
  [[ -z "$FINDINGS_TMP" ]] && return 0
  _emit "$1" "$2" "${3:-}" "${4:-}" false
}

: "${_SUPPRESSED_COUNT:=0}"

# _record_suppressed <severity> <message> [<file>] [<line>]
# Same JSONL record as _record but suppressed:true, and bumps the counter.
_record_suppressed() {
  [[ -z "$FINDINGS_TMP" ]] && { _SUPPRESSED_COUNT=$((_SUPPRESSED_COUNT + 1)); return 0; }
  _emit "$1" "$2" "${3:-}" "${4:-}" true
  _SUPPRESSED_COUNT=$((_SUPPRESSED_COUNT + 1))
}

: "${PRECHECK_VERSION:=dev}"

# render_json -> prints the structured envelope. Verdict reuses verdict.sh thresholds
# (RED >=1 FAIL; YELLOW >=5 WARN; else GREEN), counting non-suppressed findings only.
render_json() {
  local buf="${FINDINGS_TMP:-/dev/null}"
  # Thresholds live in thresholds.sh (shared with verdict.sh).
  # shellcheck source=thresholds.sh
  . "$(dirname "${BASH_SOURCE[0]}")/thresholds.sh"
  [[ -s "$buf" ]] || { printf '%s\n' '{"findings":[]}' | jq \
     --arg v "$PRECHECK_VERSION" '{tool:"appstore-precheck",version:$v,verdict:"GREEN",
       summary:{fail:0,warn:0,pass:0,suppressed:0,
                by_confidence:{"validator-blocking":0,"review-risk":0,"judgment-call":0,unclassified:0},
                needs_build_verification:0, not_audited:0},
       findings:[]}'; return 0; }
  jq -s --arg v "$PRECHECK_VERSION" \
     --argjson fmin "$RED_FAIL_MIN" --argjson wmin "$YELLOW_WARN_MIN" '
    (map(select(.suppressed==false))) as $live
    | ($live|map(select(.severity=="FAIL"))|length) as $f
    | ($live|map(select(.severity=="WARN"))|length) as $w
    | ($live|map(select(.severity=="PASS"))|length) as $p
    # RESOLVED (dynamic.sh) matches none of the four selectors below and so is
    # counted by nothing — that inertness is asserted by tests, not assumed.
    # not_audited counts EVERY SKIP, suppressed ones included: acknowledging a gap
    # in .precheck-ignore signs it, it does not close it. (suppressed counts it too —
    # two different questions: "was it examined?" and "who took responsibility?")
    | (map(select(.severity=="SKIP"))|length) as $na
    | (map(select(.suppressed==true))|length) as $s
    | (if $f>=$fmin then "RED" elif $w>=$wmin then "YELLOW" else "GREEN" end) as $verdict
    # by_confidence counts live ISSUES (FAIL + WARN) only. A PASS carries the same
    # labels, but rolling passes into the confidence mix would misread as risk.
    | ($live|map(select(.severity=="FAIL" or .severity=="WARN"))) as $issues
    | ($issues|map(select(.needs_build_verification==true))|length) as $nb
    | {tool:"appstore-precheck", version:$v, verdict:$verdict,
       summary:{fail:$f, warn:$w, pass:$p, suppressed:$s,
                by_confidence:{
                  "validator-blocking":($issues|map(select(.confidence=="validator-blocking"))|length),
                  "review-risk":($issues|map(select(.confidence=="review-risk"))|length),
                  "judgment-call":($issues|map(select(.confidence=="judgment-call"))|length),
                  unclassified:($issues|map(select(.confidence==null))|length)},
                needs_build_verification:$nb, not_audited:$na},
       findings: .}' "$buf"
}
