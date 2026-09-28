# Local dynamic scorecard

Run date: 2026-09-27 (UTC). macOS 27.0, Xcode 27.0 (27A266a),
iOS Simulator 26.5 (23F77), Maestro 2.8.0. Isolated toolchains include
Flutter 3.47.5, Gradle 9.1.0 and Kotlin Native 2.2.20; official distribution
checksums were verified. These are synthetic corpus simulator observations.

The panel builds temporary copies, checks source/artifact identity, creates its own
simulators and deletes them. Launch repetitions retain a five-second observation
window and fresh environments. Discovery results request review; they are not
whole-guideline decisions. Regenerate with
`bash tests/local/dynamic-panel.sh --out /tmp/precheck-verification-panel-new`.
Use an empty output directory; stale case outputs are refused.

| Framework | Clean | Broken | Scope |
|---|---|---|---|
| SwiftUI | Release; launch and first screen 10/10 PASS | Release; deterministic crash 3/3 FINDING | Initial frozen panel |
| React Native bare | Release; fresh launch/first screen 3/3 PASS | Release; fresh launch/first screen 3/3 PASS; 4/4 expected discovery statuses | Exact source-bound artifacts reused for new runtime; unfamiliar provider observed live, separately from earlier replay |
| Expo | Release; launch/first screen 3/3 PASS | Release; launch/first screen 3/3 PASS; 3/3 discovery statuses | Shipped camera purpose present in clean and absent in broken |
| Flutter | Debug; new source-bound build; launch/first screen 3/3 PASS | Debug; new build and fresh launch/first screen 3/3 PASS; 1/1 discovery status | Simulator Debug only |
| Kotlin Multiplatform | ARM64 Release; launch/first screen 3/3 PASS | ARM64 Release; launch/first screen 3/3 PASS; 1/1 discovery status | Static Shared archive; corrected artifacts reused for fresh runtime |

The selected ten cases matched all ten expected launch outcomes: zero launch false
positives, misses or mixed results. Nine of nine expected discovery statuses matched.
These denominators are scoped to manifest expectations; they are not a measure of
all possible defects. Two additional empty location purpose strings in generated
React Native templates remain recorded outside the launch metric. KMP HealthKit
is a source signal; unsigned simulator output does not prove distribution entitlement
or whether the capability is unused.

All selected artifacts were rehashed against build provenance. Source binding was
valid for all ten; final six cases have case-local source/runner snapshots. Initial
SwiftUI and Expo records retain their older frozen batch identity, not a fabricated
new per-case collector history. Thirteen owned runs, including failed attempts,
matched deletion ledgers and were absent from the final simulator inventory. The
initial whole-batch before inventory was not retained, limiting broader device-state
claims. Raw application/device records remain private.

Initial failures remain part of the record: SwiftUI installation SKIP, an unexplained
RN dependency-install failure, a deficient RN launch observation, Flutter source-binding
failures and KMP packaging/architecture build failures. A later Flutter driver error
was rerun in a new directory after the Bash 3 empty-array fix. Its earlier ERROR was
not relabeled successful. The deficient RN observation had only a clean log and no
positive app signal; the corrected evaluator returns SKIP. A fresh live run then
provided complete observations. No failed or slow samples were silently discarded.

Selected restore/UGC/login UI transitions retain hashed start/action/postcondition
records. Receipt, entitlement and backend completion remain UNRESOLVED. Observed
Flutter/KMP accessibility trees had useful nodes; dedicated selector checks that were
not executed remain SKIP. No framework-wide absence of accessibility is assumed.

## Timing gate

SwiftUI clean lifecycle samples in seconds were
`47, 101, 83, 72, 67, 71, 93, 98, 82, 78`: median **80.0 seconds**.
The historical **70.5 seconds** and this measurement both include repeat
reset/boot/install where performed. The unchanged **60-second gate fails**.
Pure observation samples `47, 41, 29, 29, 26, 31, 32, 47, 37, 34` have a
33-second median and do not satisfy that lifecycle gate. Early samples overlapped
SDK preparation and suite completion; all samples are retained. Bounded process
waiting removes polling overhead without reducing windows or fresh repetitions;
this experiment does not demonstrate a speed improvement.

These runs do not establish signed distribution, physical-device, live store,
production-backend or full App Review compliance. Reference-app evidence and its
remaining developer inputs are maintained privately, outside this public scorecard.
