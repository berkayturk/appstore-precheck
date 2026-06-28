#!/usr/bin/env bash
# appstore-precheck/scripts/scan.sh
# Static, read-only pre-submission scanner for iOS App Store rejection vectors.
# Convention-over-configuration: auto-detects a standard fastlane + Xcode layout,
# and honors an optional `.appstore-precheck.json` at the repo root for overrides.
#
# Output: three line prefixes on stdout — FAIL: / WARN: / PASS: <topic> — <detail> [location]
# Exit code: always 0. The skill counts FAIL/WARN lines to reach a GREEN/YELLOW/RED verdict.

set -u

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || ROOT="$(pwd)"
cd "$ROOT" || { echo "FAIL: repo-root — could not enter repository root"; exit 0; }

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

fail() { echo "FAIL: $1"; }
warn() { echo "WARN: $1"; }
pass() { echo "PASS: $1"; }

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
detect_ios_dir() {
  local d; d=$(cfg '.iosSourceDir')
  [[ -n "$d" ]] && { echo "$d"; return; }
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
  [[ -n "$best" ]] && { echo "$best"; return; }
  echo "$alt"
}

IOS_DIR="$(detect_ios_dir)"
META_DIR="$(cfg '.metadataDir')";      [[ -z "$META_DIR" ]]   && META_DIR="$(detect_first -type d -name metadata -path '*fastlane*')"
SCREEN_DIR="$(cfg '.screenshotsDir')"; [[ -z "$SCREEN_DIR" ]] && SCREEN_DIR="$(detect_first -type d -name screenshots -path '*fastlane*')"
XCSTRINGS="$(cfg '.xcstringsPath')";   [[ -z "$XCSTRINGS" ]]  && XCSTRINGS="$(detect_first -name 'Localizable.xcstrings')"
[[ -z "$XCSTRINGS" ]] && XCSTRINGS="$(detect_first -name '*.xcstrings')"
PRIVACY_FILE="$(detect_first -name 'PrivacyInfo.xcprivacy')"
INFO_PLIST="${IOS_DIR%/}/Info.plist"
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
if [[ -f "$CONFIG" ]] && have_jq && [[ "$(jq -r '.locales | type' "$CONFIG" 2>/dev/null)" == "array" ]]; then
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

echo "PASS: layout — ios='${IOS_DIR:-?}' metadata='${META_DIR:-?}' xcstrings='${XCSTRINGS:-?}' locales=${#LOCALES[@]}"

# ===================================================================
# §1 — 5.1.1(v) Privacy Manifest Required Reason API parity
# ===================================================================
check_required_reason_api() {
  local cat="$1" pattern="$2" hits declared
  hits=$(grep -rEl "$pattern" "$IOS_DIR" --include="*.swift" 2>/dev/null | head -3)
  declared=$(grep -c "NSPrivacyAccessedAPICategory${cat}" "$PRIVACY_FILE" 2>/dev/null)
  if [[ -n "$hits" && "${declared:-0}" -eq 0 ]]; then
    fail "5.1.1(v) Required Reason API — '$cat' used in code (e.g. $(echo "$hits" | head -1)) but not declared in PrivacyInfo.xcprivacy"
  elif [[ -z "$hits" && "${declared:-0}" -gt 0 ]]; then
    warn "5.1.1(v) PrivacyInfo — '$cat' declared but no code usage grepped (may be a false positive, verify manually)"
  elif [[ -n "$hits" && "${declared:-0}" -gt 0 ]]; then
    pass "5.1.1(v) Required Reason API — '$cat' parity OK"
  fi
}
if [[ -z "$IOS_DIR" ]]; then
  warn "layout — could not auto-detect iOS source dir; set .iosSourceDir in $CONFIG"
elif [[ -z "$PRIVACY_FILE" ]]; then
  fail "5.1.1(v) PrivacyInfo.xcprivacy not found (required since May 2024 for apps using Required Reason APIs)"
else
  check_required_reason_api "UserDefaults"   'UserDefaults|@AppStorage'
  check_required_reason_api "FileTimestamp"  'attributesOfItem|creationDate|modificationDate|\.fileCreationDate|\.fileModificationDate'
  check_required_reason_api "SystemBootTime" 'systemUptime|mach_absolute_time|CACurrentMediaTime\(\)'
  check_required_reason_api "DiskSpace"      'volumeAvailableCapacity|volumeTotalCapacity'
  check_required_reason_api "ActiveKeyboard" 'activeInputModes|UITextInputMode'
fi

# ===================================================================
# §2 — 5.1.1 NSUsageDescription cross-check (Info.plist)
# ===================================================================
if [[ ! -f "$INFO_PLIST" ]]; then
  [[ -n "$IOS_DIR" ]] && warn "5.1.1 Info.plist not found at $INFO_PLIST (modern Xcode may auto-generate it; verify purpose strings in build settings)"
else
  awk '/NS[A-Za-z]+UsageDescription/{key=$0; getline; if($0 ~ /<string>[[:space:]]*<\/string>/) print "EMPTY:"key}' "$INFO_PLIST" | while read -r line; do
    [[ -n "$line" ]] && fail "5.1.1 Purpose String — $line (empty usage description is rejected by App Review)"
  done
  for fw in \
    "FamilyControls|ManagedSettings|DeviceActivity:NSFamilyControlsUsageDescription" \
    "CoreLocation:NSLocationWhenInUseUsageDescription" \
    "AVFoundation:NSCameraUsageDescription|NSMicrophoneUsageDescription" \
    "Photos:NSPhotoLibraryUsageDescription" \
    "Contacts:NSContactsUsageDescription" \
    "HealthKit:NSHealthShareUsageDescription"; do
    framework="${fw%%:*}"; needed_key="${fw##*:}"
    if grep -rqE "import ($framework)|($framework)\." "$IOS_DIR" --include="*.swift" 2>/dev/null; then
      if ! grep -qE "$needed_key" "$INFO_PLIST" 2>/dev/null; then
        fail "5.1.1 framework '${framework%%|*}' imported but Info.plist is missing '${needed_key%%|*}'"
      fi
    fi
  done
fi

# ===================================================================
# §3 — 5.1.2 ATT (App Tracking Transparency)
# ===================================================================
# Ad / attribution / IDFA SDK signal, shared with §16. The reverse of §3: §3 fires
# when the ATT framework IS imported; §16 fires when a tracking SDK is present but
# the ATT prompt is NOT. Computed once here so the two checks never contradict.
tracking_sdk=$(grep -rlE 'advertisingIdentifier|ASIdentifierManager|GADMobileAds|GoogleMobileAds|AppLovinSDK|ALSdk|AppsFlyerLib|import Adjust|Adjust\.|FBAudienceNetwork|BranchSDK|IronSource' "$IOS_DIR" --include="*.swift" 2>/dev/null | head -1)
att_used=$(grep -rlE 'AppTrackingTransparency|ATTrackingManager' "$IOS_DIR" --include="*.swift" 2>/dev/null | head -1)
if [[ -n "$att_used" ]]; then
  if grep -q "NSUserTrackingUsageDescription" "$INFO_PLIST" 2>/dev/null; then
    pass "5.1.2 ATT — used + NSUserTrackingUsageDescription present"
  else
    fail "5.1.2 ATT framework imported but NSUserTrackingUsageDescription missing in Info.plist ($att_used)"
  fi
elif [[ -z "$tracking_sdk" ]]; then
  pass "5.1.2 ATT — not used (no tracking)"
fi
# If a tracking SDK is present without the ATT framework, §3 stays silent and §16
# raises the WARN, so we never print a misleading "no tracking" PASS.

# ===================================================================
# §4 — 2.3.10 Other-platform / competitor mentions in metadata
# ===================================================================
if [[ -d "$META_DIR" ]]; then
  banned_re='Android|Google[[:space:]]?Play|Play[[:space:]]?Store|Windows[[:space:]]?Phone|Samsung Galaxy|Huawei AppGallery|F-Droid'
  hits=$(grep -rEnI "$banned_re" "$META_DIR" 2>/dev/null | grep -v "^Binary file" | head -30)
  if [[ -n "$hits" ]]; then
    fail "2.3.10 Other-platform mention — banned reference in metadata:"
    echo "$hits" | sed 's/^/      /'
  else
    pass "2.3.10 Other-platform mentions — metadata clean"
  fi
fi

# ===================================================================
# §5 — 2.3.1 Metadata character limits (Unicode codepoints, like ASC)
# ===================================================================
check_len() {
  local file="$1" limit="$2" label="$3" len
  [[ -f "$file" ]] || return
  if command -v python3 >/dev/null 2>&1; then
    len=$(python3 -c "import sys; print(len(open(sys.argv[1], encoding='utf-8').read().rstrip('\n')))" "$file" 2>/dev/null)
  else
    len=$(wc -m < "$file" | tr -d ' ')
  fi
  [[ -z "$len" ]] && return
  (( len > limit )) && fail "2.3.1 $label — $file ${len} chars (limit ${limit})"
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
if (( ${#LOCALES[@]} > 0 )); then
  expected_files=(name.txt subtitle.txt description.txt keywords.txt)
  for loc in "${LOCALES[@]+"${LOCALES[@]}"}"; do
    d="$META_DIR/$loc"
    if [[ ! -d "$d" ]]; then fail "2.3.7 Locale missing — $d does not exist"; continue; fi
    for f in "${expected_files[@]}"; do
      [[ -s "$d/$f" ]] || fail "2.3.7 Metadata missing — $d/$f is empty or absent"
    done
  done
  pass "2.3.7 Localized metadata — checked ${#LOCALES[@]} locales"
fi

# ===================================================================
# §7 — 2.3.3 Screenshots per locale
# ===================================================================
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
  warn "2.3.3 Screenshots — screenshots dir not found (set .screenshotsDir if you manage them in-repo)"
fi

# ===================================================================
# In-app purchase gate — only run 3.1.2 checks if IAP signals exist
# ===================================================================
iap_detected=""
grep -rqE 'import StoreKit|RevenueCat|Purchases\.|Product\(for:|AppStore\.|SKProduct|StoreKit2' "$IOS_DIR" --include="*.swift" 2>/dev/null && iap_detected=1
[[ -n "$SUB_VIEW" ]] && iap_detected=1

if [[ -z "$iap_detected" ]]; then
  pass "3.1.2 IAP — no in-app purchase / subscription signals detected, skipping paywall checks"
else
  # ---- §8 3.1.2 Trial disclosure -------------------------------------------------
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
  if (( ${#PAYWALL_FILES[@]} > 0 )); then
    if grep -qE 'restore|restorePurchases' "${PAYWALL_FILES[@]}"; then
      pass "3.1.2 Restore Purchases — present in $(basename "$SUB_VIEW")"
    else
      fail "3.1.2 Restore Purchases — not found in the paywall views (e.g. $SUB_VIEW) (required by Apple)"
    fi
    if grep -qE 'terms_of_use|termsURL|termsOfUse|subscription_terms|EULA|/terms' "${PAYWALL_FILES[@]}"; then
      pass "3.1.2 Terms of Use (EULA) link — present"
    else
      fail "3.1.2 Terms of Use (EULA) link — not found in the paywall views (e.g. $SUB_VIEW)"
    fi
    if grep -qE 'privacy_policy|privacyURL|privacyPolicy|subscription_privacy|/privacy' "${PAYWALL_FILES[@]}"; then
      pass "3.1.2 Privacy Policy link — present"
    else
      fail "3.1.2 Privacy Policy link — not found in the paywall views (e.g. $SUB_VIEW)"
    fi
  else
    warn "3.1.2 IAP detected but no paywall/subscription view found — set .paywallGlobs so required-link checks can run"
  fi
fi

# ===================================================================
# §11 — 2.5.1 Private / banned API
# ===================================================================
banned_api='UIWebView|setSelectionIndicatorImage|_UIBackdropView|NSURLConnection[^a-zA-Z]|UIAlertView[^Q]|UIActionSheet[^Q]'
banned_hits=$(grep -rEnI "$banned_api" "$IOS_DIR" --include="*.swift" --include="*.m" --include="*.h" 2>/dev/null | head -5)
if [[ -n "$banned_hits" ]]; then
  fail "2.5.1 Private/Deprecated API:"
  echo "$banned_hits" | sed 's/^/      /'
else
  pass "2.5.1 Private API — clean"
fi

# ===================================================================
# §12 — 4.0 Minimum functionality — navigation hubs
# ===================================================================
tab_count=$(grep -rcE 'TabView|NavigationStack|NavigationSplitView' "$IOS_DIR" --include="*.swift" 2>/dev/null | awk -F: '{sum+=$2} END {print sum+0}')
if (( tab_count < 1 )); then
  warn "4.0 Minimum functionality — no TabView/NavigationStack found (heuristic, may be a false positive)"
else
  pass "4.0 Minimum functionality — $tab_count navigation hub(s) found"
fi

# ===================================================================
# §13 — 5.1.5 Screen Time / sensitive-API justification (optional, opt-in)
# ===================================================================
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
if [[ -n "$IOS_DIR" ]]; then
  social_login=$(grep -rlE 'GIDSignIn|import GoogleSignIn|FBSDKLoginKit|FBSDKLoginManager|FacebookLogin|import Auth0|LineSDK|VKSdkAuthorization' "$IOS_DIR" --include='*.swift' 2>/dev/null | head -1)
  if [[ -n "$social_login" ]]; then
    if grep -rqE 'ASAuthorizationAppleID|SignInWithAppleButton|AppleIDProvider' "$IOS_DIR" --include='*.swift' 2>/dev/null; then
      pass "4.8 Sign in with Apple — present alongside third-party login"
    else
      warn "4.8 Sign in with Apple — third-party social login detected (e.g. $(basename "$social_login")) but no Sign in with Apple found; Apple requires an equivalent option (4.8). Some account systems are exempt — verify."
    fi
  fi
fi

# ===================================================================
# §15 — 3.1.1(a) External purchase link (StoreKit External Purchase)
# ===================================================================
ext_purchase=""
grep -rqE 'ExternalPurchase|ExternalPurchaseLink|ExternalPurchaseCustomLink' "${IOS_DIR:-.}" --include='*.swift' 2>/dev/null && ext_purchase=1
grep -rqE 'external-purchase' "${IOS_DIR:-.}" --include='*.entitlements' 2>/dev/null && ext_purchase=1
if [[ -n "$ext_purchase" ]]; then
  warn "3.1.1(a) External purchase link detected — ensure the External Purchase entitlement, eligible storefronts, the required disclosure sheet, and App Store Connect reporting are in place (3.1.1(a))."
fi

# ===================================================================
# §16 — 5.1.2 Tracking SDK / IDFA without ATT (the reverse of §3)
# ===================================================================
# §3 catches "ATT framework imported but no usage string". This catches the more
# common rejection: shipping an ad / attribution SDK (or touching the IDFA) without
# ever presenting the ATT prompt. `tracking_sdk` and `att_used` are computed in §3.
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
if [[ -f "$INFO_PLIST" ]]; then
  if grep -q "ITSAppUsesNonExemptEncryption" "$INFO_PLIST" 2>/dev/null; then
    pass "export-compliance — ITSAppUsesNonExemptEncryption set in Info.plist"
  else
    warn "export-compliance — Info.plist has no ITSAppUsesNonExemptEncryption; set it (true/false) to skip the App Store Connect encryption-export prompt every submission"
  fi
fi

# ===================================================================
# §18 — Support / Privacy URL in fastlane metadata
# ===================================================================
# fastlane deliver stores the localized review URLs per locale as
# support_url.txt / privacy_url.txt / marketing_url.txt. Apple requires a working
# support URL, and a privacy policy URL for apps with accounts or IAP. Flag when
# they are absent across every locale, or contain an obvious placeholder.
if [[ -d "$META_DIR" ]]; then
  support_found="" privacy_found=""
  for loc in "${LOCALES[@]+"${LOCALES[@]}"}"; do
    [[ -s "$META_DIR/$loc/support_url.txt" ]] && support_found=1
    [[ -s "$META_DIR/$loc/privacy_url.txt" ]] && privacy_found=1
  done
  if (( ${#LOCALES[@]} > 0 )); then
    [[ -z "$support_found" ]] && warn "2.3 Support URL — no non-empty support_url.txt in any locale under fastlane metadata; Apple requires a working support URL"
    [[ -z "$privacy_found" ]] && warn "2.3 Privacy URL — no non-empty privacy_url.txt in any locale under fastlane metadata; required for apps with accounts or in-app purchases"
  fi
  url_ph=$(grep -rEnI 'example\.com|localhost|\bTODO\b|changeme' "$META_DIR" --include='*_url.txt' 2>/dev/null | grep -v "^Binary file" | head -10)
  if [[ -n "$url_ph" ]]; then
    warn "2.3 Metadata URL — placeholder URL in fastlane metadata (replace before submitting):"
    echo "$url_ph" | sed 's/^/      /'
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
analytics_sdk=$(grep -rlE 'FirebaseAnalytics|import Firebase|Amplitude|Mixpanel|import Sentry|Segment|Bugsnag|AppCenterAnalytics|Datadog' "$IOS_DIR" --include="*.swift" 2>/dev/null | head -1)
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
    warn "5.1.1 Privacy manifest — analytics SDK detected (e.g. $(basename "$analytics_sdk")) but PrivacyInfo declares no collected data types or tracking domains; verify your privacy manifest and App Privacy nutrition labels"
  fi
fi

# ===================================================================
# §20 — Placeholder / dummy content in store metadata
# ===================================================================
# Lorem ipsum, TODO/FIXME, example URLs, or "insert X here" left in the store copy
# get rejected under 2.1 and look unfinished. Conservative, specific patterns to
# avoid flagging legitimate words. Overlaps the Phase 2 precheck "No placeholder
# text" rule, but this one is local and runs before any network call.
if [[ -d "$META_DIR" ]]; then
  ph_re='lorem ipsum|Lorem ipsum|\bTODO\b|\bFIXME\b|example\.com|placeholder|insert .* here|changeme'
  ph_hits=$(grep -rEnI "$ph_re" "$META_DIR" 2>/dev/null | grep -v "^Binary file" | head -20)
  if [[ -n "$ph_hits" ]]; then
    warn "2.1 Metadata content — placeholder/dummy text in store metadata (looks unfinished; rejected under 2.1):"
    echo "$ph_hits" | sed 's/^/      /'
  fi
fi

echo "---END-OF-SCAN---"
