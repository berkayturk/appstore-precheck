# Local dynamic simulator tier (agent-mode, opt-in, non-blocking)

The fourth, opt-in tier: a **local dynamic** review that runs the app on a simulator and observes
real behavior — the class of checks a static scan cannot make (does it launch without crashing, does
the paywall actually render, does a permission prompt match its purpose string, does a demo login
work, does the live UI match the marketing screenshots). It is the free/local alternative to a paid
cloud device farm, built from `xcrun simctl` + Maestro MCP tools (`mcp__maestro__*`) already
available on a Mac with Xcode.

**Identity:** runs ONLY in agent-skill mode, ONLY when the user explicitly asks for it and supplies a
built app (or a booted simulator UDID + bundle id). It is NOT part of the offline CLI / npx /
GitHub-Action scan, and it never runs by default. Requires macOS + Xcode + a simulator runtime; it
cannot run in this project's `ubuntu-latest` CI and is permanently local-only.

**This tier never changes the verdict.** GREEN/YELLOW/RED comes only from the static scan counts
(Phases 0–2). This tier emits advisory `DYNAMIC-PASS:` / `DYNAMIC-FINDING:` / `DYNAMIC-SKIP:` lines,
like Pierre deep-review's `REVIEW-*` lines.

**No-write, but it executes your application code.** The tier never modifies the user's repo,
and it **creates its own throwaway device** (`xcrun simctl create`, a unique name), erases it before
use, deletes it after, and **never touches an existing device**: the user's everyday simulators,
their data and their installed apps are never booted, erased or written to by this tier. But
unlike Phases 0–5 it is not read-only: it *runs the app you built*, and running code has effects
the static scan never has. Say so before the first launch:
- **Network:** the app talks to whatever backends it is configured for. A Debug build may point
  at staging; a Release build may hit production and leave real traffic, analytics events or
  crash reports behind. The tier does not intercept or block network access.
- **Credentials:** D5 types the review demo credentials the user declared into the running app.
  Those go wherever the app sends them. Never type credentials the user did not supply for this
  purpose, and never paste secrets from the repo or the environment.
- **Screenshots** are written to a temp directory outside the repo and named in the transcript.
  They can contain user data the app renders (an account email, a demo profile); the agent
  shows them to the user and never uploads them anywhere. Mask or skip a screenshot that shows
  a secret the user did not intend to expose.

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
  install or launch that failed, a driver timeout: all `DYNAMIC-SKIP: <guideline> — <why>`. "Not
  applicable" is also a SKIP (`DYNAMIC-SKIP: … — not applicable: <why>`), so the summary never
  counts an unobserved behaviour as observed.
- All 7 checks (D1–D6 + D3b), every run: report each as PASS / FINDING / SKIP, each with its rule id.
- D0 runs first; if it fails, every D-check is reported as `DYNAMIC-SKIP` with the D0 reason.
- Create a throwaway simulator, install and launch the supplied app, and tear down (delete the
  device you created) even when a check fails.
- Write Pierre's 2–3 sentence explanations in the user's conversation language.

## The checks (D0 setup + 7 observations)

| # | rule id | Guideline | Dynamic question |
|---|---------|-----------|------------------|
| D0 | `dyn-install` | — | *(setup, not a check)* Create a throwaway device, install the `.app`, resolve the bundle id. |
| D1 | `dyn-launch` | **2.1** | Does the app launch on a fresh simulator and stay foregrounded briefly without crashing / a crash alert? (four signals, below) |
| D2 | `dyn-first-screen` | **2.1** | Does it reach a real first screen (not stuck on a splash, a blank screen, or an error alert)? |
| D3 | `dyn-paywall-visible` | **3.1.2** | If a paywall/subscription exists **and prices are visible**, does it render price + trial/auto-renew/terms on-screen (not just present as strings)? |
| D3b | `dyn-restore-tap` | **3.1.2** | Does tapping *Restore Purchases* produce a non-inert response within 3 s (alert, spinner, tree change)? |
| D4 | `dyn-permission-prompt[:KEY]` | **5.1.1(ii)/(iii)** | For each permission with an `Info.plist` purpose string, does the OS prompt appear at the right moment and match the declared string? One line per key. |
| D5 | `dyn-demo-login` | **2.1** | For a login-gated app, is there a reachable guest/demo path, or do the declared review demo credentials actually log in? |
| D6 | `dyn-screenshot-parity` | **2.3.5** | Do live screenshots of key screens match the submitted marketing screenshots (features shown match the running build)? |

When the tier is **not run** (the user supplied no `.app` and no UDID), Phase 5's "Not audited"
section lists the gap under its stable id **`runtime-not-audited`** — `dynamic.sh --not-run`
emits that SKIP record with the number of unobserved checks derived from its catalogue, and a
team can acknowledge it by id in `.precheck-ignore` (signing for a gap never closes it).

## Per-check procedure

The Maestro MCP tools are: `mcp__maestro__list_devices` (pick a booted simulator's `device_id`),
`mcp__maestro__run` (execute a declarative YAML flow — `launchApp`, `tapOn`, `assertVisible`, …),
`mcp__maestro__inspect_screen` (view hierarchy), `mcp__maestro__take_screenshot`, and
`mcp__maestro__cheat_sheet` (YAML command reference). Every local tool needs a `device_id` from
`list_devices` first. `xcrun simctl` is the fallback when Maestro is unavailable.

### D0 — Device + install (setup)

The `.app`-path branch is only driveable once the app is on a device; nothing else in this tier
installs it.

1. Create a throwaway device and boot it:
   `xcrun simctl create "precheck-<timestamp>" <device-type> <runtime>` → note the UDID;
   `xcrun simctl boot <udid>` then `xcrun simctl bootstatus <udid> -b`. Never reuse a UDID the tier
   did not create. If the user supplied a booted UDID + bundle id instead of an `.app`, they own that
   device: use it only for launching, never erase it, and skip the install.
2. Read the bundle id from the built app, never guess it:
   `plutil -extract CFBundleIdentifier raw -o - <path>.app/Info.plist`. An `.app` without an
   `Info.plist` or without `CFBundleIdentifier` is not installable → `DYNAMIC-SKIP` (all checks).
3. Install: `xcrun simctl install <udid> <path>.app`. A non-zero exit (wrong architecture, a
   device build instead of a simulator build, a corrupt bundle) → `DYNAMIC-SKIP` for every
   D-check, quoting the simctl error; do not fall through to D1.
4. Note whether the `.app` came from a `Debug-iphonesimulator` or `Release-iphonesimulator`
   directory; say so in the summary. A Debug build observed on a simulator does not establish what
   the shipping archive does.
5. Teardown, always, at the end of the run: `xcrun simctl shutdown <udid>` then
   `xcrun simctl delete <udid>` — only for the device this tier created.

### D1 — Launch without crash (`dyn-launch`)

Launch health is a **conjunction of four signals**, not one. Read all four; a FINDING needs a
positive failure signal, and a signal that could not be read is written into the line as such —
never assumed healthy, never assumed failed.

1. `mcp__maestro__list_devices` and pick the device D0 created; then `mcp__maestro__run` a flow
   that declares the `appId` (the bundle id from D0) and starts with `launchApp` (fallback:
   `xcrun simctl launch <udid> <bundle-id>`).
2. Observe for a short window (about 10 s) and collect:
   - **process alive:** the app's process is still running at the end of the window;
   - **screenshot not uniform:** `mcp__maestro__take_screenshot` is not a single flat colour
     (a black or white full-frame image is a hung splash or a dead process);
   - **no crash in the log stream:** no crash / `SIGABRT` / `EXC_BAD_ACCESS` line for the bundle
     id in `xcrun simctl spawn <udid> log stream --style compact` during the window;
   - **accessibility tree ≥ N nodes:** `mcp__maestro__inspect_screen` returns more than a handful
     of nodes. **Degenerate tree caveat:** Flutter and Compose Multiplatform apps return an empty
     or single-node tree on a perfectly healthy screen, so a small tree on its own is **never** a
     FINDING; it only counts when another signal also fails.
3. Verdict: process gone, crash alert, or a crash line → `DYNAMIC-FINDING`; every readable signal
   healthy → `DYNAMIC-PASS`; a signal that **could not be read** (no log access, screenshot tool
   failed) is named in the line, e.g. `… (log stream could not be read)`. If nothing could be read,
   `DYNAMIC-SKIP`.
4. `mcp__maestro__take_screenshot` at launch as evidence.

### D2 — Core screen reachable (`dyn-first-screen`)
1. After launch, inspect the first real screen (`mcp__maestro__inspect_screen` /
   `mcp__maestro__take_screenshot`).
2. Flag if stuck on a splash, blank, or an error/"something went wrong" state. The same
   degenerate-tree caveat as D1 applies: judge Flutter/Compose screens by the screenshot, not the
   tree.

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
   control found`.
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

### D5 — Demo / login path (`dyn-demo-login`)
1. For a login-gated app, look for a guest/demo entry, or enter the declared review demo credentials.
2. Confirm a reachable path to core features; `DYNAMIC-FINDING` if the only path is a wall with no
   working demo. Not login-gated → `DYNAMIC-SKIP: 2.1 — not applicable`.

### D6 — Live UI vs marketing screenshots (`dyn-screenshot-parity`)
1. Capture live screenshots of key screens.
2. Compare to the submitted marketing screenshots; flag features shown in marketing but absent in
   the running build. No marketing screenshots in the repo → `DYNAMIC-SKIP`.

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
<bundle id> from <Debug|Release>-iphonesimulator/<App>.app`. Only column-0 lines are observations;
`Pierre:` lines and any indented text are commentary.

End with a summary table: 7 checks → count of `DYNAMIC-FINDING` vs `DYNAMIC-PASS` vs
`DYNAMIC-SKIP`, plus the D0 line (device created, bundle id, Debug/Release directory, install
result). A SKIP is listed under "Not audited" in Phase 5, next to the static `SKIP:` lines.

## Feeding the transcript to dynamic.sh

Save the transcript (the DYNAMIC-* lines, commentary included) to a temp file outside the repo and
run:

```bash
bash skills/appstore-precheck/scripts/dynamic.sh \
  --transcript /tmp/precheck-dynamic.txt \
  --findings   /tmp/precheck-static.json \        # scan.sh --format json output
  --target simulator --build-config release        # or debug / unknown (the default)
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

`--build-config` is what D0 read from the `.app`'s parent directory. If you do not know, leave it
`unknown`: it is treated exactly like `debug`, and nothing static is resolved on its account.
`dynamic.sh --not-run --findings <static.json>` produces the `runtime-not-audited` gap record for a
run where the tier was not used.
