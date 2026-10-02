#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -B tests/coverage-docs.py
python3 -B scripts/update-coverage-docs.py --check
