#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -B tests/review-static.py
python3 -B tests/review-gaps.py
python3 -B tests/review-docs.py
