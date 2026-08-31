#!/usr/bin/env bash
# guideline-cite.sh — offline lookup of a PINNED App Store Review Guideline quote.
#
# WHY THIS EXISTS
# ---------------
# Pierre explains every FAIL and WARN, and an explanation is only worth reading if
# the guideline wording behind it is Apple's, not the model's recollection of it.
# Two ways to get that wording, and they trade off differently:
#
#   fetch the page every run  — always current, but needs the network, truncates
#                               past ~5.4, and gives a different answer each run
#   quote a pinned snapshot   — offline, deterministic, reviewable in git, and can
#                               be checked for staleness by the drift job
#
# This tool is the second. The pinned quotes live in guidelines-fingerprints.json
# beside the fingerprints that already detect when Apple changes a section, so a
# quote that has gone out of date is a detectable condition rather than a silent
# lie. When there is no pinned quote, this exits non-zero and says NO PINNED
# CITATION — the caller must then say the wording could not be verified. It must
# never reconstruct guideline text from memory.
#
# Usage:
#   guideline-cite.sh <guideline>            # e.g. 5.1.1, 5.1.1(v), 3.1.1(a)
#   guideline-cite.sh --json <guideline>
#   guideline-cite.sh --list
#   guideline-cite.sh --fingerprints <file> <guideline>
#
# Exit codes: 0 cited | 3 no pinned citation | 64 bad usage | 66 store unreadable
set -u

GC_BASE_URL="https://developer.apple.com/app-store/review/guidelines/"
# A pinned quote older than this is reported STALE. Not a hard error: an unchanged
# section stays correct indefinitely, but the reader deserves to know its age.
GC_STALE_DAYS="${GUIDELINE_CITE_STALE_DAYS:-120}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FINGERPRINTS="$HERE/../guidelines-fingerprints.json"
MODE="text"; ARG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) MODE="json"; shift ;;
    --list) MODE="list"; shift ;;
    --fingerprints)
      [[ $# -lt 2 ]] && { echo "guideline-cite.sh: --fingerprints needs a path" >&2; exit 64; }
      FINGERPRINTS="$2"; shift 2 ;;
    --fingerprints=*) FINGERPRINTS="${1#*=}"; shift ;;
    -h|--help) sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "guideline-cite.sh: unknown option '$1'" >&2; exit 64 ;;
    *) ARG="$1"; shift ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "guideline-cite.sh: jq is required" >&2; exit 66; }
[[ -r "$FINGERPRINTS" ]] || { echo "guideline-cite.sh: cannot read $FINGERPRINTS" >&2; exit 66; }

if [[ "$MODE" == "list" ]]; then
  jq -r '.sections | to_entries
         | map(select(.value.quote != null and .value.quote != ""))
         | sort_by(.key)[]
         | "\(.key)\t\(.value.quote_verified_on // "undated")"' "$FINGERPRINTS"
  exit 0
fi

[[ -n "$ARG" ]] || { echo "guideline-cite.sh: needs a guideline number (e.g. 5.1.1)" >&2; exit 64; }

# Apple anchors sections by their bare number; 5.1.1(v) and 3.1.1(a) are prose
# sub-items of 5.1.1 and 3.1.1, not separate anchors. Resolve to the stem.
SECTION="${ARG%%(*}"
[[ "$SECTION" =~ ^[1-5](\.[0-9]+)+$ ]] || {
  echo "guideline-cite.sh: '$ARG' is not a guideline number" >&2; exit 64; }
URL="${GC_BASE_URL}#${SECTION}"

QUOTE="$(jq -r --arg s "$SECTION" '.sections[$s].quote // ""' "$FINGERPRINTS")"
VERIFIED="$(jq -r --arg s "$SECTION" '.sections[$s].quote_verified_on // ""' "$FINGERPRINTS")"

# _days <YYYY-MM-DD> -> days since the civil epoch (Howard Hinnant's algorithm).
# Pure arithmetic on purpose: `date -d` (GNU) and `date -j -f` (BSD) disagree, and
# this script runs on both a developer laptop and CI.
_days() {
  local y m d era yoe doy doe
  y=${1%%-*}; m=${1:5:2}; d=${1:8:2}
  y=$((10#$y)); m=$((10#$m)); d=$((10#$d))
  (( m <= 2 )) && y=$((y - 1))
  (( y >= 0 )) && era=$((y / 400)) || era=$(( (y - 399) / 400 ))
  yoe=$((y - era * 400))
  if (( m > 2 )); then doy=$(( (153 * (m - 3) + 2) / 5 + d - 1 ))
  else doy=$(( (153 * (m + 9) + 2) / 5 + d - 1 )); fi
  doe=$(( yoe * 365 + yoe / 4 - yoe / 100 + doy ))
  echo $(( era * 146097 + doe - 719468 ))
}

STALE="false"; AGE=""
if [[ -n "$VERIFIED" && "$VERIFIED" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  AGE=$(( $(_days "$(date +%F)") - $(_days "$VERIFIED") ))
  (( AGE > GC_STALE_DAYS )) && STALE="true"
fi

if [[ -z "$QUOTE" ]]; then
  if [[ "$MODE" == "json" ]]; then
    jq -nc --arg g "$SECTION" --arg u "$URL" \
      '{guideline:$g, url:$u, cited:false, quote:null, verified_on:null, stale:false,
        reason:"no pinned citation for this section"}'
  else
    echo "NO PINNED CITATION for $SECTION"
    echo "  source: $URL"
    echo "  Say the wording could not be verified this run. Do NOT quote guideline text from memory."
  fi
  exit 3
fi

if [[ "$MODE" == "json" ]]; then
  jq -nc --arg g "$SECTION" --arg u "$URL" --arg q "$QUOTE" --arg v "$VERIFIED" \
         --argjson st "$STALE" --arg a "$AGE" \
    '{guideline:$g, url:$u, cited:true, quote:$q,
      verified_on:(if $v=="" then null else $v end),
      stale:$st, age_days:(if $a=="" then null else ($a|tonumber) end)}'
  exit 0
fi

echo "$SECTION — $URL"
echo "\"$QUOTE\""
if [[ "$STALE" == "true" ]]; then
  echo "  pinned quote verified ${VERIFIED} (${AGE} days ago) — STALE: re-verify against the live page before relying on the exact wording."
else
  echo "  pinned quote, verified ${VERIFIED:-undated}"
fi
