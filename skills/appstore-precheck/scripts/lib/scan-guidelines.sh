#!/usr/bin/env bash
# Additional source checks are advisory; absent inputs remain additive coverage gaps.
# shellcheck disable=SC2034
COVERAGE_GAPS_JSON="${COVERAGE_GAPS_JSON:-[]}"
STATIC_GAP_COUNT=0 STATIC_GAP_SLUGS="" STATIC_GAP_REASON="" STATIC_EMOJI_STATUS=SKIP
STATIC_GUIDELINES_JSON='{}'
if command -v python3 >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  STATIC_GUIDELINES_JSON="$(python3 -B "$SCRIPT_DIR/lib/static-reader.py" \
    --root "$ROOT" --metadata "${META_DIR:-/nonexistent}" --plist "${INFO_PLIST:-/nonexistent}" \
    "${GREP_PRUNE[@]+"${GREP_PRUNE[@]}"}" )" || STATIC_GUIDELINES_JSON='{"_reader_error":"reader invocation failed; see stderr"}'
fi

static_guideline_select() {
  local row
  STATIC_STATUS=SKIP STATIC_REASON="Python 3 or jq unavailable, or source reader failed." STATIC_FILE=""
  if command -v jq >/dev/null 2>&1; then
    STATIC_REASON="$(printf '%s' "$STATIC_GUIDELINES_JSON" | jq -r '._reader_error // "Python 3 or jq unavailable, or source reader failed."')"
    row="$(printf '%s' "$STATIC_GUIDELINES_JSON" | jq -cer --arg id "$1" '.[$id] // empty' 2>/dev/null)" || return 0
    STATIC_STATUS="$(printf '%s' "$row" | jq -r '.status')"
    STATIC_REASON="$(printf '%s' "$row" | jq -jr '.reason' | tr '\n\r\t' '   ')"
    STATIC_FILE="$(printf '%s' "$row" | jq -jr '.file' | tr '\n\r\t' '   ')"
  fi
}

static_guideline_gap() {
  local id="$1" guideline="$2" reason="$3"
  STATIC_GAP_COUNT=$((STATIC_GAP_COUNT + 1))
  STATIC_GAP_SLUGS="${STATIC_GAP_SLUGS}${STATIC_GAP_SLUGS:+, }$id"
  STATIC_GAP_REASON="$reason"
  if command -v jq >/dev/null 2>&1; then
    COVERAGE_GAPS_JSON="$(printf '%s' "$COVERAGE_GAPS_JSON" | jq -c \
      --arg id "$id" --arg guideline "$guideline" --arg reason "$reason" \
      '. + [{rule_id:$id,guideline:$guideline,status:"SKIP",reason:$reason}]')"
  else
    # These two values come only from the literal call sites below, never input files.
    COVERAGE_GAPS_JSON="${COVERAGE_GAPS_JSON%]}"
    [[ "$COVERAGE_GAPS_JSON" == '[' ]] || COVERAGE_GAPS_JSON+=','
    COVERAGE_GAPS_JSON+="{\"rule_id\":\"$id\",\"guideline\":\"$guideline\",\"status\":\"SKIP\",\"reason\":\"Optional Python 3/jq reader unavailable.\"}]"
  fi
}

# §56 — 2.3.12: release-notes-specificity
set_rule "release-notes-specificity"
static_guideline_select "release-notes-specificity"
case "$STATIC_STATUS" in
  WARN) warn "2.3.12 release-notes-specificity — $STATIC_REASON" "$STATIC_FILE" ;;
  PASS) pass "2.3.12 release-notes-specificity — $STATIC_REASON" ;;
  *) static_guideline_gap "release-notes-specificity" "2.3.12" "$STATIC_REASON" ;;
esac

# §57 — 2.4.4: device-restart-instructions
set_rule "device-restart-instructions"
static_guideline_select "device-restart-instructions"
case "$STATIC_STATUS" in
  WARN) warn "2.4.4 device-restart-instructions — $STATIC_REASON" "$STATIC_FILE" ;;
  PASS) pass "2.4.4 device-restart-instructions — $STATIC_REASON" ;;
  *) static_guideline_gap "device-restart-instructions" "2.4.4" "$STATIC_REASON" ;;
esac

# §58 — 2.5.6: browser-engine
set_rule "browser-engine"
static_guideline_select "browser-engine"
case "$STATIC_STATUS" in
  WARN) warn "2.5.6 browser-engine — $STATIC_REASON" "$STATIC_FILE" ;;
  PASS) pass "2.5.6 browser-engine — $STATIC_REASON" ;;
  *) static_guideline_gap "browser-engine" "2.5.6" "$STATIC_REASON" ;;
esac

# §59 — 2.5.11: intent-handler-parity
set_rule "intent-handler-parity"
static_guideline_select "intent-handler-parity"
case "$STATIC_STATUS" in
  WARN) warn "2.5.11 intent-handler-parity — $STATIC_REASON" "$STATIC_FILE" ;;
  PASS) pass "2.5.11 intent-handler-parity — $STATIC_REASON" ;;
  *) static_guideline_gap "intent-handler-parity" "2.5.11" "$STATIC_REASON" ;;
esac

# §60 — 2.5.12: call-filter-controls
set_rule "call-filter-controls"
static_guideline_select "call-filter-controls"
case "$STATIC_STATUS" in
  WARN) warn "2.5.12 call-filter-controls — $STATIC_REASON" "$STATIC_FILE" ;;
  PASS) pass "2.5.12 call-filter-controls — $STATIC_REASON" ;;
  *) static_guideline_gap "call-filter-controls" "2.5.12" "$STATIC_REASON" ;;
esac

# §61 — 2.5.13: face-authentication
set_rule "face-authentication"
static_guideline_select "face-authentication"
case "$STATIC_STATUS" in
  WARN) warn "2.5.13 face-authentication — $STATIC_REASON" "$STATIC_FILE" ;;
  PASS) pass "2.5.13 face-authentication — $STATIC_REASON" ;;
  *) static_guideline_gap "face-authentication" "2.5.13" "$STATIC_REASON" ;;
esac

# §62 — 2.5.15: document-browser-access
set_rule "document-browser-access"
static_guideline_select "document-browser-access"
case "$STATIC_STATUS" in
  WARN) warn "2.5.15 document-browser-access — $STATIC_REASON" "$STATIC_FILE" ;;
  PASS) pass "2.5.15 document-browser-access — $STATIC_REASON" ;;
  *) static_guideline_gap "document-browser-access" "2.5.15" "$STATIC_REASON" ;;
esac

# §63 — 2.5.16: extension-bundle-parity
set_rule "extension-bundle-parity"
static_guideline_select "extension-bundle-parity"
case "$STATIC_STATUS" in
  WARN) warn "2.5.16 extension-bundle-parity — $STATIC_REASON" "$STATIC_FILE" ;;
  PASS) pass "2.5.16 extension-bundle-parity — $STATIC_REASON" ;;
  *) static_guideline_gap "extension-bundle-parity" "2.5.16" "$STATIC_REASON" ;;
esac

# §64 — 2.5.17: matter-extension
set_rule "matter-extension"
static_guideline_select "matter-extension"
case "$STATIC_STATUS" in
  WARN) warn "2.5.17 matter-extension — $STATIC_REASON" "$STATIC_FILE" ;;
  PASS) pass "2.5.17 matter-extension — $STATIC_REASON" ;;
  *) static_guideline_gap "matter-extension" "2.5.17" "$STATIC_REASON" ;;
esac

# §65 — 2.5.18: extension-advertising
set_rule "extension-advertising"
static_guideline_select "extension-advertising"
case "$STATIC_STATUS" in
  WARN) warn "2.5.18 extension-advertising — $STATIC_REASON" "$STATIC_FILE" ;;
  PASS) pass "2.5.18 extension-advertising — $STATIC_REASON" ;;
  *) static_guideline_gap "extension-advertising" "2.5.18" "$STATIC_REASON" ;;
esac

# §66 — 4.2.1: ar-integration-depth
set_rule "ar-integration-depth"
static_guideline_select "ar-integration-depth"
case "$STATIC_STATUS" in
  WARN) warn "4.2.1 ar-integration-depth — $STATIC_REASON" "$STATIC_FILE" ;;
  PASS) pass "4.2.1 ar-integration-depth — $STATIC_REASON" ;;
  *) static_guideline_gap "ar-integration-depth" "4.2.1" "$STATIC_REASON" ;;
esac

# §67 — 4.2.3: companion-app-required
set_rule "companion-app-required"
static_guideline_select "companion-app-required"
case "$STATIC_STATUS" in
  WARN) warn "4.2.3 companion-app-required — $STATIC_REASON" "$STATIC_FILE" ;;
  PASS) pass "4.2.3 companion-app-required — $STATIC_REASON" ;;
  *) static_guideline_gap "companion-app-required" "4.2.3" "$STATIC_REASON" ;;
esac

# §68 — 4.5.5: game-center-id-sharing
set_rule "game-center-id-sharing"
static_guideline_select "game-center-id-sharing"
case "$STATIC_STATUS" in
  WARN) warn "4.5.5 game-center-id-sharing — $STATIC_REASON" "$STATIC_FILE" ;;
  PASS) pass "4.5.5 game-center-id-sharing — $STATIC_REASON" ;;
  *) static_guideline_gap "game-center-id-sharing" "4.5.5" "$STATIC_REASON" ;;
esac

# §69 — 4.5.6: metadata-emoji
set_rule "metadata-emoji"
static_guideline_select "metadata-emoji"
case "$STATIC_STATUS" in
  WARN) warn "4.5.6 metadata-emoji — $STATIC_REASON" "$STATIC_FILE" ;;
  PASS) pass "4.5.6 metadata-emoji — $STATIC_REASON" ;;
  *) static_guideline_gap "metadata-emoji" "4.5.6" "$STATIC_REASON" ;;
esac

STATIC_EMOJI_STATUS="$STATIC_STATUS"

# §70 — 4.7.2: miniapp-native-bridge
set_rule "miniapp-native-bridge"
static_guideline_select "miniapp-native-bridge"
case "$STATIC_STATUS" in
  WARN) warn "4.7.2 miniapp-native-bridge — $STATIC_REASON" "$STATIC_FILE" ;;
  PASS) pass "4.7.2 miniapp-native-bridge — $STATIC_REASON" ;;
  *) static_guideline_gap "miniapp-native-bridge" "4.7.2" "$STATIC_REASON" ;;
esac

# §71 — 5.2.4: apple-endorsement-claims
set_rule "apple-endorsement-claims"
static_guideline_select "apple-endorsement-claims"
case "$STATIC_STATUS" in
  WARN) warn "5.2.4 apple-endorsement-claims — $STATIC_REASON" "$STATIC_FILE" ;;
  PASS) pass "5.2.4 apple-endorsement-claims — $STATIC_REASON" ;;
  *) static_guideline_gap "apple-endorsement-claims" "5.2.4" "$STATIC_REASON" ;;
esac

if [[ "$STATIC_EMOJI_STATUS" != SKIP ]]; then
  static_guideline_gap "metadata-emoji-icon-not-audited" "4.5.6" "Apple emoji artwork in icon pixels requires visual review."
fi
if command -v jq >/dev/null 2>&1; then
  _input_gap="$(printf '%s' "$STATIC_GUIDELINES_JSON" | jq -r '._input_gaps // empty | "\(.count) files skipped: \(.paths | join(", "))"')"
  if [[ -n "$_input_gap" ]]; then static_guideline_gap "source-inputs-not-audited" "source" "$_input_gap"; fi
  STATIC_GAP_REASON="$(printf '%s' "$COVERAGE_GAPS_JSON" | jq -jr '[.[].reason] | unique | join("; ")' | tr '\n\r\t' '   ')"
fi
if [[ "$STATIC_GAP_COUNT" -gt 0 ]]; then
  set_rule "modular-checks-not-audited"
  skip "modular-checks-not-audited — $STATIC_GAP_COUNT check(s) did not run: $STATIC_GAP_SLUGS ($STATIC_GAP_REASON)"
fi
