#!/usr/bin/env bash
# guideline-drift.sh — MAINTAINER/CI tool. Detects section-number and text (semantic)
# drift of the App Store Review Guidelines sections our checks depend on.
# Network-using (curl); NEVER sourced by scan.sh and NEVER in the user scan path.
# READ-ONLY except `--reconcile`, which rewrites guidelines-fingerprints.json (a
# deliberate human step). Non-blocking: WARN lines, exit 0.
set -u

GD_URL="https://developer.apple.com/app-store/review/guidelines/"

# The shared parser lives inside the skill (skills/appstore-precheck/scripts/lib/)
# rather than beside this maintainer script, because it also has to ship to installed
# users: guideline-cite.sh --verify-live needs it, and only the skill dir is packaged.
here_lib="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$here_lib/skills/appstore-precheck/scripts/lib/guideline-text.sh"

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
  local module base files=( "$1" )
  base="$(dirname "$1")"
  while IFS= read -r module; do
    [[ -f "$base/$module" ]] && files+=( "$base/$module" )
  done < <(sed -nE 's/^[[:space:]]*(source|\.) "\$SCRIPT_DIR\/(lib\/scan-[[:alnum:]_-]+\.sh)".*/\2/p' "$1")
  awk -v want="$2" '
    /set_rule "/ { if (match($0, /set_rule "([^"]+)"/)) slug = substr($0, RSTART+10, RLENGTH-11) }
    slug != "" && $0 !~ /^[[:space:]]*#/ {
      s = $0
      while (match(s, /[1-5]\.[0-9]+(\.[0-9]+)?/)) {
        if (substr(s, RSTART, RLENGTH) == want) { print slug; break }
        s = substr(s, RSTART + RLENGTH)
      }
    }
  ' "${files[@]}" | awk '!seen[$0]++'
}

gd_covered_sections() {
  jq -r '(.covered_by_scan // []) + (.covered_by_pierre_deep_review // []) +
    (.covered_by_dynamic // []) + (.covered_by_vision // []) | unique[]' "$1"
}

# gd_main [--html f] [--baseline f] [--fingerprints f] [--scan f] [--reconcile] [--quotes]
gd_main() {
  local html="" reconcile=0 quotes=0
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
      --quotes) quotes=1; shift ;;
      --quote-chars)
        if [[ $# -lt 2 ]]; then echo "WARN: guideline-drift — missing value for --quote-chars; ignoring."; shift; continue; fi
        GD_QUOTE_CHARS="$2"; shift 2 ;;
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

  # Every maintained observation route participates; this is not a compliance claim.
  local covered; covered="$(gd_covered_sections "$baseline" 2>/dev/null)"

  # --quotes: fill in the citable `quote` for each covered section WITHOUT touching
  # fingerprints or reconciled_on. Kept separate from --reconcile on purpose: writing
  # a quote must never double as accepting a drift.
  #
  # A section is only re-quoted when its LIVE fingerprint still matches the pinned
  # one. Quoting a section that has drifted would take the new wording while the
  # fingerprint still claims the old — papering over exactly the change the drift
  # check exists to surface. Drifted sections are warned about and left alone, so a
  # human reconciles the fingerprint first, then re-runs --quotes.
  if [[ "$quotes" == 1 ]]; then
    local qobj sec qnorm qhash qbase qtext written=0 skipped=0 today
    today="$(date +%F)"
    qobj="$(cat "$fingerprints")"
    while IFS= read -r sec; do
      [[ -z "$sec" ]] && continue
      qbase="$(jq -r --arg s "$sec" '.sections[$s].fingerprint // ""' "$fingerprints")"
      [[ -z "$qbase" ]] && continue          # not pinned at all; --reconcile owns that
      qnorm="$(gd_section_text "$html" "$sec")"
      if [[ -z "$qnorm" ]]; then
        echo "WARN: quotes — $sec not found on live page; leaving its quote untouched"
        skipped=$((skipped + 1)); continue
      fi
      qhash="$(printf '%s' "$qnorm" | gd_hash)"
      if [[ "$qhash" != "$qbase" ]]; then
        echo "WARN: quotes — $sec has drifted since the fingerprint baseline; reconcile first, then re-run --quotes"
        skipped=$((skipped + 1)); continue
      fi
      # Character overrides may shorten the excerpt, never exceed the word budget.
      qtext="$(gd_section_quote "$html" "$sec" "${GD_QUOTE_CHARS:-600}" | awk '{
        for (i = 1; i <= NF && words < 25; i++) { printf "%s%s", (words ? " " : ""), $i; words++ }
      } END { if (words) printf "\n" }')"
      if [[ -z "$qtext" ]]; then
        echo "WARN: quotes — $sec produced an empty quote; skipping"
        skipped=$((skipped + 1)); continue
      fi
      qobj="$(printf '%s' "$qobj" | jq --arg s "$sec" --arg q "$qtext" --arg d "$today" \
                '.sections[$s].quote = $q | .sections[$s].quote_verified_on = $d')"
      written=$((written + 1))
    done <<< "$covered"
    printf '%s\n' "$qobj" | jq . > "$fingerprints"
    echo "quotes: ${written} section(s) pinned, ${skipped} skipped -> ${fingerprints}"
    [[ -n "$tmp" ]] && rm -f "$tmp"; return 0
  fi

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
      # Carry an existing pinned quote forward ONLY when the text is unchanged.
      # Rebuilding the entry from scratch would silently drop every citation (and a
      # later --quotes run would re-date them all as if freshly verified). When the
      # section HAS drifted, the old quote is now wrong, so it is deliberately
      # dropped: guideline-cite.sh then reports NO PINNED CITATION, which is the
      # honest state until someone re-runs --quotes.
      local prev_hash prev_q prev_d entry
      prev_hash="$(jq -r --arg s "$sec" '.sections[$s].fingerprint // ""' "$fingerprints" 2>/dev/null)"
      prev_q="$(jq -r --arg s "$sec" '.sections[$s].quote // ""' "$fingerprints" 2>/dev/null)"
      prev_d="$(jq -r --arg s "$sec" '.sections[$s].quote_verified_on // ""' "$fingerprints" 2>/dev/null)"
      entry="$(jq -nc --arg h "$hash" --arg n "$snap" '{fingerprint:$h, snapshot:$n}')"
      if [[ "$prev_hash" == "$hash" && -n "$prev_q" ]]; then
        entry="$(printf '%s' "$entry" | jq --arg q "$prev_q" --arg d "$prev_d" \
                  '. + {quote:$q, quote_verified_on:(if $d=="" then null else $d end)}')"
      elif [[ -n "$prev_q" ]]; then
        echo "WARN: reconcile — $sec text changed; its pinned quote was dropped (re-run --quotes)"
      fi
      obj="$(printf '%s' "$obj" | jq --arg s "$sec" --argjson e "$entry" '.sections[$s] = $e')"
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
