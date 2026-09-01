#!/usr/bin/env bash
# framework-detect.sh — which app framework a repository is built with, from FILE
# PRESENCE ONLY. Never runs a toolchain (no node, flutter, gradle, xcodebuild).
# Sourceable (detect_framework <root>) and runnable (prints one word, or --json).
# Bash 3.2 compatible.
#
# WHY THIS EXISTS
# ---------------
# Every code-level check in scan.sh greps Swift / ObjC (SRC_INC). On React Native,
# Flutter and Kotlin Multiplatform the app logic lives in JS, Dart or Kotlin, so those
# checks UNDER-DETECT rather than false-fire — and nothing said so. scan.sh uses this
# to publish a `framework-not-audited` gap record (count derived from the evidence
# catalogue). The Phase 6 dynamic tier uses it to decide launch arguments and which
# selector-based D-checks must be SKIPped up front (Flutter / Compose expose no
# accessibility semantics to Maestro), and to require Metro for a React Native Debug
# build. Output words: rn | flutter | kmp | native.
#
# The rules, deliberately narrow (a false "native" costs one missing SKIP line; a
# false "flutter" would SKIP checks that could have run):
#   rn       package.json at the root declares react-native as a dependency
#            (dependencies or devDependencies), not merely mentions the word.
#   flutter  pubspec.yaml at the root AND ios/Runner.xcodeproj (a Dart package
#            without an iOS runner has nothing an iOS scan could under-detect).
#   kmp      a Gradle build file (build.gradle.kts / build.gradle / settings.gradle*)
#            or any *.kt under the root AND an iosApp/ directory (the KMP wizard layout).
#   native   anything else.

# _fd_has_rn_dep <package.json> -> 0 when react-native is a declared dependency.
_fd_has_rn_dep() {
  local pj="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -e '((.dependencies // {}) + (.devDependencies // {})) | has("react-native")' "$pj" >/dev/null 2>&1
  else
    # No jq: accept the key only inside a dependencies block, on its own line.
    grep -qE '^[[:space:]]*"react-native"[[:space:]]*:' "$pj" 2>/dev/null
  fi
}

# _fd_has_kotlin <root> -> 0 when a Gradle build file or a .kt source exists (shallow).
_fd_has_kotlin() {
  local root="$1"
  [[ -f "$root/build.gradle.kts" || -f "$root/build.gradle" ]] && return 0
  [[ -f "$root/settings.gradle.kts" || -f "$root/settings.gradle" ]] && return 0
  [[ -n "$(find "$root" -maxdepth 6 -name '*.kt' -not -path '*/build/*' -not -path '*/node_modules/*' -print -quit 2>/dev/null)" ]]
}

# detect_framework_signals <root> -> the deciding paths, one per line (empty for native).
detect_framework_signals() {
  local root="${1:-.}"
  if [[ -f "$root/package.json" ]] && _fd_has_rn_dep "$root/package.json"; then
    echo "package.json (react-native dependency)"; return 0
  fi
  if [[ -f "$root/pubspec.yaml" && -d "$root/ios/Runner.xcodeproj" ]]; then
    echo "pubspec.yaml"; echo "ios/Runner.xcodeproj"; return 0
  fi
  if [[ -d "$root/iosApp" ]] && _fd_has_kotlin "$root"; then
    echo "iosApp/"
    if [[ -f "$root/build.gradle.kts" ]]; then echo "build.gradle.kts"
    elif [[ -f "$root/build.gradle" ]]; then echo "build.gradle"
    else echo "*.kt sources"; fi
    return 0
  fi
  return 0
}

# detect_framework <root> -> rn | flutter | kmp | native
detect_framework() {
  local root="${1:-.}" first
  first="$(detect_framework_signals "$root" | head -1)"
  case "$first" in
    package.json*) echo rn ;;
    pubspec.yaml)  echo flutter ;;
    iosApp/)       echo kmp ;;
    *)             echo native ;;
  esac
}

# --- CLI (only when executed, not when sourced) ---------------------------------
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -u
  ROOT="." JSON=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --root) [[ $# -ge 2 ]] || { echo "framework-detect.sh: --root needs a path" >&2; exit 64; }; ROOT="$2"; shift 2 ;;
      --root=*) ROOT="${1#*=}"; shift ;;
      --json) JSON=1; shift ;;
      *) echo "framework-detect.sh: unknown option '$1'" >&2; exit 64 ;;
    esac
  done
  [[ -d "$ROOT" ]] || { echo "framework-detect.sh: not a directory: $ROOT" >&2; exit 66; }
  fw="$(detect_framework "$ROOT")"
  if (( JSON )); then
    if command -v jq >/dev/null 2>&1; then
      detect_framework_signals "$ROOT" | jq -R . | jq -s --arg f "$fw" '{framework:$f, signals:.}'
    else
      printf '{"framework":"%s","signals":[]}\n' "$fw"
    fi
  else
    echo "$fw"
  fi
fi
