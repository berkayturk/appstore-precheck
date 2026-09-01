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
#   guideline-cite.sh --verify-live <guideline>   # network: has Apple changed this section?
#   guideline-cite.sh --list
#   guideline-cite.sh --fingerprints <file> <guideline>
#
# Exit codes: 0 cited | 3 no pinned citation | 4 pinned quote is out of date | 64 bad
#             usage | 66 store unreadable
set -u

GC_BASE_URL="https://developer.apple.com/app-store/review/guidelines/"
# A pinned quote older than this is reported STALE. Not a hard error: an unchanged
# section stays correct indefinitely, but the reader deserves to know its age.
GC_STALE_DAYS="${GUIDELINE_CITE_STALE_DAYS:-120}"
GC_URL="https://developer.apple.com/app-store/review/guidelines/"
# --verify-live caches the fetched page for the day, so checking every finding in a
# run costs one request, not one per finding.
GC_CACHE="${GUIDELINE_CITE_CACHE:-${TMPDIR:-/tmp}/appstore-precheck-guidelines-$(date +%Y%m%d).html}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FINGERPRINTS="$HERE/../guidelines-fingerprints.json"
LIB="$HERE/lib/guideline-text.sh"
MODE="text"; ARG=""; VERIFY_LIVE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) MODE="json"; shift ;;
    --list) MODE="list"; shift ;;
    --verify-live) VERIFY_LIVE=1; shift ;;
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

# --- Optional live verification ------------------------------------------------
# Age-based staleness is a proxy: an untouched section stays correct for years, and a
# section Apple edited yesterday is wrong while still looking fresh. This resolves it
# for real by re-hashing the live section and comparing it to the pinned fingerprint —
# the same comparison the scheduled drift job makes, available at explain time.
CHANGED="false"; LIVE_NOTE=""
if [[ "$VERIFY_LIVE" == 1 ]]; then
  if [[ ! -r "$LIB" ]]; then
    LIVE_NOTE="live check unavailable (parser not found)"
  elif ! command -v curl >/dev/null 2>&1; then
    LIVE_NOTE="live check unavailable (curl not found)"
  else
    # shellcheck source=lib/guideline-text.sh
    . "$LIB"
    [[ -s "$GC_CACHE" ]] || curl -sL --max-time 30 "$GC_URL" -o "$GC_CACHE" 2>/dev/null
    if [[ ! -s "$GC_CACHE" ]]; then
      LIVE_NOTE="live check failed (could not fetch the guidelines page)"
      rm -f "$GC_CACHE"
    else
      _pinned="$(jq -r --arg s "$SECTION" '.sections[$s].fingerprint // ""' "$FINGERPRINTS")"
      _livetxt="$(gd_section_text "$GC_CACHE" "$SECTION")"
      if [[ -z "$_livetxt" ]]; then
        LIVE_NOTE="live check inconclusive ($SECTION not found on the live page)"
      elif [[ -z "$_pinned" ]]; then
        LIVE_NOTE="live check inconclusive (no pinned fingerprint for $SECTION)"
      elif [[ "$(printf '%s' "$_livetxt" | gd_hash)" != "$_pinned" ]]; then
        CHANGED="true"; STALE="true"
      else
        LIVE_NOTE="verified against the live page just now"
        # A section confirmed unchanged is current no matter how old the pin is.
        STALE="false"
      fi
    fi
  fi
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
         --argjson st "$STALE" --arg a "$AGE" --argjson ch "$CHANGED" --arg ln "$LIVE_NOTE" \
    '{guideline:$g, url:$u, cited:true, quote:$q,
      verified_on:(if $v=="" then null else $v end),
      stale:$st, changed:$ch, age_days:(if $a=="" then null else ($a|tonumber) end),
      live_note:(if $ln=="" then null else $ln end)}'
  [[ "$CHANGED" == "true" ]] && exit 4
  exit 0
fi

echo "$SECTION — $URL"
echo "\"$QUOTE\""
if [[ "$CHANGED" == "true" ]]; then
  # The strongest signal available: not "this pin is old" but "Apple's text moved".
  echo "  CHANGED: Apple's text for $SECTION differs from the pinned quote. Treat the wording above as OUT OF DATE — read the live section and say so rather than quoting it as current."
  exit 4
elif [[ "$STALE" == "true" ]]; then
  echo "  pinned quote verified ${VERIFIED} (${AGE} days ago) — STALE: re-verify against the live page before relying on the exact wording."
else
  echo "  pinned quote, verified ${VERIFIED:-undated}${LIVE_NOTE:+ — $LIVE_NOTE}"
fi
