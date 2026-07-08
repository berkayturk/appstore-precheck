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
(Phases 0–2). This tier emits advisory `DYNAMIC-PASS:` / `DYNAMIC-FINDING:` lines, like Pierre
deep-review's `REVIEW-*` lines.

**Read-only:** read-only w.r.t. the user's project — the tier installs/launches onto a **disposable
simulator** only and never modifies the user's repo. Prefer a dedicated/disposable simulator device;
do not disturb the user's everyday simulator state; leave teardown to the user unless the tier
created the device itself.

**Not a guarantee:** a pre-submit local smoke signal — NOT a replacement for TestFlight, a crash
reporter, or real-device QA.

## Rules

- Advisory only: every check reports `DYNAMIC-PASS:` or `DYNAMIC-FINDING:` — never `FAIL`, never a
  verdict contribution.
- Evidence-based: cite a screenshot filename + what was observed. If a check cannot be driven (no
  paywall in this app, a UI selector can't be found, no permissions declared), report
  `DYNAMIC-PASS: … — not applicable` or `DYNAMIC-FINDING: … could not verify` — never invent a
  failure.
- All 6 checks, every run: report each as PASS / FINDING / not-applicable.
- Boot a disposable simulator, launch the supplied app, and tear down cleanly.
- Write Pierre's 2–3 sentence explanations in the user's conversation language.

## The 6 checks

| # | Guideline | Dynamic question |
|---|-----------|------------------|
| D1 | **2.1** | Does the app launch on a fresh simulator and stay foregrounded briefly without crashing / a crash alert? |
| D2 | **2.1** | Does it reach a real first screen (not stuck on a splash, a blank screen, or an error alert)? |
| D3 | **3.1.2** | If a paywall/subscription exists, does it render with price + trial/auto-renew/terms visible on-screen (not just present as strings)? |
| D4 | **5.1.1(ii)/(iii)** | For each permission with an `Info.plist` purpose string, does the OS prompt appear at the right moment and match the declared string? |
| D5 | **2.1** | For a login-gated app, is there a reachable guest/demo path, or do the declared review demo credentials actually log in? |
| D6 | **2.3.5** | Do live screenshots of key screens match the submitted marketing screenshots (features shown match the running build)? |

## Per-check procedure

The Maestro MCP tools are: `mcp__maestro__list_devices` (pick a booted simulator's `device_id`),
`mcp__maestro__run` (execute a declarative YAML flow — `launchApp`, `tapOn`, `assertVisible`, …),
`mcp__maestro__inspect_screen` (view hierarchy), `mcp__maestro__take_screenshot`, and
`mcp__maestro__cheat_sheet` (YAML command reference). Every local tool needs a `device_id` from
`list_devices` first. `xcrun simctl` is the fallback when Maestro is unavailable.

### D1 — Launch without crash
1. `mcp__maestro__list_devices` for a booted disposable simulator (boot one with
   `xcrun simctl boot` if needed); then `mcp__maestro__run` a flow that declares the `appId` and
   starts with `launchApp` (fallback: `xcrun simctl launch`).
2. Observe for a short window; if the app process disappears or a crash alert shows, `DYNAMIC-FINDING`.
3. `mcp__maestro__take_screenshot` at launch as evidence.

### D2 — Core screen reachable
1. After launch, inspect the first real screen (`mcp__maestro__inspect_screen` /
   `mcp__maestro__take_screenshot`).
2. Flag if stuck on a splash, blank, or an error/"something went wrong" state.

### D3 — Paywall renders
1. If a paywall exists (per the static scan / app structure), navigate to it with a
   `mcp__maestro__run` flow (`tapOn` steps; check `mcp__maestro__cheat_sheet` for selector syntax).
2. Confirm price + trial/auto-renew/cancel terms are visibly rendered; screenshot. Not applicable if no paywall.

### D4 — Permission prompt vs purpose string
1. For each `NS*UsageDescription` in `Info.plist`, trigger the feature that requests it.
2. Confirm the OS prompt appears at the right moment and its text matches the declared purpose string; screenshot.

### D5 — Demo / login path
1. For a login-gated app, look for a guest/demo entry, or enter the declared review demo credentials.
2. Confirm a reachable path to core features; `DYNAMIC-FINDING` if the only path is a wall with no working demo.

### D6 — Live UI vs marketing screenshots
1. Capture live screenshots of key screens.
2. Compare to the submitted marketing screenshots; flag features shown in marketing but absent in the running build.

## Output format

```
DYNAMIC-PASS: <guideline> — <one-line why it looks OK, with screenshot filename>
```
or
```
DYNAMIC-FINDING: <guideline> — <one-line concrete issue, with screenshot filename>
Pierre: <2–3 sentences: why Apple cares, what you saw, what to fix or verify>
```

End with a summary table: 6 checks → count of `DYNAMIC-FINDING` vs `DYNAMIC-PASS` (note any not-applicable).
