#!/usr/bin/env bash
# Local-only real Xcode build smoke test. Usage: bash tests/local/build-run.sh /path/to/ios/project
set -u
[[ $# -eq 1 && -d "$1" ]] || { echo "Usage: $0 /path/to/ios/project" >&2; exit 64; }
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE="$(cd "$1" && pwd -P)"
command -v xcodebuild >/dev/null 2>&1 || { echo "SKIP: Xcode is unavailable"; exit 3; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: Python 3 is unavailable"; exit 3; }
digest() {
  python3 - "$SOURCE" <<'PY'
import hashlib, os, sys
root = sys.argv[1]
h = hashlib.sha256()
for base, dirs, files in os.walk(root):
    dirs.sort(); files.sort()
    for name in files:
        path = os.path.join(base, name)
        h.update(os.path.relpath(path, root).encode())
        if os.path.islink(path):
            h.update(os.readlink(path).encode())
        else:
            with open(path, 'rb') as f:
                for chunk in iter(lambda: f.read(1024 * 1024), b''):
                    h.update(chunk)
print(h.hexdigest())
PY
}
BEFORE="$(digest)"
OUT="$(mktemp -d "${TMPDIR:-/tmp}/appstore-precheck-local-build.XXXXXX")"
trap 'rm -rf "$OUT"' EXIT
RUN_OUT="$(bash "$ROOT/skills/appstore-precheck/scripts/build-run.sh" --repo "$SOURCE" --out "$OUT" --timeout 1800)"; STATUS=$?
echo "$RUN_OUT"
AFTER="$(digest)"
[[ "$BEFORE" == "$AFTER" ]] || { echo "FAIL: source tree changed during build" >&2; exit 1; }
[[ "$STATUS" -eq 0 ]] || exit "$STATUS"
APP="$(printf '%s\n' "$RUN_OUT" | sed -n 's/^app_path=//p' | tail -1)"
[[ -n "$APP" && -f "$APP/Info.plist" ]] || { echo "FAIL: simulator .app missing" >&2; exit 1; }
bash "$ROOT/skills/appstore-precheck/scripts/app-discover.sh" --repo "$SOURCE" --derived-data "$OUT" --json >/dev/null || {
  echo "FAIL: app-discover could not find exported simulator .app" >&2; exit 1;
}
echo "PASS: real build exported $APP; source SHA-256 tree digest unchanged"
