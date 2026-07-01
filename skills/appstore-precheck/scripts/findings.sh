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
