# AST ↔ IOS_DIR (Xcode project-model parsing) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve `IOS_DIR` and `INFO_PLIST` authoritatively from the Xcode project model (`.pbxproj`) so the scanner stops landing on the wrong dir/plist in monorepo/SPM layouts, with the existing grep heuristic preserved as fallback.

**Architecture:** A new sourced, unit-tested script `project-model.sh` parses `.pbxproj` (pure bash + awk, zero new dependencies) to find the primary `application`-type target's source dir and `INFOPLIST_FILE`. `scan.sh`'s `detect_ios_dir` gains a chain: config `.iosSourceDir` > project-model parse > existing heuristic. When no `.pbxproj` is present (or parse fails) behavior is byte-identical to today.

**Tech Stack:** Bash 3.2 (macOS-compatible), awk, `find`, `jq` (already a dependency). No new runtime dependencies.

## Global Constraints

- **READ-ONLY**: the scanner performs no writes; the only sanctioned side effect elsewhere is `verdict.sh --apply`'s token. `project-model.sh` reads files only.
- **Zero new runtime dependencies**: pure bash + awk + find. No SwiftSyntax / SourceKit / tree-sitter. Preserve the clone-free, `npx`-runnable identity.
- **No competitor name** anywhere (code, tests, fixtures, commits, branch, docs). Stay generic.
- **Byte-identical default text output** on any input WITHOUT a `.pbxproj`. Behavior changes only when a `.pbxproj` is present and corrects detection; those changes are reconciled in fixtures + docs via TDD.
- **TDD**: failing test first, minimal impl, green, commit. Each task ends independently testable.
- **Version lockstep** (`scripts/check-versions.sh`: package.json / .claude-plugin/plugin.json / .cursor-plugin/plugin.json / SKILL.md) must stay green. Do NOT bump versions in this branch — the version bump happens at release time, after merge (out of scope here); the manifests already match at 1.6.0.
- **Bash 3.2 compat**: no associative arrays; guard empty-array expansion.

---

## File Structure

- **Create** `skills/appstore-precheck/scripts/project-model.sh` — pbxproj parser + resolver. Sourced by scan.sh. One responsibility: repo root → primary app target's ROOT-relative source dir + Info.plist path.
- **Create** `tests/test-project-model.sh` — unit tests for the parser/resolver (synthetic `.pbxproj` text + synthetic project trees in `mktemp`).
- **Create** fixtures under `tests/fixtures/`:
  - `pbxproj-generate-app/` — app target uses `GENERATE_INFOPLIST_FILE`, an extension owns the only checked-in plist (the classic wrong-dir trap).
  - `pbxproj-multiapp/` — two `application` targets; the one with more sources wins.
- **Modify** `skills/appstore-precheck/scripts/scan.sh` — source the new script (near lines 15-16); rewrite `detect_ios_dir` chain (around 112-134); override `INFO_PLIST` (around 142).
- **Modify** `tests/run.sh` — add `check_fixture` blocks asserting the corrected layout for the new fixtures.
- **Modify** `tests/all.sh` — register `test-project-model.sh` in `SUITE`.
- **Modify** `docs/fp-reduction-report.md` (append a measurement addendum) and, if the panel numbers move, regenerate `docs/scorecard.md`.

---

## Task 1: pbxproj parse primitives (`pm_app_targets`, `pm_infoplist_files`)

**Files:**
- Create: `skills/appstore-precheck/scripts/project-model.sh`
- Test: `tests/test-project-model.sh`

**Interfaces:**
- Produces:
  - `pm_app_targets <pbxproj-path>` → prints each `application`-productType target's `name`, one per line.
  - `pm_infoplist_files <pbxproj-path>` → prints each `INFOPLIST_FILE` value (unquoted, `sort -u`), one per line.

- [ ] **Step 1: Write the failing test**

Create `tests/test-project-model.sh`:

```bash
#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCAN="skills/appstore-precheck/scripts"
# shellcheck source=tests/_assert.sh
source "$ROOT/tests/_assert.sh"
# shellcheck source=skills/appstore-precheck/scripts/project-model.sh
source "$ROOT/$SCAN/project-model.sh"

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

# --- pm_app_targets: only application productType, ignore tests/extensions ---
cat > "$work/sample.pbxproj" <<'EOF'
		AAA /* MyApp */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = BBB /* list for "MyApp" */;
			name = MyApp;
			productName = MyApp;
			productType = "com.apple.product-type.application";
		};
		CCC /* MyAppTests */ = {
			isa = PBXNativeTarget;
			name = MyAppTests;
			productType = "com.apple.product-type.bundle.unit-test";
		};
		DDD /* MyWidget */ = {
			isa = PBXNativeTarget;
			name = MyWidget;
			productType = "com.apple.product-type.app-extension";
		};
EOF
got="$(pm_app_targets "$work/sample.pbxproj")"
assert_eq "$got" "MyApp" "pm_app_targets returns only the application target"

# --- quoted target name with spaces ---
cat > "$work/quoted.pbxproj" <<'EOF'
		EEE /* app */ = {
			isa = PBXNativeTarget;
			name = "My Cool App";
			productType = "com.apple.product-type.application";
		};
EOF
assert_eq "$(pm_app_targets "$work/quoted.pbxproj")" "My Cool App" "pm_app_targets strips quotes"

# --- pm_infoplist_files: collect, unquote, dedupe ---
cat > "$work/plists.pbxproj" <<'EOF'
				INFOPLIST_FILE = MyWidget/Info.plist;
				INFOPLIST_FILE = "MyApp/Info.plist";
				INFOPLIST_FILE = MyWidget/Info.plist;
EOF
got="$(pm_infoplist_files "$work/plists.pbxproj" | tr '\n' '|')"
assert_eq "$got" "MyApp/Info.plist|MyWidget/Info.plist|" "pm_infoplist_files unquotes + dedupes + sorts"

echo "test-project-model: OK"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-project-model.sh`
Expected: FAIL — `project-model.sh` does not exist / functions undefined.

- [ ] **Step 3: Write minimal implementation**

Create `skills/appstore-precheck/scripts/project-model.sh`:

```bash
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-project-model.sh`
Expected: PASS — prints `test-project-model: OK`.

- [ ] **Step 5: Commit**

```bash
git add skills/appstore-precheck/scripts/project-model.sh tests/test-project-model.sh
git commit -m "feat(project-model): parse app targets + INFOPLIST_FILE from pbxproj"
```

---

## Task 2: Resolver (`pm_find_pbxproj`, `pm_resolve`)

**Files:**
- Modify: `skills/appstore-precheck/scripts/project-model.sh`
- Test: `tests/test-project-model.sh`

**Interfaces:**
- Consumes: `pm_app_targets`, `pm_infoplist_files` (Task 1).
- Produces:
  - `pm_find_pbxproj <root>` → shallowest `*.xcodeproj/project.pbxproj` under root (vendored dirs pruned), or "".
  - `pm_resolve <root>` → prints one line `DIR\tPLIST` (both ROOT-relative, `PLIST` may be empty) for the primary app target; returns non-zero (no output) when no `.pbxproj` / no app target resolves. Multi-app: the app target whose resolved dir holds the most `*.swift` wins.

- [ ] **Step 1: Write the failing test**

Append to `tests/test-project-model.sh` (before the final `echo`):

```bash
# --- pm_resolve: GENERATE_INFOPLIST_FILE app + extension owns the only plist ---
gen="$(mktemp -d)"
mkdir -p "$gen/App.xcodeproj" "$gen/MyApp" "$gen/MyWidget"
cat > "$gen/App.xcodeproj/project.pbxproj" <<'EOF'
		AAA /* MyApp */ = {
			isa = PBXNativeTarget;
			name = MyApp;
			productType = "com.apple.product-type.application";
		};
		DDD /* MyWidget */ = {
			isa = PBXNativeTarget;
			name = MyWidget;
			productType = "com.apple.product-type.app-extension";
		};
EOF
# only the extension declares a plist; the app uses GENERATE_INFOPLIST_FILE
printf 'INFOPLIST_FILE = MyWidget/Info.plist;\n' >> "$gen/App.xcodeproj/project.pbxproj"
touch "$gen/MyApp/App.swift" "$gen/MyApp/ContentView.swift" "$gen/MyWidget/Widget.swift"
touch "$gen/MyWidget/Info.plist"
assert_eq "$(pm_resolve "$gen")" "$(printf 'MyApp\t')" "resolve picks the app dir, not the extension plist"
rm -rf "$gen"

# --- pm_resolve: older app that declares its own INFOPLIST_FILE ---
old="$(mktemp -d)"
mkdir -p "$old/App.xcodeproj" "$old/MyApp"
cat > "$old/App.xcodeproj/project.pbxproj" <<'EOF'
		AAA /* MyApp */ = {
			isa = PBXNativeTarget;
			name = MyApp;
			productType = "com.apple.product-type.application";
		};
EOF
printf 'INFOPLIST_FILE = MyApp/Info.plist;\n' >> "$old/App.xcodeproj/project.pbxproj"
touch "$old/MyApp/App.swift" "$old/MyApp/Info.plist"
assert_eq "$(pm_resolve "$old")" "$(printf 'MyApp\tMyApp/Info.plist')" "resolve returns app dir + its declared plist"
rm -rf "$old"

# --- pm_resolve: nested .xcodeproj (ios/) yields ROOT-relative paths ---
nest="$(mktemp -d)"
mkdir -p "$nest/ios/App.xcodeproj" "$nest/ios/MyApp"
cat > "$nest/ios/App.xcodeproj/project.pbxproj" <<'EOF'
		AAA /* MyApp */ = {
			isa = PBXNativeTarget;
			name = MyApp;
			productType = "com.apple.product-type.application";
		};
EOF
printf 'INFOPLIST_FILE = MyApp/Info.plist;\n' >> "$nest/ios/App.xcodeproj/project.pbxproj"
touch "$nest/ios/MyApp/App.swift" "$nest/ios/MyApp/Info.plist"
assert_eq "$(pm_resolve "$nest")" "$(printf 'ios/MyApp\tios/MyApp/Info.plist')" "resolve prefixes the .xcodeproj parent dir"
rm -rf "$nest"

# --- pm_resolve: multi-app picks the one with more sources ---
multi="$(mktemp -d)"
mkdir -p "$multi/App.xcodeproj" "$multi/AppA" "$multi/AppB"
cat > "$multi/App.xcodeproj/project.pbxproj" <<'EOF'
		AAA /* AppA */ = {
			isa = PBXNativeTarget;
			name = AppA;
			productType = "com.apple.product-type.application";
		};
		BBB /* AppB */ = {
			isa = PBXNativeTarget;
			name = AppB;
			productType = "com.apple.product-type.application";
		};
EOF
touch "$multi/AppA/One.swift"
touch "$multi/AppB/One.swift" "$multi/AppB/Two.swift" "$multi/AppB/Three.swift"
assert_eq "$(pm_resolve "$multi" | cut -f1)" "AppB" "resolve picks the app with more sources"
rm -rf "$multi"

# --- pm_resolve: no pbxproj -> empty + non-zero ---
none="$(mktemp -d)"; touch "$none/readme.md"
pm_resolve "$none" >/dev/null && r=0 || r=1
assert_eq "$r" "1" "resolve fails cleanly when no pbxproj is present"
rm -rf "$none"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-project-model.sh`
Expected: FAIL — `pm_resolve` / `pm_find_pbxproj` undefined.

- [ ] **Step 3: Write minimal implementation**

Append to `skills/appstore-precheck/scripts/project-model.sh`:

```bash
# Vendored dirs whose .xcodeproj must never win detection.
PM_PRUNE_DIRS='node_modules|Pods|Carthage|.build|DerivedData|.git'

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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-project-model.sh`
Expected: PASS — `test-project-model: OK`.

- [ ] **Step 5: Commit**

```bash
git add skills/appstore-precheck/scripts/project-model.sh tests/test-project-model.sh
git commit -m "feat(project-model): resolve primary app dir + plist (multi-app, nested, GENERATE)"
```

---

## Task 3: Wire into scan.sh + fixtures + suite registration

**Files:**
- Modify: `skills/appstore-precheck/scripts/scan.sh` (source line ~15-16; `detect_ios_dir` ~112-134; `INFO_PLIST` ~142)
- Create: `tests/fixtures/pbxproj-generate-app/` and `tests/fixtures/pbxproj-multiapp/`
- Modify: `tests/run.sh` (new `check_fixture` blocks)
- Modify: `tests/all.sh` (register `test-project-model.sh`)

**Interfaces:**
- Consumes: `pm_resolve` (Task 2).
- Produces: `detect_ios_dir` now sets global `PM_INFO_PLIST` when it resolves via the project model; scan.sh's `INFO_PLIST` prefers it.

- [ ] **Step 1: Write the failing fixtures + assertions**

Create the wrong-dir-trap fixture. `tests/fixtures/pbxproj-generate-app/`:

```
pbxproj-generate-app/
  App.xcodeproj/project.pbxproj
  MyApp/MyAppApp.swift          (the real app sources; NO checked-in plist)
  MyApp/CameraView.swift        (uses AVCaptureDevice to make a locatable check exercise the dir)
  MyWidget/Widget.swift
  MyWidget/Info.plist           (the ONLY checked-in plist — belongs to the extension)
```

`App.xcodeproj/project.pbxproj`:

```
// !$*UTF8*$!
{
	objects = {
		AAA /* MyApp */ = {
			isa = PBXNativeTarget;
			name = MyApp;
			productType = "com.apple.product-type.application";
		};
		DDD /* MyWidget */ = {
			isa = PBXNativeTarget;
			name = MyWidget;
			productType = "com.apple.product-type.app-extension";
		};
	};
	buildSettings = {
		GENERATE_INFOPLIST_FILE = YES;
		INFOPLIST_FILE = MyWidget/Info.plist;
	};
}
```

`MyApp/MyAppApp.swift`:

```swift
import SwiftUI
@main
struct MyAppApp: App { var body: some Scene { WindowGroup { ContentView() } } }
```

`MyApp/CameraView.swift`:

```swift
import AVFoundation
func startCapture() { _ = AVCaptureDevice.default(for: .video) }
```

`MyWidget/Widget.swift`:

```swift
import WidgetKit
struct MyWidget {}
```

`MyWidget/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict/></plist>
```

Create the multi-app fixture. `tests/fixtures/pbxproj-multiapp/`:

```
pbxproj-multiapp/
  App.xcodeproj/project.pbxproj   (AppA + AppB, both application)
  AppA/AppAApp.swift
  AppB/AppBApp.swift
  AppB/Extra1.swift
  AppB/Extra2.swift
```

`App.xcodeproj/project.pbxproj`:

```
// !$*UTF8*$!
{
	objects = {
		AAA /* AppA */ = {
			isa = PBXNativeTarget;
			name = AppA;
			productType = "com.apple.product-type.application";
		};
		BBB /* AppB */ = {
			isa = PBXNativeTarget;
			name = AppB;
			productType = "com.apple.product-type.application";
		};
	};
}
```

`AppA/AppAApp.swift`, `AppB/AppBApp.swift`, `AppB/Extra1.swift`, `AppB/Extra2.swift` — each a trivial one-line Swift file, e.g.:

```swift
import SwiftUI
struct Placeholder {}
```

Add to `tests/run.sh` (after the last existing `finish_fixture`, before the final tally):

```bash
check_fixture "pbxproj-generate-app" "app uses GENERATE_INFOPLIST_FILE; extension owns the only plist"
assert_has  "PASS: layout — ios='MyApp'"  "project-model picks the app dir, not the extension"
assert_absent "ios='MyWidget'"            "detection does not land on the extension dir"
finish_fixture

check_fixture "pbxproj-multiapp" "two application targets; the larger one wins"
assert_has  "ios='AppB'"                  "project-model picks the app with more sources"
finish_fixture
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/run.sh`
Expected: FAIL — current heuristic resolves `ios='./MyWidget'` (extension plist) for `pbxproj-generate-app`; the `ios='MyApp'` assertion fails.

- [ ] **Step 3: Wire scan.sh**

Add the source line after `scan.sh:16` (`source .../suppress.sh`):

```bash
source "$(dirname "${BASH_SOURCE[0]}")/project-model.sh"
```

Replace the body of `detect_ios_dir` (scan.sh ~112-134) so the config check stays first, then project-model, then the existing heuristic. Keep the existing heuristic code verbatim as the tail:

```bash
detect_ios_dir() {
  local d; d=$(cfg '.iosSourceDir')
  [[ -n "$d" ]] && { echo "$d"; return; }
  # Authoritative: parse the Xcode project model when a .pbxproj exists.
  local pm; pm="$(pm_resolve . 2>/dev/null)"
  if [[ -n "$pm" ]]; then
    PM_INFO_PLIST="$(printf '%s' "$pm" | cut -f2)"
    printf '%s' "$pm" | cut -f1
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
  [[ -n "$best" ]] && { echo "$best"; return; }
  echo "$alt"
}
```

Initialize the global near the other detection vars (add just above `IOS_DIR="$(detect_ios_dir)"` at ~136):

```bash
PM_INFO_PLIST=""
```

Change the `INFO_PLIST` assignment (scan.sh ~142) to prefer the project-model plist:

```bash
INFO_PLIST="${PM_INFO_PLIST:-${IOS_DIR%/}/Info.plist}"
```

- [ ] **Step 4: Run to verify the new fixtures pass**

Run: `bash tests/run.sh`
Expected: PASS — `pbxproj-generate-app` reports `ios='MyApp'`, `pbxproj-multiapp` reports `ios='AppB'`; all pre-existing fixtures unchanged (byte-identity: none contain a `.pbxproj`, so `pm_resolve` returns empty and the heuristic runs exactly as before).

- [ ] **Step 5: Register the unit suite + run everything**

Add to `tests/all.sh` `SUITE` array (after `test-scorecard.sh`):

```bash
  "test-project-model.sh" # project-model.sh pbxproj parser + resolver
```

Run: `bash tests/all.sh`
Expected: `SUITE PASSED (12 files)`.

Run: `npm test`
Expected: full suite green.

- [ ] **Step 6: Commit**

```bash
git add skills/appstore-precheck/scripts/scan.sh tests/fixtures/pbxproj-generate-app tests/fixtures/pbxproj-multiapp tests/run.sh tests/all.sh
git commit -m "feat(scan): resolve IOS_DIR/INFO_PLIST from pbxproj, heuristic fallback"
```

---

## Task 4: Measure the 18-app panel + document

**Files:**
- Modify: `docs/fp-reduction-report.md` (append a "project-model detection" addendum)
- Modify: `docs/scorecard.md` (regenerate only if panel numbers move)

**Interfaces:**
- Consumes: the wired scanner (Task 3), `scripts/scorecard-real.sh`, `corpus/real/` candidate labels.

- [ ] **Step 1: Re-run the real panel (network-heavy, non-blocking)**

Run: `bash scripts/scorecard-real.sh 2>&1 | tee /tmp/panel-after.txt`
Expected: the script clones the 18 commit-pinned apps and prints per-rule precision/recall. Note this clones ~18 repos; it is the non-blocking real panel, not a CI gate.

- [ ] **Step 2: Capture the delta for the detection-sensitive rules**

Compare `usage-description-crosscheck`, `export-compliance`, and `min-functionality-nav` precision/recall before (v1.6.0 report figures in `docs/fp-reduction-report.md`) vs after (`/tmp/panel-after.txt`). Record which false positives were rooted in `IOS_DIR` mis-detection and are now cleared (e.g. `wikipedia-ios`'s custom-named-plist case named in the FP report).

- [ ] **Step 3: Verify zero true-positive loss**

Confirm every rule's true-positive count is unchanged or higher (the FP-round discipline: no recall regression). If any TP dropped, treat it as a defect and open a follow-up before claiming success.

- [ ] **Step 4: Write the addendum**

Append a dated "Project-model detection (roadmap #2b)" section to `docs/fp-reduction-report.md` with: the before/after numbers for the three rules, the specific apps whose FPs cleared, an explicit honesty note (the panel labels remain candidate/directional, not human-final), and confirmation of zero TP loss. Regenerate `docs/scorecard.md` only if the aggregate moved.

- [ ] **Step 5: Full green + commit**

Run: `npm test && ./scripts/scorecard.sh --check`
Expected: suite green; synthetic `--check` still passes (precision ≥ 0.80).

```bash
git add docs/fp-reduction-report.md docs/scorecard.md
git commit -m "docs: measure project-model detection impact on the 18-app panel"
```

---

## Self-Review

**Spec coverage:**
- Layer-1 pbxproj parse, zero deps → Tasks 1-2 (`project-model.sh`). ✓
- Detection chain config > pbxproj > heuristic → Task 3 `detect_ios_dir`. ✓
- `INFO_PLIST` from `INFOPLIST_FILE`, GENERATE case preserves the existing WARN → Task 3 (`PM_INFO_PLIST`, empty plist → falls back to `${IOS_DIR}/Info.plist` guess → existing "not found / auto-generated" path). ✓
- Primary app target by productType + most-sources, config override → Tasks 2-3. ✓
- Byte-identity when no pbxproj → Task 3 Step 4 (existing fixtures unchanged). ✓
- New wrong-dir-trap + multi-app fixtures, unit tests, suite registration → Tasks 1-3. ✓
- 18-app measurement + honesty note + zero-TP-loss → Task 4. ✓
- Out-of-scope (XcodeGen/Tuist pre-gen, workspace, all-app audit, Swift AST) → not implemented; fall back to heuristic by construction (no `.pbxproj` ⇒ `pm_resolve` empty). ✓

**Placeholder scan:** No TBD/TODO; every code + test step shows real content; commands have expected output. ✓

**Type consistency:** `pm_app_targets` / `pm_infoplist_files` (Task 1) are consumed by `pm_resolve` (Task 2); `pm_resolve`'s `DIR\tPLIST` contract is consumed by `detect_ios_dir` via `cut -f1`/`cut -f2` and `PM_INFO_PLIST` (Task 3). Names consistent across tasks. ✓
