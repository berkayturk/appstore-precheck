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
