#!/usr/bin/env bash
# Opt-in simulator build in a disposable copy of the user's project. Bash 3.2.
# Exit: 0 app exported; 3 SKIP (tool/setup/build unavailable); 64 usage; 66 input.
# Bash 3.2 treats an intentionally empty array as unbound under nounset.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/framework-detect.sh"
source "$HERE/lib/build-plan.sh"

REPO="" FRAMEWORK="" PLATFORM=ios OUT="" DRY=0 KEEP=0 TIMEOUT=1200
usage() { echo "build-run.sh: $1" >&2; exit 64; }
need() { [[ $# -ge 2 ]] || usage "$1 needs a value"; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) need "$@"; REPO="$2"; shift 2 ;;
    --framework) need "$@"; FRAMEWORK="$2"; shift 2 ;;
    --platform) need "$@"; PLATFORM="$2"; shift 2 ;;
    --out) need "$@"; OUT="$2"; shift 2 ;;
    --timeout) need "$@"; TIMEOUT="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --keep-build) KEEP=1; shift ;;
    *) usage "unknown option '$1'" ;;
  esac
done
[[ -n "$REPO" ]] || REPO=.
[[ -d "$REPO" ]] || { echo "build-run.sh: repo directory missing" >&2; exit 66; }
REPO="$(cd "$REPO" && pwd -P)"
case "$FRAMEWORK" in ""|native|rn|flutter|kmp) ;; *) usage "--framework must be native|rn|flutter|kmp" ;; esac
[[ -n "$FRAMEWORK" ]] || FRAMEWORK="$(detect_framework "$REPO")"
[[ "$TIMEOUT" =~ ^[0-9]+$ ]] && (( TIMEOUT >= 1 )) || usage "--timeout must be positive seconds"
if [[ "$PLATFORM" != ios ]]; then
  echo "SKIP: platform-not-audited — $PLATFORM is outside the iOS simulator build tier"
  exit 3
fi

skip() {
  echo "SKIP: build-run — $1; provide your own simulator .app with --app <path>"
  exit 3
}
if (( DRY == 0 )); then
  command -v python3 >/dev/null 2>&1 || skip "Python 3.8+ is required (install Python 3)"
  command -v rsync >/dev/null 2>&1 || skip "rsync is required (install rsync)"
  TEMP_BASE="$(python3 - "${TMPDIR:-/tmp}" <<'PY'
import os, sys
print(os.path.realpath(sys.argv[1]))
PY
)"
  case "$TEMP_BASE/" in "$REPO/"*) skip "TMPDIR must be outside the source project";; esac
  if [[ -n "$OUT" ]]; then
    OUT="$(python3 - "$OUT" <<'PY'
import os, sys
print(os.path.realpath(sys.argv[1]))
PY
)"
    case "$OUT/" in "$REPO/"*) skip "--out must be outside the source project";; esac
  fi
  build_check_symlinks "$REPO" || skip "project contains a symlink; remove it from the build input to preserve source isolation"
fi

WORK="" COPY="" LOG="" EVIDENCE="" EXPORTED_APP="" BUILD_CONFIG=unknown
cleanup() {
  local status=$? integrity=0
  trap - EXIT HUP INT TERM
  if [[ -n "$EVIDENCE" ]]; then
    python3 "$HERE/lib/build-evidence.py" --repo "$REPO" --copy "$COPY" --evidence "$EVIDENCE" \
      --status "$status" --app "$EXPORTED_APP" --configuration "$BUILD_CONFIG" || integrity=$?
    echo "build_evidence=$EVIDENCE/build-provenance.json"
    echo "event_log=$LOG"
    if [[ "$status" -eq 0 && "$integrity" -ne 0 ]]; then
      echo 'SKIP: build source identity changed or could not be verified; provenance binding unavailable'
      status=3
    fi
  fi
  if [[ -n "$WORK" && -d "$WORK" && "$KEEP" -eq 0 ]]; then rm -rf -- "$WORK"; fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM
if (( DRY )); then
  WORK='${TMPDIR}/appstore-precheck-build.XXXXXX'
  COPY="$WORK/project"
  LOG="$WORK/build-events.jsonl"
else
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/appstore-precheck-build.XXXXXX")" || skip "cannot create temporary build directory"
  COPY="$WORK/project"
  mkdir -p "$COPY" "$WORK/home" "$WORK/tmp" || skip "cannot prepare temporary build directory"
  if [[ -z "$OUT" ]]; then
    OUT="$(mktemp -d "${TMPDIR:-/tmp}/appstore-precheck-artifact.XXXXXX")" || skip "cannot create artifact directory"
  else
    mkdir -p "$OUT" || skip "cannot create artifact directory"
  fi
  EVIDENCE="$(mktemp -d "$OUT/build-evidence.XXXXXX")" || skip "cannot create evidence directory"
  LOG="$EVIDENCE/build-events.jsonl"
  : > "$LOG"
  python3 "$HERE/source-snapshot.py" --repo "$REPO" --out "$EVIDENCE/source-before.json" || skip "source snapshot is unstable"

  rsync -a --exclude='.git/' --exclude='node_modules/' --exclude='Pods/' \
    --exclude='build/' --exclude='DerivedData/' --exclude='.build/' --exclude='.dart_tool/' --exclude='__pycache__/' --exclude='.env' --exclude='.env.*' \
    --exclude='.appstore-precheck.json' --exclude='*asc-key*.json' \
    --exclude='*.p8' --exclude='*.p12' --exclude='*.mobileprovision' \
    -- "$REPO/" "$COPY/" >/dev/null 2>&1 || skip "rsync could not copy project (check permissions and disk space)"
  chmod -R u+w "$COPY" >/dev/null 2>&1 || :
  python3 "$HERE/source-snapshot.py" --repo "$COPY" --out "$EVIDENCE/copy-initial.json" || skip "copied source snapshot is unstable"
fi
echo "build-run: framework=$FRAMEWORK"
(( DRY )) && echo "PLAN source=$REPO copy=$COPY (rsync excludes .git, node_modules, Pods, build, DerivedData, .env*, credentials)"

show_step() {
  local step="$1" cwd="$2" arg
  shift 2
  printf 'PLAN step=%s cwd=%s command=' "$step" "$cwd"
  for arg in "$@"; do printf '%q ' "$arg"; done
  printf '\n'
}
RUN_OUT="" RUN_CLASS=""
run_step() {
  local step="$1" cwd="$2" tool="$3" scheme_mode="${4:-no}" status
  shift 4
  if (( DRY )); then show_step "$step" "$cwd" "$tool" "$@"; RUN_OUT=""; RUN_CLASS=OK; return 0; fi
  command -v "$tool" >/dev/null 2>&1 || { RUN_CLASS=MISSING_TOOL; return 3; }
  if [[ "$scheme_mode" == yes ]]; then
    RUN_OUT="$(python3 "$HERE/lib/build-exec.py" --step "$step" --cwd "$cwd" --timeout "$TIMEOUT" \
      --log "$LOG" --home "$WORK/home" --temp "$WORK/tmp" --scheme -- "$tool" "$@")"; status=$?
  else
    RUN_OUT="$(python3 "$HERE/lib/build-exec.py" --step "$step" --cwd "$cwd" --timeout "$TIMEOUT" \
      --log "$LOG" --home "$WORK/home" --temp "$WORK/tmp" -- "$tool" "$@")"; status=$?
  fi
  RUN_CLASS="${RUN_OUT#STATUS=}"
  [[ "$RUN_OUT" == SCHEME=* ]] && RUN_CLASS=OK
  return "$status"
}
prepare_snapshot() {
  (( DRY )) && return 0
  python3 "$HERE/source-snapshot.py" --repo "$COPY" --out "$EVIDENCE/copy-before.json" || skip "prepared source snapshot is unstable"
}
step_or_skip() {
  local name="$1" cwd="$2" tool="$3"; shift 3
  run_step "$name" "$cwd" "$tool" no "$@" || {
    [[ "$RUN_CLASS" == MISSING_TOOL ]] && skip "$name: $tool unavailable (install the required framework tool)"
    skip "$name: $RUN_CLASS"
  }
}

if [[ "$FRAMEWORK" == rn ]]; then
  installer="$(build_installer "$REPO")" || skip "React Native requires package-lock.json, yarn.lock, or pnpm-lock.yaml"
  case "$installer" in
    npm)  step_or_skip js-install "$COPY" npm ci ;;
    yarn) step_or_skip js-install "$COPY" yarn --frozen-lockfile ;;
    pnpm) step_or_skip js-install "$COPY" pnpm i --frozen-lockfile ;;
  esac
  if build_has_expo "$REPO"; then
    step_or_skip expo-prebuild "$COPY" npx expo prebuild --platform ios --no-install
  fi
  if [[ -f "$REPO/ios/Podfile" ]] || { (( DRY == 0 )) && [[ -f "$COPY/ios/Podfile" ]]; }; then
    step_or_skip pod-install "$COPY/ios" pod install
  fi
fi

if [[ "$FRAMEWORK" == flutter ]]; then
  step_or_skip flutter-pub "$COPY" flutter pub get
  # Flutter writes generated Xcode settings into the copied source. Prepare them
  # before binding compilation to its snapshot; keep these files integrity-checked.
  step_or_skip flutter-config "$COPY" flutter build ios --simulator --config-only
  prepare_snapshot
  step_or_skip flutter-build "$COPY" flutter build ios --simulator
  BUILD_CONFIG=debug
else
  if (( DRY )) && [[ "$FRAMEWORK" == rn ]] && build_has_expo "$REPO"; then
    PROJECT='<generated-ios-project>'
  else
    PROJECT="$(build_project "$COPY" "$FRAMEWORK")" || {
      if (( DRY )); then PROJECT="$(build_project "$REPO" "$FRAMEWORK")" || skip "no Xcode project, workspace, or Package.swift"
      else skip "no Xcode project, workspace, or Package.swift"; fi
    }
  fi
  # The dry plan inspects source layout; actual discovery uses only the copied tree.
  if (( DRY )) && [[ "$PROJECT" != '<generated-ios-project>' ]]; then
    PROJECT="$(build_project "$REPO" "$FRAMEWORK")" || skip "no Xcode project, workspace, or Package.swift"
  fi
  flags=()
  case "$PROJECT" in *.xcworkspace) flags=(-workspace "$PROJECT");; *.xcodeproj) flags=(-project "$PROJECT");; esac
  run_step scheme-list "$COPY" xcodebuild yes -list -json "${flags[@]}" || {
    [[ "$RUN_CLASS" == MISSING_TOOL ]] && skip "xcodebuild unavailable (install Xcode and select its developer directory)"
    skip "Xcode scheme discovery: $RUN_CLASS"
  }
  if (( DRY )); then SCHEME='<auto-discovered-scheme>'; else SCHEME="${RUN_OUT#SCHEME=}"; fi
  prepare_snapshot
  run_step xcode-release "$COPY" xcodebuild no "${flags[@]}" -scheme "$SCHEME" -sdk iphonesimulator -configuration Release -derivedDataPath "$WORK/dd" CODE_SIGNING_ALLOWED=NO build
  if [[ "$RUN_CLASS" == OK ]]; then
    BUILD_CONFIG=release
  else
    RELEASE_CLASS="$RUN_CLASS"
    # KMP may need its generated shared framework before the Xcode build.
    if [[ "$FRAMEWORK" == kmp && "$RELEASE_CLASS" == MISSING_FRAMEWORK && -x "$COPY/gradlew" ]]; then
      step_or_skip kmp-framework "$COPY" ./gradlew :shared:linkDebugFrameworkIosSimulatorArm64
    fi
    run_step xcode-debug "$COPY" xcodebuild no "${flags[@]}" -scheme "$SCHEME" -sdk iphonesimulator -configuration Debug -derivedDataPath "$WORK/dd" CODE_SIGNING_ALLOWED=NO build \
      || skip "Release $RELEASE_CLASS; Debug $RUN_CLASS"
    BUILD_CONFIG=debug
  fi
fi
echo "build_config=$BUILD_CONFIG"
if (( DRY )); then
  echo 'PLAN output=<temporary-artifact-dir>/<configuration>-iphonesimulator/<App>.app'
  exit 0
fi

# Export one simulator bundle to a caller-owned temp artifact directory. The build
# workspace (source copy + DerivedData) is removed unless --keep-build was requested.
APP=""
if [[ "$FRAMEWORK" == flutter ]]; then
  APP="$(find "$COPY/build/ios/iphonesimulator" -maxdepth 1 -type d -name '*.app' -print -quit 2>/dev/null)"
else
  if [[ "$BUILD_CONFIG" == release ]]; then FIND_CONFIG=Release; else FIND_CONFIG=Debug; fi
  APP="$(find "$WORK/dd/Build/Products" -maxdepth 2 -type d -path "*/$FIND_CONFIG-iphonesimulator/*.app" -print -quit 2>/dev/null)"
fi
[[ -n "$APP" && -f "$APP/Info.plist" ]] || skip "build finished without a simulator .app (check the selected scheme/target)"
if [[ -z "$OUT" ]]; then
  OUT="$(mktemp -d "${TMPDIR:-/tmp}/appstore-precheck-artifact.XXXXXX")" || skip "cannot create artifact directory"
else
  mkdir -p "$OUT" || skip "cannot create artifact directory"
  OUT="$(cd "$OUT" && pwd -P)"
fi
if [[ "$FRAMEWORK" == flutter ]]; then CFG_DIR=Debug-iphonesimulator; else
  if [[ "$BUILD_CONFIG" == release ]]; then CFG_DIR=Release-iphonesimulator; else CFG_DIR=Debug-iphonesimulator; fi
fi
mkdir -p "$OUT/precheck/Build/Products/$CFG_DIR" || skip "cannot create artifact configuration directory"
EXPORTED_APP="$OUT/precheck/Build/Products/$CFG_DIR/$(basename "$APP")"
mkdir -p "$EXPORTED_APP" || skip "cannot create exported bundle directory"
rsync -a --delete -- "$APP/" "$EXPORTED_APP/" >/dev/null 2>&1 || skip "cannot export simulator .app"
echo "app_path=$EXPORTED_APP"
echo "artifact_dir=$OUT"
if (( KEEP )); then echo "build_workspace=$WORK"; fi
exit 0
