# Screenshot vision — deterministic dimension/format checks + agent-mode structured vision review

**Roadmap:** #2(a), the last sub-capability of #2 ("smarter analysis"). Follows #2(b) AST↔IOS_DIR (v1.7.0) and #2(c) semantic guideline drift (v1.8.0).

**Date:** 2026-07-02
**Target release:** v1.9.0 (bump happens at release, not in-branch)

## Problem

`scan.sh` §7 currently checks screenshots only for **count / presence / per-locale coverage**
(`set_rule "screenshots-per-locale"`, ~scan.sh:381). Pierre deep-review (check #8, 2.3.5) has a
single one-line screenshot instruction ("open ≥1 screenshot per primary locale; compare visible UI
to metadata claims"). Two real rejection sources are unaddressed:

1. **Wrong screenshot dimensions / corrupt or mislabelled image files** — Apple rejects screenshots
   whose pixel size is not an accepted App Store size, and rejects files that are corrupt or whose
   content does not match the extension. This is deterministically detectable and belongs in the
   offline CLI.
2. **Screenshot *content* problems** — placeholder/dev-debug/empty-state UI, text overflow/truncation,
   wrong device frame, misleading marketing art (splash/logo instead of the app in use), features
   shown that the app does not ship. This requires a vision model and belongs in agent-mode
   (the same identity pattern as Pierre deep-review and the guideline-drift WebFetch phase).

## Identity constraints (non-negotiable)

- **READ-ONLY** preserved. No new side effects.
- **No competitor names** anywhere.
- **CLI/scan.sh/npx/GitHub-Action path stays OFFLINE, zero-dependency, deterministic, and
  behavior-byte-identical** on any input without a real in-repo screenshots directory.
- **No new runtime dependency** for the distributed scanner. Dimension parsing uses only bash +
  `od`/`awk` (already required). Web access is maintainer/CI-only.
- **bash 3.2 compatible** (macOS; no associative arrays).
- **TDD + version lockstep** (bump at release across the 4 manifests).

## Two layers

### Layer 1 — Deterministic (scan.sh / CLI, offline, TDD, byte-identity)

**New file:** `skills/appstore-precheck/scripts/image-dims.sh` — pure bash + `od`/`awk`, sourced by
`scan.sh`. Keeps `scan.sh` from growing (coding-style: many small focused files). Responsibilities:

- `img_format <file>` — read the leading bytes and return `png`, `jpeg`, or `unknown` from the
  magic bytes (PNG signature `89 50 4E 47 0D 0A 1A 0A`; JPEG `FF D8 FF`).
- `png_dims <file>` — parse the IHDR chunk: width = big-endian bytes 16–19, height = 20–23
  (`od -An -tu1 -j16 -N8` piped to `awk` doing the base-256 accumulation). Echoes `W H` or nothing.
- `dims_match_accepted <W> <H>` — return 0 if `W×H` **or** `H×W` matches an entry in the accepted-size
  constant table; else 1.
- `ACCEPTED_SIZES` — a verified constant list of current Apple iPhone + iPad screenshot pixel sizes
  (portrait dims; the match tries both orientations). **The exact pixel values are verified during
  implementation against Apple's official screenshot-specifications page — the values must not be
  copied from a single unverified source.** Like the guideline fingerprints, this table can drift;
  WARN severity (below) absorbs that risk.

**scan.sh integration** — inside the existing §7 block, when `SCREEN_DIR` exists, iterate the image
files already found and, under a **new** rule id:

```
set_rule "screenshot-dimensions"
for each image file f under SCREEN_DIR:
  fmt = img_format(f)
  ext = extension of f
  if fmt == unknown or fmt != ext-implied-format:
      warn "2.3.3 Screenshot <f> is not a valid <EXT> (file content does not match extension)"
      continue
  if fmt == png:
      read W H via png_dims
      if W/H unparseable:
          warn "2.3.3 Screenshot <f> — could not read PNG dimensions (possibly truncated)"
      elif not dims_match_accepted(W,H):
          warn "2.3.3 Screenshot <f> is <W>x<H>, which matches no known App Store screenshot size — verify against the current spec"
  # jpeg: format-validated + counted (existing §7), dimensions not checked in v1 (documented limit)
set_rule "screenshots-per-locale"   # restore for the rest of §7's PASS line
```

**Severity = WARN, never FAIL.** Rationale:
1. Tool identity is honest + low-false-positive.
2. The accepted-size table drifts (Apple changed screenshot specs; even authoritative-looking
   third-party sources disagree on exact 6.9" pixels). WARN means a stale table produces a soft,
   honest nudge — never a false RED that flips an already-approved app's verdict.
3. The scanner cannot know which display slot a given file targets, so "matches no accepted size at
   all" is the only unambiguous signal, and even that is surfaced cautiously.

**New rule_id:** add `42) screenshot-dimensions` to the `rule_slug` catalog in `findings.sh`. §7's
`screenshots-per-locale` slug keeps its count/presence/locale semantics; the new dimension/format
findings are attributable separately in JSON output.

**Byte-identity:** every existing fixture and every real-corpus app is scanned with either no in-repo
screenshots dir or none containing real PNGs, so the new code emits nothing for them → the 13 test
suites and the scorecard stay byte-identical. New output fires only on real image files under a
detected `SCREEN_DIR`.

**JPEG dimensions deferred:** SOF-marker scanning is materially harder and error-prone. JPEGs are
format-validated (magic bytes) and counted (existing §7) but not dimension-checked in v1. This is a
documented limitation, not a silent gap. No per-JPEG "cannot verify" warning (that would be noise on
every JPEG).

### Layer 2 — Agent-mode structured vision review (host vision model, non-blocking)

**New file:** `skills/appstore-precheck/references/screenshot-vision-review.md`, modeled on the
structure of `references/pierre-deep-review.md` (rules block, output format, per-check procedure).

**Identity:** uses the **host LLM's vision capability** — exactly like Pierre deep-review reads code
and the drift phase fetches URLs. It is NOT a bundled dependency and does NOT run in the offline
CLI/npx/Action path. It lives only in agent-skill mode.

**Behavior:** non-blocking. Emits `REVIEW-PASS:` / `REVIEW-FINDING: … WARN` lines (Pierre pattern) —
**never changes the GREEN/YELLOW/RED verdict** (verdict comes only from scan `FAIL:`/`WARN:` counts).
Reads ≥1 screenshot per primary locale. Runs every check every run. Every finding cites a screenshot
filename as evidence. When there are no in-repo screenshots, each check reports
`REVIEW-PASS: … — not applicable (no in-repo screenshots; managed in App Store Connect)`.

**Checklist (dedicated, structured):**

1. **Placeholder / dev-debug / empty-state** — Lorem ipsum, debug overlays or logs, "TODO"/"FIXME"
   visible, empty lists / skeleton loaders shown as content, simulator status bars with placeholder
   carrier/time. (2.3.3, 2.3.7)
2. **Text overflow / truncation / clipping** — clipped or overlapping labels, cut-off buttons, text
   running off-screen. (2.3.3 quality)
3. **Wrong device frame / aspect** — an iPad screenshot in an iPhone slot (or vice-versa),
   letterboxing, obviously stretched/squished aspect ratio. (2.3.5)
4. **Misleading marketing** — 2.3.3 "show the app in use": the screenshot is a splash/title/logo/pure
   marketing art rather than actual app UI; 2.3.10: a feature is depicted that the app does not ship.
5. **Metadata ↔ screenshot claim mismatch** — visible UI text/features contradict the description,
   keywords, or promo text (deepens Pierre check #8 / 2.3.5).

**Wiring:** Pierre deep-review check #8 (2.3.5) is deepened to point at the new checklist; `SKILL.md`
Phase 4 references `references/screenshot-vision-review.md`. Output format, "not applicable"
handling, evidence-citation, and Pierre 2–3 sentence explanations (in the user's language) mirror
pierre-deep-review.md exactly.

## Testing (TDD)

- **New suite `tests/test-image-dims.sh`** (registered in `tests/all.sh`, shellcheck lint, CI):
  unit-tests `img_format`, `png_dims`, and `dims_match_accepted` against tiny committed fixture
  images — a valid PNG at an accepted size, a valid PNG at a non-accepted size, and a
  renamed/truncated non-PNG (`.png` extension, non-PNG content). Fixtures are minimal valid PNGs
  (generated with a documented one-liner or committed as tiny binaries).
- **New fixture `tests/fixtures/screenshots-app/`** with `fastlane/screenshots/en-US/*.png` of known
  dimensions and a config pointing `screenshotsDir`, exercised end-to-end by the fixture scan suite
  (`tests/run.sh`): `assert_contains` for the new dimension/format WARN, plus a JSON assertion that
  the finding carries `rule_id == screenshot-dimensions`.
- **Byte-identity guard:** confirm every pre-existing fixture output and the scorecard are unchanged
  (the established byte-identity check across fixtures).
- **`findings.sh` catalog test:** extend `tests/test-findings.sh` with
  `assert_eq "screenshot-dimensions" "$(rule_slug 42)"`.
- **Layer 2** has no deterministic test (it is agent-mode / vision). Its correctness is a
  documentation/checklist concern, consistent with how pierre-deep-review.md is maintained.

## Measurement

If any behavior changes visibly, demonstrate impact with synthetic fixtures (the new
`screenshots-app` fixture with a deliberately wrong-sized PNG) and, if warranted, the 18-app real
panel (most real OSS apps manage screenshots in App Store Connect, so the real-panel delta is
expected to be ~zero — which is itself the byte-identity evidence).

## Out of scope (v1)

- JPEG dimension parsing (SOF-marker scan) — deferred; JPEGs are format-validated + counted only.
- A maintainer "screenshot-size drift" reconcile tool paralleling guideline-drift.sh — WARN severity
  already absorbs table staleness; revisit only if the table proves churny.
- Any change to the GREEN/YELLOW/RED verdict semantics (Layer 1 adds WARNs within existing
  thresholds; Layer 2 is non-blocking by construction).

## Build method

superpowers subagent-driven-development: fresh implementer per task + two-stage review (spec +
quality); final Opus whole-branch review; `superpowers:finishing-a-development-branch`. New feature
branch; no direct commits to main; PR/merge at the end; release (v1.9.0) runs after merge.
