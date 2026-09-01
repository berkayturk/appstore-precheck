#!/usr/bin/env bash
# scripts/lib/guideline-text.sh — shared Apple App Store Review Guidelines HTML
# parsing helpers. Source this; do not execute directly. Used by
# scripts/guideline-drift.sh (drift detection) and eval/rag/ingest.sh (RAG corpus
# ingestion) so the extraction logic has exactly one implementation.

# gd_section_ids <html> -> numeric guideline anchor ids, document order, deduped.
# Sub-sections come out as anchored (id="2.3.3" -> 2.3.3). The five bare category
# anchors (id="1".."5") come out as "N.0": Apple's own rejection notices cite the
# category intro prose that way ("Guideline 4.0 - Design", the #1 removal reason in
# Apple's 2024 transparency report), but the page has no id="4.0" — only the
# category header's id="4", verified live 2026-09-01. Mapping it here is what lets
# the intro prose be baselined, fingerprinted and cited like any other section.
# Anything else with a bare digit id (nav chrome such as id="globalnav-4") has a
# non-numeric prefix and is not matched.
gd_section_ids() {
  grep -oE 'id="[1-5](\.[0-9]+)*"' "$1" 2>/dev/null \
    | sed -E 's/^id="//; s/"$//' \
    | sed -E 's/^([1-5])$/\1.0/' \
    | awk '!seen[$0]++'
}

# gd_anchor_id <section> -> the id attribute that section carries on the live page.
# "N.0" is our name for a category intro; Apple anchors it as the bare "N". Every
# other section is its own anchor. Shared by the text helpers and the URL builders
# so a "#4.0" link (which resolves to nothing) can never be produced.
gd_anchor_id() {
  case "$1" in
    [1-5].0) printf '%s' "${1%.0}" ;;
    *) printf '%s' "$1" ;;
  esac
}

# _gd_section_raw <html> <id> -> normalized prose for exactly that section, in the
# ORIGINAL case. Shared by gd_section_text (which lowercases it for fingerprinting)
# and gd_section_quote (which keeps the case, because a citation has to read like
# Apple wrote it). Lowercasing moved to the caller: tr and the whitespace squeeze
# commute, so gd_section_text is byte-identical to before this split.
_gd_section_raw() {
  local html="$1" want
  want="$(gd_anchor_id "$2")"
  # Replace each opening guideline-anchor tag (e.g. <span id="2.3.3"> or <li id="2.3.3" ...>)
  # with a whole-tag sentinel @@SEC:<id>@@ on its own line, so no partial tag leaks.
  sed -E 's#<[a-zA-Z]+[^>]*id="([1-5](\.[0-9]+)*)"[^>]*>#\'$'\n''@@SEC:\1@@#g' "$html" \
  | awk -v want="$want" '
      {
        if ($0 ~ /^@@SEC:/) {
          id=$0; sub(/^@@SEC:/,"",id); sub(/@@.*/,"",id)
          insec = (id == want)
          sub(/^@@SEC:[^@]*@@/,"")   # drop the sentinel, keep any trailing content on the line
        }
        if (insec) buf = buf $0 " "
      }
      END { printf "%s", buf }
    ' \
  | sed -E 's/<[^>]+>/ /g' \
  | sed -E 's/&amp;/\&/g; s/&lt;/</g; s/&gt;/>/g; s/&#39;/'\''/g; s/&quot;/"/g; s/&nbsp;/ /g' \
  | tr -s ' \t\n' ' ' \
  | sed -E 's/^ +//; s/ +$//'
}

# gd_section_text <html> <id> -> normalized, LOWERCASED prose for exactly that
# section. This is the fingerprint input; its bytes must stay stable.
gd_section_text() {
  _gd_section_raw "$1" "$2" \
  | tr 'A-Z' 'a-z' \
  | sed -E 's/ after you submit once .*$//; s/ last updated: .*$//'
}
# That final sed guards the LAST numbered section (currently 5.6.4): it has no
# following section anchor, so the raw extraction runs to end-of-page and would
# glue the "After You Submit" info block, the "last updated" date, and the whole
# site footer (program lists etc.) onto its prose — making its fingerprint churn
# on every footer edit. Both markers are page chrome, never guideline prose.

# gd_section_quote <html> <id> [max-chars] -> a citable, original-case excerpt of
# that section, cut at a sentence boundary. Default 600 chars.
#
# The page-chrome tail (the "After You Submit" block and the footer) is stripped by
# gd_section_text case-sensitively on lowercased text. Rather than duplicate those
# patterns for mixed case, take the raw prose and keep exactly as many characters as
# the trimmed lowercase form has: lowercasing preserves length, and the tail strip
# only ever removes a suffix, so the prefix lengths line up exactly.
gd_section_quote() {
  local html="$1" want="$2" max="${3:-600}" raw norm n quote
  raw="$(_gd_section_raw "$html" "$want")"
  [[ -z "$raw" ]] && { printf ''; return; }
  norm="$(gd_section_text "$html" "$want")"
  n=${#norm}
  quote="${raw:0:$n}"
  (( ${#quote} <= max )) && { printf '%s' "$quote"; return; }
  # Prefer the last sentence end inside the budget; fall back to a word boundary,
  # then to a hard cut. A citation that stops mid-word reads like a bug.
  local head="${quote:0:$max}" cut
  cut="$(printf '%s' "$head" | awk '{ n=0; for(i=length($0); i>1; i--) { c=substr($0,i,1); d=substr($0,i+1,1); if (c=="." && d==" ") { n=i; break } } print n }')"
  if (( cut > max / 3 )); then printf '%s' "${head:0:$cut}"; return; fi
  cut="${head% *}"
  printf '%s…' "$cut"
}

# gd_hash -> sha256 hex of stdin (portable across macOS/Linux).
gd_hash() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1
  else shasum -a 256 | cut -d' ' -f1; fi
}
