#!/usr/bin/env bash
# image-dims.sh — zero-dependency image format + PNG dimension helpers for scan.sh.
# Pure bash + od + awk; bash 3.2 compatible; sourced, no side effects, no output on load.

# img_format <file> -> "png" | "jpeg" | "unknown"
img_format() {
  local f="$1" sig
  [[ -r "$f" ]] || { echo unknown; return; }
  sig="$(od -An -tx1 -N8 "$f" 2>/dev/null | tr -d ' \n')"
  case "$sig" in
    89504e470d0a1a0a*) echo png ;;
    ffd8ff*)           echo jpeg ;;
    *)                 echo unknown ;;
  esac
}

# png_dims <file> -> "W H" (decimal) and return 0, or return 1 with no output.
# IHDR width = big-endian bytes 16-19, height = 20-23 (8-byte signature + 4-byte
# length + "IHDR" tag precede the 8 dimension bytes at offset 16).
png_dims() {
  local f="$1"
  [[ "$(img_format "$f")" == png ]] || return 1
  local b
  read -r -a b < <(od -An -tu1 -j16 -N8 "$f" 2>/dev/null)
  [[ "${#b[@]}" -ge 8 ]] || return 1
  local w=$(( b[0]*16777216 + b[1]*65536 + b[2]*256 + b[3] ))
  local h=$(( b[4]*16777216 + b[5]*65536 + b[6]*256 + b[7] ))
  printf '%s %s\n' "$w" "$h"
}

# ACCEPTED_SIZES — Apple App Store screenshot pixel sizes (portrait "W H").
# The matcher tries both orientations. This table is intentionally generous
# (includes current + legacy device sizes) because this check is WARN-only.
# Verified against Apple's official page:
# https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications/
ACCEPTED_SIZES="
1260 2736
1290 2796
1320 2868
1284 2778
1242 2688
1179 2556
1206 2622
1170 2532
1125 2436
1080 2340
1242 2208
750 1334
640 1096
640 1136
640 920
640 960
2064 2752
2048 2732
1488 2266
1668 2420
1668 2388
1640 2360
1668 2224
1536 2008
1536 2048
768 1004
768 1024
"

# dims_match_accepted <W> <H> -> return 0 if W×H or H×W is an accepted size.
dims_match_accepted() {
  local w="$1" h="$2" aw ah
  while read -r aw ah; do
    [[ -z "$aw" ]] && continue
    if { [[ "$w" == "$aw" && "$h" == "$ah" ]]; } || { [[ "$w" == "$ah" && "$h" == "$aw" ]]; }; then
      return 0
    fi
  done <<< "$ACCEPTED_SIZES"
  return 1
}
