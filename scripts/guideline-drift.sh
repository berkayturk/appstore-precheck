#!/usr/bin/env bash
# guideline-drift.sh — MAINTAINER/CI tool. Detects section-number and text (semantic)
# drift of the App Store Review Guidelines sections our checks depend on.
# Network-using (curl); NEVER sourced by scan.sh and NEVER in the user scan path.
# READ-ONLY except `--reconcile`, which rewrites guidelines-fingerprints.json (a
# deliberate human step). Non-blocking: WARN lines, exit 0.
set -u

GD_URL="https://developer.apple.com/app-store/review/guidelines/"

# gd_section_ids <html> -> numeric guideline anchor ids, document order, deduped.
gd_section_ids() {
  grep -oE 'id="[1-5](\.[0-9]+)*"' "$1" 2>/dev/null \
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
  | sed -E 's/^ +//; s/ +$//'
}

# main runs only when executed directly (so tests can source the functions).
gd_main() { :; }   # fleshed out in Task 3
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then gd_main "$@"; fi
