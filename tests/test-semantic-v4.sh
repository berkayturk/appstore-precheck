#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1
PYTHONDONTWRITEBYTECODE=1 python3 tests/test-semantic-v4.py
