#!/usr/bin/env bash
# tests/local/run-dynamic.sh — macOS-only, NOT part of tests/all.sh (CI is ubuntu).
# The whole Phase 6 pipeline on a real simulator: discover a built .app → confirm →
# dynamic-run.sh (throwaway device, N=3 launches, observations) → dynamic.sh
# (reconcile with the static scan of the repo). Run before a release
# (MAINTENANCE.md "Before each release") and whenever the runner or its libs change.
#
# Usage:
#   bash tests/local/run-dynamic.sh [--repo DIR] [--app PATH.app] [--repeats 3] [--window 10] [--ipad] [--pktap] [--yes]
# Without --app the newest discovered candidate is proposed and you must type "yes":
# running the app has network and credential effects the static scan never has.
# It never builds anything: build the simulator app yourself first (the discovery
# output prints the command it will NOT run for you).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
S="$ROOT/skills/appstore-precheck/scripts"
REPO="$ROOT" APP="" YES=0 EXTRA=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --app)  APP="$2"; shift 2 ;;
    --yes)  YES=1; shift ;;
    --repeats|--window) EXTRA+=("$1" "$2"); shift 2 ;;
    --ipad|--pktap) EXTRA+=("$1"); shift ;;
    *) echo "run-dynamic.sh: unknown option '$1'" >&2; exit 64 ;;
  esac
done
[[ "$(uname -s)" == Darwin ]] || { echo "run-dynamic.sh: macOS only (needs xcrun simctl)"; exit 69; }
command -v xcrun >/dev/null 2>&1 || { echo "run-dynamic.sh: xcrun not found"; exit 69; }

if [[ -z "$APP" ]]; then
  disc="$(bash "$S/app-discover.sh" --repo "$REPO" --json)" || { bash "$S/app-discover.sh" --repo "$REPO"; exit 3; }
  bash "$S/app-discover.sh" --repo "$REPO"
  APP="$(jq -r '.recommended.path' <<<"$disc")"
  if (( ! YES )); then
    printf '\nRun the recommended app above on a throwaway simulator? It will execute the app (network, credentials). Type yes to continue: '
    read -r answer; [[ "$answer" == yes ]] || { echo "aborted; nothing was launched"; exit 0; }
  fi
fi
CFG="$(bash "$S/app-discover.sh" --repo "$REPO" --json 2>/dev/null | jq -r --arg p "$APP" '[.candidates[]|select(.path==$p)][0].build_config // "unknown"')"
OUT="$(mktemp -d "${TMPDIR:-/tmp}/precheck-dynamic.XXXXXX")"
echo "== static scan of $REPO =="
( cd "$REPO" && bash "$S/scan.sh" --format json ) > "$OUT/static.json"
echo "== dynamic run: $APP (build config $CFG) → $OUT =="
bash "$S/dynamic-run.sh" --app "$APP" --repo "$REPO" --out "$OUT" "${EXTRA[@]+"${EXTRA[@]}"}"
echo "== reconciled =="
bash "$S/dynamic.sh" --transcript "$OUT/transcript.txt" --findings "$OUT/static.json" --target simulator --build-config "$CFG" \
  | tee "$OUT/reconciled.json" | jq '{verdict, summary}'
echo "artifacts: $OUT (transcript.txt, run.json, launch-*.png, dark.png, dynamic-type.png, reconciled.json)"
