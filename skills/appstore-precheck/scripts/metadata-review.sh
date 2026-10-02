#!/usr/bin/env bash
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v python3 >/dev/null 2>&1 || { echo 'SKIP: metadata-review — Python 3 required'; exit 3; }
exec python3 -B "$HERE/lib/metadata-review.py" "$@"
