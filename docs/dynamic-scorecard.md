# Local dynamic scorecard

Run date: 2026-09-28 UTC (finished after midnight in Europe/Istanbul). macOS 27.0,
Xcode 27.0 (27A266a), iPhone 17 Simulator with iOS 26.5 (23F77), Maestro 2.8.0.
Isolated build toolchains include Flutter 3.47.5, Gradle 9.1.0 and Kotlin Native
2.2.20; official distribution checksums were verified. These are synthetic corpus
observations, not reference-app or App Review compliance results.

All ten cases ran fresh against one frozen collector revision. They reused exact
previously built, source-bound artifacts after checking full artifact hashes,
configuration, source and retained toolchain evidence. This is a new runtime panel,
not ten new builds. The direct collector, corpus and build-provenance code matched
the integrated feature branch; its verification/metadata integration had a separate
passing full test suite.

Launch repetitions used a five-second observation window (every run record has
`window_seconds: 5`) and fresh environments; the panel and `dynamic-run.sh` default
to 10 seconds, so pass the window explicitly. Regenerate builds and runtime with
`bash tests/local/dynamic-panel.sh --window 5 --out /tmp/precheck-verification-panel-new`.
The SwiftUI clean timing benchmark used ten repeats (`--framework swiftui --variant clean
--repeats 10`); the other cases used the default three. Use an empty output directory;
stale case outputs are refused.

| Framework | Clean | Broken | Scope |
|---|---|---|---|
| SwiftUI | Release; launch and first screen 10/10 PASS | Release; deliberate crash 3/3 FINDING | Fresh owned environments; unchanged lifecycle benchmark |
| React Native bare | Release; launch and first screen 3/3 PASS | Release; launch and first screen 3/3 PASS; 4/4 expected discovery statuses | Unfamiliar sign-in provider observed in the new live hierarchy |
| Expo | Release; launch and first screen 3/3 PASS | Release; launch and first screen 3/3 PASS; 3/3 expected discovery statuses | Shipped camera purpose present in clean and absent in broken |
| Flutter | Debug; launch and first screen 3/3 PASS | Debug; launch and first screen 3/3 PASS; 1/1 expected discovery status | Simulator Debug only; retained Runner debug-library lineage |
| Kotlin Multiplatform | ARM64 Release; launch and first screen 3/3 PASS | ARM64 Release; launch and first screen 3/3 PASS; 1/1 expected discovery status | Static Shared archive; source-bound artifact reuse |

All ten expected launch outcomes matched: zero launch false positives, misses or
mixed outcomes, and no final case SKIP/NOT_RUN. Nine of nine expected discovery
statuses matched. These are manifest expectation denominators, not recall across all
possible defects. Discovery statuses remain NEEDS_REVIEW, not verified guideline
violations. Two additional empty location purpose strings in the generated React
Native templates remain recorded separately. KMP HealthKit is a source signal;
unsigned simulator output does not prove a distribution entitlement or unused access.

All ten cases have before/after source and runner snapshots, full artifact rehashes,
configuration binding and owned-device deletion records. An independent review
rehashed the completed evidence inventory with no mismatch. All ten owned simulators
were absent from an independent final inventory; all nine initial device IDs remained.
The current panel retains its whole-run before inventory. Older attempts with missing
whole-run inventory retain that limitation; the new inventory does not repair them.

## Flow evidence and limits

Nine transition packets retain actual start/action/postcondition evidence and a
separate replay result. Six selected UI attempts passed and seven stayed UNKNOWN.
All thirteen recorded flows remain UNRESOLVED: UI observations do not prove receipt,
entitlement, completed deletion or backend/operational outcomes. Flutter broken has
an empty flow packet and does not receive a flow PASS. Missing postconditions remain
gaps; no flow was declared complete merely because a button existed.

Useful Flutter/KMP accessibility nodes were observed. Dark Mode and Dynamic Type
checks are limited geometric observations. This panel does not cover a complete iPad,
offline/slow-network, permission grant/deny, HIG or accessibility matrix. There were
no signed distribution, physical-device, live store or independent test-backend
completion checks. Raw records and reference-app evidence remain private.

Historical failures remain recorded: SwiftUI installation SKIP, RN dependency-install
failure and deficient observation, Flutter source-binding/driver errors, and KMP
packaging/architecture failures. The log-only RN observation was disqualified as SKIP;
new live evidence replaced it without relabeling the old run. Earlier replay and the
current live provider observation are separate. No failed or slow sample was discarded.

## Timing gate

SwiftUI clean lifecycle samples in seconds were
`47, 74, 95, 90, 76, 74, 81, 76, 74, 73`: median **75.0 seconds**.
The historical **70.5 seconds**, interim **80.0 seconds**, and current measurement
include per-repeat reset/boot/install where performed. The unchanged **60-second
lifecycle gate fails**. Pure observation samples
`47, 31, 38, 43, 32, 33, 34, 35, 32, 32` have a **33.5-second** median and do not
satisfy that lifecycle gate.

Our heavy builds and full suite did not overlap the clean ten-repeat timing loop;
other user-owned simulator activity was present, so the whole host was not claimed
idle. Later validation work overlapped parts of the remaining panel. Expo retained
long wall-clock samples, including 503 seconds in a clean repeat; no cause was
established and those three-repeat cases do not replace the benchmark. Bounded
process waiting removes polling overhead without reducing observation windows or
fresh repetitions; these measurements do not establish a speed improvement.
