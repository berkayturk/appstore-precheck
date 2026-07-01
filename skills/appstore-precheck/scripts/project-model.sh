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

# pm_find_pbxprojs <root> -> all project.pbxproj under *.xcodeproj (pruned), deterministic order.
pm_find_pbxprojs() {
  local root="${1:-.}"
  find "$root" -name 'project.pbxproj' -path '*.xcodeproj/*' 2>/dev/null \
    | grep -Ev "/($PM_PRUNE_DIRS)/" \
    | LC_ALL=C sort
}

# pm_resolve <root> -> "DIR<TAB>PLIST" (ROOT-relative; PLIST may be empty) for the
# primary app target, or non-zero with no output.
#
# A monorepo may contain several .xcodeproj (samples, sub-projects, the real
# app). The shallowest one is not necessarily the real app, so every pbxproj
# is resolved on its own terms (against its own SRCROOT-relative projdir) and
# the single global best — most *.swift sources — wins across all of them.
pm_resolve() {
  local root="${1:-.}" pbx rel projdir apps plists app plist dir n cand_dir cand_plist
  local best="" best_plist="" best_n=-1 found=0
  # Normalize a trailing slash so the ROOT-relative strip below reliably matches
  # (root="/" strips to "" and must stay "/"; root="." is untouched).
  root="${root%/}"; [[ -z "$root" ]] && root="/"
  while IFS= read -r pbx; do
    [[ -z "$pbx" ]] && continue
    apps="$(pm_app_targets "$pbx")"; [[ -z "$apps" ]] && continue
    found=1
    # ROOT-relative dir that contains this .xcodeproj (SRCROOT). Its
    # INFOPLIST_FILE paths and app source dir are relative to this.
    rel="${pbx#"$root"/}"                 # e.g. ios/App.xcodeproj/project.pbxproj
    projdir="$(dirname "$(dirname "$rel")")"; projdir="${projdir#./}"
    [[ "$projdir" == "." ]] && projdir=""
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
      # Prefix the projdir so paths are ROOT-relative before comparing/storing.
      cand_dir="${projdir:+$projdir/}$dir"
      cand_plist=""
      [[ -n "$plist" ]] && cand_plist="${projdir:+$projdir/}$plist"
      if (( n > best_n )); then
        best_n=$n; best="$cand_dir"; best_plist="$cand_plist"
      fi
    done <<< "$apps"
  done <<< "$(pm_find_pbxprojs "$root")"
  [[ $found -eq 0 || -z "$best" ]] && return 1
  printf '%s\t%s\n' "$best" "$best_plist"
}
