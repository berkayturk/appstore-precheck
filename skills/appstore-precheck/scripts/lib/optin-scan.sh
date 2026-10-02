#!/usr/bin/env bash
# Explicit optional-tier wiring, isolated from default finding emission.
optin_trust() {
  if [[ "${APPSTORE_PRECHECK_TRUST_CONFIG:-}" == 1 ]]; then
    if [[ "$OPT_BUILD" != 1 && -z "$OPT_APP" && "$(cfg_bool '.dynamic.build')" == true ]]; then OPT_BUILD=1; fi
    if [[ ( "$OPT_BUILD" == 1 || -n "$OPT_APP" ) && "$OPT_NO_RUNTIME" != 1 && "$(cfg_bool '.dynamic.demoLogin')" == true ]]; then OPT_DEMO=1; fi
  fi
}

optin_validate() {
  [[ "$OPT_BUILD" != 1 || -z "$OPT_APP" ]] || { echo 'scan.sh: choose --build or --app' >&2; return 64; }
  if [[ "$OPT_DEMO" == 1 || "$OPT_DYN_BLOCK" == 1 ]]; then
    [[ "$OPT_NO_RUNTIME" != 1 && ( "$OPT_BUILD" == 1 || -n "$OPT_APP" ) ]] || { echo 'scan.sh: runtime flags need --build/--app and cannot use --no-runtime' >&2; return 64; }
  fi
  [[ -n "$OPT_OUT" ]] || return 0
  python3 - "$OPT_OUT" "$ROOT" <<'PY'
from pathlib import Path
import sys
out, repo = [Path(p).resolve() for p in sys.argv[1:]]
if out == repo or repo in out.parents or (out.exists() and not out.is_dir()):
    print('scan.sh: --out must be a directory outside the project', file=sys.stderr)
    raise SystemExit(64)
PY
}

optin_run() {
  [[ "$OPT_BUILD" == 1 || -n "$OPT_APP" || "$OPT_METADATA" == 1 ]] || return 0
  if ! command -v python3 >/dev/null 2>&1; then
    set_rule 'opt-in-review'; skip 'opt-in review — Python 3 required'; return 0
  fi
  if [[ -z "$OPT_OUT" ]]; then
    OPT_TEMP="$(mktemp -d "${TMPDIR:-/tmp}/precheck-review.XXXXXX")"; OPT_OUT="$OPT_TEMP"
  fi
  local args=( --repo "$ROOT" --out-dir "$OPT_OUT" ) status=0 line
  [[ "$OPT_BUILD" == 1 ]] && args+=( --build )
  [[ -n "$OPT_APP" ]] && args+=( --app "$OPT_APP" )
  [[ "$OPT_METADATA" == 1 ]] && args+=( --metadata )
  [[ "$OPT_NO_RUNTIME" == 1 ]] && args+=( --no-runtime )
  [[ "$OPT_DEMO" == 1 ]] && args+=( --demo-login )
  [[ "$OPT_DYN_BLOCK" == 1 ]] && args+=( --dynamic-blocking )
  [[ "$OPT_DRY" == 1 ]] && args+=( --dry-run )
  [[ "$OPT_URLS" == 1 ]] && args+=( --check-urls )
  [[ -n "$OPT_ASC" ]] && args+=( --asc-app-id "$OPT_ASC" )
  [[ -n "$OPT_ASC_VERSION" ]] && args+=( --asc-version-id "$OPT_ASC_VERSION" )
  [[ -n "$OPT_ASC_INFO" ]] && args+=( --asc-info-id "$OPT_ASC_INFO" )
  python3 -B "$SCRIPT_DIR/opt-in-review.py" "${args[@]}" >/dev/null || status=$?
  if (( status != 0 )); then
    [[ "$OPT_DYN_BLOCK" == 1 && "$status" == 2 ]] && return 64
    set_rule 'opt-in-review'; skip 'opt-in review — runner unavailable; no optional conclusions imported'; return 0
  fi
  OPT_RAN_OK=1
  [[ "$FORMAT" != text ]] || printf 'OPT-IN: report — %s/summary.json\n' "$OPT_OUT"
  if [[ "$OPT_DYN_BLOCK" == 1 ]] && ! command -v jq >/dev/null 2>&1; then
    set_rule 'dynamic-blocking'; skip 'dynamic blocking — jq unavailable; no blocking conclusions imported'; return 0
  fi
  if [[ "$OPT_DYN_BLOCK" == 1 ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      set_rule 'dynamic-blocking'; fail "$line"
    done < <(jq -r '.blocking[]' "$OPT_OUT/summary.json")
  fi
}

optin_render_json() {
  if [[ "$OPT_RAN_OK" == 1 ]]; then
    python3 -B "$SCRIPT_DIR/augment-json.py" --opt-summary "$OPT_OUT/summary.json"
  else cat; fi
}

optin_cleanup() {
  rm -f "$FINDINGS_TMP"
  if [[ -n "$OPT_TEMP" && ( "$OPT_RAN_OK" != 1 || "$FORMAT" == sarif ) ]]; then rm -rf -- "$OPT_TEMP"; fi
}
