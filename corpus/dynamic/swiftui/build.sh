#!/usr/bin/env bash
# Build either checked-in Xcode project in an isolated temporary copy.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
VARIANT="${1:-}"
[[ "$VARIANT" == clean || "$VARIANT" == broken ]] || { echo "usage: $0 clean|broken [build-run options]" >&2; exit 64; }
shift
exec bash "$ROOT/skills/appstore-precheck/scripts/build-run.sh" --repo "$HERE/$VARIANT" --framework native "$@"
