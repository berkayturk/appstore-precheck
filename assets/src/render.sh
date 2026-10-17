#!/usr/bin/env bash
# Renders the README visuals from their HTML sources with headless Chrome at 2x.
#   bash assets/src/render.sh
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
render() { # file width height out
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=2 \
    --window-size="$2,$3" --virtual-time-budget=8000 --screenshot="$4" "file://$PWD/$1" 2>/dev/null
}
render social-preview.html 1280 640 ../social-preview.png
# GitHub's repository social preview upload is capped at 1 MB: quantize to 255 colours.
magick ../social-preview.png -strip -colors 255 -dither FloydSteinberg ../social-preview.png
render how-it-works.html 1600 520 ../how-it-works.png
