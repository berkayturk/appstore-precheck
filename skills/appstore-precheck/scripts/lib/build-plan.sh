#!/usr/bin/env bash
# Helpers sourced by build-run.sh. Bash 3.2 compatible.

build_project() { # root framework -> prints relative .xcworkspace/.xcodeproj or Package.swift
  local root="$1" fw="$2" base found
  base="$root"
  [[ "$fw" == kmp ]] && base="$root/iosApp"
  # Every .xcodeproj contains an internal project.xcworkspace. That is not a
  # top-level CocoaPods workspace and must not shadow the project itself.
  found="$(find "$base" -maxdepth 4 -type d -name '*.xcworkspace' \
    -not -path '*/Pods/*' -not -path '*.xcodeproj/*' -print -quit 2>/dev/null)"
  [[ -n "$found" ]] || found="$(find "$base" -maxdepth 4 -type d -name '*.xcodeproj' -print -quit 2>/dev/null)"
  if [[ -z "$found" && -f "$root/Package.swift" ]]; then found="$root/Package.swift"; fi
  [[ -n "$found" ]] || return 1
  printf '%s\n' "${found#"$root"/}"
}

build_project_flags() { # relative project -> print -workspace/-project + value, or nothing for Package.swift
  case "$1" in
    *.xcworkspace) printf '%s\n' '-workspace' "$1" ;;
    *.xcodeproj) printf '%s\n' '-project' "$1" ;;
    Package.swift) : ;;
  esac
}

build_installer() { # root -> npm|yarn|pnpm; 3 when there is no reproducible lockfile
  if [[ -f "$1/pnpm-lock.yaml" ]]; then echo pnpm
  elif [[ -f "$1/yarn.lock" ]]; then echo yarn
  elif [[ -f "$1/package-lock.json" || -f "$1/npm-shrinkwrap.json" ]]; then echo npm
  else return 3; fi
}

build_has_expo() {
  [[ -f "$1/package.json" ]] && python3 - "$1/package.json" <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1], encoding='utf-8'))
except (OSError, ValueError):
    sys.exit(1)
deps = dict(data.get('dependencies') or {})
deps.update(data.get('devDependencies') or {})
sys.exit(0 if 'expo' in deps else 1)
PY
}

build_check_symlinks() { # reject links; a build script could otherwise follow one into the source
  python3 - "$1" <<'PY'
import fnmatch, os, sys
excluded = {'.git', 'node_modules', 'Pods', 'build', 'DerivedData'}
for base, dirs, files in os.walk(sys.argv[1], followlinks=False):
    dirs[:] = [d for d in dirs if d not in excluded]
    for name in dirs + files:
        if name in excluded or name == '.appstore-precheck.json' or name == '.env' or name.startswith('.env.') or fnmatch.fnmatch(name, '*asc-key*.json') or name.endswith(('.p8', '.p12', '.mobileprovision')):
            continue
        if os.path.islink(os.path.join(base, name)):
            sys.exit(3)
PY
}
