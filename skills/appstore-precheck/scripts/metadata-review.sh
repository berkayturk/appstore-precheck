#!/usr/bin/env bash
# Opt-in read-only inspection of fastlane metadata and App Store Connect.
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v python3 >/dev/null 2>&1; then
  echo 'metadata-review: Python 3.8+ is required' >&2
  exit 69
fi
exec python3 "$HERE/lib/metadata-review.py" "$@"
