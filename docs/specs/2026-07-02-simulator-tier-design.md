# Local dynamic simulator tier (agent-mode)

**Roadmap:** #5 (local dynamic simulator tier). The last roadmap item. Agent-mode, opt-in, non-blocking — a pre-submit local smoke signal, not a TestFlight/QA replacement.

**Date:** 2026-07-02
**Target release:** v1.12.0 (bump at release, not in-branch)

## Problem

Every existing layer is **static**: `scan.sh` greps source/metadata, Pierre deep-review reads code
and fetched text, guideline-drift watches Apple's page. A class of real rejections requires the app
to actually **run** — most importantly 2.1 crashes (Apple's most common reject reason), and the
"does it actually render / behave" checks a static scan can't confirm (paywall renders, permission
prompt text matches the Info.plist purpose string, a login-gated app exposes a working demo path,
live UI matches submitted marketing screenshots).

This adds a **fourth, opt-in tier**: a local dynamic simulator review driven by Maestro MCP tools
(`mcp__maestro__*`) + `xcrun simctl`, the free/local answer to paid cloud device farms — built from
tools already on a Mac with Xcode, no new paid dependency, no uploading a build anywhere.

## Approach decision: agent-mode only (v1)

The scoping draft offered a hybrid (a deterministic `simulator-smoke.sh` + agent-mode narration).
**v1 is agent-mode only** (scoping Approach A), for three reasons:

1. The only nominally "deterministic" check — launch-crash detection — is precisely the part that is
   **flaky and timing-sensitive** on a simulator (boot time, first-launch warmup). Brittle bash
   thresholds around it are false-positive-prone, and false positives are uniquely damaging to a
   tool whose identity is low-false-positive.
2. A live simulator + UI judgment is exactly the "model-needing work lives in agent-mode" pattern
   the project already uses (Pierre deep-review, screenshot-vision Layer 2, guideline-drift Phase 0)
   — the host LLM, running against a real simulator, handles flakiness with judgment better than a
   fixed bash heuristic.
3. This project's CI is `ubuntu-latest` only; a deterministic simctl script could not be validated
   in CI, and shipping unvalidated dynamic-test code would violate the project's "verify, don't
   narrate" ethic.

A deterministic `scripts/simulator-smoke.sh` remains a **deferred future option**, worth revisiting
only if a macOS CI runner (to validate it) comes into scope. v1 ships the agent-mode reference tier.

## Resolved design decisions (scoping open questions)

1. **Verdict semantics: purely advisory (Option 1).** Dynamic findings are `DYNAMIC-PASS:` /
   `DYNAMIC-FINDING:` (advisory, WARN-in-tone) and **never** enter the FAIL/WARN counts `verdict.sh`
   uses. The GREEN/YELLOW/RED verdict stays a pure function of the offline static scan — a hard
   identity guarantee that a simulator-dependent result must not break. A crash produces a
   prominent advisory finding, not a verdict change. (A narrow crash→FAIL carve-out is explicitly
   deferred.)
2. **Getting a built app:** the tier attaches to what the user supplies — a booted simulator UDID +
   bundle id (already installed), or a built `.app` path the user hands it. It only ever touches
   **disposable simulator state**, never the user's repo. Documented as the READ-ONLY boundary:
   read-only w.r.t. project source, not w.r.t. the ephemeral simulator.
3. **MVP vs full tier:** the checklist covers launch/crash + paywall + permission + login/demo +
   live-screenshot. Authored per-app Maestro YAML flows (`run_flow_files` with app-specific
   selectors) are a deferred follow-up; v1 uses the host LLM driving the MCP tools opportunistically
   with graceful "could not verify" skips.
4. **Voice/positioning:** "local dynamic simulator tier"; Pierre narrates (no new persona — YAGNI).
5. **CI: permanently local-only,** documented. No CI job (CI is `ubuntu-latest`; no simulator there).

## Identity constraints (non-negotiable)

- **READ-ONLY w.r.t. the user's project.** The tier installs/launches onto a **disposable
  simulator** only; it never modifies the user's repo. Every doc that mentions the tier states this
  scoped caveat precisely so it never contradicts the core "never change code or assets" promise.
- **No competitor name** anywhere — frame as "the free/local alternative to a paid cloud device
  farm," never name one.
- **Offline CLI path untouched:** `scan.sh`, `bin/cli.js`, `action.yml`, `install.sh`, `verdict.sh`
  are UNCHANGED and byte-identical. The tier lives only in agent-skill mode, opt-in, never in the
  offline/npx/Action path.
- **Never changes the verdict** (advisory only).
- Version lockstep (bump at release).

## Components

### 1. `skills/appstore-precheck/references/simulator-dynamic-review.md`

A new reference doc modeled exactly on `references/pierre-deep-review.md` and
`references/screenshot-vision-review.md` (rules block → checklist table → per-check procedure →
output format). Content:

- **Identity/preamble:** agent-mode only (host LLM + Maestro MCP + `xcrun simctl`), opt-in, runs
  ONLY when the user explicitly requests it and supplies an app/booted simulator; NOT in the
  CLI/npx/Action path; **never changes the verdict**; a pre-submit local smoke signal, explicitly
  **not** a TestFlight / crash-reporter / QA replacement.
- **Read-only caveat:** touches disposable simulator state only, never the user's repo; prefer a
  dedicated/disposable simulator device, never disturb the user's everyday simulator state.
- **Rules:** advisory `DYNAMIC-PASS:` / `DYNAMIC-FINDING:` only; evidence = screenshot filename +
  what was observed; every check every run; when a check can't be driven (UI selector not found,
  no paywall in this app), report `DYNAMIC-PASS: … — not applicable`/`could not verify` rather than
  false-flagging; write Pierre's explanations in the user's language.
- **Checklist (6 checks):**
  - **D1 — 2.1 Launch without crash:** boot a disposable simulator, launch the app, confirm it
    stays foregrounded for a short window without the process disappearing / a crash alert.
  - **D2 — 2.1 Core screen reachable:** the app reaches a real first screen (not stuck on a splash,
    a blank screen, or an error/"something went wrong" alert).
  - **D3 — 3.1.2 Paywall renders:** if a paywall/subscription exists, navigate to it and confirm
    price + trial/auto-renew/terms are actually visible on-screen (not just present as strings).
  - **D4 — 5.1.1(ii)/(iii) Permission prompt vs purpose string:** trigger each permission that has
    an `Info.plist` purpose string; confirm the OS prompt appears at the right moment and its text
    matches the declared purpose string.
  - **D5 — 2.1 Demo/login path:** for a login-gated app, confirm a reachable guest/demo path OR that
    the declared review demo credentials actually log in.
  - **D6 — 2.3.5 Live UI vs marketing screenshots:** capture live screenshots of key screens and
    compare to the submitted marketing screenshots (features shown match the running build).
- **Output format:** `DYNAMIC-PASS:`/`DYNAMIC-FINDING:` + a Pierre 2–3 sentence explanation, mirroring
  the other reference docs; a summary table of the 6 checks.

### 2. `skills/appstore-precheck/SKILL.md`

- A new **optional "Phase 6: local dynamic simulator tier (opt-in)"** section after Phase 5,
  explicitly stating: off by default; runs ONLY when the user asks and supplies a built `.app` or a
  booted simulator UDID + bundle id; uses Maestro MCP + `xcrun simctl`; emits advisory `DYNAMIC-*`
  lines that **never change the GREEN/YELLOW/RED verdict**; macOS + Xcode + a simulator required;
  cross-references `references/simulator-dynamic-review.md`. The READ-ONLY line gets a scoped caveat
  noting the tier touches disposable simulator state only.
- The "Flow (6 phases: 0–5)" heading/text is updated to note Phase 6 is an optional opt-in tier
  outside the standard flow (the default run is still Phases 0–5).

### 3. Docs

- `references/methodology.md`: a note describing the optional dynamic tier, its advisory nature, and
  its local-only/never-in-CI reality.
- `README.md`: update the "Known limits" line (currently "No runtime crash testing; that's
  TestFlight + a crash reporter. Static analysis only.") to point at the optional local simulator
  tier **without overclaiming** — still not a TestFlight/crash-reporter/QA replacement, a pre-submit
  local smoke signal.

## Testing

Agent-mode, like `pierre-deep-review.md` and `screenshot-vision-review.md` — **no deterministic
test** (there is no shipped code path to unit-test; the tier is a checklist the host LLM executes
against a live simulator). The existing suite stays green (this change touches only docs). CI is
unaffected (no simulator on `ubuntu-latest`; the tier never runs there). Doc consistency is verified
by the suite passing and by the SKILL.md/methodology/README cross-references resolving.

## Out of scope (v1 / deferred)

- A deterministic `scripts/simulator-smoke.sh` (revisit only with a macOS CI runner to validate it).
- Authored per-app Maestro YAML flows (`run_flow_files`) — the host drives the MCP tools
  opportunistically in v1.
- Any verdict-affecting behavior (crash→FAIL carve-out deferred).
- Any change to the offline `scan.sh`/CLI/Action path.
- CI integration (permanently local-only).

## Build method

superpowers subagent-driven-development (docs tasks reviewed the same way); final Opus whole-branch
review; `superpowers:finishing-a-development-branch`. New feature branch; merge + release (v1.12.0)
after the final review.
