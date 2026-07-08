#!/usr/bin/env bash
# appstore-precheck/scripts/scan.sh
# Static, read-only pre-submission scanner for iOS App Store rejection vectors.
# Convention-over-configuration: auto-detects a standard fastlane + Xcode layout,
# and honors an optional `.appstore-precheck.json` at the repo root for overrides.
#
# Output: three line prefixes on stdout — FAIL: / WARN: / PASS: <topic> — <detail> [location]
# Exit code: always 0. The skill counts FAIL/WARN lines to reach a GREEN/YELLOW/RED verdict.

set -u

# Resolve the script dir to an absolute path BEFORE any cd, so the sibling
# sources below cannot break when an explicit --dir moves us elsewhere.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FORMAT="text"
SCAN_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --format)
      if [[ $# -lt 2 ]]; then echo "scan.sh: --format needs a value (text|json|sarif)" >&2; exit 64; fi
      FORMAT="$2"; shift 2 ;;
    --format=*) FORMAT="${1#*=}"; shift ;;
    --dir)
      if [[ $# -lt 2 ]]; then echo "scan.sh: --dir needs a path" >&2; exit 64; fi
      SCAN_DIR="$2"; shift 2 ;;
    --dir=*) SCAN_DIR="${1#*=}"; shift ;;
    *) shift ;;
  esac
done
[[ "$FORMAT" == json || "$FORMAT" == text || "$FORMAT" == sarif ]] || { echo "scan.sh: --format must be text|json|sarif" >&2; exit 64; }

# An explicit --dir is authoritative: scan exactly that directory. Without it,
# snap to the enclosing git toplevel (monorepo subdirs need --dir to opt out).
if [[ -n "$SCAN_DIR" ]]; then
  ROOT="$(cd "$SCAN_DIR" 2>/dev/null && pwd)" || { echo "scan.sh: --dir is not a directory: $SCAN_DIR" >&2; exit 64; }
else
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || ROOT="$(pwd)"
fi
cd "$ROOT" || { echo "FAIL: repo-root — could not enter repository root"; exit 0; }

source "$SCRIPT_DIR/findings.sh"
source "$SCRIPT_DIR/suppress.sh"
source "$SCRIPT_DIR/project-model.sh"
source "$SCRIPT_DIR/image-dims.sh"
source "$SCRIPT_DIR/sarif.sh"
FINDINGS_TMP="$(mktemp)"; export FINDINGS_TMP
trap 'rm -f "$FINDINGS_TMP"' EXIT
# The envelope `version` is the appstore-precheck TOOL's own version (from this
# skill's SKILL.md), never the scanned repo's — $ROOT above is the SCANNED app's
# git root, so reading its package.json here would leak the wrong version.
PRECHECK_VERSION="$(grep -m1 -E '^[[:space:]]*version:' "$SCRIPT_DIR/../SKILL.md" 2>/dev/null | sed -E 's/.*version:[[:space:]]*//; s/[[:space:]]*$//')"
[[ -z "$PRECHECK_VERSION" ]] && PRECHECK_VERSION="dev"

CONFIG="${APPSTORE_PRECHECK_CONFIG:-.appstore-precheck.json}"
have_jq() { command -v jq >/dev/null 2>&1; }

# cfg <json-path> <fallback> — read a value from the config file, else fallback.
cfg() {
  local path="$1" fallback="${2:-}"
  if [[ -f "$CONFIG" ]] && have_jq; then
    local v; v=$(jq -r "$path // empty" "$CONFIG" 2>/dev/null)
    [[ -n "$v" && "$v" != "auto" ]] && { echo "$v"; return; }
  fi
  echo "$fallback"
}
cfg_bool() { # cfg_bool <json-path> — echoes "true"/"false"
  if [[ -f "$CONFIG" ]] && have_jq; then
    local v; v=$(jq -r "$1 // false" "$CONFIG" 2>/dev/null)
    [[ "$v" == "true" ]] && { echo "true"; return; }
  fi
  echo "false"
}

_LAST_SUPPRESSED=0
fail() { if is_suppressed "$_CURRENT_RULE" "${2:-}" "${3:-}"; then _record_suppressed FAIL "$1" "${2:-}" "${3:-}"; _LAST_SUPPRESSED=1; else echo "FAIL: $1"; _record FAIL "$1" "${2:-}" "${3:-}"; _LAST_SUPPRESSED=0; fi; }
warn() { if is_suppressed "$_CURRENT_RULE" "${2:-}" "${3:-}"; then _record_suppressed WARN "$1" "${2:-}" "${3:-}"; _LAST_SUPPRESSED=1; else echo "WARN: $1"; _record WARN "$1" "${2:-}" "${3:-}"; _LAST_SUPPRESSED=0; fi; }
pass() { if is_suppressed "$_CURRENT_RULE" "${2:-}" "${3:-}"; then _record_suppressed PASS "$1" "${2:-}" "${3:-}"; _LAST_SUPPRESSED=1; else echo "PASS: $1"; _record PASS "$1" "${2:-}" "${3:-}"; _LAST_SUPPRESSED=0; fi; }

# detail <text> — indented evidence under the previous finding; skipped when it was suppressed.
detail() { [[ "${_LAST_SUPPRESSED:-0}" == 1 ]] || printf '%s\n' "$1" | sed 's/^/      /'; }

# ===================================================================
# Auto-detection of the project layout
# ===================================================================

# Paths to ignore everywhere: VCS, dependency checkouts, build output, worktrees.
PRUNE=( -not -path '*/.git/*' -not -path '*/Pods/*' -not -path '*/Carthage/*'
        -not -path '*/.build/*' -not -path '*/build/*' -not -path '*/DerivedData/*'
        -not -path '*/SourcePackages/*' -not -path '*/checkouts/*' -not -path '*/.swiftpm/*'
        -not -path '*/.claude/*' -not -path '*/worktrees/*'
        -not -path '*/node_modules/*' -not -path '*/vendor/*' )

# Same prune set expressed as grep --exclude-dir globs, for repo-wide grep -r passes
# (the find-style PRUNE above is not valid grep syntax).
GREP_PRUNE=( --exclude-dir=.git --exclude-dir=Pods --exclude-dir=Carthage
            --exclude-dir=.build --exclude-dir=build --exclude-dir=DerivedData
            --exclude-dir=SourcePackages --exclude-dir=checkouts --exclude-dir=.swiftpm
            --exclude-dir=.claude --exclude-dir=worktrees
            --exclude-dir=node_modules --exclude-dir=vendor )

# One shared source include-set: Swift plus Objective-C(++). Every code-level
# grep uses this set — scanning *.swift only silently passes real rejection
# vectors (missing purpose strings, tracking SDKs) living in .m/.h files.
SRC_INC=( --include='*.swift' --include='*.m' --include='*.mm' --include='*.h' )

# Load .precheck-ignore path exclusions (Task 2 suppress.sh) and extend both
# prune sets so a suppressed path is skipped by detection AND grep passes.
load_precheck_ignore "$ROOT"
while IFS= read -r _g; do
  [[ -z "$_g" ]] && continue
  PRUNE+=( -not -path "*/$_g/*" -not -path "$_g/*" )
  GREP_PRUNE+=( --exclude-dir="${_g##*/}" )
done <<PRUNE_GLOBS
$(precheck_prune_globs)
PRUNE_GLOBS

# Reads newline-separated paths on stdin, prints the one with the fewest path
# segments (the shallowest, i.e. the real project copy rather than a nested one).
pick_shallowest() { awk '{ n=gsub(/\//,"/"); print n"\t"$0 }' | sort -n | head -1 | cut -f2-; }

detect_first() { find . "${PRUNE[@]}" "$@" 2>/dev/null | pick_shallowest; }

# Non-app Xcode target basenames, matched CamelCase + case-sensitively so glued
# suffixes ("WikipediaUnitTests", "WidgetExtension") are caught while lowercase
# substrings ("Latest" → "test") are not. These are deprioritized in detection.
NONAPP_TARGET='(Watch|Extension|Widget|Intents|Clip|Notification|Share|Sticker|Tests|UITests|Framework)'

# iOS source dir: the app target's source root. Candidates are Info.plist directories
# AND app-entry-point directories — because modern Xcode apps often have NO checked-in
# Info.plist for the main target (it is auto-generated), so an Info.plist-only search
# can land on a Watch app, an app extension, or a framework instead of the real app.
# We score candidates by Swift-file count and deprioritize obvious non-app targets, so
# they only win when nothing app-like exists.
# Sets the globals IOS_DIR (and, when resolved via the project model, PM_INFO_PLIST)
# directly rather than echoing a result — this function MUST be called without
# command substitution (no `IOS_DIR="$(detect_ios_dir)"`) so its assignments run
# in the caller's shell instead of a subshell, where they would be discarded.
detect_ios_dir() {
  local d; d=$(cfg '.iosSourceDir')
  [[ -n "$d" ]] && { IOS_DIR="$d"; return; }
  # Authoritative: parse the Xcode project model when a .pbxproj exists.
  local pm; pm="$(pm_resolve . 2>/dev/null)"
  if [[ -n "$pm" ]]; then
    PM_INFO_PLIST="$(printf '%s' "$pm" | cut -f2)"
    IOS_DIR="$(printf '%s' "$pm" | cut -f1)"
    return
  fi
  # Fallback: the original grep heuristic (unchanged).
  local candidates plist entry
  candidates=$(
    find . "${PRUNE[@]}" -name Info.plist 2>/dev/null | while IFS= read -r plist; do dirname "$plist"; done
    grep -rlE '@main|@UIApplicationMain|class AppDelegate' --include='*.swift' "${GREP_PRUNE[@]}" . 2>/dev/null \
      | while IFS= read -r entry; do dirname "$entry"; done
  )
  candidates=$(printf '%s\n' "$candidates" | sort -u)
  local best="" best_n=-1 alt="" alt_n=-1 dir n
  while IFS= read -r dir; do
    [[ -z "$dir" ]] && continue
    n=$(find "$dir" -maxdepth 4 -name '*.swift' "${PRUNE[@]}" 2>/dev/null | wc -l | tr -d ' ')
    if printf '%s' "$dir" | grep -qE "$NONAPP_TARGET"; then
      (( n > alt_n )) && { alt_n=$n; alt="$dir"; }
    else
      (( n > best_n )) && { best_n=$n; best="$dir"; }
    fi
  done <<< "$candidates"
  if [[ -n "$best" ]]; then IOS_DIR="$best"; else IOS_DIR="$alt"; fi
}

PM_INFO_PLIST=""
IOS_DIR=""
detect_ios_dir
META_DIR="$(cfg '.metadataDir')";      [[ -z "$META_DIR" ]]   && META_DIR="$(detect_first -type d -name metadata -path '*fastlane*')"
SCREEN_DIR="$(cfg '.screenshotsDir')"; [[ -z "$SCREEN_DIR" ]] && SCREEN_DIR="$(detect_first -type d -name screenshots -path '*fastlane*')"
XCSTRINGS="$(cfg '.xcstringsPath')";   [[ -z "$XCSTRINGS" ]]  && XCSTRINGS="$(detect_first -name 'Localizable.xcstrings')"
[[ -z "$XCSTRINGS" ]] && XCSTRINGS="$(detect_first -name '*.xcstrings')"
PRIVACY_FILE="$(detect_first -name 'PrivacyInfo.xcprivacy')"
INFO_PLIST="${PM_INFO_PLIST:-${IOS_DIR%/}/Info.plist}"
REVIEW_PREP="$(cfg '.reviewPrepNotes')"

# Paywall / subscription views. A real app spreads its purchase UI across several files
# (the paywall, a price row, a footer with the links), so we collect the whole cluster —
# every glob match, minus *ViewModel* files, which are logic, never the screen — and run
# the required-link checks across all of them. Checking a single auto-picked file gives
# false FAILs when detection lands on a manage/cancel screen instead of the paywall.
# Config globs win if provided. SUB_VIEW is the shallowest match, used only for messages.
SUB_VIEW=""
# Initialize with =() so the arrays are definitively assigned: under `set -u`, a
# `declare -a` that is never populated makes ${#arr[@]} an unbound-variable error on
# some bash builds (seen on the CI runner). The ${arr[@]+...} idiom below additionally
# guards empty-array expansion on bash 3.2 (macOS).
declare -a PAYWALL_GLOBS=() PAYWALL_FILES=()
if [[ -f "$CONFIG" ]] && have_jq && [[ "$(jq -r '.paywallGlobs | type' "$CONFIG" 2>/dev/null)" == "array" ]]; then
  while IFS= read -r g; do PAYWALL_GLOBS+=("$g"); done < <(jq -r '.paywallGlobs[]' "$CONFIG" 2>/dev/null)
else
  PAYWALL_GLOBS=( '*SubscriptionView*.swift' '*PaywallView*.swift' '*Paywall*.swift' '*[Ss]ubscription*View.swift' '*[Pp]urchase*View.swift' )
fi
for g in "${PAYWALL_GLOBS[@]+"${PAYWALL_GLOBS[@]}"}"; do
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    PAYWALL_FILES+=("$f")
  done < <(find "${IOS_DIR:-.}" "${PRUNE[@]}" -name "$g" 2>/dev/null | grep -v 'ViewModel')
done
if (( ${#PAYWALL_FILES[@]} > 0 )); then
  SUB_VIEW=$(printf '%s\n' "${PAYWALL_FILES[@]}" | pick_shallowest)
fi

# Locales: explicit config array, else the directory names under metadata/.
declare -a LOCALES=()
LOCALES_FROM_CONFIG=""
if [[ -f "$CONFIG" ]] && have_jq && [[ "$(jq -r '.locales | type' "$CONFIG" 2>/dev/null)" == "array" ]]; then
  LOCALES_FROM_CONFIG=1
  while IFS= read -r l; do LOCALES+=("$l"); done < <(jq -r '.locales[]' "$CONFIG" 2>/dev/null)
elif [[ -d "$META_DIR" ]]; then
  while IFS= read -r d; do
    b=$(basename "$d")
    # ASC locale dirs look like xx or xx-YY; skip non-locale folders.
    [[ "$b" =~ ^[a-z]{2}(-[A-Za-z]{2,4})?$ ]] && LOCALES+=("$b")
  done < <(find "$META_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
fi

SUB_KEY="$(cfg '.disclosureKeys.subscription' 'subscription_disclosure')"
TRIAL_KEY="$(cfg '.disclosureKeys.trial' 'subscription_trial_disclosure')"
CHECK_FAMILY="$(cfg_bool '.optionalChecks.familyControls')"

if [[ "$FORMAT" != text ]]; then exec 4>&1 1>/dev/null; fi

echo "PASS: layout — ios='${IOS_DIR:-?}' metadata='${META_DIR:-?}' xcstrings='${XCSTRINGS:-?}' locales=${#LOCALES[@]}"

# ===================================================================
# §1 — 5.1.1 Privacy Manifest / Required Reason API parity
# Apple documents the Required Reason API rules under 5.1.1 (Data Collection and
# Storage) + the privacy-manifest developer docs; it is NOT roman sub-item (v).
# (v) "Account Sign-In" is a different rule — its account-deletion requirement is
# checked separately in §38.
# ===================================================================
set_rule "privacy-manifest-parity"
check_required_reason_api() {
  local cat="$1" pattern="$2" hits declared
  hits=$(grep -rEl "$pattern" "$IOS_DIR" "${GREP_PRUNE[@]}" "${SRC_INC[@]}" 2>/dev/null | head -3)
  declared=$(grep -c "NSPrivacyAccessedAPICategory${cat}" "$PRIVACY_FILE" 2>/dev/null)
  if [[ -n "$hits" && "${declared:-0}" -eq 0 ]]; then
    fail "5.1.1 Required Reason API — '$cat' used in code (e.g. $(echo "$hits" | head -1)) but not declared in PrivacyInfo.xcprivacy" "$PRIVACY_FILE"
  elif [[ -z "$hits" && "${declared:-0}" -gt 0 ]]; then
    warn "5.1.1 PrivacyInfo — '$cat' declared but no code usage grepped (may be a false positive, verify manually)" "$PRIVACY_FILE"
  elif [[ -n "$hits" && "${declared:-0}" -gt 0 ]]; then
    pass "5.1.1 Required Reason API — '$cat' parity OK"
  fi
}
if [[ -z "$IOS_DIR" ]]; then
  warn "layout — could not auto-detect iOS source dir; set .iosSourceDir in $CONFIG"
elif [[ -z "$PRIVACY_FILE" ]]; then
  fail "5.1.1 Required Reason API — PrivacyInfo.xcprivacy not found (required since May 2024 for apps using Required Reason APIs)" "$INFO_PLIST"
else
  check_required_reason_api "UserDefaults"   'UserDefaults|@AppStorage'
  # Anchored to real filesystem APIs: bare `creationDate` / `modificationDate`
  # are ubiquitous model/Core-Data property names and false-FAIL on them.
  check_required_reason_api "FileTimestamp"  'attributesOfItem|fileCreationDate|fileModificationDate|creationDateKey|contentModificationDateKey|contentModificationDate'
  check_required_reason_api "SystemBootTime" 'systemUptime|mach_absolute_time|CACurrentMediaTime\(\)'
  check_required_reason_api "DiskSpace"      'volumeAvailableCapacity|volumeTotalCapacity'
  check_required_reason_api "ActiveKeyboard" 'activeInputModes|UITextInputMode'
fi

# ===================================================================
# §2 — 5.1.1 NSUsageDescription cross-check (Info.plist)
# ===================================================================
set_rule "usage-description-crosscheck"
if [[ ! -f "$INFO_PLIST" ]]; then
  [[ -n "$IOS_DIR" ]] && warn "5.1.1 Info.plist not found at $INFO_PLIST (modern Xcode may auto-generate it; verify purpose strings in build settings)" "$INFO_PLIST"
else
  awk '/NS[A-Za-z]+UsageDescription/{key=$0; getline; if($0 ~ /<string>[[:space:]]*<\/string>/) print "EMPTY:"key}' "$INFO_PLIST" | while read -r line; do
    [[ -n "$line" ]] && fail "5.1.1 Purpose String — $line (empty usage description is rejected by App Review)" "$INFO_PLIST"
  done
  for fw in \
    "FamilyControls|ManagedSettings|DeviceActivity:NSFamilyControlsUsageDescription" \
    "CoreLocation:NSLocationWhenInUseUsageDescription" \
    "Contacts:NSContactsUsageDescription" \
    "HealthKit:NSHealthShareUsageDescription"; do
    framework="${fw%%:*}"; needed_key="${fw##*:}"
    if grep -rqE "import ($framework)|($framework)\." "$IOS_DIR" "${GREP_PRUNE[@]}" "${SRC_INC[@]}" 2>/dev/null; then
      if ! grep -qE "$needed_key" "$INFO_PLIST" 2>/dev/null; then
        fail "5.1.1 framework '${framework%%|*}' imported but Info.plist is missing '${needed_key%%|*}'" "$INFO_PLIST"
      fi
    fi
  done
  # AVFoundation and Photos are gated on real capture/read APIs, not bare
  # imports: an import only signals framework linkage, not camera/mic/library
  # access (e.g. AVFoundation is commonly imported for playback-only use via
  # AVAudioPlayer/AVPlayer, and Photos/PhotosUI's PhotosPicker/PHPickerViewController
  # run out-of-process and need no Info.plist key at all).
  # Camera: purpose string required only when a capture API is actually used.
  if grep -rqE 'AVCaptureDevice|AVCaptureSession|UIImagePickerController' "$IOS_DIR" "${GREP_PRUNE[@]}" "${SRC_INC[@]}" 2>/dev/null; then
    grep -qE 'NSCameraUsageDescription' "$INFO_PLIST" 2>/dev/null || \
      fail "5.1.1 camera capture API used but Info.plist is missing 'NSCameraUsageDescription'" "$INFO_PLIST"
  fi
  # Microphone: required only for recording/capture, not playback. Matched
  # separately from the camera check above: a bare AVCaptureDevice only
  # implies microphone use when it is audio-typed (`.audio` device/media
  # type), not for a video-only capture device.
  if grep -rqE 'AVAudioRecorder|installTap\(|AVAudioEngine\(|AVAudioSession[^;]*\.(playAndRecord|record)|AVCaptureDevice[^;)]*\.audio|for:[[:space:]]*\.audio' "$IOS_DIR" "${GREP_PRUNE[@]}" "${SRC_INC[@]}" 2>/dev/null; then
    grep -qE 'NSMicrophoneUsageDescription' "$INFO_PLIST" 2>/dev/null || \
      fail "5.1.1 microphone/recording API used but Info.plist is missing 'NSMicrophoneUsageDescription'" "$INFO_PLIST"
  fi
  # Photo library READ: PhotosPicker/PHPicker need no key; only true read/fetch APIs do.
  if grep -rqE 'PHAsset\b|PHFetchResult|PHImageManager|fetchAssets|PHAssetCollection' "$IOS_DIR" "${GREP_PRUNE[@]}" "${SRC_INC[@]}" 2>/dev/null; then
    grep -qE 'NSPhotoLibraryUsageDescription' "$INFO_PLIST" 2>/dev/null || \
      fail "5.1.1 Photos read API used but Info.plist is missing 'NSPhotoLibraryUsageDescription'" "$INFO_PLIST"
  elif grep -rqE 'PHAssetCreationRequest|UIImageWriteToSavedPhotosAlbum|performChanges' "$IOS_DIR" "${GREP_PRUNE[@]}" "${SRC_INC[@]}" 2>/dev/null; then
    # Add-only save: covered by the add-only key.
    grep -qE 'NSPhotoLibraryAddUsageDescription' "$INFO_PLIST" 2>/dev/null || \
      fail "5.1.1 Photos add-only API used but Info.plist is missing 'NSPhotoLibraryAddUsageDescription'" "$INFO_PLIST"
  fi
fi

# ===================================================================
# §3 — 5.1.2 ATT (App Tracking Transparency)
# ===================================================================
# Ad / attribution / IDFA SDK signal, shared with §16. The reverse of §3: §3 fires
# when the ATT framework IS imported; §16 fires when a tracking SDK is present but
# the ATT prompt is NOT. Computed once here so the two checks never contradict.
set_rule "att-usage"
tracking_sdk=$(grep -rlE 'advertisingIdentifier|ASIdentifierManager|GADMobileAds|GoogleMobileAds|AppLovinSDK|ALSdk|AppsFlyerLib|import Adjust|Adjust\.|FBAudienceNetwork|BranchSDK|IronSource' "$IOS_DIR" "${GREP_PRUNE[@]}" "${SRC_INC[@]}" 2>/dev/null | head -1)
att_used=$(grep -rlE 'AppTrackingTransparency|ATTrackingManager' "$IOS_DIR" "${GREP_PRUNE[@]}" "${SRC_INC[@]}" 2>/dev/null | head -1)
if [[ -n "$att_used" ]]; then
  if grep -q "NSUserTrackingUsageDescription" "$INFO_PLIST" 2>/dev/null; then
    pass "5.1.2 ATT — used + NSUserTrackingUsageDescription present"
  else
    fail "5.1.2 ATT framework imported but NSUserTrackingUsageDescription missing in Info.plist ($att_used)" "$INFO_PLIST"
  fi
elif [[ -z "$tracking_sdk" ]]; then
  pass "5.1.2 ATT — not used (no tracking)"
fi
# If a tracking SDK is present without the ATT framework, §3 stays silent and §16
# raises the WARN, so we never print a misleading "no tracking" PASS.

# ===================================================================
# §4 — 2.3.10 Other-platform / competitor mentions in metadata
# ===================================================================
set_rule "competitor-mentions"
if [[ -d "$META_DIR" ]]; then
  banned_re='Android|Google[[:space:]]?Play|Play[[:space:]]?Store|Windows[[:space:]]?Phone|Samsung Galaxy|Huawei AppGallery|F-Droid'
  hits=$(grep -rEnI "$banned_re" "$META_DIR" 2>/dev/null | grep -v "^Binary file" | head -30)
  if [[ -n "$hits" ]]; then
    fail "2.3.10 Other-platform mention — banned reference in metadata:"
    detail "$hits"
  else
    pass "2.3.10 Other-platform mentions — metadata clean"
  fi
fi

# ===================================================================
# §5 — 2.3.1 Metadata character limits (Unicode codepoints, like ASC)
# ===================================================================
set_rule "metadata-char-limits"
check_len() {
  local file="$1" limit="$2" label="$3" len
  [[ -f "$file" ]] || return
  if command -v python3 >/dev/null 2>&1; then
    len=$(python3 -c "import sys; print(len(open(sys.argv[1], encoding='utf-8').read().rstrip('\n')))" "$file" 2>/dev/null)
  else
    len=$(wc -m < "$file" | tr -d ' ')
  fi
  [[ -z "$len" ]] && return
  (( len > limit )) && fail "2.3.1 $label — $file ${len} chars (limit ${limit})" "$file"
}
for loc in "${LOCALES[@]+"${LOCALES[@]}"}"; do
  d="$META_DIR/$loc"; [[ -d "$d" ]] || continue
  check_len "$d/name.txt" 30 "name[$loc]"
  check_len "$d/subtitle.txt" 30 "subtitle[$loc]"
  check_len "$d/keywords.txt" 100 "keywords[$loc]"
  check_len "$d/promotional_text.txt" 170 "promo[$loc]"
  check_len "$d/description.txt" 4000 "description[$loc]"
done

# ===================================================================
# §6 — 2.3.7 Localized metadata parity across all detected locales
# ===================================================================
set_rule "locale-metadata-parity"
if (( ${#LOCALES[@]} > 0 )); then
  expected_files=(name.txt subtitle.txt description.txt keywords.txt)
  for loc in "${LOCALES[@]+"${LOCALES[@]}"}"; do
    d="$META_DIR/$loc"
    if [[ ! -d "$d" ]]; then
      # A locale listed in .appstore-precheck.json but absent on disk is a
      # config/reality mismatch, not a build fault: the locale was simply never
      # submitted. Warn (don't block) so an approved set isn't falsely RED.
      # Auto-detected locales always exist, so this only fires in config mode.
      if [[ -n "$LOCALES_FROM_CONFIG" ]]; then
        warn "2.3.7 Locale '$loc' is in .appstore-precheck.json but has no metadata folder ($d) — add it or remove '$loc' from the config 'locales' list"
      else
        fail "2.3.7 Locale missing — $d does not exist"
      fi
      continue
    fi
    for f in "${expected_files[@]}"; do
      [[ -s "$d/$f" ]] || fail "2.3.7 Metadata missing — $d/$f is empty or absent"
    done
  done
  pass "2.3.7 Localized metadata — checked ${#LOCALES[@]} locales"
fi

# ===================================================================
# §7 — 2.3.3 Screenshots per locale
# ===================================================================
set_rule "screenshots-per-locale"
if [[ -n "$SCREEN_DIR" && -d "$SCREEN_DIR" ]]; then
  for loc in "${LOCALES[@]+"${LOCALES[@]}"}"; do
    d="$SCREEN_DIR/$loc"
    if [[ ! -d "$d" ]]; then warn "2.3.3 Screenshots — no folder for $loc"; continue; fi
    cnt=$(find "$d" -maxdepth 2 -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" \) 2>/dev/null | wc -l | tr -d ' ')
    if (( cnt == 0 )); then
      fail "2.3.3 Screenshots — $loc folder is empty (at least one iPhone screenshot required)"
    elif (( cnt < 3 )); then
      warn "2.3.3 Screenshots — $loc has only $cnt image(s) (3-10 recommended)"
    fi
  done
  pass "2.3.3 Screenshots — checked ${#LOCALES[@]} locales under $SCREEN_DIR"
else
  pass "2.3.3 Screenshots — no in-repo screenshots dir; assumed managed in App Store Connect (set .screenshotsDir to check in-repo)"
fi

# ===================================================================
# §7b — 2.3.3 Screenshot format + PNG dimensions (deterministic; PNG dims,
# JPEG format only). WARN-only: the accepted-size table can drift, and we
# cannot know which display slot a file targets, so mismatches never FAIL.
# ===================================================================
if [[ -n "$SCREEN_DIR" && -d "$SCREEN_DIR" ]]; then
  set_rule "screenshot-dimensions"
  while IFS= read -r img; do
    [[ -z "$img" ]] && continue
    fmt="$(img_format "$img")"
    case "$img" in
      *.png)
        if [[ "$fmt" != png ]]; then
          warn "2.3.3 Screenshot $img is not a valid PNG (file content does not match .png extension)" "$img"
          continue
        fi
        dims="$(png_dims "$img")"
        if [[ -z "$dims" ]]; then
          warn "2.3.3 Screenshot $img — could not read PNG dimensions (possibly truncated)" "$img"
        else
          w="${dims% *}"; h="${dims#* }"
          if ! dims_match_accepted "$w" "$h"; then
            warn "2.3.3 Screenshot $img is ${w}x${h}, which matches no known App Store screenshot size — verify against the current spec" "$img"
          fi
        fi
        ;;
      *.jpg|*.jpeg)
        if [[ "$fmt" != jpeg ]]; then
          warn "2.3.3 Screenshot $img is not a valid JPEG (file content does not match extension)" "$img"
        fi
        ;;
    esac
  done < <(find "$SCREEN_DIR" -maxdepth 3 -type f \( -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' \) 2>/dev/null | sort)
  set_rule ""
fi

# ===================================================================
# In-app purchase gate — only run 3.1.2 checks if IAP signals exist
# ===================================================================
iap_detected=""
grep -rqE 'SKPaymentQueue|SKProduct|SKMutablePayment|Product\.products|Product\(for:|Product\(id:|\.purchase\(|Transaction\.currentEntitlements|Transaction\.updates|RevenueCat|Purchases\.(shared|configure|logIn|getProducts)|Adapty|Glassfy|import Qonversion' "$IOS_DIR" "${GREP_PRUNE[@]}" "${SRC_INC[@]}" 2>/dev/null && iap_detected=1
[[ -n "$SUB_VIEW" ]] && iap_detected=1

if [[ -z "$iap_detected" ]]; then
  # Not one of the 42 catalog sections — clear the rule_id so this PASS doesn't
  # inherit §7's "screenshots-per-locale" slug in the JSON output.
  set_rule ""
  pass "3.1.2 IAP — no in-app purchase / subscription signals detected, skipping paywall checks"
else
  # ---- §8 3.1.2 Trial disclosure -------------------------------------------------
  set_rule "trial-disclosure"
  trial_re='free[[:space:]]?trial|trial[[:space:]]?period|ücretsiz[[:space:]]?dene|kostenlos[[:space:]]?test|essai[[:space:]]?gratuit|prueba[[:space:]]?grat|無料.*トライアル|무료[[:space:]]?체험'
  if [[ -n "$XCSTRINGS" ]] && grep -EqI "$trial_re" "$XCSTRINGS" 2>/dev/null; then
    if grep -q "$TRIAL_KEY" "$XCSTRINGS" 2>/dev/null; then
      pass "3.1.2 Free trial offered + trial disclosure key '$TRIAL_KEY' present"
    else
      warn "3.1.2 Trial wording detected but disclosure key '$TRIAL_KEY' not found — ensure trial→paid auto-renew terms (length, price, cancel) are shown near the CTA"
    fi
  else
    pass "3.1.2 Trial — no trial wording detected, disclosure check skipped"
  fi

  # ---- §9 3.1.2 Auto-renew subscription disclosure -------------------------------
  set_rule "autorenew-disclosure"
  if [[ -n "$XCSTRINGS" ]]; then
    if have_jq && jq -e ".strings | has(\"$SUB_KEY\")" "$XCSTRINGS" >/dev/null 2>&1; then
      pass "3.1.2 subscription disclosure key '$SUB_KEY' present"
      for loc in "${LOCALES[@]+"${LOCALES[@]}"}"; do
        short="${loc%%-*}"
        if ! jq -e ".strings.\"$SUB_KEY\".localizations | (has(\"$loc\") or has(\"$short\"))" "$XCSTRINGS" >/dev/null 2>&1; then
          warn "3.1.2 subscription disclosure — translation missing for '$loc' (key '$SUB_KEY')"
        fi
      done
    elif grep -qEiI 'auto.?renew|renews automatically|otomatik.*yenilen|automatisch.*verläng|se renueva' "$XCSTRINGS" 2>/dev/null; then
      warn "3.1.2 auto-renew language found but not under key '$SUB_KEY' — verify disclosure key naming or set .disclosureKeys.subscription"
    else
      warn "3.1.2 No auto-renewal disclosure string detected — Apple requires it for auto-renewable subscriptions; verify manually"
    fi
  fi

  # ---- §10 3.1.2 Required links + Restore Purchases ------------------------------
  # Grep across the whole paywall cluster: a link present in ANY paywall view satisfies
  # the requirement; only its absence from ALL of them is a FAIL. SUB_VIEW names the
  # representative file in messages.
  set_rule "subscription-links-restore"
  if (( ${#PAYWALL_FILES[@]} > 0 )); then
    # Remote-configured paywalls (RevenueCatUI's PaywallView, presentPaywall,
    # paywallFooter, AdaptyUI) render Restore/Terms/Privacy from the vendor
    # dashboard, so those controls never appear in app source. A hard FAIL here
    # would false-RED a compliant app; downgrade the missing-link findings to
    # verify-in-dashboard WARNs when that signal is present.
    remote_paywall=""
    grep -rqE 'RevenueCatUI|presentPaywall|paywallFooter|AdaptyUI' "$IOS_DIR" "${GREP_PRUNE[@]}" "${SRC_INC[@]}" 2>/dev/null && remote_paywall=1
    # paywall_req <label> <pattern> [pass-suffix]: PASS when the pattern is in
    # any paywall view, WARN when a remote paywall likely renders it, else FAIL.
    paywall_req() {
      local label="$1" pattern="$2" pass_suffix="${3:-— present}"
      if grep -qiE "$pattern" "${PAYWALL_FILES[@]}"; then
        pass "3.1.2 $label $pass_suffix"
      elif [[ -n "$remote_paywall" ]]; then
        warn "3.1.2 $label — not in app source, but a remote-configured paywall (RevenueCatUI / presentPaywall) was detected; verify the dashboard-configured paywall shows it before submitting"
      else
        fail "3.1.2 $label — not found in the paywall views (e.g. $SUB_VIEW)"
      fi
    }
    paywall_req "Restore Purchases" 'restore|AppStore\.sync' "— present in $(basename "$SUB_VIEW")"
    paywall_req "Terms of Use (EULA) link" 'terms[ _]?of[ _]?(use|service)|termsURL|subscription_terms|EULA|/terms|/tos\b|/eula'
    paywall_req "Privacy Policy link" 'privacy[ _]?policy|privacyURL|subscription_privacy|/privacy|datenschutz|gizlilik'
  else
    warn "3.1.2 IAP detected but no paywall/subscription view found — set .paywallGlobs so required-link checks can run"
  fi
fi

# ===================================================================
# §11 — 2.5.1 Private / banned API
# ===================================================================
set_rule "private-api"
banned_api='UIWebView|setSelectionIndicatorImage|_UIBackdropView|NSURLConnection[^a-zA-Z]|UIAlertView[^Q]|UIActionSheet[^Q]'
banned_hits=$(grep -rEnI "$banned_api" "$IOS_DIR" "${GREP_PRUNE[@]}" "${SRC_INC[@]}" 2>/dev/null | head -5)
if [[ -n "$banned_hits" ]]; then
  pa_first="$(printf '%s\n' "$banned_hits" | head -1)"   # "path:line:match"
  pa_file="${pa_first%%:*}"
  pa_rest="${pa_first#*:}"; pa_line="${pa_rest%%:*}"
  fail "2.5.1 Private/Deprecated API:" "$pa_file" "$pa_line"
  detail "$banned_hits"
else
  pass "2.5.1 Private API — clean"
fi

# ===================================================================
# §12 — 4.2 Minimum functionality — navigation hubs
# ===================================================================
set_rule "min-functionality-nav"
tab_count=$(grep -rcE 'TabView|NavigationStack|NavigationSplitView|NavigationView|UITabBarController|UINavigationController|createBottomTabNavigator|createStackNavigator|createNativeStackNavigator' . "${GREP_PRUNE[@]}" --include='*.swift' --include='*.m' --include='*.js' --include='*.jsx' --include='*.ts' --include='*.tsx' 2>/dev/null | awk -F: '{sum+=$2} END {print sum+0}')
if (( tab_count < 1 )); then
  warn "4.2 Minimum functionality — no TabView/NavigationStack found (heuristic, may be a false positive)"
else
  pass "4.2 Minimum functionality — $tab_count navigation hub(s) found"
fi

# ===================================================================
# §13 — 5.1.5 Screen Time / sensitive-API justification (optional, opt-in)
# ===================================================================
set_rule "screentime-justification"
if [[ "$CHECK_FAMILY" == "true" ]] && grep -q "NSFamilyControlsUsageDescription" "$INFO_PLIST" 2>/dev/null; then
  if [[ -n "$REVIEW_PREP" && -f "$REVIEW_PREP" ]] && grep -qiE 'family|screen[[:space:]]?time' "$REVIEW_PREP" 2>/dev/null; then
    pass "5.1.5 Screen Time API — reviewer-prep justification note present"
  else
    warn "5.1.5 Screen Time API in use — add a justification in your ASC App Review notes (point .reviewPrepNotes at the file). Otherwise 5.1.1 rejection risk is high."
  fi
fi

# ===================================================================
# §14 — 4.8 Sign in with Apple parity (only when a third-party social login is used)
# ===================================================================
set_rule "siwa-parity"
if [[ -n "$IOS_DIR" ]]; then
  social_login=$(grep -rlE 'GIDSignIn|import GoogleSignIn|FBSDKLoginKit|FBSDKLoginManager|FacebookLogin|import Auth0|LineSDK|VKSdkAuthorization' "$IOS_DIR" "${GREP_PRUNE[@]}" "${SRC_INC[@]}" 2>/dev/null | head -1)
  if [[ -n "$social_login" ]]; then
    if grep -rqE 'ASAuthorizationAppleID|SignInWithAppleButton|AppleIDProvider' "$IOS_DIR" "${GREP_PRUNE[@]}" "${SRC_INC[@]}" 2>/dev/null; then
      pass "4.8 Sign in with Apple — present alongside third-party login"
    else
      warn "4.8 Sign in with Apple — third-party social login detected (e.g. $(basename "$social_login")) but no Sign in with Apple found; Apple requires an equivalent option (4.8). Some account systems are exempt — verify."
    fi
  fi
fi

# ===================================================================
# §15 — 3.1.1(a) External purchase link (StoreKit External Purchase)
# ===================================================================
set_rule "external-purchase-link"
ext_purchase=""
grep -rqE 'ExternalPurchase|ExternalPurchaseLink|ExternalPurchaseCustomLink' "${IOS_DIR:-.}" "${GREP_PRUNE[@]}" "${SRC_INC[@]}" 2>/dev/null && ext_purchase=1
grep -rqE 'external-purchase' "${IOS_DIR:-.}" "${GREP_PRUNE[@]}" --include='*.entitlements' 2>/dev/null && ext_purchase=1
if [[ -n "$ext_purchase" ]]; then
  warn "3.1.1(a) External purchase link detected — ensure the External Purchase entitlement, eligible storefronts, the required disclosure sheet, and App Store Connect reporting are in place (3.1.1(a))."
fi

# ===================================================================
# §16 — 5.1.2 Tracking SDK / IDFA without ATT (the reverse of §3)
# ===================================================================
# §3 catches "ATT framework imported but no usage string". This catches the more
# common rejection: shipping an ad / attribution SDK (or touching the IDFA) without
# ever presenting the ATT prompt. `tracking_sdk` and `att_used` are computed in §3.
set_rule "tracking-sdk-no-att"
if [[ -n "$tracking_sdk" ]]; then
  att_present=""
  [[ -n "$att_used" ]] && att_present=1
  grep -q "NSUserTrackingUsageDescription" "$INFO_PLIST" 2>/dev/null && att_present=1
  if [[ -n "$att_present" ]]; then
    pass "5.1.2 Tracking SDK — present alongside an ATT prompt"
  else
    warn "5.1.2 Tracking SDK — IDFA/tracking signals detected (e.g. $(basename "$tracking_sdk")) but no ATT prompt found; apps that track must request permission via AppTrackingTransparency (5.1.2)"
  fi
fi

# ===================================================================
# §17 — Export-compliance key (ITSAppUsesNonExemptEncryption)
# ===================================================================
# Without this key, App Store Connect asks the encryption/export question on every
# submission. Setting it (true/false) removes that friction. Only checked when an
# Info.plist exists; a modern app may auto-generate it, in which case the key lives
# in build settings, so we stay silent rather than nag.
set_rule "export-compliance"
if [[ -f "$INFO_PLIST" ]]; then
  if grep -q "ITSAppUsesNonExemptEncryption" "$INFO_PLIST" 2>/dev/null; then
    pass "export-compliance — ITSAppUsesNonExemptEncryption set in Info.plist"
  else
    warn "export-compliance — Info.plist has no ITSAppUsesNonExemptEncryption; set it (true/false) to skip the App Store Connect encryption-export prompt every submission" "$INFO_PLIST"
  fi
fi

# ===================================================================
# §18 — Support / Privacy URL in fastlane metadata
# ===================================================================
# fastlane deliver stores the localized review URLs per locale as
# support_url.txt / privacy_url.txt / marketing_url.txt. Apple requires a working
# support URL, and a privacy policy URL for apps with accounts or IAP. Flag when
# they are absent across every locale, or contain an obvious placeholder.
set_rule "support-privacy-url"
if [[ -d "$META_DIR" ]]; then
  support_found="" privacy_found=""
  for loc in "${LOCALES[@]+"${LOCALES[@]}"}"; do
    [[ -s "$META_DIR/$loc/support_url.txt" ]] && support_found=1
    [[ -s "$META_DIR/$loc/privacy_url.txt" ]] && privacy_found=1
  done
  if (( ${#LOCALES[@]} > 0 )); then
    [[ -z "$support_found" ]] && warn "2.3 Support URL — no non-empty support_url.txt in any locale under fastlane metadata; Apple requires a working support URL with developer contact info (1.5 / 2.3)"
    [[ -z "$privacy_found" ]] && warn "2.3 Privacy URL — no non-empty privacy_url.txt in any locale under fastlane metadata; a privacy policy link is required for every app, and especially apps with accounts or in-app purchases (5.1.1(i))"
  fi
  url_ph=$(grep -rEnI 'example\.com|localhost|\bTODO\b|\bchangeme\b' "$META_DIR" --include='*_url.txt' 2>/dev/null | grep -v "^Binary file" | head -10)
  if [[ -n "$url_ph" ]]; then
    url_ph_file="$(printf '%s\n' "$url_ph" | head -1 | cut -d: -f1)"
    warn "2.3 Metadata URL — placeholder URL in fastlane metadata (replace before submitting):" "$url_ph_file"
    detail "$url_ph"
  fi
fi

# ===================================================================
# §19 — Analytics SDK present but PrivacyInfo declares no collected data
# ===================================================================
# Privacy-manifest completeness is a growing rejection area. If an analytics SDK is
# linked but PrivacyInfo.xcprivacy declares neither collected data types nor tracking
# domains, the privacy manifest and the App Privacy nutrition labels are probably
# incomplete. Soft "verify" wording (a crash-only Sentry may genuinely collect
# nothing), so WARN, never FAIL.
set_rule "analytics-privacyinfo-mismatch"
analytics_sdk=$(grep -rlE 'FirebaseAnalytics|import Firebase|import Amplitude|Amplitude\(|import Mixpanel|Mixpanel\.|import Sentry|SentrySDK|import Segment|SEGAnalytics|Analytics\.shared\(|import Bugsnag|Bugsnag\.|AppCenterAnalytics|import Datadog|DatadogCore' "$IOS_DIR" "${GREP_PRUNE[@]}" "${SRC_INC[@]}" 2>/dev/null | head -1)
if [[ -n "$analytics_sdk" ]]; then
  declared_data=""
  if [[ -n "$PRIVACY_FILE" && -f "$PRIVACY_FILE" ]]; then
    if grep -qE 'NSPrivacyCollectedDataType</key>' "$PRIVACY_FILE" 2>/dev/null \
       || grep -qE 'NSPrivacyTrackingDomains</key>[[:space:]]*<array>[[:space:]]*<string>' "$PRIVACY_FILE" 2>/dev/null; then
      declared_data=1
    fi
  fi
  if [[ -n "$declared_data" ]]; then
    pass "5.1.1 Privacy manifest — analytics SDK present and PrivacyInfo declares collected data"
  else
    warn "5.1.1 Privacy manifest — analytics SDK detected (e.g. $(basename "$analytics_sdk")) but PrivacyInfo declares no collected data types or tracking domains; verify your privacy manifest and App Privacy nutrition labels" "$PRIVACY_FILE"
  fi
fi

# ===================================================================
# §20 — Placeholder / dummy content in store metadata
# ===================================================================
# Lorem ipsum, TODO/FIXME, example URLs, or "insert X here" left in the store copy
# get rejected under 2.1 and look unfinished. Conservative, specific patterns to
# avoid flagging legitimate words. Overlaps the Phase 2 precheck "No placeholder
# text" rule, but this one is local and runs before any network call.
set_rule "placeholder-metadata"
if [[ -d "$META_DIR" ]]; then
  ph_re='lorem ipsum|Lorem ipsum|\bTODO\b|\bFIXME\b|example\.com|placeholder|insert .* here|\bchangeme\b'
  ph_hits=$(grep -rEnI "$ph_re" "$META_DIR" 2>/dev/null | grep -v "^Binary file" | head -20)
  if [[ -n "$ph_hits" ]]; then
    ph_file="$(printf '%s\n' "$ph_hits" | head -1 | cut -d: -f1)"
    warn "2.1 Metadata content — placeholder/dummy text in store metadata (looks unfinished; rejected under 2.1):" "$ph_file"
    detail "$ph_hits"
  fi
fi

# ===================================================================
# §21 — 3.1.1 Third-party payment SDK for digital goods
# ===================================================================
# Apple requires in-app purchase to unlock digital content/functionality. A
# third-party payment SDK (Stripe, Braintree, PayPal, …) is legitimate for
# PHYSICAL goods/services but a frequent rejection when used to sell digital
# content. We can't tell digital from physical statically, so this is advisory.
set_rule "thirdparty-payment-sdk"
if [[ -n "$IOS_DIR" ]]; then
  payment_sdk=$(grep -rlE 'import Stripe|StripePaymentSheet|StripeApplePay|import Braintree|BTPaymentFlow|import PayPal|PayPalCheckout|PayPalNativeCheckout|import Square|SquareInAppPayments|import Adyen|AdyenComponents|RazorpaySDK|import Paddle' "$IOS_DIR" "${GREP_PRUNE[@]}" "${SRC_INC[@]}" 2>/dev/null | head -1)
  if [[ -n "$payment_sdk" ]]; then
    warn "3.1.1 Third-party payment SDK — '$(basename "$payment_sdk")' detected; selling digital content/functionality must use in-app purchase, not an external processor (3.1.1). Allowed only for physical goods/services — verify your offering."
  fi
fi

# ===================================================================
# §22 — 1.2 User-generated content without moderation affordances
# ===================================================================
# Apps with UGC must provide: a content filter, a report mechanism, the ability
# to block abusive users, and published contact info. We detect a UGC signal and
# warn when no report/block/moderation affordance is found anywhere in the source.
set_rule "ugc-no-moderation"
if [[ -n "$IOS_DIR" ]]; then
  ugc_signal=$(grep -rlE 'userGeneratedContent|\bUGC\b|StreamChat|MessageKit|SendbirdSDK|PubNub|postComment|submitComment|createPost|publishPost|uploadUserPhoto|uploadVideo' "$IOS_DIR" "${GREP_PRUNE[@]}" "${SRC_INC[@]}" 2>/dev/null | head -1)
  if [[ -n "$ugc_signal" ]]; then
    if grep -rqiE 'report(Content|User|Abuse|Post|Comment|Message|Reason|ed)|block(ed)?User|unblockUser|moderat(e|ion|or)|flag(Content|Post|User|Comment|Message)|content.?filter' "$IOS_DIR" "${GREP_PRUNE[@]}" "${SRC_INC[@]}" 2>/dev/null; then
      pass "1.2 UGC — user-generated content with report/block/moderation affordances present"
    else
      warn "1.2 UGC — user-generated content detected (e.g. $(basename "$ugc_signal")) but no report/block/moderation mechanism found; UGC apps must offer content filtering, a report mechanism, user blocking, and published contact info (1.2)"
    fi
  fi
fi

# ===================================================================
# §23 — 1.6 App Transport Security disabled globally
# ===================================================================
# NSAllowsArbitraryLoads=true turns off ATS for the whole app, weakening
# data-in-transit security and inviting a 1.6 / data-security question at review.
set_rule "ats-arbitrary-loads"
if [[ -f "$INFO_PLIST" ]]; then
  # Anchor to the exact key: `NSAllowsArbitraryLoads</key>` (followed by `<`), so the
  # narrower scoped exceptions NSAllowsArbitraryLoadsInWebContent / ...ForMedia — which
  # do NOT disable ATS app-wide and are the recommended alternative — don't false-fire.
  if awk '/NSAllowsArbitraryLoads</{getline; if ($0 ~ /<true/) print "ON"}' "$INFO_PLIST" 2>/dev/null | grep -q ON; then
    warn "1.6 App Transport Security — NSAllowsArbitraryLoads=true in Info.plist disables ATS app-wide; prefer per-domain exceptions, and expect a data-security justification request at review (1.6)" "$INFO_PLIST"
  fi
fi

# ===================================================================
# §24 — 4.9 Apple Pay recurring-payment disclosure
# ===================================================================
# Apps using Apple Pay for recurring payments must disclose the renewal term,
# what's provided, the charges, and how to cancel. Gated strictly on the Apple
# Pay recurring API (PKRecurringPaymentRequest) so it does NOT conflate StoreKit
# auto-renew copy or a one-time PassKit payment with recurring Apple Pay. We don't
# try to detect the disclosure text (too noisy) — we flag it for manual verify.
set_rule "applepay-recurring-disclosure"
if [[ -n "$IOS_DIR" ]] && grep -rqE 'PKRecurringPaymentRequest' "$IOS_DIR" "${GREP_PRUNE[@]}" "${SRC_INC[@]}" 2>/dev/null; then
  warn "4.9 Apple Pay — recurring Apple Pay (PKRecurringPaymentRequest) detected; verify you disclose the renewal term, what's provided, the charges, and how to cancel before purchase (4.9)"
fi

# ===================================================================
# §25 — 5.6.1 Custom App Store review prompt
# ===================================================================
# Apple disallows custom review prompts and direct write-review links — apps must
# use the system SKStoreReviewController / requestReview API.
set_rule "custom-review-prompt"
if [[ -n "$IOS_DIR" ]]; then
  review_link=$(grep -rlE 'write-review|action=write-review|itms-apps[^"]*review' "$IOS_DIR" "${GREP_PRUNE[@]}" "${SRC_INC[@]}" 2>/dev/null | head -1)
  if [[ -n "$review_link" ]]; then
    if grep -rqE 'requestReview|SKStoreReviewController|\.requestReview' "$IOS_DIR" "${GREP_PRUNE[@]}" "${SRC_INC[@]}" 2>/dev/null; then
      pass "5.6.1 App reviews — uses the system requestReview API alongside the review link"
    else
      warn "5.6.1 App reviews — a direct App Store review link/prompt was found (e.g. $(basename "$review_link")) but no system requestReview (SKStoreReviewController) call; Apple disallows custom review prompts (5.6.1)"
    fi
  fi
fi

# ===================================================================
# §26 — 2.3.1 Misleading marketing claims in metadata
# ===================================================================
# Marketing the app for things iOS apps can't actually do (virus/malware
# scanners, fake speed boosters) is a 2.3.1 removal vector.
set_rule "misleading-marketing"
if [[ -d "$META_DIR" ]]; then
  mislead_re='virus scan|virus scanner|antivirus|anti-virus|malware (scan|remov|clean)|spyware remov|clean your (iphone|device)|speed booster|boost.*(speed|ram)|free money|guaranteed.*(win|prize)'
  mislead_hits=$(grep -rEniI "$mislead_re" "$META_DIR" 2>/dev/null | grep -v "^Binary file" | head -10)
  if [[ -n "$mislead_hits" ]]; then
    mislead_file="$(printf '%s\n' "$mislead_hits" | head -1 | cut -d: -f1)"
    warn "2.3.1 Misleading marketing — claims that often violate 2.3.1 (e.g. iOS virus/malware scanners, fake speed boosters) in metadata; verify the app truly delivers them or remove the claim:" "$mislead_file"
    detail "$mislead_hits"
  fi
fi

# ===================================================================
# §27 — 2.3.8 "For Kids/Children" wording outside the Kids Category
# ===================================================================
# Terms implying a child audience in name/subtitle/keywords/description are
# reserved for the Kids Category (2.3.8 / 5.1.4).
set_rule "kids-wording"
if [[ -d "$META_DIR" ]]; then
  kids_re='for kids|for children|for your (kid|child)|kids[[:space:]]?app|für kinder|para niños|pour enfants'
  kids_hits=$(grep -rEniI "$kids_re" "$META_DIR" 2>/dev/null | grep -v "^Binary file" | head -10)
  # Cross-gate with §39 (5.1.4): when an ads/analytics SDK is also linked, §39 fires the
  # more specific Kids finding for the same wording signal — don't double-count it here
  # (one root signal must not cost two WARNs against the 5-WARN YELLOW threshold).
  if [[ -n "$kids_hits" && -z "${tracking_sdk:-}" && -z "${analytics_sdk:-}" ]]; then
    kids_file="$(printf '%s\n' "$kids_hits" | head -1 | cut -d: -f1)"
    warn "2.3.8 'For Kids/Children' wording — terms implying a child audience are reserved for the Kids Category (2.3.8); if not enrolled, remove them from name/subtitle/keywords/description:" "$kids_file"
    detail "$kids_hits"
  fi
fi

# ===================================================================
# §28 — 4.4.1 Keyboard extension requiring full access
# ===================================================================
# Keyboards must stay functional without full network access / "full access",
# and may only collect data to enhance the keyboard.
set_rule "keyboard-full-access"
kb_plist=$(grep -rlE 'com\.apple\.keyboard-service' --include='Info.plist' "${GREP_PRUNE[@]}" . 2>/dev/null | pick_shallowest)
if [[ -n "$kb_plist" ]]; then
  if grep -A1 'RequestsOpenAccess' "$kb_plist" 2>/dev/null | grep -q '<true'; then
    warn "4.4.1 Keyboard extension — RequestsOpenAccess=true in $(basename "$kb_plist"); keyboards must remain functional without full access and may only collect data to enhance the keyboard (4.4.1). Justify full access in your review notes."
  else
    pass "4.4.1 Keyboard extension — present without requiring full access"
  fi
fi

# ===================================================================
# §29 — 5.1.3 Health data with an iCloud sync path
# ===================================================================
# Personal health information must not be stored in iCloud, and HealthKit data
# may not be used for advertising/marketing.
set_rule "health-icloud-sync"
if [[ -n "$IOS_DIR" ]] && grep -rqE 'import HealthKit|HKHealthStore' "$IOS_DIR" "${GREP_PRUNE[@]}" "${SRC_INC[@]}" 2>/dev/null; then
  if grep -rqE 'import CloudKit|CKRecord|CKContainer|NSUbiquitousKeyValueStore|NSUbiquitousContainer' "$IOS_DIR" "${GREP_PRUNE[@]}" "${SRC_INC[@]}" 2>/dev/null; then
    warn "5.1.3 Health data — HealthKit and iCloud/CloudKit are both used; personal health information must not be stored in iCloud (5.1.3). Verify HealthKit data is not synced to iCloud."
  else
    pass "5.1.3 Health data — HealthKit used without an obvious iCloud sync path"
  fi
fi

# ===================================================================
# §30 — 5.4 VPN apps (NetworkExtension)
# ===================================================================
# VPN apps must be offered by an organization account, declare data collection
# on-screen before use, and may not sell/share data.
set_rule "vpn-networkextension"
if [[ -n "$IOS_DIR" ]]; then
  vpn_use=$(grep -rlE 'NEVPNManager|NETunnelProviderManager|NEPacketTunnelProvider|NEVPNProtocol' "$IOS_DIR" "${GREP_PRUNE[@]}" "${SRC_INC[@]}" 2>/dev/null | head -1)
  if [[ -n "$vpn_use" ]]; then
    warn "5.4 VPN — NetworkExtension/NEVPNManager usage detected (e.g. $(basename "$vpn_use")); VPN apps must be offered by an organization account, disclose data collection on-screen before use, and not sell/share data (5.4). Verify compliance."
  fi
fi

# ===================================================================
# §31 — 2.1 Demo account for a credential login
# ===================================================================
# Apps behind a login must give App Review working credentials (a demo account
# or notes). We fire only on a credential-login signal (a password field or a
# Login/SignIn view), then look for demo creds in fastlane review_information or
# the reviewer-prep notes. Social-only logins are not gated here (too noisy).
set_rule "demo-account"
if [[ -n "$IOS_DIR" ]]; then
  auth_signal=$(grep -rlE 'SecureField' "$IOS_DIR" "${GREP_PRUNE[@]}" "${SRC_INC[@]}" 2>/dev/null | head -1)
  [[ -z "$auth_signal" ]] && auth_signal=$(find "$IOS_DIR" "${PRUNE[@]}" \( -name '*Login*View*.swift' -o -name '*SignIn*View*.swift' \) 2>/dev/null | head -1)
  if [[ -n "$auth_signal" ]]; then
    demo_present=""
    ri="$META_DIR/review_information"
    if [[ -d "$ri" ]]; then
      for f in demo_user.txt demo_password.txt notes.txt; do [[ -s "$ri/$f" ]] && demo_present=1; done
    fi
    if [[ -z "$demo_present" && -n "$REVIEW_PREP" && -f "$REVIEW_PREP" ]]; then
      grep -qiE 'demo|review.*(account|credential)|test.*account' "$REVIEW_PREP" 2>/dev/null && demo_present=1
    fi
    if [[ -n "$demo_present" ]]; then
      pass "2.1 Demo account — credential login present and reviewer demo credentials/notes found"
    else
      warn "2.1 Demo account — a credential login was detected (e.g. $(basename "$auth_signal")) but no demo account/credentials for App Review found (fastlane review_information or .reviewPrepNotes); apps behind a login must give reviewers working credentials (2.1)"
    fi
  fi
fi

# ===================================================================
# §32 — 2.5.2 Executable code download / hot-patch
# ===================================================================
# Apps must be self-contained; native hot-patching frameworks (JSPatch, Rollout,
# DynamicCocoa) download code that changes features and are a removal vector.
# JS-bundle OTA for React Native (CodePush) is allowed, so we do NOT flag it.
set_rule "executable-code-download"
if [[ -n "$IOS_DIR" ]]; then
  hotcode=$(grep -rlE 'import JSPatch|JSPatch\.|[Jj][Ss][Pp]atch|import Rollout|Rollout\.|rollout\.io|DynamicCocoa|import SwiftPatch' "$IOS_DIR" "${GREP_PRUNE[@]}" "${SRC_INC[@]}" 2>/dev/null | head -1)
  if [[ -n "$hotcode" ]]; then
    warn "2.5.2 Executable code — a hot-patch / remote-code framework was detected (e.g. $(basename "$hotcode")); apps may not download or run code that changes features (JSPatch/Rollout-style native hot-patching). Allowed JS-bundle OTA (e.g. React Native CodePush) is fine — verify this is not native hot-patching (2.5.2)"
  fi
fi

# ===================================================================
# §33 — 2.5.4 Background modes declared but unused
# ===================================================================
# Declare only the UIBackgroundModes the app actually uses; a mode declared with
# no matching API is a frequent rejection. We parse the array and check each
# declared mode against its framework/API in Swift.
set_rule "background-modes-unused"
if [[ -f "$INFO_PLIST" && -n "$IOS_DIR" ]]; then
  modes=$(awk '/<key>UIBackgroundModes<\/key>/{f=1;next} f&&/<\/array>/{f=0} f&&/<string>/{gsub(/.*<string>|<\/string>.*/,""); print}' "$INFO_PLIST" 2>/dev/null)
  if [[ -n "$modes" ]]; then
    unused=""
    while IFS= read -r m; do
      [[ -z "$m" ]] && continue
      case "$m" in
        location) grep -rqE 'CLLocationManager|CoreLocation' "$IOS_DIR" "${GREP_PRUNE[@]}" "${SRC_INC[@]}" 2>/dev/null || unused="$unused location" ;;
        audio) grep -rqE 'AVAudioSession|AVPlayer|AVAudioPlayer|AVQueuePlayer|AVAudioEngine|AVKit|VideoPlayer|AVPlayerViewController|MPMusicPlayerController|MPNowPlayingInfoCenter' "$IOS_DIR" "${GREP_PRUNE[@]}" "${SRC_INC[@]}" 2>/dev/null || unused="$unused audio" ;;
        voip) grep -rqE 'PushKit|PKPushRegistry|CallKit|CXProvider' "$IOS_DIR" "${GREP_PRUNE[@]}" "${SRC_INC[@]}" 2>/dev/null || unused="$unused voip" ;;
        fetch) grep -rqE 'BGAppRefreshTask|BGTaskScheduler|BackgroundTasks|setMinimumBackgroundFetchInterval|performFetchWithCompletionHandler' "$IOS_DIR" "${GREP_PRUNE[@]}" "${SRC_INC[@]}" 2>/dev/null || unused="$unused fetch" ;;
        processing) grep -rqE 'BGProcessingTask|BGTaskScheduler|BackgroundTasks' "$IOS_DIR" "${GREP_PRUNE[@]}" "${SRC_INC[@]}" 2>/dev/null || unused="$unused processing" ;;
        bluetooth-central|bluetooth-peripheral) grep -rqE 'CoreBluetooth|CBCentralManager|CBPeripheralManager' "$IOS_DIR" "${GREP_PRUNE[@]}" "${SRC_INC[@]}" 2>/dev/null || unused="$unused $m" ;;
        remote-notification) grep -rqE 'didReceiveRemoteNotification|UNUserNotificationCenter|registerForRemoteNotifications' "$IOS_DIR" "${GREP_PRUNE[@]}" "${SRC_INC[@]}" 2>/dev/null || unused="$unused remote-notification" ;;
      esac
    done <<< "$modes"
    if [[ -n "$unused" ]]; then
      warn "2.5.4 Background modes —$unused declared in UIBackgroundModes but no matching API usage found in Swift; declare only the background modes the app actually uses (2.5.4)" "$INFO_PLIST"
    else
      pass "2.5.4 Background modes — declared modes have matching API usage"
    fi
  fi
fi

# ===================================================================
# §34 — 3.1.5(a) Cryptocurrency wallet / exchange / mining
# ===================================================================
set_rule "crypto-wallet-mining"
if [[ -n "$IOS_DIR" ]]; then
  crypto_sdk=$(grep -rlE 'import Web3|web3swift|Web3Swift|WalletConnect|TrustWalletCore|CoinbaseWalletSDK|SolanaSwift|CryptoMining|coinhive|MoneroMiner' "$IOS_DIR" "${GREP_PRUNE[@]}" "${SRC_INC[@]}" 2>/dev/null | head -1)
  if [[ -n "$crypto_sdk" ]]; then
    warn "3.1.5(a) Cryptocurrency — a crypto wallet/exchange/mining signal was detected (e.g. $(basename "$crypto_sdk")); wallets & exchanges have entity and licensing requirements, and on-device mining is not permitted (3.1.5(a)). Verify eligibility."
  fi
fi

# ===================================================================
# §35 — 4.2.3 Web-wrapper / thin app
# ===================================================================
# A thin WKWebView wrapper around a website is rejected under minimum
# functionality. Heuristic: WKWebView present in a project with very few Swift
# files. WARN (verify) — this is the most false-positive-prone of the batch.
set_rule "webview-wrapper"
if [[ -n "$IOS_DIR" ]]; then
  if grep -rqE 'WKWebView' "$IOS_DIR" "${GREP_PRUNE[@]}" "${SRC_INC[@]}" 2>/dev/null; then
    swift_n=$(find "$IOS_DIR" "${PRUNE[@]}" -name '*.swift' 2>/dev/null | wc -l | tr -d ' ')
    if (( swift_n > 0 && swift_n <= 4 )); then
      warn "4.2.3 Minimum functionality — the app appears to be a WKWebView wrapper with only $swift_n Swift file(s); a thin wrapper around a website is rejected under 4.2.3. Add native value, or verify this is a real app rather than a repackaged site."
    fi
  fi
fi

# ===================================================================
# §36 — 4.2.7 Remote desktop / host-mirroring
# ===================================================================
set_rule "remote-desktop"
if [[ -n "$IOS_DIR" ]]; then
  remote_desktop=$(grep -rlE 'import libvncclient|LibVNC|VNCClient|RDPSession|RDPKit|RemoteDesktopClient|import FreeRDP|JumpDesktop' "$IOS_DIR" "${GREP_PRUNE[@]}" "${SRC_INC[@]}" --include="*.m" 2>/dev/null | head -1)
  if [[ -n "$remote_desktop" ]]; then
    warn "4.2.7 Remote desktop — a remote-desktop/mirroring signal was detected (e.g. $(basename "$remote_desktop")); host-mirroring apps must only show/control the owner's host, display host content (not App Store content), and be free or use IAP (4.2.7). Verify."
  fi
fi

# ===================================================================
# §37 — 4.4.2 Safari extension / content blocker
# ===================================================================
set_rule "safari-extension"
safari_ext=$(grep -rlE 'com\.apple\.Safari\.(content-blocker|web-extension|extension)' --include='Info.plist' "${GREP_PRUNE[@]}" . 2>/dev/null | pick_shallowest)
if [[ -n "$safari_ext" ]]; then
  warn "4.4.2 Safari extension — a Safari content-blocker / web extension was detected ($(basename "$safari_ext")); it must use the extension APIs as intended, do only what it declares, and not include hidden analytics/ads or track without consent (4.4.2). Verify."
fi

# ===================================================================
# §38 — 5.1.1(v) Account Sign-In: account creation without in-app deletion
# ===================================================================
# Apple 5.1.1(v): apps that support account creation must also let users delete
# their account from within the app. Detect account-creation signals, then look
# for an in-app deletion path. Deletion via a web page is missed → WARN, not FAIL.
set_rule "account-no-delete"
if [[ -n "$IOS_DIR" ]]; then
  signup=$(grep -rlE 'createUser|signUp|signup|createAccount|registerUser|registerNewUser|Auth\.auth\(\)\.createUser' "$IOS_DIR" "${GREP_PRUNE[@]}" "${SRC_INC[@]}" 2>/dev/null | head -1)
  if [[ -n "$signup" ]]; then
    if grep -rqiE 'delete.?account|account.?deletion|closeAccount|deleteUser|removeAccount|deleteMyAccount' "$IOS_DIR" "${GREP_PRUNE[@]}" "${SRC_INC[@]}" 2>/dev/null; then
      pass "5.1.1(v) Account deletion — account creation present and an in-app account-deletion path was found"
    else
      warn "5.1.1(v) Account deletion — account creation was detected (e.g. $(basename "$signup")) but no in-app account-deletion path found; apps that support account creation must let users delete their account from within the app (5.1.1(v))"
    fi
  fi
fi

# ===================================================================
# §39 — 5.1.4 Kids audience with third-party ads / analytics
# ===================================================================
# Kids Category apps may not include third-party advertising or analytics and
# must include a parental gate. We fire when the metadata targets a child
# audience AND an ad/analytics SDK is linked. tracking_sdk/analytics_sdk come
# from §3/§19.
set_rule "kids-ads-analytics"
if [[ -d "$META_DIR" && -n "$IOS_DIR" ]]; then
  if grep -rqEiI 'for kids|for children|kids[[:space:]]?app|für kinder|para niños|pour enfants' "$META_DIR" 2>/dev/null; then
    if [[ -n "$tracking_sdk" || -n "$analytics_sdk" ]]; then
      warn "5.1.4 Kids — the metadata targets a child audience and a third-party ads/analytics SDK is linked (e.g. $(basename "${tracking_sdk:-$analytics_sdk}")); Kids Category apps may not include third-party advertising or analytics and must offer a parental gate (5.1.4)"
    fi
  fi
fi

# ===================================================================
# §40 — 5.3.4 Real-money gambling
# ===================================================================
set_rule "realmoney-gambling"
if [[ -d "$META_DIR" ]]; then
  gamble_re='real[ -]?money|gambling|casino|sportsbook|sports[ -]?betting|place[ -].*bets|wager(ing)?|roulette.*real'
  gamble_hits=$(grep -rEniI "$gamble_re" "$META_DIR" 2>/dev/null | grep -v "^Binary file" | head -10)
  if [[ -n "$gamble_hits" ]]; then
    gamble_first="$(printf '%s\n' "$gamble_hits" | head -1)"   # "path:line:match"
    gamble_file="${gamble_first%%:*}"
    gamble_rest="${gamble_first#*:}"; gamble_line="${gamble_rest%%:*}"
    warn "5.3.4 Gambling — real-money gaming language in metadata; real-money gambling/lotteries need the proper licenses, must be geo-restricted to permitted regions, and must be free on the App Store (5.3.4):" "$gamble_file" "$gamble_line"
    detail "$gamble_hits"
  fi
fi

# ===================================================================
# §41 — 5.5 Mobile Device Management
# ===================================================================
set_rule "mdm"
if [[ -n "$IOS_DIR" ]]; then
  mdm_sig=$(grep -rlE 'import DeviceManagement|MDMConfiguration|ManagedAppConfiguration|com\.apple\.mdm' "$IOS_DIR" "${GREP_PRUNE[@]}" "${SRC_INC[@]}" 2>/dev/null | head -1)
  [[ -z "$mdm_sig" ]] && mdm_sig=$(grep -rlE 'com\.apple\.configuration\.managed' --include='*.plist' "${GREP_PRUNE[@]}" . 2>/dev/null | pick_shallowest)
  if [[ -n "$mdm_sig" ]]; then
    warn "5.5 MDM — a Mobile Device Management signal was detected (e.g. $(basename "$mdm_sig")); MDM apps require a commercial enterprise/education entity, may request the MDM capability only for that purpose, and must not sell or use the data for other ends (5.5). Verify eligibility."
  fi
fi

echo "---END-OF-SCAN---"
if [[ "$FORMAT" == text && "${_SUPPRESSED_COUNT:-0}" -gt 0 ]]; then
  printf '(%s finding(s) suppressed via .precheck-ignore)\n' "$_SUPPRESSED_COUNT"
fi
if [[ "$FORMAT" == json ]]; then exec 1>&4 4>&-; render_json;
elif [[ "$FORMAT" == sarif ]]; then exec 1>&4 4>&-; render_sarif; fi
