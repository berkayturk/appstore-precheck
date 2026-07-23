#!/usr/bin/env bash
# scripts/lib/guideline-text.sh — shared Apple App Store Review Guidelines HTML
# parsing helpers. Source this; do not execute directly. Used by
# scripts/guideline-drift.sh (drift detection) and eval/rag/ingest.sh (RAG corpus
# ingestion) so the extraction logic has exactly one implementation.

# gd_section_ids <html> -> numeric guideline anchor ids, document order, deduped.
# Requires at least one dotted component so bare top-level category anchors
# (id="1".."5") aren't tracked as drift-able sections — those are just the
# five category headers, not sub-sections with their own prose.
gd_section_ids() {
  grep -oE 'id="[1-5](\.[0-9]+)+"' "$1" 2>/dev/null \
    | sed -E 's/^id="//; s/"$//' \
    | awk '!seen[$0]++'
}

# gd_section_text <html> <id> -> normalized prose for exactly that section.
gd_section_text() {
  local html="$1" want="$2"
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
  | tr 'A-Z' 'a-z' \
  | tr -s ' \t\n' ' ' \
  | sed -E 's/^ +//; s/ +$//' \
  | sed -E 's/ after you submit once .*$//; s/ last updated: .*$//'
}
# The final sed guards the LAST numbered section (currently 5.6.4): it has no
# following section anchor, so the raw extraction runs to end-of-page and would
# glue the "After You Submit" info block, the "last updated" date, and the whole
# site footer (program lists etc.) onto its prose — making its fingerprint churn
# on every footer edit. Both markers are page chrome, never guideline prose.

# gd_hash -> sha256 hex of stdin (portable across macOS/Linux).
gd_hash() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1
  else shasum -a 256 | cut -d' ' -f1; fi
}
