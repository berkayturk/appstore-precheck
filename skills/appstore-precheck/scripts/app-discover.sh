#!/usr/bin/env bash
# app-discover.sh — find simulator .app bundles the USER already built, describe them,
# recommend the newest, and stop. Never builds (no xcodebuild / flutter / gradle),
# never launches, never writes under the repo. Bash 3.2 compatible.
#
# WHY THIS EXISTS
# ---------------
# The Phase 6 dynamic tier needs a simulator .app. Building it ourselves is out of
# the question (principle 2: never run the user's build), so the tier either finds a
# build the user already made or asks for one. Two places hold such builds:
#   ~/Library/Developer/Xcode/DerivedData/*/Build/Products/*-iphonesimulator/*.app
#   <repo>/build/ios/iphonesimulator/*.app                    (flutter build ios --simulator)
#   <repo>/ios/build/Build/Products/*-iphonesimulator/*.app  (react-native run-ios)
# Each candidate is reported with its mtime, its configuration READ FROM THE DIRECTORY
# NAME (Debug-iphonesimulator → debug, Release-iphonesimulator → release, anything
# else → unknown; never inferred from the plist), and its bundle id from Info.plist.
# The newest is recommended. It is only a recommendation: the caller must obtain an
# explicit confirmation before installing or launching anything, because running the
# app has effects (network, credentials) the static scan never has.
#
# The configuration matters downstream: dynamic.sh --build-config <debug|release|unknown>
# is what decides whether a runtime observation may clear `needs build verification`.
# A Debug DerivedData build never does (evidence.sh).
#
# USAGE
#   app-discover.sh [--repo DIR] [--derived-data DIR] [--framework rn|flutter|kmp|native] [--json]
#   Exit 0 with candidates; 3 when none were found (the run then carries the
#   runtime-not-audited gap record); 64 on a bad argument.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=framework-detect.sh
. "$HERE/framework-detect.sh"
# shellcheck source=lib/dyn-bundle.sh
. "$HERE/lib/dyn-bundle.sh"

REPO="." DD="${HOME}/Library/Developer/Xcode/DerivedData" FRAMEWORK="" JSON=0
usage_err() { echo "app-discover.sh: $1" >&2; exit 64; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)         [[ $# -ge 2 ]] || usage_err "--repo needs a path";         REPO="$2"; shift 2 ;;
    --derived-data) [[ $# -ge 2 ]] || usage_err "--derived-data needs a path"; DD="$2";   shift 2 ;;
    --framework)    [[ $# -ge 2 ]] || usage_err "--framework needs a value";   FRAMEWORK="$2"; shift 2 ;;
    --json) JSON=1; shift ;;
    *) usage_err "unknown option '$1'" ;;
  esac
done
[[ -d "$REPO" ]] || usage_err "--repo is not a directory: $REPO"
case "$FRAMEWORK" in ""|rn|flutter|kmp|native) ;; *) usage_err "--framework must be rn|flutter|kmp|native" ;; esac
[[ -n "$FRAMEWORK" ]] || FRAMEWORK="$(detect_framework "$REPO")"

# --- Portable helpers (macOS + Linux) ----------------------------------------------
mtime_epoch() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }
epoch_iso()   { date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo ""; }

# plist_string <plist> <key> -> the string value, or "" (lib/dyn-bundle.sh: plutil on
# macOS for the binary plists of a real .app, a tag-per-line XML fallback elsewhere).
plist_string() { dyn_plist_string "$1" "$2"; }

# config_from_dir <app-path> -> debug | release | unknown, from the parent directory name only.
config_from_dir() {
  case "$(basename "$(dirname "$1")")" in
    Debug-iphonesimulator)   echo debug ;;
    Release-iphonesimulator) echo release ;;
    *)                       echo unknown ;;
  esac
}

# --- Collect candidates --------------------------------------------------------------
# One line per candidate: epoch<TAB>path. Globs that match nothing expand to nothing
# (checked with -d). Shell globs, no find -newer tricks: the order is decided by sort.
CANDS="$(mktemp)"; trap 'rm -f "$CANDS"' EXIT
add_candidate() {
  local app="$1"
  [[ -d "$app" && -f "$app/Info.plist" ]] || return 0
  printf '%s\t%s\n' "$(mtime_epoch "$app")" "$app" >> "$CANDS"
}
for app in "$DD"/*/Build/Products/*-iphonesimulator/*.app; do add_candidate "$app"; done
for app in "$REPO"/build/ios/iphonesimulator/*.app; do add_candidate "$app"; done
for app in "$REPO"/ios/build/Build/Products/*-iphonesimulator/*.app; do add_candidate "$app"; done

# --- Build hint: the command WE WILL NOT RUN, for the user to paste ----------------
build_hint() {
  case "$1" in
    flutter) printf '%s' "flutter build ios --simulator   # then re-run discovery; the .app lands in build/ios/iphonesimulator/" ;;
    rn)      printf '%s' "npx react-native run-ios --simulator \"iPhone 17\"   # bare RN; managed Expo projects first need: npx expo prebuild -p ios. A Debug build also needs Metro running (port 8081) at launch, or supply a release bundle" ;;
    kmp)     printf '%s' "xcodebuild -sdk iphonesimulator -project iosApp/iosApp.xcodeproj -scheme iosApp -configuration Debug -derivedDataPath /tmp/precheck-dd build   # the KMP iosApp Xcode project" ;;
    *)       printf '%s' "xcodebuild -sdk iphonesimulator -scheme <YourScheme> -configuration Debug -derivedDataPath /tmp/precheck-dd build   # then pass --derived-data /tmp/precheck-dd" ;;
  esac
}

# --- Render ---------------------------------------------------------------------------
CONFIRM="Recommendation only: obtain the user's explicit confirmation of ONE candidate before installing or launching anything (running the app has network and credential effects the static scan never has)."
n="$(grep -c . "$CANDS" 2>/dev/null)"; n="${n:-0}"

emit_json() {
  local hint; hint="$(build_hint "$FRAMEWORK")"
  if [[ "$n" -eq 0 ]]; then
    jq -n --arg fw "$FRAMEWORK" --arg hint "$hint" --arg c "$CONFIRM" \
      '{framework:$fw, candidates:[], recommended:null, launched:false, confirm:$c,
        gap:"runtime-not-audited", build_hint:$hint}'
    return
  fi
  sort -t "$(printf '\t')" -k1,1nr "$CANDS" | while IFS="$(printf '\t')" read -r ep path; do
    jq -n --arg p "$path" --arg name "$(basename "$path" .app)" \
          --arg bid "$(plist_string "$path/Info.plist" CFBundleIdentifier)" \
          --arg cfg "$(config_from_dir "$path")" --argjson ep "$ep" --arg iso "$(epoch_iso "$ep")" \
          --arg exe "$(plist_string "$path/Info.plist" CFBundleExecutable)" \
      '{path:$p, name:$name, bundle_id:(if $bid=="" then null else $bid end), executable:(if $exe=="" then null else $exe end),
        build_config:$cfg, mtime_epoch:$ep, mtime_iso:$iso}'
  done | jq -s --arg fw "$FRAMEWORK" --arg hint "$hint" --arg c "$CONFIRM" \
      '{framework:$fw, candidates:., recommended:.[0], launched:false, confirm:$c, build_hint:$hint}'
}

emit_text() {
  if [[ "$n" -eq 0 ]]; then
    echo "app-discover: no simulator .app found under $DD or $REPO/build/ios/iphonesimulator (framework: $FRAMEWORK)."
    echo "The dynamic tier cannot run; the report will carry the runtime-not-audited gap record."
    echo "To close it, build a simulator app yourself and re-run discovery. This tool will not run the build for you:"
    echo "    $(build_hint "$FRAMEWORK")"
    return
  fi
  echo "app-discover: $n simulator .app candidate(s), newest first (framework: $FRAMEWORK)"
  local i=0
  sort -t "$(printf '\t')" -k1,1nr "$CANDS" | while IFS="$(printf '\t')" read -r ep path; do
    i=$((i + 1))
    local tag=""; [[ $i -eq 1 ]] && tag="   <- Recommended (newest)"
    printf '  %d. %s\n     bundle id: %s   config: %s   built: %s%s\n' \
      "$i" "$path" "$(plist_string "$path/Info.plist" CFBundleIdentifier)" \
      "$(config_from_dir "$path")" "$(epoch_iso "$ep")" "$tag"
  done
  echo "$CONFIRM"
  echo "Pass the chosen path to dynamic-run.sh --app, and its config to dynamic.sh --build-config (a debug build never clears 'needs build verification')."
}

if (( JSON )); then emit_json; else emit_text; fi
[[ "$n" -eq 0 ]] && exit 3
exit 0
