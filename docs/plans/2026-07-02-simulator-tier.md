# Local Dynamic Simulator Tier Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an opt-in, agent-mode "local dynamic simulator tier" — a reference checklist the host LLM runs against a live simulator (Maestro MCP + `xcrun simctl`) emitting advisory findings — without touching the scan/verdict path.

**Architecture:** Docs-only. A new `references/simulator-dynamic-review.md` (modeled on `pierre-deep-review.md` / `screenshot-vision-review.md`) defines a 6-check dynamic checklist; `SKILL.md` gains an optional opt-in "Phase 6" section referencing it; methodology/README note the tier. No shipped code, no verdict change, byte-identical scan path.

**Tech Stack:** Markdown docs; the tier itself is driven at runtime by Maestro MCP tools + `xcrun simctl` (host/agent-mode only, never in the offline path).

## Global Constraints

- Agent-mode only, OPT-IN, off by default. Never runs in the offline CLI / npx / GitHub-Action path.
- Advisory only: `DYNAMIC-PASS:` / `DYNAMIC-FINDING:` lines; NEVER enters the FAIL/WARN counts; NEVER changes the GREEN/YELLOW/RED verdict.
- READ-ONLY w.r.t. the user's project: the tier touches disposable simulator state only, never the user's repo. Every doc mentioning it states this scoped caveat.
- No competitor name anywhere ("the free/local alternative to a paid cloud device farm").
- Offline path untouched: `scan.sh`, `bin/cli.js`, `action.yml`, `install.sh`, `verdict.sh` UNCHANGED and byte-identical.
- Permanently local-only (CI is `ubuntu-latest`; no simulator there) — documented, no CI job.
- NO version bump in-branch (bump at release).
- Not a TestFlight / crash-reporter / QA replacement — a pre-submit local smoke signal (state this without overclaiming).

---

### Task 1: Reference doc + SKILL.md Phase 6 wiring

**Files:**
- Create: `skills/appstore-precheck/references/simulator-dynamic-review.md`
- Modify: `skills/appstore-precheck/SKILL.md` (Flow heading ~line 95; add Phase 6 after Phase 5's step 7 ~line 315; READ-ONLY rule ~line 319; Known limits ~line 327)

**Interfaces:** documentation only.

- [ ] **Step 1: Create `references/simulator-dynamic-review.md`**

```markdown
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

### D1 — Launch without crash
1. `mcp__maestro__start_device` (or `xcrun simctl boot`) a disposable simulator; `launch_app` the supplied app/bundle id.
2. Observe for a short window; if the app process disappears or a crash alert shows, `DYNAMIC-FINDING`.
3. `take_screenshot` at launch as evidence.

### D2 — Core screen reachable
1. After launch, inspect the first real screen (`inspect_view_hierarchy` / `take_screenshot`).
2. Flag if stuck on a splash, blank, or an error/"something went wrong" state.

### D3 — Paywall renders
1. If a paywall exists (per the static scan / app structure), navigate to it (`tap_on` / a flow).
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
```

- [ ] **Step 2: Update the Flow heading in `SKILL.md`**

Change the heading (currently `## Flow (6 phases: 0–5)`, ~line 95) to:
```markdown
## Flow (Phases 0–5; plus an optional opt-in Phase 6)
```

- [ ] **Step 3: Add the Phase 6 section in `SKILL.md`**

After Phase 5's step 7 (the "Print the final manual checklist" item, ~line 315) and BEFORE the `## Rules` heading (~line 317), insert:
```markdown

### Phase 6: local dynamic simulator tier (optional, opt-in — off by default)

**This phase does not run by default.** Run it ONLY when the user explicitly asks for a dynamic /
simulator check AND supplies a built app (a simulator `.app` path, or a booted simulator UDID +
bundle id). It uses `xcrun simctl` + Maestro MCP tools (`mcp__maestro__*`) to launch the app on a
disposable simulator and observe real behavior — the free/local alternative to a paid cloud device
farm.

It emits advisory `DYNAMIC-PASS:` / `DYNAMIC-FINDING:` lines and **never changes the
GREEN/YELLOW/RED verdict** (the verdict stays derived only from Phases 0–2). It is read-only w.r.t.
the user's project — it touches only disposable simulator state, never the repo. It requires macOS +
Xcode + a simulator runtime and is permanently local-only (it cannot run in CI). It is a pre-submit
local smoke signal, not a TestFlight / crash-reporter / QA replacement.

Follow [`references/simulator-dynamic-review.md`](references/simulator-dynamic-review.md) for the
6-check dynamic checklist and output format.
```

- [ ] **Step 4: Add the scoped caveat to the READ-ONLY rule in `SKILL.md`**

Change the READ-ONLY rule (currently `- **READ-ONLY:** never change code or assets. Only report and write the token.`, ~line 319) to:
```markdown
- **READ-ONLY:** never change code or assets. Only report and write the token. (The optional Phase 6
  simulator tier touches disposable simulator state only — never the user's project.)
```

- [ ] **Step 5: Update the Known limits line in `SKILL.md`**

Change the first Known-limits bullet (currently `- No runtime crash testing; that's TestFlight + a crash reporter. Static analysis only.`, ~line 327) to:
```markdown
- The default flow is static analysis only. Runtime crash/behavior testing is available as an
  optional, opt-in local simulator tier (Phase 6, `references/simulator-dynamic-review.md`); it is a
  pre-submit local smoke signal, not a TestFlight / crash-reporter replacement.
```

- [ ] **Step 6: Verify docs consistency + suite unaffected**

Run:
```bash
bash tests/all.sh
grep -c "simulator-dynamic-review" skills/appstore-precheck/SKILL.md
test -f skills/appstore-precheck/references/simulator-dynamic-review.md && echo "ref doc present"
grep -cE "DYNAMIC-PASS|DYNAMIC-FINDING|never changes the .*verdict|disposable simulator" skills/appstore-precheck/references/simulator-dynamic-review.md
```
Expected: `SUITE PASSED (17 files)` (docs-only, nothing broke); SKILL.md references the doc at least once; `ref doc present`; the DYNAMIC/verdict/disposable markers are present.

- [ ] **Step 7: Confirm the offline scan path is byte-identical (no code touched)**

Run: `git diff --name-only HEAD | grep -E 'scan\.sh|verdict\.sh|cli\.js|action\.yml|install\.sh|findings\.sh' && echo "!! code touched" || echo "docs-only — offline path untouched"`
Expected: `docs-only — offline path untouched`.

- [ ] **Step 8: Commit**

```bash
git add skills/appstore-precheck/references/simulator-dynamic-review.md skills/appstore-precheck/SKILL.md
git commit -m "feat(simulator): opt-in agent-mode local dynamic simulator tier (Phase 6, advisory, never changes verdict)"
```

---

### Task 2: methodology + README notes

**Files:**
- Modify: `skills/appstore-precheck/references/methodology.md` (a note on the optional dynamic tier)
- Modify: `README.md` (Disclaimer paragraph, ~line 472)

**Interfaces:** documentation only.

- [ ] **Step 1: Add a methodology note**

In `skills/appstore-precheck/references/methodology.md`, add:
```markdown
### Optional local dynamic simulator tier

Beyond the static scan and the agent-mode deep reviews, an **opt-in** local dynamic tier
(`references/simulator-dynamic-review.md`, SKILL.md Phase 6) can run the app on a simulator
(`xcrun simctl` + Maestro MCP) and emit advisory `DYNAMIC-PASS:` / `DYNAMIC-FINDING:` observations —
launch/crash, paywall render, permission prompt vs purpose string, demo-login path, live UI vs
marketing screenshots. It is off by default, never changes the verdict, is read-only w.r.t. the
user's project (touches disposable simulator state only), and is permanently local-only (it cannot
run in CI). It is a pre-submit local smoke signal, not a TestFlight / crash-reporter / QA
replacement.
```

- [ ] **Step 2: Update the README Disclaimer**

In `README.md`, replace the sentence `It performs no runtime crash testing; always do a final manual review before you submit.` (in the `## Disclaimer` paragraph, ~line 472) with:
```markdown
The default flow performs no runtime crash testing; an optional, opt-in local simulator tier (Maestro
+ `xcrun simctl`) adds a pre-submit smoke signal but is not a TestFlight / crash-reporter / QA
replacement. Always do a final manual review before you submit.
```

- [ ] **Step 3: Verify suite + versions (no bump) + cross-references**

Run:
```bash
bash tests/all.sh && ./scripts/check-versions.sh
grep -c "dynamic simulator tier\|simulator-dynamic-review\|local simulator tier\|opt-in local simulator" README.md skills/appstore-precheck/references/methodology.md
```
Expected: `SUITE PASSED (17 files)`; `OK: versions match (1.11.0)`; each file mentions the tier at least once.

- [ ] **Step 4: Commit**

```bash
git add skills/appstore-precheck/references/methodology.md README.md
git commit -m "docs(simulator): document the optional local dynamic simulator tier"
```

---

## Self-Review

**Spec coverage:**
- Agent-mode reference doc with 6 checks + advisory output → Task 1 Step 1. ✓
- Verdict = advisory, never changes GREEN/YELLOW/RED → doc + Phase 6 text state it; no verdict code touched. ✓
- Opt-in / off by default / local-only / macOS → Phase 6 section + doc identity block. ✓
- READ-ONLY scoped caveat (disposable simulator only) → doc + SKILL.md READ-ONLY rule (Task 1 Step 4). ✓
- No competitor name → "free/local alternative to a paid cloud device farm" phrasing only. ✓
- Not a TestFlight/QA replacement (no overclaim) → doc + Known limits + README Disclaimer. ✓
- Offline path byte-identical → docs-only; Task 1 Step 7 asserts no code touched. ✓
- Deterministic smoke script + Maestro YAML flows deferred → not in any task (documented as out of scope in the spec). ✓
- No version bump → Task 2 Step 3 asserts 1.11.0. ✓

**Placeholder scan:** every step has full content; no TBD/TODO. ✓

**Type/name consistency:** `DYNAMIC-PASS` / `DYNAMIC-FINDING`, `simulator-dynamic-review.md`, "Phase 6", "disposable simulator" used identically across both tasks and the reference doc. No suite-count change (docs-only → stays 17 files). ✓

**Note for executor:** this is a docs-only feature — there is no code to unit-test (the tier is an agent-mode checklist, like `pierre-deep-review.md`). "Tests" here mean the existing suite stays green (byte-identical) and the cross-references resolve. Do NOT add a `scripts/simulator-smoke.sh` — the deterministic script is deliberately deferred (see spec).
