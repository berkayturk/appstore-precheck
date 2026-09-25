#!/usr/bin/env bash
# Flutter's own generator supplies the iOS host in a temporary stage.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
VARIANT="${1:-}"
[[ "$VARIANT" == clean || "$VARIANT" == broken ]] || { echo "usage: $0 clean|broken [build-run options]" >&2; exit 64; }
shift
command -v flutter >/dev/null 2>&1 || { echo "SKIP: Flutter SDK unavailable; install flutter and run flutter doctor"; exit 3; }
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/precheck-flutter-corpus.XXXXXX")" || exit 3
trap 'rm -rf "$STAGE"' EXIT
export HOME="$STAGE/home" PUB_CACHE="$STAGE/pub-cache"
mkdir -p "$HOME"
if ! flutter create --platforms ios --org org.appstoreprecheck.corpus --project-name precheck_flutter "$STAGE/project" >/dev/null 2>&1; then
  echo "SKIP: Flutter could not generate the iOS host (check flutter doctor and package access)"
  exit 3
fi
cp "$HERE/$VARIANT/lib/main.dart" "$STAGE/project/lib/main.dart"
if [[ "$VARIANT" == clean ]]; then
  /usr/libexec/PlistBuddy -c 'Add :NSCameraUsageDescription string Attach a photo to a report.' "$STAGE/project/ios/Runner/Info.plist" >/dev/null 2>&1 || :
fi
bash "$ROOT/skills/appstore-precheck/scripts/build-run.sh" --repo "$STAGE/project" --framework flutter "$@"
