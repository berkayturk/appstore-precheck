# Design: Roadmap #2(c) — Semantic Guideline Drift (deterministic text-fingerprint)

**Date:** 2026-07-02
**Status:** Approved (brainstorming) — pending implementation plan
**Roadmap:** #2 "smarter analysis", sub-capability (c) semantic guideline drift
**Depends on:** the existing `guidelines-baseline.json` + agent-driven Phase-0 drift check

## Problem

Today's guideline-drift check (SKILL.md Phase 0 + `guidelines-baseline.json`) only detects
**section-number** changes: the host agent `WebFetch`es the live App Store Review Guidelines,
diffs the section-number set against `all_sections`, and WARNs on numbers Apple added or removed.
It is blind to **semantic drift** — Apple rewriting the *text/meaning* of a section while its
number stays the same (e.g. 3.1.1 tightening). When that happens, a `scan.sh` check mapped to
that section can silently go stale. The current check also relies on `WebFetch`, which truncates
the page (~5.4), so the 5.5–5.6.x tail is not machine-checkable at all.

## Identity reconciliation (why this fits)

The tool has two run modes:
- **Deterministic CLI / CI** (`scan.sh`, `npx`, GitHub Action): offline, zero-dependency, byte-stable — the distributed scanner's identity.
- **Agent-skill mode** (Claude Code / Codex / etc.): the host LLM adds Phase-0 drift (`WebFetch`) and the Pierre semantic deep-review.

Semantic drift is a **maintainer / CI concern**, not part of a user's app scan. So it lives in a
separate maintainer/CI script that may use the network (`curl`) — it is NEVER sourced by `scan.sh`
and never runs in the user scan path. The deterministic offline CLI is untouched. No model is
required: text-change detection is deterministic; judging whether a flagged change is *materially*
semantic is a documented human/agent triage step (the host LLM can interpret the script's output).

## Feasibility (confirmed)

A `curl` of `https://developer.apple.com/app-store/review/guidelines/` returns the full,
untruncated page (~234 KB, including the 5.6.x tail that `WebFetch` drops). Every guideline
section carries an HTML anchor — `<span id="N.N.N"></span><strong>…</strong>` or
`<li id="N.N.N"><strong>N.N.N</strong> …</li>` — so per-section text is deterministically
extractable by slicing from a section's `id="X"` anchor to the next anchor (125 anchors present,
matching the `all_sections` scope). Number-level drift via `curl` is therefore *more* complete
than the current `WebFetch` path (full page, no truncation).

## Approach (A: deterministic text-fingerprint drift detector)

### Architecture

New script `scripts/guideline-drift.sh` — maintainer/CI only, network-using (`curl`), **not**
sourced by `scan.sh`. Fetch is separable from parse/diff: the script accepts `--html <file>` to
run the parse/fingerprint/diff logic against a local HTML file (no network) so the logic is
unit-testable. Pure bash + awk/sed + `curl` + `shasum`/`sha256sum` (`jq` already a dependency).
No new *runtime* dependency for the distributed scanner (this tool is maintainer-only).

### Data: a companion fingerprint file

New `skills/appstore-precheck/guidelines-fingerprints.json` (kept separate from
`guidelines-baseline.json` so the number-baseline stays small; the fingerprint data is larger and
regenerated at reconciliation). Per **covered** section (the sections our checks depend on —
`covered_by_scan` ∪ `covered_by_pierre_deep_review`):
- `fingerprint`: a hash of the section's normalized prose.
- `snapshot`: the normalized prose (short) so a drift report can show *what* changed, not just that it did.
- a **section → check** map (`{ "2.3.3": ["screenshots-per-locale"], … }`) so a text-drift WARN names the affected check(s).

Human-reconciled only — never auto-updated by the script (identical discipline to
`guidelines-baseline.json`), so a warning is never silently swallowed.

### Detection logic

1. `curl` the full page (or read `--html <file>`). On fetch failure/empty →
   `WARN: guideline-drift-check degraded — verify manually` and exit 0.
2. Extract the ordered anchor-id set → **number drift**: ids present live but not in
   `all_sections` (added) and ids in `all_sections` but absent live (removed) → WARN each. This
   supersedes the manual/`WebFetch` number method and now covers the full page incl. 5.6.x.
3. For each covered section: slice its `id="X"` anchor → next anchor, strip HTML tags, normalize
   (collapse whitespace, lowercase), hash. Compare to the stored `fingerprint`.
4. **Text drift**: any covered section whose live hash differs from baseline →
   `WARN: semantic drift — <section> text changed since <reconciled_on>; review check(s): <rule-ids>`,
   with a normalized before/after snippet for reconciliation.
5. Always non-blocking: WARN lines, exit 0. (A `--check`-style non-zero mode MAY be added for CI
   gating, but default is advisory.)

### Normalization

Strip tags, decode the handful of common HTML entities, collapse runs of whitespace to one space,
trim, lowercase. Goal: robust to trivial HTML/whitespace churn, sensitive to real prose edits.
The snapshot stores the normalized text so drift is human-reviewable.

## Integration

- **CI:** a manual/scheduled **non-blocking** workflow runs `guideline-drift.sh` and surfaces its
  output (job summary / logs). It does not block PRs and does not touch the user scan.
- **SKILL.md Phase 0 + methodology.md:** point to `guideline-drift.sh` as the drift source of
  truth; the host LLM runs it and interprets whether a flagged text change is materially semantic
  (the triage step). The offline CLI path is unchanged.
- **`scan.sh` / user CLI / GitHub Action scan:** untouched — stays offline, deterministic, byte-stable.

## Testing

- `tests/test-guideline-drift.sh` (registered in `tests/all.sh`), run against a small saved
  fixture HTML (a few sections in the real anchor markup) + a fixture fingerprint file, via
  `--html`:
  - number drift: an added and a removed section id are each WARNed.
  - text drift: changing one covered section's prose WARNs and names its mapped check; an
    unchanged section does not WARN.
  - no-drift: identical input → clean, no WARN.
  - degraded fetch: empty/missing HTML → the degraded WARN, exit 0.
- **Consistency test:** every covered section (`covered_by_scan` ∪ `covered_by_pierre_deep_review`)
  has a fingerprint entry and maps to a real `scan.sh` rule-id (or a named Pierre check); every
  mapping references a section present in `all_sections`. This prevents the map from rotting
  (mirrors `check-versions.sh`'s lockstep discipline).
- The network fetch itself is not unit-tested; the parse/diff is, via `--html`.

## Out of scope (YAGNI)

- No model in the required path (host-LLM interpretation of flagged changes is a documented triage
  step, not a bundled dependency).
- No auto-reconciliation of the fingerprint file — deliberate human step.
- No change to `scan.sh` or the deterministic CLI/CI scan path.
- Screenshot-vision (#2a) is a separate sub-project, brainstormed next.

## Success criteria

- `guideline-drift.sh` deterministically detects, on the full guidelines page: added/removed
  section numbers AND text changes to covered sections, naming the affected check(s).
- Zero new runtime dependency for the distributed scanner; `scan.sh` and the offline CLI output
  are unchanged (byte-identical).
- Parse/diff logic is unit-tested against a fixture with `--html` (no network in tests); the
  covered-section ↔ fingerprint ↔ rule-id mapping is consistency-tested.
- Non-blocking everywhere; the fingerprint baseline is human-reconciled only.
