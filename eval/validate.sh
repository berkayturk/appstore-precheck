#!/usr/bin/env bash
# validate.sh — validate every eval dataset case against eval/schema/case.schema.json.
# Thin wrapper over eval/lib/validate_case.py (python3, stdlib-only).
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

command -v python3 >/dev/null 2>&1 || {
  echo "validate: python3 is required" >&2; exit 1; }

# The schema file itself must be valid JSON (also checked by CI's jq pass).
python3 -c "import json,sys; json.load(open(sys.argv[1]))" \
  "$ROOT/eval/schema/case.schema.json" || {
  echo "validate: eval/schema/case.schema.json is not valid JSON" >&2; exit 1; }

exec python3 "$ROOT/eval/lib/validate_case.py" "$ROOT/eval"
