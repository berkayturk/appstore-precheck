#!/usr/bin/env bash
# project-model.sh — resolve the primary app target's source dir + Info.plist from
# an Xcode project model (.pbxproj), authoritatively and dependency-free.
# Sourced by scan.sh. Pure bash + awk. READ-ONLY. Bash 3.2 compatible.

# pm_app_targets <pbxproj> -> names of targets whose productType is the application type.
# .pbxproj PBXNativeTarget blocks list `name` before `productType`; the block closes
# with a bare `};`. Nested lists close with `)`, never `};`, so `};` reliably ends a block.
pm_app_targets() {
  awk '
    /isa = PBXNativeTarget;/ { in_t=1; name=""; pt=""; next }
    in_t && /^[[:space:]]*name = / {
      l=$0; sub(/^[[:space:]]*name = /,"",l); sub(/;[[:space:]]*$/,"",l); gsub(/^"|"$/,"",l); name=l
    }
    in_t && /^[[:space:]]*productType = / {
      l=$0; sub(/^[[:space:]]*productType = /,"",l); sub(/;[[:space:]]*$/,"",l); gsub(/^"|"$/,"",l); pt=l
    }
    in_t && /^[[:space:]]*};[[:space:]]*$/ {
      if (pt == "com.apple.product-type.application" && name != "") print name
      in_t=0
    }
  ' "$1"
}

# pm_infoplist_files <pbxproj> -> every INFOPLIST_FILE value, unquoted, sorted, deduped.
pm_infoplist_files() {
  awk '/^[[:space:]]*INFOPLIST_FILE = /{
    l=$0; sub(/^[[:space:]]*INFOPLIST_FILE = /,"",l); sub(/;[[:space:]]*$/,"",l); gsub(/^"|"$/,"",l); print l
  }' "$1" | sort -u
}

# Vendored dirs whose .xcodeproj must never win detection.
PM_PRUNE_DIRS='node_modules|Pods|Carthage|\.build|DerivedData|\.git'

# pm_find_pbxproj <root> -> shallowest project.pbxproj under an *.xcodeproj (pruned), or "".
pm_find_pbxproj() {
  local root="${1:-.}"
  find "$root" -name 'project.pbxproj' -path '*.xcodeproj/*' 2>/dev/null \
    | grep -Ev "/($PM_PRUNE_DIRS)/" \
    | awk '{ print gsub(/\//,"/"), $0 }' | sort -n | head -1 | cut -d' ' -f2-
}

# pm_resolve <root> -> "DIR<TAB>PLIST" (ROOT-relative; PLIST may be empty) for the
# primary app target, or non-zero with no output.
pm_resolve() {
  local root="${1:-.}" pbx rel projdir apps plists app plist dir n
  local best="" best_plist="" best_n=-1
  # Normalize a trailing slash so the ROOT-relative strip below reliably matches
  # (root="/" strips to "" and must stay "/"; root="." is untouched).
  root="${root%/}"; [[ -z "$root" ]] && root="/"
  pbx="$(pm_find_pbxproj "$root")"; [[ -z "$pbx" ]] && return 1
  # ROOT-relative dir that contains the .xcodeproj (SRCROOT). INFOPLIST_FILE paths
  # and the app source dir are relative to this.
  rel="${pbx#"$root"/}"                 # e.g. ios/App.xcodeproj/project.pbxproj
  projdir="$(dirname "$(dirname "$rel")")"; projdir="${projdir#./}"
  [[ "$projdir" == "." ]] && projdir=""
  apps="$(pm_app_targets "$pbx")"; [[ -z "$apps" ]] && return 1
  plists="$(pm_infoplist_files "$pbx")"
  while IFS= read -r app; do
    [[ -z "$app" ]] && continue
    # A declared plist whose leading path component equals the app target name.
    plist="$(printf '%s\n' "$plists" | awk -v a="$app" -F/ '$1==a{print; exit}')"
    if [[ -n "$plist" ]]; then
      dir="$(dirname "$plist")"
    else
      # GENERATE_INFOPLIST_FILE: no app plist. Use the dir named after the target.
      dir="$(cd "$root${projdir:+/$projdir}" 2>/dev/null && \
             find . -type d -name "$app" 2>/dev/null | sed 's#^\./##' \
             | awk '{print length, $0}' | sort -n | head -1 | cut -d' ' -f2-)"
      [[ -z "$dir" ]] && continue
    fi
    n="$(cd "$root${projdir:+/$projdir}" 2>/dev/null && \
         find "$dir" -name '*.swift' 2>/dev/null | wc -l | tr -d ' ')"
    if (( n > best_n )); then
      best_n=$n; best="$dir"; best_plist="$plist"
    fi
  done <<< "$apps"
  [[ -z "$best" ]] && return 1
  # Prefix the projdir so paths are ROOT-relative.
  local out_dir="${projdir:+$projdir/}$best"
  local out_plist=""
  [[ -n "$best_plist" ]] && out_plist="${projdir:+$projdir/}$best_plist"
  printf '%s\t%s\n' "$out_dir" "$out_plist"
}
