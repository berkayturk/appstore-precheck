#!/usr/bin/env bash
# Shared isolated HOME/cache/deadline for official template generation.
# Caller supplies ROOT and STAGE; build-exec keeps tool diagnostics private.
corpus_bootstrap() {
  local step="$1" cwd="$2"
  shift 2
  mkdir -p "$STAGE/home" "$STAGE/tmp"
  python3 "$ROOT/skills/appstore-precheck/scripts/lib/build-exec.py" \
    --step "$step" --cwd "$cwd" --timeout 600 --log "$STAGE/bootstrap.jsonl" \
    --home "$STAGE/home" --temp "$STAGE/tmp" -- "$@" >/dev/null 2>&1
}
