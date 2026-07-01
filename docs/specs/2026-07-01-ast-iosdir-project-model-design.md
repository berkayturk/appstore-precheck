# Design: Roadmap #2(b) — AST ↔ IOS_DIR via Xcode project-model parsing

**Date:** 2026-07-01
**Status:** Approved (brainstorming) — pending implementation plan
**Roadmap:** #2 "smarter analysis", sub-capability (b) AST ↔ IOS_DIR auto-detection
**Depends on:** #1 measurement infrastructure (structured findings, suppression, scorecard) — shipped in v1.6.0

## Problem

The dominant remaining false-positive source after the v1.6.0 FP-reduction round is
`IOS_DIR` auto-detection landing on the wrong directory or the wrong `Info.plist` in
SPM / monorepo / multi-target layouts. Concretely, on `wikipedia-ios` the real app
target carries the purpose strings, but detection reads a different (custom-named or
extension-owned) plist, so `usage-description`, `export-compliance`, and
`min-functionality` checks fire spuriously.

Root cause confirmed against a real project (`controldopamine`, 7 native targets):

- Only **one** target is `com.apple.product-type.application`; the rest are
  extensions / tests / UI-tests.
- Modern Xcode sets `GENERATE_INFOPLIST_FILE = YES` on the app target, so the app has
  **no checked-in `Info.plist`** — it is auto-generated. The only checked-in plists
  belong to extensions. The current grep heuristic therefore has no app-owned plist to
  find and lands on an extension's.

The current `detect_ios_dir` is a pure grep heuristic: candidate dirs are Info.plist
locations plus `@main` / `@UIApplicationMain` / `class AppDelegate` directories, scored
by `.swift` file count, with a `NONAPP_TARGET` name-regex deprioritizing
Watch/Extension/Widget/etc. The authoritative source of truth — the Xcode project file
— is never consulted.

## Scope decision (from brainstorming)

- **Layer 1 only** — parse the structured project model (`.pbxproj`). Do **not**
  introduce a real Swift source AST (SwiftSyntax / SourceKit / tree-sitter): those add a
  toolchain dependency and break the tool's "clone-free, `npx`-runnable, zero-dependency,
  READ-ONLY bash" identity. Swift-source-AST is explicitly out of scope for this round.
- **Multi-app monorepo** (e.g. firefox-ios: Firefox + Focus + Klar): select the primary
  app target (the `application`-type target with the most sources), overridable via
  config. Auditing every app target is a separate future job — it would require removing
  scan.sh's single-`IOS_DIR` assumption and changing the output format.

## Approach (A: pbxproj-first extraction + heuristic fallback)

### Architecture

New isolated, unit-testable, sourced script:
**`skills/appstore-precheck/scripts/project-model.sh`**. Single responsibility: given a
repo root, authoritatively resolve the primary app target's source root and Info.plist
path from an Xcode project model. Pure bash + awk, zero new dependencies, READ-ONLY.
`scan.sh` sources it and calls it inside `detect_ios_dir`.

### Detection chain (with fallback)

```
IOS_DIR =  config .iosSourceDir            (highest priority — existing escape hatch)
        >  project-model parse (.pbxproj)  (NEW — authoritative)
        >  existing grep heuristic         (unchanged fallback: no project file / parse fails)
```

`INFO_PLIST` resolves the same way: the selected app target's `INFOPLIST_FILE` build
setting (when present) > the existing `${IOS_DIR}/Info.plist` guess. When the app target
has `GENERATE_INFOPLIST_FILE = YES` and no checked-in plist, detection reports **no app
plist** rather than an extension's — preserving the existing "Info.plist not found …
modern Xcode may auto-generate it; verify build settings" WARN path instead of false-firing.

### What is extracted from `.pbxproj`

- `PBXNativeTarget` blocks whose `productType` is `com.apple.product-type.application`
  (extensions / tests / watch / clips excluded by **exact productType match**, no longer
  by name-regex guessing).
- If more than one app target exists: the one with the most sources (deterministic),
  overridable via config `.iosSourceDir`.
- The selected target's `INFOPLIST_FILE` (if set) and its source root directory.

### Parsing note

`.pbxproj` is OpenStep-plist text. Full object-graph parsing is **not** required; a
block-scoped awk pass extracts productType per native target and the `INFOPLIST_FILE` /
source references for the app target. Implementation detail deferred to the plan; the
key invariant is that extraction is targeted, deterministic, and dependency-free.

## Byte-identity & output impact

The `PASS: layout — ios='…'` line will **change** when detection corrects to the right
directory — this is an intentional behavior change. Rule:

- When no new pbxproj path applies (fixtures without a real `.pbxproj`, repos with no
  project file), output stays **byte-identical**.
- When a `.pbxproj` is present and changes the resolved dir, output changes → affected
  fixture expectations are updated via TDD and `docs/` is reconciled.

## Testing strategy (TDD)

- **New fixtures** containing `.pbxproj` "wrong-dir trap" scenarios:
  1. extension has a checked-in plist while the app target uses
     `GENERATE_INFOPLIST_FILE = YES` (heuristic lands on the extension plist; pbxproj
     finds the app);
  2. multi-app monorepo (two `application` targets → primary selected);
  3. vendored / SPM-module directory that the heuristic would mis-score.
- **Unit tests** for `project-model.sh`: `tests/test-project-model.sh` (isolated parse
  assertions on synthetic `.pbxproj` snippets).
- **Measurement**: re-run the 18-app real panel via `scorecard-real.sh` and report the
  `usage-description` / `export-compliance` / `min-functionality` precision/recall delta
  against the candidate labels. The synthetic `--check` blocking gate must stay green.

## Out of scope (falls back to the existing heuristic)

- XcodeGen / Tuist projects before generation (no `.pbxproj` checked in).
- `.xcworkspace` multi-project resolution.
- Auditing every app target in a multi-app monorepo.
- Any Swift source-level AST (Layer 2).

## Success criteria

- Zero new runtime dependencies; tool identity (clone-free, npx-runnable, READ-ONLY)
  preserved.
- On repos with a `.pbxproj`, `IOS_DIR` and `INFO_PLIST` resolve to the primary app
  target authoritatively.
- 18-app panel: measurable reduction in `usage-description` / `export-compliance` /
  `min-functionality` false positives with zero true-positive loss (mirrors the v1.6.0
  FP-round measurement discipline).
- Byte-identical text output on all inputs without a `.pbxproj`; synthetic `--check`
  gate green.
