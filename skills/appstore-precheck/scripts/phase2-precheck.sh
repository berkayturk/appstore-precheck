#!/usr/bin/env bash
# appstore-precheck/scripts/phase2-precheck.sh
# Phase 2 wrapper: build the App Store Connect API key JSON from the environment,
# run Apple's `fastlane precheck`, then delete the key. The key is created with a
# restrictive mode and removed on exit (even on failure), so it never lingers and
# is never committed.
#
# Env (required): ASC_KEY_ID, ASC_ISSUER_ID, ASC_P8_PATH (path to the .p8 file).
# App identifier: first positional arg, or $APP_IDENTIFIER.
#
# Usage:
#   ASC_KEY_ID=... ASC_ISSUER_ID=... ASC_P8_PATH=/path/AuthKey.p8 \
#     bash phase2-precheck.sh com.example.app
#   bash phase2-precheck.sh --dry-run com.example.app   # build+validate the key JSON
#                                                        # and print the command, no
#                                                        # network and no real key needed
set -euo pipefail

DRY=false
APP_ID="${APP_IDENTIFIER:-}"
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY=true ;;
    -*) echo "phase2-precheck.sh: unknown option '$arg'" >&2; exit 64 ;;
    *)  APP_ID="$arg" ;;
  esac
done

: "${ASC_KEY_ID:?set ASC_KEY_ID (App Store Connect API key id)}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID (App Store Connect issuer id)}"
: "${ASC_P8_PATH:?set ASC_P8_PATH (path to the .p8 private key)}"
[[ -n "$APP_ID" ]] || { echo "usage: phase2-precheck.sh <app_identifier> (or set APP_IDENTIFIER)" >&2; exit 64; }

command -v jq >/dev/null 2>&1 || { echo "phase2-precheck.sh: jq is required" >&2; exit 69; }

KEYJSON="$(mktemp -t asc-key.XXXXXX)"
trap 'rm -f "$KEYJSON"' EXIT

# Build the key JSON. A real run reads the .p8 from disk; --dry-run tolerates a
# missing file (treats ASC_P8_PATH as literal key text) so it can be exercised in
# tests and previews without real credentials.
if [[ -f "$ASC_P8_PATH" ]]; then
  jq -n --arg kid "$ASC_KEY_ID" --arg iss "$ASC_ISSUER_ID" --rawfile key "$ASC_P8_PATH" \
     '{key_id:$kid, issuer_id:$iss, key:$key, in_house:false}' > "$KEYJSON"
elif $DRY; then
  jq -n --arg kid "$ASC_KEY_ID" --arg iss "$ASC_ISSUER_ID" --arg key "$ASC_P8_PATH" \
     '{key_id:$kid, issuer_id:$iss, key:$key, in_house:false}' > "$KEYJSON"
else
  echo "phase2-precheck.sh: .p8 not found at $ASC_P8_PATH" >&2; exit 66
fi
chmod 600 "$KEYJSON"

# The verbatim Phase 2 command (IAP is covered by Phase 1, so it is excluded here).
CMD=( fastlane run precheck
      "app_identifier:$APP_ID"
      "api_key_path:$KEYJSON"
      include_in_app_purchases:false
      default_rule_level::error )

if $DRY; then
  echo "DRY-RUN: would run: ${CMD[*]}"
  jq -e '.key_id and .issuer_id and .key' "$KEYJSON" >/dev/null \
    && echo "key json OK" || { echo "key json INVALID" >&2; exit 1; }
  exit 0
fi

command -v fastlane >/dev/null 2>&1 || { echo "phase2-precheck.sh: fastlane is required" >&2; exit 69; }
"${CMD[@]}"
