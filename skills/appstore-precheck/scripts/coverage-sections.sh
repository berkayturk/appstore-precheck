#!/usr/bin/env bash
# Maintainer inventory; never a claim of full guideline verification.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v python3 >/dev/null 2>&1 || { echo 'coverage-sections: Python 3.8+ required' >&2; exit 69; }
exec python3 -B "$HERE/lib/coverage-sections.py" "$@"
