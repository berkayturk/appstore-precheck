# Local dynamic simulator tier — SCOPING DRAFT (Maestro + xcrun simctl)

**Status: DRAFT SCOPING — pre-brainstorm, not approved.** This is a menu of options + a
recommendation + open questions for BT to react to, not a spec to build from. No code, tests, or
manifests were touched to produce this document. Roadmap item **#5** ("local dynamic simulator
tier").

**Date:** 2026-07-02

## 1. Problem / value

Every existing layer of this tool is **static**: `scan.sh` (42 vectors) greps/parses source and
metadata; Pierre deep-review (28 checks) reads code, metadata, and fetched text; guideline-drift
watches Apple's page. `SKILL.md`'s own "Known limits" section says it plainly:

> No runtime crash testing; that's TestFlight + a crash reporter. Static analysis only.

That gap is exactly where a class of real rejections lives — ones that require the app to
actually **run**:

| Dynamic check | App Store rejection risk it targets |
|---|---|
| App launches on a fresh simulator without crashing | 2.1 "the app is buggy / crashes" (the single most common reject reason in Apple's own published stats) |
| Paywall actually renders, price + terms visible before purchase | 3.1.2 (auto-renewable subscription disclosure) — static scan can find the *strings*, but not confirm they *render* on the real paywall screen |
| Permission prompt appears and its OS-level text matches the `Info.plist` purpose string it was declared for | 5.1.1(ii)/(iii) — static scan checks the string exists and is non-generic; only a runtime trigger proves the string is *actually shown at the right moment* |
| Login-gated app exposes a reachable demo/guest path, or the declared demo credentials actually log in | 2.1 demo account (Pierre check 4, Tier B) — today this is a text-file plausibility check; a real login attempt is the only way to *prove* it works |
| Screenshot capture of the live running UI, compared against submitted marketing screenshots | 2.3.5 (screenshots match shipped features) — today Pierre reads static PNG files; live capture would show the *current* build, not last month's screenshots |
| Accessibility / hittability pass (VoiceOver labels present, tap targets reachable) | Not a hard rejection vector today, but Apple has tightened on this; forward-looking value |

The value proposition: this is the **free/local answer** to paid cloud-device-testing services,
built from tools already on a Mac with Xcode (`xcrun simctl`) plus an open-source mobile UI-testing
tool driven through its MCP server (`mcp__maestro__*`). No new paid dependency, no uploading a
build anywhere.

## 2. Hard constraints (recap, must hold in any option below)

1. **Read-only identity.** The tool "never modifies the user's project" today because every phase
   only *reads* source/metadata and *writes* `.precheck-pass`. A simulator tier writes to the
   **simulator's** ephemeral filesystem (installs an `.app` bundle into a sandboxed simulator
   runtime), never to the user's repo. That is the honest boundary to state explicitly: read-only
   w.r.t. **project source**, not w.r.t. "does anything on the machine" — same category as Phase 2
   already invoking `fastlane precheck` over the network, or Phase 0 fetching a live URL. The
   simulator install/launch/teardown must be scoped to a disposable simulator device (fresh or a
   dedicated named device the tool creates and can delete), never the user's own paired simulator
   state.
2. **No competitor name anywhere.** Frame everything as "a local dynamic tier" / "the free/local
   alternative to a paid cloud device farm" — never name one.
3. **Offline CLI path is untouchable.** `scan.sh`, `bin/cli.js` (npx), the reusable GitHub Action
   (`action.yml`), and `install.sh` must stay zero-dependency, deterministic, and byte-identical.
   A dynamic tier categorically cannot live there: it needs a **built `.app`**, a **macOS host with
   Xcode + simulator runtimes installed**, and (for the agent-mode path) **live MCP tool access**
   — none of which the offline path has or should ever require. `.github/workflows/ci.yml` and
   `guideline-drift.yml` both run on `ubuntu-latest` today; this tier cannot run there without a
   self-hosted macOS runner, which is out of scope for this project's CI.
4. **bash 3.2** for any shipped bash (macOS ships an ancient bash 3.2; the project already avoids
   associative arrays etc. for this reason).
5. Must slot into the existing three-tier shape: offline `scan.sh` → Pierre agent-mode deep-review
   (28 checks, non-blocking `REVIEW-FINDING`) → maintainer/CI guideline-drift. A simulator tier is
   a **fourth, separate, opt-in tier**, following that same "separate but referenced from SKILL.md"
   pattern (like how Phase 4 references `pierre-deep-review.md` and `screenshot-vision-review.md`
   as sibling reference docs rather than inlining them into `scan.sh`).

## 3. Architectural approaches

### Approach A — MVP smoke-test tier (agent-mode only, minimal surface)

A small new reference doc (`references/simulator-smoke-review.md`) plus a short new `SKILL.md`
section ("Phase 6: optional dynamic smoke test"), invoked only when the user explicitly opts in
and supplies a built app. Flow, entirely via `mcp__maestro__*` + `xcrun simctl`:

1. `list_devices` / `start_device` — boot a disposable simulator (a specific named device the tool
   creates, e.g. `appstore-precheck-sim`, so it never touches the user's everyday simulator).
2. `launch_app` with the user-provided `.app` path or bundle id (already installed by the user via
   `xcrun simctl install`, or the tool shells out to `simctl install` itself — see open question).
3. Wait/observe: did it launch and stay foregrounded for N seconds without the process disappearing
   (crash proxy)?
4. `take_screenshot` at launch, and after tapping past any splash/onboarding if easily reachable.
5. `inspect_view_hierarchy` opportunistically to note obviously-empty screens or crash/error alerts.
6. Emit `REVIEW-PASS:` / `REVIEW-FINDING:` lines in the same advisory vocabulary as Pierre
   deep-review — **never FAIL, never touches verdict** (see §4).
7. `stop_app`, and leave simulator teardown as a documented manual/optional step (don't auto-delete
   a device the user might reuse, unless the tool created it itself this run).

**Value:** launch-crash detection + one real screenshot, which alone covers the single highest-value
dynamic check (crash risk under 2.1) at low build cost.
**Cost:** does not touch permission prompts, paywall, or login flows — a thin slice.

### Approach B — Full guided-flow tier (agent-mode, scripted Maestro flows per rejection vector)

Same entry point as A, but adds authored Maestro YAML flows (`run_flow_files`) per dynamic check:
a `paywall-check.yaml` that navigates to the paywall and screenshots it, a `permission-check.yaml`
that triggers each permission requiring a purpose string and screenshots the OS prompt next to the
declared string, a `login-demo-check.yaml` that attempts the declared demo credentials from
`review_information/` end-to-end. Pierre (or a dedicated persona) narrates each flow's outcome the
same way Phase 4 narrates the 28 static deep-review checks — full parity with the existing "28
checks" table format (one row per dynamic check, `REVIEW-PASS`/`REVIEW-FINDING`, evidence =
screenshot filename + timestamp).

**Value:** covers essentially all the dynamic checks in §1's table; strongest signal, closest to
"App Store review simulation" positioning.
**Cost:** materially larger scope — authoring and maintaining Maestro flows per app shape (every
app's paywall/login UI is different, so flows likely need light app-specific parameterization,
e.g. accessibility IDs or text selectors supplied via `.appstore-precheck.json`), more moving parts
(simulator boot flakiness, timing waits, app-specific selectors going stale), and a much bigger
"what if the flow doesn't match this app's UI" failure mode to handle gracefully (skip + note
"could not verify" rather than false-flagging).

### Approach C — Deterministic scriptable subset + agent-mode narration (hybrid)

Split the tier the same way screenshot-vision split into Layer 1 (deterministic bash) / Layer 2
(agent-mode vision): a new **small deterministic bash script**
(`scripts/simulator-smoke.sh`, maintainer/opt-in, NOT part of the offline `scan.sh` path) that
shells out directly to `xcrun simctl boot/install/launch/terminate` and asserts "process is still
alive after N seconds" / "app icon check" — no Maestro, no MCP, no LLM judgment required. This
covers the crash/launch check deterministically and could even be unit-tested in a way the rest of
the dynamic tier cannot. Everything requiring UI interaction or visual judgment (paywall, permission
UX-vs-purpose-string, login demo path, screenshot content) stays agent-mode, using Maestro MCP
tools, layered on top exactly as in Approach B.

**Value:** gets one piece of real, testable, deterministic signal (the highest-value one — crash
detection) without depending on MCP/Maestro availability at all; the richer checks remain available
when the host has Maestro MCP wired up.
**Cost:** two code paths to maintain (bash smoke test + Maestro flows); the bash script still needs
a real simulator + `xcrun` on the host, so it is **not** part of the zero-dependency offline
`scan.sh`/CLI/Action path even though it's deterministic — it is a separate opt-in script the
user runs locally, parallel to `phase2-precheck.sh`'s pattern of "separate script, real
credentials/environment required, not in the default offline flow."

## 4. Recommended approach

**Approach C (hybrid), built in two stages, starting with only the deterministic slice of stage
1.**

Rationale against the hard constraints:

- It preserves the sharpest form of the project's existing pattern: *deterministic-when-possible,
  agent-mode-only-when-it-requires-judgment* — the same split that shipped for screenshot-vision
  (image-dims.sh deterministic vs vision-review agent-mode) and for guideline-drift
  (guideline-drift.sh deterministic vs Phase 0 agent-mode narration). BT has shipped this shape
  twice already; reusing it keeps the codebase's mental model consistent rather than introducing a
  third pattern.
- `scripts/simulator-smoke.sh` is real, testable code with an actual exit code — it can get a
  `tests/test-simulator-smoke.sh` the same way `verdict.sh` and `image-dims.sh` did, which matches
  this project's "verify, don't just narrate" ethic. It just runs as a **separate, explicitly
  opt-in** script (documented, not auto-invoked, not part of `npm test`'s default suite since it
  needs a real Mac + simulator + a built app — more like `phase2-precheck.sh`, which also needs
  real credentials and is excluded from the zero-dependency default path).
- The richer guided-flow checks (paywall, permission-vs-purpose-string, login demo,
  screenshot-content) are inherently judgment calls best left to agent-mode narration in Pierre's
  voice, matching how Phase 4 and screenshot-vision Layer 2 already work — no new identity pattern
  needed, just a new reference doc (`references/simulator-dynamic-review.md`) and a new optional
  `SKILL.md` phase that explicitly states it is off by default.
- Starting with **only the crash/launch smoke check** (a slice of Approach A) as the literal first
  shippable unit keeps initial scope small and self-contained, with the guided-flow richness
  (Approach B's Maestro YAML checks) as an explicit, separately-scoped follow-up once the smoke
  check has proven the wiring (simulator lifecycle, opt-in UX, "how does a user hand us a built
  app") works end to end.

## 5. Identity / verdict decision options

This is a real fork BT should decide, not something to default silently:

- **Option 1 — Purely advisory, like Phase 4/screenshot-vision.** Dynamic findings are
  `REVIEW-PASS`/`REVIEW-FINDING` (or a new tier-specific label, e.g. `DYNAMIC-FINDING`), always
  `WARN`-equivalent in tone, **never** added to the FAIL/WARN counts `verdict.sh` uses. Cleanest
  fit with "verdict is deterministic, derived only from Phases 0–2" (`SKILL.md` Phase 5). Risk:
  a genuine launch **crash** feels like it deserves more weight than "advisory," undercutting the
  tier's value proposition if it's always soft-pedaled.
- **Option 2 — Narrow verdict-affecting carve-out.** Exactly one signal — "app failed to launch /
  crashed within N seconds on the simulator" — is allowed to escalate to a real FAIL if (and only
  if) the user explicitly opted into the dynamic tier for this run; everything else in the tier
  stays advisory. This preserves "verdict is deterministic" (crash-or-not is a boolean, not a
  judgment call) while giving the tier real teeth on the one check that most resembles "the app is
  broken." Requires `verdict.sh` to accept an optional new input channel — a currently
  clean, single-purpose script that would need a documented extension point.
  Requires this to be **strictly additive and opt-in**: the offline-only user (no simulator run) must
  see byte-identical verdict behavior — this only fires when the tier ran.
- **Option 3 — Separate verdict entirely.** The dynamic tier produces its own GREEN/YELLOW/RED-style
  readout, presented alongside but never merged with the static verdict — two independent gates a
  user can choose to honor. Avoids any risk of quietly changing `verdict.sh` semantics but adds a
  second "verdict" concept for users to reason about, arguably at odds with the project's current
  single-verdict simplicity.

Recommendation leans toward **Option 1 to start** (zero risk to the existing verdict contract,
fastest to ship, consistent with how every other agent-mode layer already behaves), with **Option
2 explicitly flagged as the natural v2 once the crash-check is proven reliable** — but this is
squarely BT's call given how central "verdict = deterministic, Phase 0-2 only" is to the project's
current identity.

## 6. How the tier gets a built app (open design point, not decided here)

Three non-exclusive on-ramps worth having BT pick from:

1. **User supplies a path.** `--app-path /path/to/Foo.app` (simulator build) — simplest, no build
   orchestration in this tool at all. Matches the project's general philosophy of consuming
   artifacts rather than producing them (it doesn't run `xcodebuild` today, doesn't build
   anything).
2. **User supplies a bundle id already installed on a running simulator.** `--bundle-id
   com.example.app --udid <UDID>` — for users who already have a dev loop running the app in
   Simulator.app; the tool just attaches (`launch_app`, `inspect_view_hierarchy`, etc.) rather than
   installing anything.
3. **Tool boots a fresh disposable simulator and installs the given `.app` itself** via `xcrun
   simctl create/install`, only when handed a raw `.app` path (bundles the "how do I get from a
   build product to a running instance" step so the user doesn't have to know `simctl` syntax).

All three are compatible with the read-only-w.r.t.-project-source framing since none of them touch
the user's repo; they only touch simulator state the tool can tear down afterward.

## 7. Rough task breakdown (if built, for the recommended MVP slice)

1. `scripts/simulator-smoke.sh` — boot/install/launch a given `.app` on a disposable named
   simulator via `xcrun simctl`, poll process liveness for N seconds, `simctl io screenshot`,
   terminate, print machine-readable PASS/FAIL lines (own script, not sourced by `scan.sh`).
2. `tests/test-simulator-smoke.sh` — needs a real macOS CI runner or is explicitly marked
   local-only/manual (documented, not in the default `npm test` / `ci.yml` — see Risks below for
   why this may never be CI-automatable in this project's current GitHub Actions setup).
3. `references/simulator-dynamic-review.md` — new reference doc modeled exactly on
   `pierre-deep-review.md` / `screenshot-vision-review.md` structure (rules block, output format,
   per-check table, per-check procedure) for the agent-mode guided-flow checks (paywall, permission
   UX, login demo, screenshot capture).
4. New optional `SKILL.md` phase (working title "Phase 6: optional dynamic simulator tier") —
   explicitly opt-in, states its inputs (built app / bundle id / udid), states it never runs
   unless invoked, cross-references the two docs above.
5. Config surface: extend `.appstore-precheck.json` (or a new `.appstore-precheck.dynamic.json`
   to keep the static config file's schema untouched) with `simulatorTier.appPath` /
   `.bundleId` / `.udid` / `.demoCredentialsHint` etc.
6. Update `README.md` "Known limits" line (currently: "No runtime crash testing; that's TestFlight
   + a crash reporter") to describe the new optional tier without overclaiming (still not a
   TestFlight/crash-reporter replacement — a pre-submit local smoke signal).
7. Version/changelog entry, following the existing lockstep-version-bump-at-release convention.

Guided-flow richness (Approach B/C's Maestro YAML checks) is a distinctly separate, larger
follow-up task list once the above is proven, not bundled into this MVP breakdown.

## 8. Open questions for BT (decisions that are genuinely his)

1. **Verdict semantics** (§5): purely advisory forever, or is a narrow crash-only FAIL carve-out
   (Option 2) worth the added complexity to `verdict.sh`'s currently clean single-purpose
   contract?
2. **How opinionated should the "get a built app" step be** (§6): should the tool ever shell out to
   `xcrun simctl install` itself (on a path the user gives it), or should it always require the
   user to have already installed/booted the app themselves and only hand the tool a UDID/bundle
   id — the more conservative, more clearly "read-only w.r.t. everything" option?
3. **Where does the line sit between MVP and "full tier"** — is the crash/launch smoke check alone
   worth shipping as v1 (this scoping's recommendation), or does the tier need at least the
   paywall-render check to feel valuable enough to ship at all (login-gated/subscription apps are
   a large share of the target audience)?
4. **Naming/positioning**: is "local dynamic simulator tier" the right external name, or does this
   need its own persona/voice choice (does Pierre narrate this too, or is a dynamic/runtime tier a
   good moment to introduce a distinct voice, given it's a genuinely different kind of evidence —
   screenshots and live behavior rather than static text)?
5. **CI story**: is this tier permanently local-only (never runs in `ci.yml`/`guideline-drift.yml`
   since both are `ubuntu-latest`), or is a future self-hosted macOS runner in scope for this
   project at all? (Leaning toward "permanently local-only" being the honest answer — see Risks.)

## 9. Risks / unknowns

- **CI is `ubuntu-latest` today, full stop.** Neither `xcrun simctl` nor a real iOS Simulator
  exists there. Any deterministic test for `simulator-smoke.sh` is either (a) manual/local-only
  and documented as such (breaking the project's "everything has a `tests/test-*.sh` in CI" norm
  for the first time), or (b) requires a macOS self-hosted runner, a real infra/cost decision
  outside this project's current footprint.
- **Maestro MCP availability in headless/CI/agent-mode contexts is unproven** — the MCP tools
  listed (`mcp__maestro__list_devices`, `start_device`, `launch_app`, `tap_on`, `input_text`,
  `take_screenshot`, `inspect_view_hierarchy`, `run_flow`/`run_flow_files`) assume a host that has
  registered the Maestro MCP server and has the Maestro CLI + a real simulator locally; this tier
  is unusable in any environment lacking that (e.g. a cloud/headless Claude Code session with no
  local Mac).
- **Needing a built app is a real adoption barrier.** Unlike the static scanner (works on raw
  source with zero build step), this tier requires the user to have already built for Simulator —
  a meaningfully higher bar that will filter out a chunk of the audience who'd otherwise run this
  pre-submit.
- **App-specific UI coupling for guided flows (Approach B/C's richer checks).** Every app's paywall
  and login screen differ; generic Maestro flows will need per-app selectors/hints
  (`.appstore-precheck.json` additions), which is more configuration surface than every other check
  in this tool currently requires (everything else is fully auto-detected).
  Flows going stale as an app's UI changes is an ongoing maintenance cost the static scanner doesn't
  have.
- **Simulator flakiness / timing.** Boot time, first-launch compile/JIT warmup, and animation
  timing make "crashed" vs. "just slow" ambiguous without careful thresholds — false positives here
  would be uniquely damaging to trust compared to the rest of the tool's low-false-positive
  static checks.
- **Read-only framing needs to be worded carefully in every doc that mentions this tier** — it is
  the first capability in the project that installs/runs a binary and writes to *something*
  (simulator state), even though it never touches the user's repo. The existing "READ-ONLY: never
  change code or assets" line in `SKILL.md` will need a precise, scoped caveat wherever this tier
  is documented, or it risks contradicting the tool's core selling point.
- **Scope creep toward "we do dynamic testing now"** — must stay explicitly framed as a narrow,
  opt-in, pre-submit smoke signal, not a replacement for TestFlight/real device testing/a real QA
  process, mirroring how Phase 4 and screenshot-vision both carry "this does not guarantee Apple's
  decision" disclaimers.

## 10. Non-goals (explicit, to keep scope honest)

- Not a CI-integrated dynamic test suite (see CI risk above).
- Not a replacement for TestFlight, a crash reporter, or manual QA.
- Not a cloud/remote device farm of any kind — deliberately the free/local answer, local Mac +
  simulator only.
- Not modifying the offline `scan.sh`/CLI/Action path in any way, at any stage.
- Not (in the MVP) attempting full guided-flow coverage of every dynamic check in §1's table —
  that is an explicit, separately-scoped v2.
