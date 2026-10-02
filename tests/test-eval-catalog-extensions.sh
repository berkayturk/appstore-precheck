#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -B tests/eval-catalog-extensions.py
bash eval/validate.sh
