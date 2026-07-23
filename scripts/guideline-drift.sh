#!/usr/bin/env bash
# guideline-drift.sh — MAINTAINER/CI tool. Detects section-number and text (semantic)
# drift of the App Store Review Guidelines sections our checks depend on.
# Network-using (curl); NEVER sourced by scan.sh and NEVER in the user scan path.
# READ-ONLY except `--reconcile`, which rewrites guidelines-fingerprints.json (a
# deliberate human step). Non-blocking: WARN lines, exit 0.
set -u

GD_URL="https://developer.apple.com/app-store/review/guidelines/"

here_lib="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here_lib/lib/guideline-text.sh"

# gd_number_drift <live-ids-file> <baseline-json> -> ADDED/REMOVED lines.
gd_number_drift() {
  local live="$1" base="$2" bfile
  bfile="$(mktemp)"; jq -r '.all_sections[]' "$base" 2>/dev/null | sort -u > "$bfile"
  comm -23 <(sort -u "$live") "$bfile" | sed 's/^/ADDED /'
  comm -13 <(sort -u "$live") "$bfile" | sed 's/^/REMOVED /'
  rm -f "$bfile"
}

# gd_checks_for_section <scan.sh> <section> -> scan rule-id(s) whose set_rule block
# cites that guideline number, one per line. Derived, never stored (cannot rot).
gd_checks_for_section() {
  awk -v want="$2" '
    /set_rule "/ { if (match($0, /set_rule "([^"]+)"/)) slug = substr($0, RSTART+10, RLENGTH-11) }
    slug != "" && $0 !~ /^[[:space:]]*#/ {
      s = $0
      while (match(s, /[1-5]\.[0-9]+(\.[0-9]+)?/)) {
        if (substr(s, RSTART, RLENGTH) == want) { print slug; break }
        s = substr(s, RSTART + RLENGTH)
      }
    }
  ' "$1" | awk '!seen[$0]++'
}

# gd_main [--html f] [--baseline f] [--fingerprints f] [--scan f] [--reconcile]
gd_main() {
  local html="" reconcile=0
  local here; here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  local baseline="$here/skills/appstore-precheck/guidelines-baseline.json"
  local fingerprints="$here/skills/appstore-precheck/guidelines-fingerprints.json"
  local scan="$here/skills/appstore-precheck/scripts/scan.sh"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --html|--baseline|--fingerprints|--scan)
        if [[ $# -lt 2 ]]; then echo "WARN: guideline-drift — missing value for $1; ignoring."; shift; continue; fi
        case "$1" in
          --html) html="$2" ;;
          --baseline) baseline="$2" ;;
          --fingerprints) fingerprints="$2" ;;
          --scan) scan="$2" ;;
        esac
        shift 2 ;;
      --reconcile) reconcile=1; shift ;;
      *) echo "WARN: guideline-drift — unknown arg: $1; ignoring."; shift ;;
    esac
  done

  # 1. Obtain the HTML (local file or curl).
  local tmp=""
  if [[ -z "$html" ]]; then
    tmp="$(mktemp)"; curl -sL --max-time 30 "$GD_URL" -o "$tmp" 2>/dev/null; html="$tmp"
  fi
  if [[ ! -s "$html" ]]; then
    echo "WARN: guideline-drift-check degraded — fetch empty/failed; verify manually."
    [[ -n "$tmp" ]] && rm -f "$tmp"; return 0
  fi

  # Covered sections = covered_by_scan ∪ covered_by_pierre_deep_review.
  local covered; covered="$(jq -r '(.covered_by_scan // []) + (.covered_by_pierre_deep_review // []) | unique[]' "$baseline" 2>/dev/null)"

  if [[ "$reconcile" == 1 ]]; then
    # Surface section-number drift first — --reconcile should never silently paper
    # over an ADDED/REMOVED section number just because it's about to rewrite text
    # fingerprints for the (possibly stale) covered set.
    local liveids_r; liveids_r="$(mktemp)"; gd_section_ids "$html" > "$liveids_r"
    gd_number_drift "$liveids_r" "$baseline" | while IFS= read -r line; do
      [[ -n "$line" ]] && echo "WARN: guideline-drift section-number change: $line"
    done
    rm -f "$liveids_r"

    # Rewrite the fingerprints file from the live page (deliberate human step).
    # A covered section that no longer resolves to any prose on the live page
    # (removed/renumbered) must NOT get an empty-hash placeholder — that would
    # silently pass future drift checks forever. Warn and omit it instead; a
    # human must reconcile guidelines-baseline.json to point at the new number.
    local obj='{}' sec norm hash snap written=0
    while IFS= read -r sec; do
      [[ -z "$sec" ]] && continue
      norm="$(gd_section_text "$html" "$sec")"
      if [[ -z "$norm" ]]; then
        echo "WARN: reconcile — $sec not found on live page (removed/renumbered?); skipping"
        continue
      fi
      hash="$(printf '%s' "$norm" | gd_hash)"
      snap="$(printf '%s' "$norm" | cut -c1-160)"
      obj="$(printf '%s' "$obj" | jq --arg s "$sec" --arg h "$hash" --arg n "$snap" '.sections[$s] = {fingerprint:$h, snapshot:$n}')"
      written=$((written + 1))
    done <<< "$covered"
    printf '%s' "$obj" | jq --arg d "$(date +%F)" '. + {reconciled_on: $d}' > "$fingerprints"
    echo "reconciled ${fingerprints} (${written} sections)"
    [[ -n "$tmp" ]] && rm -f "$tmp"; return 0
  fi

  # 2. Number drift (full page vs baseline all_sections).
  local liveids; liveids="$(mktemp)"; gd_section_ids "$html" > "$liveids"
  gd_number_drift "$liveids" "$baseline" | while IFS= read -r line; do
    [[ -n "$line" ]] && echo "WARN: guideline-drift section-number change: $line"
  done
  rm -f "$liveids"

  # 3. Text (semantic) drift for covered sections.
  local sec live_hash base_hash checks
  while IFS= read -r sec; do
    [[ -z "$sec" ]] && continue
    base_hash="$(jq -r --arg s "$sec" '.sections[$s].fingerprint // ""' "$fingerprints" 2>/dev/null)"
    [[ -z "$base_hash" ]] && continue   # no baseline fingerprint -> nothing to compare
    live_hash="$(printf '%s' "$(gd_section_text "$html" "$sec")" | gd_hash)"
    if [[ "$live_hash" != "$base_hash" ]]; then
      checks="$(gd_checks_for_section "$scan" "$sec" | tr '\n' ' ' | sed 's/ *$//')"
      [[ -z "$checks" ]] && checks="(covered — review manually)"
      echo "WARN: guideline text drift — $sec changed since baseline; review check(s): $checks"
    fi
  done <<< "$covered"

  [[ -n "$tmp" ]] && rm -f "$tmp"
  return 0
}
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then gd_main "$@"; fi
