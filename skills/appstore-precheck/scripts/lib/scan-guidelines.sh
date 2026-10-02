#!/usr/bin/env bash
# Additional source checks are advisory; absent inputs remain additive coverage gaps.
# shellcheck disable=SC2034
COVERAGE_GAPS_JSON="${COVERAGE_GAPS_JSON:-[]}"
STATIC_GAP_COUNT=0 STATIC_GAP_TOTAL=0 STATIC_GAP_SLUGS="" STATIC_GAP_REASON="" STATIC_EMOJI_STATUS=SKIP
STATIC_GUIDELINES_JSON='{}'
# The reader understands only --exclude-dir=... entries; grep-only flags such as `-D skip` stay out.
STATIC_READER_EXCLUDES=()
for _prune in "${GREP_PRUNE[@]+"${GREP_PRUNE[@]}"}"; do
  case "$_prune" in --exclude-dir=*) STATIC_READER_EXCLUDES+=("$_prune") ;; esac
done
if command -v python3 >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  STATIC_GUIDELINES_JSON="$(python3 -B "$SCRIPT_DIR/lib/static-reader.py" \
    --root "$ROOT" --metadata "${META_DIR:-/nonexistent}" --plist "${INFO_PLIST:-/nonexistent}" \
    "${STATIC_READER_EXCLUDES[@]+"${STATIC_READER_EXCLUDES[@]}"}" )" || STATIC_GUIDELINES_JSON='{"_reader_error":"reader invocation failed; see stderr"}'
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
  STATIC_GAP_TOTAL=$((STATIC_GAP_TOTAL + 1))
  case "$id" in
    *-not-audited) ;;
    *) STATIC_GAP_COUNT=$((STATIC_GAP_COUNT + 1))
       STATIC_GAP_SLUGS="${STATIC_GAP_SLUGS}${STATIC_GAP_SLUGS:+, }$id" ;;
  esac
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

# §56–§71: slug | guideline | evidence class. Keep coverage-sections.py in sync.
while IFS='|' read -r _static_slug _static_guideline _static_evidence; do
  set_rule "$_static_slug"
  set_evidence "$_static_evidence"
  static_guideline_select "$_static_slug"
  case "$STATIC_STATUS" in
    WARN) warn "$_static_guideline $_static_slug — $STATIC_REASON" "$STATIC_FILE" ;;
    PASS) pass "$_static_guideline $_static_slug — $STATIC_REASON" ;;
    *) static_guideline_gap "$_static_slug" "$_static_guideline" "$STATIC_REASON" ;;
  esac
  if [[ "$_static_slug" == metadata-emoji ]]; then STATIC_EMOJI_STATUS="$STATIC_STATUS"; fi
done <<'STATIC_GUIDELINE_TABLE'
release-notes-specificity|2.3.12|metadata
device-restart-instructions|2.4.4|source
browser-engine|2.5.6|source
intent-handler-parity|2.5.11|source
call-filter-controls|2.5.12|source
face-authentication|2.5.13|source
document-browser-access|2.5.15|source
extension-bundle-parity|2.5.16|source
matter-extension|2.5.17|source
extension-advertising|2.5.18|source
ar-integration-depth|4.2.1|source
companion-app-required|4.2.3|source
game-center-id-sharing|4.5.5|source
metadata-emoji|4.5.6|resource
miniapp-native-bridge|4.7.2|source
apple-endorsement-claims|5.2.4|metadata
STATIC_GUIDELINE_TABLE

if [[ "$STATIC_EMOJI_STATUS" != SKIP ]]; then
  static_guideline_gap "metadata-emoji-icon-not-audited" "4.5.6" "Apple emoji artwork in icon pixels requires visual review."
fi
STATIC_GAP_FALLBACK_SLUGS="$STATIC_GAP_SLUGS" STATIC_GAP_REASON_FALLBACK="$STATIC_GAP_REASON"
if command -v jq >/dev/null 2>&1; then
  _input_gap="$(printf '%s' "$STATIC_GUIDELINES_JSON" | jq -r '._input_gaps // empty | "\(.count) files skipped: \(.paths | join(", "))"')"
  if [[ -n "$_input_gap" ]]; then static_guideline_gap "source-inputs-not-audited" "source" "$_input_gap"; fi
  STATIC_GAP_SLUGS="$(printf '%s' "$COVERAGE_GAPS_JSON" | jq -jr '
    def grouped: group_by(.reason) | map((map(.rule_id) | join(", ")) + " (" + .[0].reason + ")") | join("; ");
    [.[] | select(.rule_id | endswith("-not-audited") | not)] | grouped' | tr '\n\r\t' '   ')"
  STATIC_GAP_REASON="$(printf '%s' "$COVERAGE_GAPS_JSON" | jq -jr '
    [.[] | select(.rule_id | endswith("-not-audited"))] |
    map(.rule_id + " (" + .reason + ")") | join("; ")' | tr '\n\r\t' '   ')"
  if [[ -z "$STATIC_GAP_SLUGS" && -n "$STATIC_GAP_FALLBACK_SLUGS" ]]; then
    # jq is present but failed: fall back to the bash accumulator so the list is never empty.
    STATIC_GAP_SLUGS="$STATIC_GAP_FALLBACK_SLUGS ($STATIC_GAP_REASON_FALLBACK)"
  fi
  STATIC_GAP_SLUGS="${STATIC_GAP_SLUGS}${STATIC_GAP_REASON:+; additional coverage gaps: $STATIC_GAP_REASON}"
else
  STATIC_GAP_SLUGS="$STATIC_GAP_SLUGS ($STATIC_GAP_REASON)"
fi
if [[ "$STATIC_GAP_TOTAL" -gt 0 ]]; then
  set_rule "modular-checks-not-audited"
  if [[ "$STATIC_GAP_COUNT" -eq 0 ]]; then
    skip "modular-checks-not-audited — additional coverage gaps: $STATIC_GAP_REASON"
  else
    skip "modular-checks-not-audited — $STATIC_GAP_COUNT check(s) did not run: $STATIC_GAP_SLUGS"
  fi
fi
