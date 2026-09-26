# Local dynamic simulator tier (agent-mode, opt-in, non-blocking)

The fourth, opt-in tier: a **local dynamic** review that runs the app on a simulator and observes
real behavior — the class of checks a static scan cannot make (does it launch without crashing, does
the paywall actually render, does a permission prompt match its purpose string, does a demo login
work, does the live UI match the marketing screenshots, does the layout survive dark mode and the
largest Dynamic Type size, what did the *installed* bundle actually ship, which hosts did it talk
to). It is the free/local alternative to a paid cloud device farm, built from `xcrun simctl` +
Maestro (the MCP tools `mcp__maestro__*` for the agent-driven checks, the `maestro` CLI for the
runner's hierarchy reads) already available on a Mac with Xcode.

**Identity:** runs ONLY in agent-skill mode, ONLY when the user explicitly asks for it and supplies a
built app (or a booted simulator UDID + bundle id). It is NOT part of the offline CLI / npx /
GitHub-Action scan, and it never runs by default. Requires macOS + Xcode + a simulator runtime; it
cannot run in this project's `ubuntu-latest` CI and is permanently local-only.

**This tier never changes the verdict.** GREEN/YELLOW/RED comes only from the static scan counts
(Phases 0–2). This tier emits advisory `DYNAMIC-PASS:` / `DYNAMIC-FINDING:` / `DYNAMIC-SKIP:` lines,
like Pierre deep-review's `REVIEW-*` lines.

**No-write, but it executes your application code.** The tier never modifies the user's repo,
and it **creates its own throwaway device** (`xcrun simctl create`, a unique name), erases it before
each repeat, deletes it after, and **never touches an existing device**: the user's everyday
simulators, their data and their installed apps are never booted, erased or written to by this tier.
But unlike Phases 0–5 it is not read-only: it *runs the app you built*, and running code has effects
the static scan never has. Say so before the first launch:
- **Network:** the app talks to whatever backends it is configured for. A Debug build may point
  at staging; a Release build may hit production and leave real traffic, analytics events or
  crash reports behind. The tier does not intercept or block network access (it *observes* hosts,
  D11).
- **Credentials:** D5 types the review demo credentials the user declared into the running app.
  Those go wherever the app sends them. Never type credentials the user did not supply for this
  purpose, and never paste secrets from the repo or the environment.
- **Screenshots** are written to a temp directory outside the repo and named in the transcript.
  They can contain user data the app renders (an account email, a demo profile); the agent
  shows them to the user and never uploads them anywhere. Mask or skip a screenshot that shows
  a secret the user did not intend to expose.

**It never builds.** No `xcodebuild`, `flutter build`, `gradle` — ever. The `.app` must already
exist. [`scripts/app-discover.sh`](../scripts/app-discover.sh) lists the simulator apps the user
already built (DerivedData, `build/ios/iphonesimulator`), with their **build time**, their
**configuration read from the directory name** (`Debug-iphonesimulator` → `debug`,
`Release-iphonesimulator` → `release`, anything else → `unknown`) and their bundle id, and
recommends the newest. **Obtain the user's explicit confirmation of one candidate before installing
or launching anything.** If nothing is found, the report carries the `runtime-not-audited` gap
record and the discovery output prints the build command **for the user to run** — this tool will
not run it.

**Machine-readable:** every observation line carries a **rule id** (`[dyn-…]`, table below) so
[`scripts/dynamic.sh`](../scripts/dynamic.sh) can turn the transcript into the same JSONL records
the static scan writes (`evidence: runtime`, plus `runtime_target` and `build_config`) and
reconcile them with the static findings. A runtime observation of a **Debug or unknown build never
clears `needs build verification`** (simulator ≠ archive). See "Feeding the transcript to
dynamic.sh" at the end.

**Not a guarantee:** a pre-submit local smoke signal — NOT a replacement for TestFlight, a crash
reporter, or real-device QA.

## Rules

- Advisory only: every check reports `DYNAMIC-PASS:`, `DYNAMIC-FINDING:` or `DYNAMIC-SKIP:` — never
  `FAIL`, never a verdict contribution.
- Evidence-based: cite a screenshot filename + what was observed.
- **A check that could not be driven is a `DYNAMIC-SKIP`, never a PASS and never an invented
  FINDING.** No paywall in this app, a UI selector that cannot be found, no permissions declared, an
  install or launch that failed, **a Maestro driver timeout**: all `DYNAMIC-SKIP: <guideline> — <why>`.
  "Not applicable" is also a SKIP (`DYNAMIC-SKIP: … — not applicable: <why>`), so the summary never
  counts an unobserved behaviour as observed.
- **Determinism before findings.** The launch checks run **N=3 times**, each on a freshly erased
  device; a `DYNAMIC-FINDING` for a crash needs **3/3**. A mixed result is a FINDING that carries its
  ratio (`quorum 1/3: failed on 1 of 3 launches (not unanimous; advisory, never blocking)`) — the
  Phase 3 blocking channel reads that ratio and never blocks on it.
- **One flow per Maestro invocation.** The iOS 26 driver misbehaves in batch mode (Maestro issues
  #3254 / #3318): every `mcp__maestro__run` call carries exactly one flow; the runner reads the
  hierarchy with one `maestro hierarchy` call at a time.
- **Labels live in `accessibilityText`.** In the Maestro hierarchy JSON the label a control exposes
  is the `accessibilityText` attribute, not `text` — every matcher (Restore button, demo login
  fields, geometry heuristics) reads it.
- Every check, every run: report each as PASS / FINDING / SKIP, each with its rule id.
- D0 runs first; if it fails, every D-check is reported as `DYNAMIC-SKIP` with the D0 reason.
- Create a throwaway simulator, install and launch the supplied app, and tear down (delete the
  device you created) even when a check fails.
- Write Pierre's 2–3 sentence explanations in the user's conversation language.

## The checks (D0 setup + observations)

Two kinds. **Observation-based** checks need no UI selector and are produced by
[`scripts/dynamic-run.sh`](../scripts/dynamic-run.sh) (D0, D1, D2, D7–D11). **Selector-based**
checks need Maestro to find and tap controls and stay with the agent (D3, D3b, D4, D5, D6).

| # | rule id | Guideline | Kind | Dynamic question |
|---|---------|-----------|------|------------------|
| D0 | `dyn-install` | — | setup | Create a throwaway device, install the `.app`, resolve the bundle id, record the build configuration from the directory name. |
| D1 | `dyn-launch` | **2.1** | observation | Does the app launch and stay up? Four signals per repeat, N=3 repeats, FINDING only on 3/3. |
| D2 | `dyn-first-screen` | **2.1** | observation | Does it reach a real first screen (not a flat splash, blank, or dead process)? |
| D3 | `dyn-paywall-visible` | **3.1.2** | selector | If a paywall exists **and prices are visible**, does it render price + trial/auto-renew/terms on-screen? |
| D3b | `dyn-restore-tap` | **3.1.2** | selector | Does tapping *Restore Purchases* produce a non-inert response within 3 s? |
| D4 | `dyn-permission-prompt[:KEY]` | **5.1.1(ii)/(iii)** | selector (trigger) | For each purpose string, does the OS prompt appear at the right moment with the declared text? One line per key. |
| D5 | `dyn-demo-login` | **2.1** | selector | For a login-gated app, is there a guest/demo path, or do the declared demo credentials log in? |
| D6 | `dyn-screenshot-parity` | **2.3.5** | observation (human) | Do live screenshots of key screens match the submitted marketing screenshots? |
| D7 | `dyn-dark-mode` | **4.0** | observation | Under `simctl ui appearance dark`: any clipped, zero-size or overlapping labelled frame? |
| D8 | `dyn-dynamic-type` | **4.0** | observation | At `content_size accessibility-extra-extra-extra-large`: the same heuristics. |
| D9 | `dyn-ipad-layout` | **2.4.1** | observation (opt-in `--ipad`) | On an iPad simulator this run creates: the same heuristics; iPhone-only apps are `not applicable`. |
| D10 | `dyn-shipped-bundle[:KEY]` / `dyn-shipped-sdk` / `dyn-shipped-links` | **5.1.1 / 5.1.2 / 2.1 / 2.5.1** | observation (nothing executed) | The **installed** bundle: `Info.plist` purpose strings (one line per key) and drift vs the repo plist; `DTXcode` / `DTSDKName` (the toolchain that built *this* bundle); `otool -L` private-framework links. |
| D11 | `dyn-hosts-contacted` | **5.1.2** | observation | Hosts seen in CFNetwork diagnostics (opt-in `--pktap` adds DNS for every process) vs `NSPrivacyTrackingDomains`. |

When the tier is **not run** (the user supplied no `.app` and no UDID), Phase 5's "Not audited"
section lists the gap under its stable id **`runtime-not-audited`** — `dynamic.sh --not-run`
emits that SKIP record with the number of unobserved checks derived from its catalogue, and a
team can acknowledge it by id in `.precheck-ignore` (signing for a gap never closes it).

### Framework awareness

[`scripts/framework-detect.sh`](../scripts/framework-detect.sh) decides `rn` / `flutter` / `kmp` /
`native` from file presence alone (`package.json` with a `react-native` dependency; `pubspec.yaml`
+ `ios/Runner.xcodeproj`; a Gradle build or `.kt` sources + `iosApp/`). The static scan uses it to
publish the `framework-not-audited` gap record (its code-level greps read Swift/ObjC only, so they
under-detect on those toolkits). This tier uses it for two things:

| Framework | Launch precondition | Selector-based checks | Observation-based checks |
|---|---|---|---|
| native | — | agent-driven | run |
| rn | A Debug `.app` without an embedded `main.jsbundle` needs **Metro on port 8081**. If Metro is not listening, D1/D2 are `DYNAMIC-SKIP: 2.1 [dyn-launch] — Metro bundler not running …` — otherwise every RN app "crashes on launch" for a reason that is not the app's. | agent-driven | run |
| flutter, kmp (Compose Multiplatform) | — | **SKIPped up front**: `dyn-restore-tap`, `dyn-demo-login` and the trigger half of `dyn-permission-prompt` are `DYNAMIC-SKIP … no accessibility semantics exposed to Maestro` (the tree is empty or single-node on a healthy screen). D3 and D6 can still be judged from screenshots. | pre-SKIP | run — but a degenerate tree is never a failure signal on its own, and D7–D9 are SKIP when the tree is degenerate (judge the screenshot by eye) |

## Per-check procedure

The Maestro MCP tools are: `mcp__maestro__list_devices` (pick the device D0 created), `mcp__maestro__run`
(execute ONE declarative YAML flow — `launchApp`, `tapOn`, `assertVisible`, …),
`mcp__maestro__inspect_screen` (view hierarchy), `mcp__maestro__take_screenshot`, and
`mcp__maestro__cheat_sheet` (YAML command reference). `xcrun simctl` is the fallback when Maestro is
unavailable.

### D0 — Device + install (setup)

The `.app`-path branch is only driveable once the app is on a device; nothing else in this tier
installs it. `dynamic-run.sh` does all of this; the steps are listed so the agent can do the same by
hand with `xcrun simctl` when it drives the selector-based checks.

1. Create a throwaway device and boot it:
   `xcrun simctl create "precheck-<timestamp>-<pid>" <device-type> <runtime>` → note the UDID;
   `xcrun simctl boot <udid>` then `xcrun simctl bootstatus <udid> -b`. Never reuse a UDID the tier
   did not create. If the user supplied a booted UDID + bundle id instead of an `.app`, they own that
   device: use it only for launching — never erase it, never `privacy reset` it, never delete it —
   and skip the install (the repeats are then less deterministic, and the line says so).
2. Make the device deterministic: `xcrun simctl status_bar <udid> override --time 9:41
   --batteryLevel 100 --batteryState charged --wifiBars 3 --cellularBars 4`, then
   `xcrun simctl privacy <udid> reset all`. (`simctl privacy` cannot touch camera, notifications,
   Bluetooth, HealthKit or ATT; for ATT the only reset is uninstall + reinstall, which the erase
   between repeats provides.)
3. Read the bundle id from the built app, never guess it:
   `plutil -extract CFBundleIdentifier raw -o - <path>.app/Info.plist`. An `.app` without an
   `Info.plist` or without `CFBundleIdentifier` is not installable → `DYNAMIC-SKIP` (all checks).
4. Install: `xcrun simctl install <udid> <path>.app`. A non-zero exit (wrong architecture, a
   device build instead of a simulator build, a corrupt bundle) → `DYNAMIC-SKIP` for every
   D-check, quoting the simctl error; do not fall through to D1.
5. Record whether the `.app` came from a `Debug-iphonesimulator` or `Release-iphonesimulator`
   directory in the D0 line itself (`dynamic.sh` cross-checks `--build-config` against it). A Debug
   build observed on a simulator does not establish what the shipping archive does.
6. Observers: start `xcrun simctl spawn <udid> log stream --style compact --predicate 'process ==
   "<Executable>" …' > log.txt &` BEFORE each launch, and launch with
   `SIMCTL_CHILD_CFNETWORK_DIAGNOSTICS=3 xcrun simctl launch --terminate-running-process <udid>
   <bundle-id>` so the same log carries the hosts for D11. (`xcrun simctl io <udid> recordVideo`
   is optional and off by default.)
7. Between repeats: `xcrun simctl shutdown <udid>`, `xcrun simctl erase <udid>`, boot, step 2,
   install again — a fresh erase every time, only on the device this run created.
8. Teardown, always, at the end of the run: `xcrun simctl shutdown <udid>` then
   `xcrun simctl delete <udid>` — only for the device this tier created.

### D1 — Launch without crash (`dyn-launch`)

Launch health is a **conjunction of four signals**, not one, read after an observation window
(default 10 s) on every repeat. A FINDING needs a positive failure signal, and a signal that could
not be read is written into the line as such — never assumed healthy, never assumed failed.

- **process alive:** `kill -0` on the PID `simctl launch` printed (simulator apps are host
  processes);
- **screenshot not uniform:** `xcrun simctl io <udid> screenshot` decoded by
  [`lib/png-uniform.py`](../scripts/lib/png-uniform.py): a single flat colour is a hung splash or a
  dead process;
- **no crash in the log stream:** no `SIGABRT` / `EXC_BAD_ACCESS` / `Terminating app` / `Fatal
  error` line for the app in the window, and no new `<Executable>-*.ips` in
  `~/Library/Logs/DiagnosticReports`;
- **accessibility tree ≥ N nodes:** `maestro --device <udid> hierarchy` (one call). **Degenerate
  tree caveat:** Flutter and Compose Multiplatform apps return an empty or single-node tree on a
  perfectly healthy screen, so a small tree on its own is **never** a FINDING; it only counts when
  another signal also fails.

Per repeat: process gone, a crash line, or a flat screenshot → failed; every readable signal
healthy → passed; nothing readable → skipped. Across the N=3 repeats
([`lib/dyn-quorum.sh`](../scripts/lib/dyn-quorum.sh)): every repeat failed → `DYNAMIC-FINDING …
quorum 3/3`; some failed → `DYNAMIC-FINDING … quorum k/3 … (not unanimous; advisory, never
blocking)`; every repeat skipped (driver timeouts) → `DYNAMIC-SKIP`; otherwise `DYNAMIC-PASS`
naming the signals and, in parentheses, the ones that could not be read.

### D2 — Core screen reachable (`dyn-first-screen`)
Derived from the same repeats: a non-uniform screenshot with the process alive at the end of the
window is a real first screen; a flat frame or a dead process is not. Same quorum. The
degenerate-tree caveat applies: judge Flutter/Compose screens by the screenshot, not the tree.

### D3 — Paywall renders (`dyn-paywall-visible`)

**Precondition, verified 2026-09-01:** a StoreKit configuration file is a *scheme Run-action*
setting applied by Xcode. `xcrun simctl launch` (and a Maestro `launchApp`) does not apply it, so
`Product.products(for:)` returns an empty array and a paywall with **no prices is the expected
default** for an app launched by this tier. An empty or price-less paywall is therefore never
evidence of a 3.1.2 problem here.

1. If a paywall exists (per the static scan / app structure), navigate to it with a
   `mcp__maestro__run` flow (`tapOn` steps; check `mcp__maestro__cheat_sheet` for selector syntax).
   No paywall → `DYNAMIC-SKIP: 3.1.2 — not applicable: no paywall in this app`.
2. Look for a rendered price (a currency amount) on the paywall screen.
   - **No price visible** → `DYNAMIC-SKIP: 3.1.2 — StoreKit products are not loaded under simctl
     launch; paywall prices cannot be observed on a local simulator. Launch the app from Xcode with
     a StoreKit configuration selected in the scheme to observe them.` Never a FINDING.
   - **Price visible** (the user launched from Xcode with a StoreKit configuration, or the app
     loads prices from its own backend) → run the check: confirm price + trial/auto-renew/cancel
     terms are visibly rendered; screenshot; `DYNAMIC-PASS` or `DYNAMIC-FINDING`.

### D3b — Restore Purchases responds (`dyn-restore-tap`)

Static §10 can only see that a "Restore Purchases" string exists. This checks that the control
does something.

1. On the paywall (or settings) screen, find the Restore control by **`accessibilityText`** in
   the `mcp__maestro__inspect_screen` hierarchy — that is the field Maestro exposes the label in,
   not `text`. No such control → `DYNAMIC-SKIP: 3.1.2 [dyn-restore-tap] — no Restore Purchases
   control found`. On Flutter / KMP this is pre-SKIPped (no semantics).
2. `tapOn` it and wait up to 3 s for a **non-inert response**: an alert, a spinner / progress
   indicator, or any change in the accessibility tree or screenshot.
3. A response → `DYNAMIC-PASS`. No visible reaction at all within 3 s → `DYNAMIC-FINDING` (a
   dead Restore button is a 3.1.2 rejection). StoreKit products are not loaded under `simctl
   launch`, so "restore found nothing" *with* an alert is still a PASS: the control works.

This is a **partial** test of §10 (`subscription-links-restore`), which also wants terms and
privacy links on the paywall — so a PASS here can downgrade a static FAIL to WARN but never
resolve it (see the reconciliation table in `dynamic.sh`).

### D4 — Permission prompt vs purpose string (`dyn-permission-prompt:<KEY>`)
1. For each `NS*UsageDescription` in `Info.plist`, trigger the feature that requests it.
2. Confirm the OS prompt appears at the right moment and its text matches the declared purpose
   string; screenshot. **One line per key**, with the key in the rule id
   (`[dyn-permission-prompt:NSCameraUsageDescription]`): that is what lets a PASS resolve the
   matching static §2 finding for that key. A permission whose trigger cannot be found →
   `DYNAMIC-SKIP` for that key. A keyless line (`[dyn-permission-prompt]`) is treated as partial.
   On Flutter / KMP the trigger half is pre-SKIPped; the OS prompt itself is native and visible in
   a screenshot if the agent reaches the feature by coordinates.

### D5 — Demo / login path (`dyn-demo-login`)
1. For a login-gated app, look for a guest/demo entry, or enter the declared review demo credentials.
2. Confirm a reachable path to core features; `DYNAMIC-FINDING` if the only path is a wall with no
   working demo. Not login-gated → `DYNAMIC-SKIP: 2.1 — not applicable`.

### D6 — Live UI vs marketing screenshots (`dyn-screenshot-parity`)
1. Capture live screenshots of key screens.
2. Compare to the submitted marketing screenshots; flag features shown in marketing but absent in
   the running build. No marketing screenshots in the repo → `DYNAMIC-SKIP`.

### D7 / D8 / D9 — Dark mode, Dynamic Type, iPad geometry (`dyn-dark-mode`, `dyn-dynamic-type`, `dyn-ipad-layout`)

After the last healthy repeat, `dynamic-run.sh` switches `xcrun simctl ui <udid> appearance dark`
(D7), then `content_size accessibility-extra-extra-extra-large` (D8), takes a screenshot and one
hierarchy read each, and applies three heuristics
([`lib/dyn-geometry.sh`](../scripts/lib/dyn-geometry.sh)) over the labelled nodes:

- **clipped** — a labelled frame that leaves the screen rectangle;
- **zero-size** — a labelled frame with an empty rectangle (text that cannot be seen);
- **overlap** — two labelled *leaf* frames overlapping by more than half of the smaller one.

Any hit → `DYNAMIC-FINDING: 4.0 [dyn-dynamic-type] — … 2 clipped, 1 zero-size, 0 overlapping
labelled frame(s) …` (judgment-call: a clipped frame is a hint, not a rejection); none →
`DYNAMIC-PASS`; a degenerate tree → `DYNAMIC-SKIP … judge the screenshot by eye`. Appearance and
text size are reset afterwards. D9 (`--ipad`) repeats the launch on an iPad simulator this run
creates (and deletes); an app whose `UIDeviceFamily` has no iPad entry is `not applicable`.

### D10 — The installed bundle (`dyn-shipped-bundle[:KEY]`, `dyn-shipped-sdk`, `dyn-shipped-links`)

`xcrun simctl get_app_container <udid> <bundle-id> app` gives the installed `.app`. Reading it
executes nothing and establishes what the repository could only promise
([`lib/dyn-bundle.sh`](../scripts/lib/dyn-bundle.sh)):

- one `DYNAMIC-PASS: 5.1.1 [dyn-shipped-bundle:<KEY>]` per `NS*UsageDescription` the installed
  `Info.plist` declares (a **complete** per-key test of the static purpose-string claim), a
  FINDING for an empty one, a FINDING for a key the repo plist has and the bundle lacks, and a
  keyless drift summary (which aims at no static rule);
- `dyn-shipped-sdk`: `DTXcode` / `DTSDKName` — the toolchain that built *this* bundle, which is
  what ITMS-90725 reads (complete for `xcode-sdk-requirement`);
- `dyn-shipped-links`: `otool -L` on the executable — a `/System/Library/PrivateFrameworks` link is
  decisive, its absence is only partial (private selectors are not linkage).

The **build configuration comes from the `.app`'s parent directory name, never from the plist**;
on a Debug/unknown build every one of these can only confirm or downgrade, never resolve.

### D11 — Hosts contacted (`dyn-hosts-contacted`)

Hosts are read from the CFNetwork diagnostics in the log stream across all repeats
([`lib/dyn-hosts.sh`](../scripts/lib/dyn-hosts.sh)) and compared with `NSPrivacyTrackingDomains` in
the installed `PrivacyInfo.xcprivacy`: a host that matches a known ad / attribution vendor and is
not declared → `DYNAMIC-FINDING: 5.1.2`; all declared → PASS; no vendor host → PASS listing the
hosts; nothing seen → SKIP. **Limit:** Flutter's Dart `HttpClient` (and some Go / Rust stacks)
bypass CFNetwork and are invisible here; the SKIP says so. Opt-in `--pktap` runs `sudo tcpdump -i
pktap,en0 -k P` for the duration and adds DNS-derived hosts for every process — off by default
because it needs sudo. The vendor→domain catalogue mirrors the §16 tracking-SDK list and is on the
quarterly review in MAINTENANCE.md.

## Output format

Every line carries the rule id in brackets, right after the guideline:

```
DYNAMIC-PASS: <guideline> [dyn-<check>] — <one-line why it looks OK, with screenshot filename>
```
or
```
DYNAMIC-FINDING: <guideline> [dyn-<check>] — <one-line concrete issue, with screenshot filename>
Pierre: <2–3 sentences: why Apple cares, what you saw, what to fix or verify>
```
or
```
DYNAMIC-SKIP: <guideline> [dyn-<check>] — <why this check could not be driven, or "not applicable: <why>">
```

D0 uses the guideline slot for `setup`: `DYNAMIC-PASS: setup [dyn-install] — installed
<bundle id> from <Debug|Release>-iphonesimulator/<App>.app on <device> (created by this run …)`.
Only column-0 lines are observations; `Pierre:` lines, `# …` notes and any indented text are
commentary.

End with a summary table: count of `DYNAMIC-FINDING` vs `DYNAMIC-PASS` vs `DYNAMIC-SKIP` over every
check, plus the D0 line (device created, bundle id, Debug/Release directory, install result). A
SKIP is listed under "Not audited" in Phase 5, next to the static `SKIP:` lines.

## Running it

```bash
# 1. find a build the user already made (never builds); the user confirms ONE candidate
bash skills/appstore-precheck/scripts/app-discover.sh --repo /path/to/app --json

# 2. the observation-based checks on a throwaway device (3 repeats, 10 s window)
bash skills/appstore-precheck/scripts/dynamic-run.sh --app <path>.app --repo /path/to/app --out /tmp/precheck-dyn
#    add --ipad for D9, --pktap (sudo) for DNS-based hosts, --dry-run to print the plan only

# 3. the selector-based checks (D3, D3b, D4, D5, D6) via Maestro MCP on the device the
#    runner used — or on a fresh one — appending DYNAMIC-* lines to the same transcript
```

`tests/local/run-dynamic.sh` chains discovery → confirmation → runner → `dynamic.sh` on macOS; it is
not part of `tests/all.sh`.
`run.json` records `d1_d2_seconds` for each launch/first-screen repeat. Later repeats include
device erase, boot, and reinstall time; the median describes this local workflow, not app startup.

## Feeding the transcript to dynamic.sh

Save the transcript (the DYNAMIC-* lines, commentary included) to a temp file outside the repo and
run:

```bash
bash skills/appstore-precheck/scripts/dynamic.sh \
  --transcript /tmp/precheck-dyn/transcript.txt \
  --findings   /tmp/precheck-static.json \        # scan.sh --format json output
  --target simulator --build-config debug          # from run.json / the directory name
```

It prints the same envelope as `scan.sh --format json`, with `summary.runtime`
(`observed` / `resolved` / `confirmed`) added and the records reconciled:

| static ↔ runtime | result |
|---|---|
| static FAIL/WARN, runtime **confirms** the violation | one record, `evidence: runtime`, severity unchanged; `needs_build_verification` re-derived for this build (false only on `release`) |
| runtime **contradicts**, dynamic check is the **complete** test | severity `RESOLVED`, `resolved_by: runtime` — inert: counted by nothing, verdict unchanged |
| runtime contradicts, check is **partial** (or the build is Debug/unknown and the claim depended on the build) | FAIL → WARN only, observation appended to the message, never PASS |
| static PASS, runtime FINDING | a new `WARN` record with `evidence: runtime`; the static PASS stays (it was true about the repo) |
| could not be driven | `SKIP`, no labels |

Complete / partial pairs: `demo-account ↔ dyn-demo-login`; `usage-description-crosscheck ↔
dyn-permission-prompt:<KEY>` and `↔ dyn-shipped-bundle:<KEY>` (per key; a keyless D4 line is
partial, a keyless D10 line aims at nothing); `att-usage ↔ dyn-shipped-bundle:NSUserTrackingUsageDescription`;
`xcode-sdk-requirement ↔ dyn-shipped-sdk`; partial: `subscription-links-restore ↔ dyn-restore-tap`,
`private-api ↔ dyn-shipped-links`.

`--build-config` is what D0 read from the `.app`'s parent directory. If you do not know, leave it
`unknown`: it is treated exactly like `debug`, and nothing static is resolved on its account. A
`release` claim over a transcript whose D0 line says `Debug-iphonesimulator` is degraded to
`unknown`, loudly. `dynamic.sh --not-run --findings <static.json>` produces the
`runtime-not-audited` gap record for a run where the tier was not used.
