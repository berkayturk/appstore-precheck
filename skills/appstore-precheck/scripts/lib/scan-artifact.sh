#!/usr/bin/env bash
# lib/scan-artifact.sh — the artifact tier of scan.sh (`--artifact <path>` / `--ipa <path>`).
# Runs lib/artifact-review.py (read-only: plists, entitlements, Mach-O linkage, embedded
# frameworks; nothing is launched) on a built .app, .ipa or .xcarchive and files its nine
# checks as catalogued rules §78–§86 with `artifact` evidence. Statuses map as:
#   PASS -> PASS; FINDING / NEEDS_REVIEW -> WARN; SKIP / NOT_RUN -> SKIP.
# Nothing here FAILs on its own: the tier says "this bundle needs a look", the human decides.
# Sourced by scan.sh only when OPT_ARTIFACT is set. Bash 3.2; python3 + jq required.

ARTIFACT_JSON=""
if command -v python3 >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  ARTIFACT_JSON="$(python3 -B "$SCRIPT_DIR/lib/artifact-review.py" --app "$OPT_ARTIFACT" --format json 2>/dev/null)" || ARTIFACT_JSON=""
fi

# artifact_row <check-id> -> sets ART_STATUS / ART_REASON / ART_EVIDENCE for that check.
artifact_row() {
  ART_STATUS=SKIP ART_REASON="python3 or jq unavailable, or artifact-review failed" ART_EVIDENCE=""
  [[ -n "$ARTIFACT_JSON" ]] || return 0
  local row
  row="$(printf '%s' "$ARTIFACT_JSON" | jq -c --arg id "$1" '.checks[]? | select(.check_id == $id)' 2>/dev/null | head -1)"
  [[ -n "$row" ]] || { ART_REASON="artifact-review returned no row for $1"; return 0; }
  ART_STATUS="$(printf '%s' "$row" | jq -r '.status')"
  ART_REASON="$(printf '%s' "$row" | jq -jr '.reason' | tr '\n\r\t' '   ')"
  ART_EVIDENCE="$(printf '%s' "$row" | jq -r '.evidence[]?' 2>/dev/null | head -5)"
}

# The guideline each check is filed under is literal here on purpose: the coverage
# derivation and the catalogue walk read these strings.
set_rule "artifact-entitlements";       artifact_row artifact-entitlements
case "$ART_STATUS" in PASS) pass "2.1 artifact-entitlements — $ART_REASON" ;; FINDING|NEEDS_REVIEW) warn "2.1 artifact-entitlements — $ART_REASON (read from $(basename "$OPT_ARTIFACT"), not executed)" "$OPT_ARTIFACT"; [[ -n "$ART_EVIDENCE" ]] && detail "$ART_EVIDENCE" ;; *) skip "2.1 artifact-entitlements — $ART_REASON" ;; esac
set_rule "artifact-reason-api";         artifact_row artifact-reason-api
case "$ART_STATUS" in PASS) pass "5.1.1 artifact-reason-api — $ART_REASON" ;; FINDING|NEEDS_REVIEW) warn "5.1.1 artifact-reason-api — $ART_REASON (read from $(basename "$OPT_ARTIFACT"), not executed)" "$OPT_ARTIFACT"; [[ -n "$ART_EVIDENCE" ]] && detail "$ART_EVIDENCE" ;; *) skip "5.1.1 artifact-reason-api — $ART_REASON" ;; esac
set_rule "artifact-private-api";        artifact_row artifact-private-api
case "$ART_STATUS" in PASS) pass "2.5.1 artifact-private-api — $ART_REASON" ;; FINDING|NEEDS_REVIEW) warn "2.5.1 artifact-private-api — $ART_REASON (read from $(basename "$OPT_ARTIFACT"), not executed)" "$OPT_ARTIFACT"; [[ -n "$ART_EVIDENCE" ]] && detail "$ART_EVIDENCE" ;; *) skip "2.5.1 artifact-private-api — $ART_REASON" ;; esac
set_rule "artifact-url-schemes";        artifact_row artifact-url-schemes
case "$ART_STATUS" in PASS) pass "2.5.1 artifact-url-schemes — $ART_REASON" ;; FINDING|NEEDS_REVIEW) warn "2.5.1 artifact-url-schemes — $ART_REASON (read from $(basename "$OPT_ARTIFACT"), not executed)" "$OPT_ARTIFACT"; [[ -n "$ART_EVIDENCE" ]] && detail "$ART_EVIDENCE" ;; *) skip "2.5.1 artifact-url-schemes — $ART_REASON" ;; esac
set_rule "artifact-ats";                artifact_row artifact-ats
case "$ART_STATUS" in PASS) pass "1.6 artifact-ats — $ART_REASON" ;; FINDING|NEEDS_REVIEW) warn "1.6 artifact-ats — $ART_REASON (read from $(basename "$OPT_ARTIFACT"), not executed)" "$OPT_ARTIFACT"; [[ -n "$ART_EVIDENCE" ]] && detail "$ART_EVIDENCE" ;; *) skip "1.6 artifact-ats — $ART_REASON" ;; esac
set_rule "artifact-sdk";                artifact_row artifact-sdk
case "$ART_STATUS" in PASS) pass "2.1 artifact-sdk — $ART_REASON" ;; FINDING|NEEDS_REVIEW) warn "2.1 artifact-sdk — $ART_REASON (read from $(basename "$OPT_ARTIFACT"), not executed)" "$OPT_ARTIFACT"; [[ -n "$ART_EVIDENCE" ]] && detail "$ART_EVIDENCE" ;; *) skip "2.1 artifact-sdk — $ART_REASON" ;; esac
set_rule "artifact-embedded-sdk";       artifact_row artifact-embedded-sdk
case "$ART_STATUS" in PASS) pass "5.1.1 artifact-embedded-sdk — $ART_REASON" ;; FINDING|NEEDS_REVIEW) warn "5.1.1 artifact-embedded-sdk — $ART_REASON (read from $(basename "$OPT_ARTIFACT"), not executed)" "$OPT_ARTIFACT"; [[ -n "$ART_EVIDENCE" ]] && detail "$ART_EVIDENCE" ;; *) skip "5.1.1 artifact-embedded-sdk — $ART_REASON" ;; esac
set_rule "artifact-executable-loading"; artifact_row artifact-executable-loading
case "$ART_STATUS" in PASS) pass "2.5.2 artifact-executable-loading — $ART_REASON" ;; FINDING|NEEDS_REVIEW) warn "2.5.2 artifact-executable-loading — $ART_REASON (read from $(basename "$OPT_ARTIFACT"), not executed)" "$OPT_ARTIFACT"; [[ -n "$ART_EVIDENCE" ]] && detail "$ART_EVIDENCE" ;; *) skip "2.5.2 artifact-executable-loading — $ART_REASON" ;; esac
set_rule "artifact-debug";              artifact_row artifact-debug
case "$ART_STATUS" in PASS) pass "2.1 artifact-debug — $ART_REASON" ;; FINDING|NEEDS_REVIEW) warn "2.1 artifact-debug — $ART_REASON (read from $(basename "$OPT_ARTIFACT"), not executed)" "$OPT_ARTIFACT"; [[ -n "$ART_EVIDENCE" ]] && detail "$ART_EVIDENCE" ;; *) skip "2.1 artifact-debug — $ART_REASON" ;; esac
