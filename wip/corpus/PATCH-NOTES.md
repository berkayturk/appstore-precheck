# Corpus integration notes

- Add `corpus/dynamic/` and `tests/local/dynamic-panel.sh` unchanged; neither
  belongs in `tests/all.sh` because the full panel needs macOS, Xcode, networked
  framework dependencies, and iOS Simulator.
- `tests/local/dynamic-panel.sh --out DIR` emits `DIR/panel.json` and `DIR/panel.tsv`
  plus per-case build/runtime transcripts. `--framework` and `--variant` filter.
- SwiftUI clean and broken Xcode projects built successfully with Xcode 27.0 using
  direct `xcodebuild -sdk iphonesimulator -configuration Release` and temp DerivedData.
- This worktree's older `build-exec.py` mishandles early Xcode diagnostic braces in
  scheme discovery and makes `build-run.sh` return `NO_SCHEME`; root fixed this on
  the feature branch as commit `b5c3463`. Re-run the panel after integration.
- RN/Expo package registry is unreachable here; Flutter and Gradle are absent.
  Their real builds must be attempted on a host with those tools and reported as
  `SKIP` until successfully observed. Do not infer a PASS from source alone.
- Runtime integration: panel passes `--explore` only when `dynamic-run.sh` supports
  it and reads `screen-inventory.json` when present. It compares `dyn-launch`
  strictly and selected exploratory `NEEDS_REVIEW` results as provisional
  expectations; mismatch remains visible in `panel.json`.
- SwiftUI broken deliberately crashes at `App.init`; its exploratory checks will
  likely be `SKIP` because no screen becomes available. Other broken variants
  target discoverable UI and artifact defects; `clean` variants are synthetic
  controls, not complete App Store compliant apps.
