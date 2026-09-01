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

**Read-only w.r.t. the user's project:** the tier never modifies the user's repo. It **creates its
own throwaway device** (`xcrun simctl create`, a unique name), erases it before use, deletes it after,
and **never touches an existing device**: the user's everyday simulators, their data and their
installed apps are never booted, erased or written to by this tier.

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
- All 6 checks, every run: report each as PASS / FINDING / SKIP.
- D0 runs first; if it fails, every D-check is reported as `DYNAMIC-SKIP` with the D0 reason.
- Create a throwaway simulator, install and launch the supplied app, and tear down (delete the
  device you created) even when a check fails.
- Write Pierre's 2–3 sentence explanations in the user's conversation language.

## The 6 checks

| # | Guideline | Dynamic question |
|---|-----------|------------------|
| D0 | — | *(setup, not a check)* Create a throwaway device, install the `.app`, resolve the bundle id. |
| D1 | **2.1** | Does the app launch on a fresh simulator and stay foregrounded briefly without crashing / a crash alert? |
| D2 | **2.1** | Does it reach a real first screen (not stuck on a splash, a blank screen, or an error alert)? |
| D3 | **3.1.2** | If a paywall/subscription exists **and prices are visible**, does it render price + trial/auto-renew/terms on-screen (not just present as strings)? |
| D4 | **5.1.1(ii)/(iii)** | For each permission with an `Info.plist` purpose string, does the OS prompt appear at the right moment and match the declared string? |
| D5 | **2.1** | For a login-gated app, is there a reachable guest/demo path, or do the declared review demo credentials actually log in? |
| D6 | **2.3.5** | Do live screenshots of key screens match the submitted marketing screenshots (features shown match the running build)? |

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

### D1 — Launch without crash
1. `mcp__maestro__list_devices` and pick the device D0 created; then `mcp__maestro__run` a flow
   that declares the `appId` (the bundle id from D0) and starts with `launchApp` (fallback:
   `xcrun simctl launch <udid> <bundle-id>`).
2. Observe for a short window; if the app process disappears or a crash alert shows, `DYNAMIC-FINDING`.
3. `mcp__maestro__take_screenshot` at launch as evidence.

### D2 — Core screen reachable
1. After launch, inspect the first real screen (`mcp__maestro__inspect_screen` /
   `mcp__maestro__take_screenshot`).
2. Flag if stuck on a splash, blank, or an error/"something went wrong" state.

### D3 — Paywall renders

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

### D4 — Permission prompt vs purpose string
1. For each `NS*UsageDescription` in `Info.plist`, trigger the feature that requests it.
2. Confirm the OS prompt appears at the right moment and its text matches the declared purpose
   string; screenshot. A permission whose trigger cannot be found → `DYNAMIC-SKIP` for that key.

### D5 — Demo / login path
1. For a login-gated app, look for a guest/demo entry, or enter the declared review demo credentials.
2. Confirm a reachable path to core features; `DYNAMIC-FINDING` if the only path is a wall with no
   working demo. Not login-gated → `DYNAMIC-SKIP: 2.1 — not applicable`.

### D6 — Live UI vs marketing screenshots
1. Capture live screenshots of key screens.
2. Compare to the submitted marketing screenshots; flag features shown in marketing but absent in
   the running build. No marketing screenshots in the repo → `DYNAMIC-SKIP`.

## Output format

```
DYNAMIC-PASS: <guideline> — <one-line why it looks OK, with screenshot filename>
```
or
```
DYNAMIC-FINDING: <guideline> — <one-line concrete issue, with screenshot filename>
Pierre: <2–3 sentences: why Apple cares, what you saw, what to fix or verify>
```
or
```
DYNAMIC-SKIP: <guideline> — <why this check could not be driven, or "not applicable: <why>">
```

End with a summary table: 6 checks → count of `DYNAMIC-FINDING` vs `DYNAMIC-PASS` vs `DYNAMIC-SKIP`,
plus the D0 line (device created, bundle id, Debug/Release directory, install result). A SKIP is
listed under "Not audited" in Phase 5, next to the static `SKIP:` lines.
