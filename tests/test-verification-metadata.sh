#!/usr/bin/env bash
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PYTHONPYCACHEPREFIX="${TMPDIR:-/tmp}/precheck-pycache" python3 "$ROOT/tests/test-verification-metadata.py"
