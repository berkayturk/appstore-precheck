#!/usr/bin/env bash
# Additional observations are collected only after a verified owned fresh erase.
# Dependencies: HERE, UDID/BID/INSTALLED/EXE/REPO, OUT and the runner's emit helper.
dyn_extended_capture() {
  local folder="$DYN_EXT_DIR/repeat-$1" pid="" tree="$OUT/hierarchy-$1.json"
  mkdir "$folder" || return 0
  [[ -f "$DYN_EXT_DIR/pid-$1.txt" ]] && pid="$(cat "$DYN_EXT_DIR/pid-$1.txt")"
  [[ "${LAST_SIGNALS##*,}" != unread ]] || tree="$folder/unavailable.json"
  python3 -B "$HERE/lib/dyn-process.py" --timeout 240 --grace 1 -- \
    python3 -B "$HERE/lib/dyn-guideline-capture.py" \
    --udid "$UDID" --bundle-id "$BID" --app "$INSTALLED" --executable "$EXE" \
    --pid "$pid" --initial-tree "$tree" --repo "$REPO" \
    --out "$folder" --repeat "$1" --fresh-owned > "$DYN_EXT_DIR/repeat-$1.json" 2> "$DYN_EXT_DIR/repeat-$1.stderr.log" || {
      printf 'Additional observation collector failed; see %s\n' "$DYN_EXT_DIR/repeat-$1.stderr.log" >&2
    }
}

dyn_extended_report() {
  local line
  while IFS= read -r line; do emit "$line"; done < <(
    python3 -B "$HERE/lib/dyn-guidelines.py" "$DYN_EXT_DIR" --expected "$REPEATS"
  )
}
