#!/usr/bin/env bash
# eval/rag/ingest.sh — MAINTAINER-ONLY. Fetches the live App Store Review
# Guidelines and extracts full per-section prose for every section listed in
# guidelines-baseline.json's `all_sections`, writing eval/rag/corpus/sections.json.
# Deliberate human step (like guideline-drift.sh --reconcile) — never run
# automatically, never sourced by scan.sh or any user-facing path.
set -u
GD_URL="https://developer.apple.com/app-store/review/guidelines/"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/lib/guideline-text.sh
source "$here/scripts/lib/guideline-text.sh"

ri_main() {
  local html="" baseline="$here/skills/appstore-precheck/guidelines-baseline.json"
  local out="$here/eval/rag/corpus/sections.json"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --html)     html="$2"; shift 2 ;;
      --baseline) baseline="$2"; shift 2 ;;
      --out)      out="$2"; shift 2 ;;
      *) echo "ingest.sh: unknown arg: $1" >&2; return 64 ;;
    esac
  done

  local tmp=""
  if [[ -z "$html" ]]; then
    tmp="$(mktemp)"; curl -sL --max-time 30 "$GD_URL" -o "$tmp" 2>/dev/null; html="$tmp"
  fi
  if [[ ! -s "$html" ]]; then
    echo "ingest.sh: fetch empty/failed; aborting" >&2
    [[ -n "$tmp" ]] && rm -f "$tmp"
    return 1
  fi

  local sections; sections="$(jq -r '.all_sections[]' "$baseline")"
  local obj='{}' sec text
  while IFS= read -r sec; do
    [[ -z "$sec" ]] && continue
    text="$(gd_section_text "$html" "$sec")"
    if [[ -z "$text" ]]; then
      echo "ingest.sh: WARN — $sec not found on live page; skipping" >&2
      continue
    fi
    obj="$(printf '%s' "$obj" | jq --arg s "$sec" --arg t "$text" \
      '.sections[$s] = {text: $t, char_count: ($t | length)}')"
  done <<< "$sections"

  printf '%s' "$obj" \
    | jq --arg date "$(date -u +%F)" --arg url "$GD_URL" \
        '. + {fetched_on: $date, source_url: $url}' \
    > "$out"
  echo "ingest.sh: wrote $out ($(jq '.sections | length' "$out") sections)"
  [[ -n "$tmp" ]] && rm -f "$tmp"
  return 0
}
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then ri_main "$@"; fi
