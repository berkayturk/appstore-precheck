# Local dynamic scorecard

Run date: 2026-09-26 (Europe/Istanbul). Host: macOS 27.0 (26A428), Xcode 27.0 (27A266a), iOS Simulator 26.5 (23F77), Maestro 2.8.0. These are simulator observations; a simulator is not a physical device or an App Store review environment.

The corpus panel builds each variant into a disposable copy, creates and deletes its own simulator, runs launch health three times, and records bounded screen exploration when the app stays up. `SKIP` means the required tool or package source was unavailable; `ERROR` is a harness/build/runtime failure. The machine-readable `panel.json` is local and is not packaged; regenerate it with `bash tests/local/dynamic-panel.sh --out /tmp/precheck-panel`.

| Framework | Clean build/run | Clean launch | Broken build/run | Broken launch | Notes |
|---|---|---|---|---|---|
| SwiftUI | Pending | Pending | Pending | Pending | Native Release simulator builds |
| React Native bare | Pending | Pending | Pending | Pending | Template/package access required |
| Expo | Pending | Pending | Pending | Pending | Template/package access required |
| Flutter | Pending | Pending | Pending | Pending | Flutter SDK required |
| Kotlin Multiplatform | Pending | Pending | Pending | Pending | Gradle/Kotlin tooling required |

## Real app: ControlDopamine

The source at `/Users/bt/claude/controldopamine` was read without writing to it. An isolated Release simulator build produced a `.app`; artifact review ran, followed by three simulator launches and bounded screen exploration. Launch health passed 3/3 and the first screen was nonblank. The inventory captured one screen and thirteen pattern checks; most paths needed further interaction or were skipped. The Dynamic Type hierarchy showed one possible overlapping label and CFNetwork diagnostics observed attribution hosts that need a privacy manifest review. These are advisory signals, not a rejection conclusion. Artifact inspection reported partial clean signals for direct private linkage, URL scheme declarations, ATS, and mapped required-reason API symbols; signing entitlements were unreadable in the unsigned simulator bundle.

Local fastlane metadata was detected under `ios/fastlane/metadata`; its review produced three PASS, two NEEDS_REVIEW, one SKIP, and five NOT_RUN records without App Store Connect credentials. No App Store Connect request or URL HEAD check was made.

## Acceptance and limits

The launch false-positive check uses the clean SwiftUI variant. The broken variant must reach a 3/3 launch finding to count as detected. D1+D2 latency and any mismatch are reported after the panel completes. A clean or broken result outside the simulator cannot be inferred from these runs.
