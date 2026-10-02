#!/usr/bin/env bash
# Explicit opt-in build helper. Never invoked by the dynamic runner.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v python3 >/dev/null 2>&1 || { echo 'SKIP: build-run — Python 3 required'; exit 3; }
exec python3 -B "$HERE/lib/build-run.py" "$@"
