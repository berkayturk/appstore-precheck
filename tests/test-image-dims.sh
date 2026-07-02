#!/usr/bin/env bash
# tests/test-image-dims.sh — unit tests for image-dims.sh (format + PNG dims).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/_assert.sh
source "$HERE/_assert.sh"
# shellcheck source=skills/appstore-precheck/scripts/image-dims.sh
source "$HERE/../skills/appstore-precheck/scripts/image-dims.sh"

FX="$HERE/fixtures/img-dims"

section "img_format"
assert_eq "png"     "$(img_format "$FX/accepted.png")"    "PNG magic detected"
assert_eq "png"     "$(img_format "$FX/nonaccepted.png")" "PNG magic detected (non-accepted size)"
assert_eq "unknown" "$(img_format "$FX/notreally.png")"   "text file with .png name is not a PNG"
assert_eq "unknown" "$(img_format "$FX/missing.png")"     "missing file is unknown"

section "png_dims"
assert_eq "1290 2796" "$(png_dims "$FX/accepted.png")"    "IHDR dimensions parsed (accepted)"
assert_eq "1000 1000" "$(png_dims "$FX/nonaccepted.png")" "IHDR dimensions parsed (non-accepted)"
assert_eq ""          "$(png_dims "$FX/notreally.png")"   "non-PNG yields no dims"

section "dims_match_accepted"
dims_match_accepted 1290 2796 && r=yes || r=no
assert_eq "yes" "$r" "1290x2796 is an accepted size"
dims_match_accepted 2796 1290 && r=yes || r=no
assert_eq "yes" "$r" "landscape orientation of an accepted size matches"
dims_match_accepted 1000 1000 && r=yes || r=no
assert_eq "no"  "$r" "1000x1000 is not an accepted size"

echo
if (( fails == 0 )); then echo "[test-image-dims.sh] OK"; else echo "[test-image-dims.sh] $fails FAILED"; fi
exit "$fails"
