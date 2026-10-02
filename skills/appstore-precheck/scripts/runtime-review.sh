#!/usr/bin/env bash
# Explicit runtime tier. The caller supplies an existing simulator app; no builds.
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$HERE/dynamic-run.sh" "$@"
