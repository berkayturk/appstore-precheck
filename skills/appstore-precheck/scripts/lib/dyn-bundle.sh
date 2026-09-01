#!/usr/bin/env bash
# lib/dyn-bundle.sh — read the INSTALLED bundle (what `xcrun simctl get_app_container
# <udid> <bundle-id> app` returns) and report what it establishes, executing nothing:
#   dyn-shipped-bundle[:KEY]  installed Info.plist vs the repo Info.plist; one line per
#                             NS*UsageDescription key the installed plist declares
#                             (a complete per-key test of the static purpose-string
#                             claim), one FINDING per key the repo declares and the
#                             installed plist lacks, and a keyless drift summary.
#   dyn-shipped-sdk           DTXcode / DTSDKName: the toolchain that built THIS bundle
#                             (what ITMS-90725 reads), versus the LastUpgradeCheck proxy.
#   dyn-shipped-links         otool -L on the executable: a /System/Library/PrivateFrameworks
#                             link is decisive for 2.5.1; absence is only partial.
# The build configuration is NOT read from the plist: it comes from the .app's parent
# directory name (app-discover.sh), because a plist cannot tell Debug from Release.
# Sourced by dynamic-run.sh. Bash 3.2. plutil on macOS; XML fallback for CI fixtures.

# --- plist readers ------------------------------------------------------------------
# plutil on macOS (a real .app carries BINARY plists); an XML fallback for CI fixtures
# and for a Mac without Xcode tools. DYN_NO_PLUTIL=1 forces the fallback (tests use it
# to run the ubuntu path on macOS). The fallback first puts every tag on its own line
# (`sed 's/>/>\n/g'`), so one-line `<key>K</key><string>v</string>` pairs and
# pretty-printed plists parse identically.
_dyn_have_plutil() { [[ -z "${DYN_NO_PLUTIL:-}" ]] && command -v plutil >/dev/null 2>&1; }
_dyn_plist_tokens() { sed 's/>/>\
/g' "$1" 2>/dev/null | sed -E 's/^[[:space:]]+//' | grep -v '^$'; }

# dyn_plist_keys <plist> -> top-level keys, one per line, sorted.
dyn_plist_keys() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  if _dyn_have_plutil && plutil -convert json -o - "$f" >/dev/null 2>&1; then
    plutil -convert json -o - "$f" 2>/dev/null | jq -r 'keys[]' 2>/dev/null | sort
  else
    _dyn_plist_tokens "$f" | awk '
      /<dict>/   { depth++; next }
      /<\/dict>/ { depth--; next }
      /<array>/  { arr++; next }
      /<\/array>/ { arr--; next }
      depth == 1 && arr == 0 && /<\/key>/ { sub(/<\/key>.*/, ""); print }
    ' | sort
  fi
}

# dyn_plist_string <plist> <key> -> string value or "" (empty for a non-string or a missing key).
dyn_plist_string() {
  local f="$1" k="$2" v=""
  [[ -f "$f" ]] || { printf ''; return; }
  if _dyn_have_plutil; then v="$(plutil -extract "$k" raw -o - "$f" 2>/dev/null)" || v=""; fi
  if [[ -z "$v" ]]; then
    v="$(_dyn_plist_tokens "$f" | awk -v K="$k</key>" '
      state == 2 { sub(/<\/string>.*/, ""); print; exit }
      state == 1 { if ($0 ~ /^<string>/) state = 2; else exit; next }
      $0 == K { state = 1 }
    ')"
  fi
  printf '%s' "$v"
}

# dyn_plist_array_strings <plist> <key> -> the string members of an array value, one per line.
dyn_plist_array_strings() {
  local f="$1" k="$2"
  [[ -f "$f" ]] || return 0
  if _dyn_have_plutil && plutil -extract "$k" json -o - "$f" >/dev/null 2>&1; then
    plutil -extract "$k" json -o - "$f" 2>/dev/null | jq -r '.[]? | strings' 2>/dev/null
  else
    _dyn_plist_tokens "$f" | awk -v K="$k</key>" '
      on && /<\/array>/ { exit }
      on && /<\/string>/ { sub(/<\/string>.*/, ""); print; next }
      $0 == K { on = 1 }
    '
  fi
}

# dyn_plist_array_has_int <plist> <key> <int> -> 0 when the array value contains the integer.
dyn_plist_array_has_int() {
  local f="$1" k="$2" want="$3"
  [[ -f "$f" ]] || return 1
  if _dyn_have_plutil && plutil -extract "$k" json -o - "$f" >/dev/null 2>&1; then
    plutil -extract "$k" json -o - "$f" 2>/dev/null | jq -e --argjson w "$want" 'index($w) != null' >/dev/null 2>&1
  else
    _dyn_plist_tokens "$f" | awk -v K="$k</key>" -v W="$want</integer>" '
      on && /<\/array>/ { exit }
      on && $0 == W { found = 1; exit }
      $0 == K { on = 1 }
      END { exit found ? 0 : 1 }
    '
  fi
}

# dyn_bundle_plist_lines <installed-plist> <repo-plist|""> -> transcript lines.
dyn_bundle_plist_lines() {
  local inst="$1" repo="${2:-}" k v g only_repo only_inst n_inst n_diff
  [[ -f "$inst" ]] || { echo "DYNAMIC-SKIP: 5.1.1 [dyn-shipped-bundle] — installed bundle has no readable Info.plist"; return 0; }
  # One complete per-key observation for every purpose string the installed plist declares.
  while IFS= read -r k; do
    case "$k" in NS*UsageDescription) ;; *) continue ;; esac
    v="$(dyn_plist_string "$inst" "$k")"
    g="5.1.1"; [[ "$k" == NSUserTrackingUsageDescription ]] && g="5.1.2"
    if [[ -n "$v" ]]; then
      printf 'DYNAMIC-PASS: %s [dyn-shipped-bundle:%s] — installed Info.plist declares %s ("%s")\n' "$g" "$k" "$k" "$(printf '%s' "$v" | cut -c1-80)"
    else
      printf 'DYNAMIC-FINDING: %s [dyn-shipped-bundle:%s] — installed Info.plist has %s but it is EMPTY (the validator treats an empty purpose string as missing)\n' "$g" "$k" "$k"
    fi
  done < <(dyn_plist_keys "$inst")
  n_inst="$(dyn_plist_keys "$inst" | grep -c .)"
  if [[ -n "$repo" && -f "$repo" ]]; then
    only_repo="$(comm -23 <(dyn_plist_keys "$repo") <(dyn_plist_keys "$inst"))"
    only_inst="$(comm -13 <(dyn_plist_keys "$repo") <(dyn_plist_keys "$inst") | grep -vE '^(DT|BuildMachine|CFBundleSupportedPlatforms|MinimumOSVersion|UIDeviceFamily|CFBundleInfoDictionaryVersion|CFBundleNumericVersion|LSRequiresIPhoneOS|UIRequiredDeviceCapabilities|CFBundleDevelopmentRegion|CFBundlePackageType|CFBundleShortVersionString|CFBundleVersion|CFBundleName|CFBundleDisplayName|CFBundleExecutable|CFBundleIdentifier|UILaunchScreen|UISupportedInterfaceOrientations)' || true)"
    while IFS= read -r k; do
      [[ -n "$k" ]] || continue
      case "$k" in NS*UsageDescription)
        g="5.1.1"; [[ "$k" == NSUserTrackingUsageDescription ]] && g="5.1.2"
        printf 'DYNAMIC-FINDING: %s [dyn-shipped-bundle:%s] — %s is in the repo Info.plist but NOT in the installed bundle (a build setting or target-specific plist dropped it)\n' "$g" "$k" "$k" ;;
      esac
    done <<< "$only_repo"
    n_diff="$(printf '%s\n%s\n' "$only_repo" "$only_inst" | grep -c .)"
    printf 'DYNAMIC-PASS: 5.1.1 [dyn-shipped-bundle] — installed Info.plist has %s keys; %s key(s) differ from the repo Info.plist%s%s\n' \
      "$n_inst" "$n_diff" \
      "$([[ -n "$only_repo" ]] && printf ' (only in repo: %s)' "$(printf '%s' "$only_repo" | tr '\n' ' ' | sed 's/ $//')")" \
      "$([[ -n "$only_inst" ]] && printf ' (only in bundle: %s)' "$(printf '%s' "$only_inst" | tr '\n' ' ' | sed 's/ $//')")"
  else
    printf 'DYNAMIC-PASS: 5.1.1 [dyn-shipped-bundle] — installed Info.plist has %s keys (no repo Info.plist to compare against)\n' "$n_inst"
  fi
}

# dyn_bundle_privacy_note <installed-app-dir> -> short note on PrivacyInfo.xcprivacy presence.
dyn_bundle_privacy_note() {
  local app="$1"
  if [[ -f "$app/PrivacyInfo.xcprivacy" ]]; then echo "PrivacyInfo.xcprivacy present in the bundle"
  else echo "no PrivacyInfo.xcprivacy at the bundle root"; fi
}

# dyn_bundle_sdk_line <installed-plist> -> transcript line for dyn-shipped-sdk.
# Floor: iOS 26 SDK == DTXcode >= 2600 (ITMS-90725 since 2026-04-28).
dyn_bundle_sdk_line() {
  local inst="$1" xc sdk xb
  xc="$(dyn_plist_string "$inst" DTXcode)"; sdk="$(dyn_plist_string "$inst" DTSDKName)"; xb="$(dyn_plist_string "$inst" DTXcodeBuild)"
  if [[ -z "$xc" || ! "$xc" =~ ^[0-9]+$ ]]; then
    echo "DYNAMIC-SKIP: 2.1 [dyn-shipped-sdk] — installed Info.plist carries no DTXcode; the build toolchain cannot be read from this bundle"
    return 0
  fi
  if (( 10#$xc >= 2600 )); then
    printf 'DYNAMIC-PASS: 2.1 [dyn-shipped-sdk] — installed Info.plist: DTXcode=%s%s%s (built with the iOS 26 SDK or later)\n' "$xc" "${xb:+ DTXcodeBuild=$xb}" "${sdk:+ DTSDKName=$sdk}"
  else
    printf 'DYNAMIC-FINDING: 2.1 [dyn-shipped-sdk] — installed Info.plist: DTXcode=%s%s (pre-26 toolchain; App Store uploads have required the iOS 26 SDK since April 2026)\n' "$xc" "${sdk:+ DTSDKName=$sdk}"
  fi
}

# dyn_bundle_links_line <installed-app-dir> -> transcript line for dyn-shipped-links.
# Xcode 16+ Debug builds put the app's code in <Executable>.debug.dylib and leave a thin
# stub as the main executable, so the stub links almost nothing; the dylib is read too
# when present, and the line says which binaries were read.
dyn_bundle_links_line() {
  local app="$1" exe out n priv read_list dbg
  exe="$(dyn_plist_string "$app/Info.plist" CFBundleExecutable)"
  [[ -n "$exe" && -f "$app/$exe" ]] || { echo "DYNAMIC-SKIP: 2.5.1 [dyn-shipped-links] — executable not found in the installed bundle"; return 0; }
  command -v otool >/dev/null 2>&1 || { echo "DYNAMIC-SKIP: 2.5.1 [dyn-shipped-links] — otool not available; linked frameworks could not be read"; return 0; }
  out="$(otool -L "$app/$exe" 2>/dev/null)" || { echo "DYNAMIC-SKIP: 2.5.1 [dyn-shipped-links] — otool -L failed on the installed executable"; return 0; }
  read_list="$exe"
  dbg="$app/$exe.debug.dylib"
  if [[ -f "$dbg" ]]; then
    out="$out"$'\n'"$(otool -L "$dbg" 2>/dev/null)"; read_list="$exe + $exe.debug.dylib (Debug build: the code lives in the dylib)"
  fi
  n="$(printf '%s\n' "$out" | grep -c '^[[:space:]]')"
  priv="$(printf '%s\n' "$out" | grep -E 'PrivateFrameworks/' | sed -E 's/^[[:space:]]+//; s/ \(.*//' | sort -u | head -3)"
  if [[ -n "$priv" ]]; then
    printf 'DYNAMIC-FINDING: 2.5.1 [dyn-shipped-links] — otool -L %s: links a private framework: %s\n' "$read_list" "$(printf '%s' "$priv" | tr '\n' ' ' | sed 's/ $//')"
  else
    printf 'DYNAMIC-PASS: 2.5.1 [dyn-shipped-links] — otool -L %s: %s linked libraries, none under /System/Library/PrivateFrameworks (linkage only; private selectors are not visible here)\n' "$read_list" "$n"
  fi
}

# dyn_config_from_dir <app-path> -> debug | release | unknown, from the PARENT DIRECTORY
# NAME only (Debug-iphonesimulator / Release-iphonesimulator). Never from the plist: a
# plist cannot tell the configurations apart, and this value gates the qualifier.
dyn_config_from_dir() {
  case "$(basename "$(dirname "$1")")" in
    Debug-iphonesimulator)   echo debug ;;
    Release-iphonesimulator) echo release ;;
    *)                       echo unknown ;;
  esac
}

# dyn_plist_supports_ipad <plist> -> 0 when UIDeviceFamily contains 2.
dyn_plist_supports_ipad() { dyn_plist_array_has_int "$1" UIDeviceFamily 2; }
