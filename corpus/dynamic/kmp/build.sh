#!/usr/bin/env bash
# Xcode invokes the checked-in KMP Gradle project inside build-run's temp copy.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
VARIANT="${1:-}"
[[ "$VARIANT" == clean || "$VARIANT" == broken ]] || { echo "usage: $0 clean|broken [build-run options]" >&2; exit 64; }
shift
command -v gradle >/dev/null 2>&1 || { echo "SKIP: KMP corpus needs Gradle on PATH; install Gradle and allow Maven dependencies"; exit 3; }
bash "$ROOT/skills/appstore-precheck/scripts/build-run.sh" --repo "$HERE/$VARIANT" --framework kmp "$@"
