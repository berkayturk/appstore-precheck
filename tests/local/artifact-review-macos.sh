#!/usr/bin/env bash
# Optional local smoke test using a real built app/archive. Not part of tests/all.sh.
set -eu
if [[ $# -ne 1 ]]; then
  echo "usage: $0 /absolute/path/to/App.app|App.ipa|App.xcarchive" >&2
  exit 64
fi
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
bash "$ROOT/skills/appstore-precheck/scripts/artifact-review.sh" --app "$1" --format json
