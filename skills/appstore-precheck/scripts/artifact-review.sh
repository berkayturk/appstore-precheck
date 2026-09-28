#!/usr/bin/env bash
# Inspect an existing iOS app bundle without installing or executing it.
# Python 3.8+ stdlib; optional Apple command-line tools are detected per check.
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v python3 >/dev/null 2>&1; then
  echo 'artifact-review: Python 3.8+ is required for plist/archive inspection' >&2
  exit 69
fi
exec python3 "$HERE/lib/artifact-review.py" "$@"
