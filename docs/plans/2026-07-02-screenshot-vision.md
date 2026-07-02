# Screenshot Vision Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add deterministic screenshot format + PNG-dimension checks to `scan.sh` §7, and deepen Pierre's one-line screenshot review into a dedicated agent-mode structured vision checklist.

**Architecture:** A new sourced, zero-dependency bash helper (`image-dims.sh`) parses PNG magic bytes and IHDR dimensions with `od`/`awk`; `scan.sh` §7 iterates the screenshot files it already finds and emits WARN-only findings under a new `screenshot-dimensions` rule id. A new reference doc (`screenshot-vision-review.md`) adds a non-blocking, host-vision-model checklist wired into Pierre Phase 4. Existing placeholder screenshot fixtures (1–2 byte non-PNG files) are refreshed to real accepted-size PNGs so behavior stays byte-identical.

**Tech Stack:** bash 3.2, `od`, `awk`, `find`, `jq` (already required); `python3` (test-fixture generation only, never at scan/test runtime).

## Global Constraints

- READ-ONLY: no new side effects; the scanner never writes project files.
- No competitor name anywhere (repo, files, commits, branches).
- CLI/scan.sh/npx/GitHub-Action path stays OFFLINE, zero-dependency, deterministic, behavior-byte-identical on any input that does not contain real screenshot images.
- No new runtime dependency for the distributed scanner (only `bash`+`od`+`awk`+`find`+`jq`). `python3` is used ONLY to pre-generate committed test fixtures, never at scan or test runtime.
- bash 3.2 compatible (macOS; no associative arrays).
- TDD for every behavior change; byte-identity re-verified after each behavior change.
- NO version bump in-branch (bump happens at the release step across all 4 manifests).
- New Layer-1 findings are severity **WARN**, never FAIL. Layer 2 is non-blocking (`REVIEW-FINDING`), never changes the verdict.
- Register every new test suite in `tests/all.sh`.

---

### Task 1: `image-dims.sh` — format + PNG dimension helpers (unit-tested)

**Files:**
- Create: `skills/appstore-precheck/scripts/image-dims.sh`
- Create: `tests/make-png.py` (committed fixture generator; NOT shipped — outside `skills/`)
- Create: `tests/fixtures/img-dims/accepted.png` (generated, 1290×2796)
- Create: `tests/fixtures/img-dims/nonaccepted.png` (generated, 1000×1000)
- Create: `tests/fixtures/img-dims/notreally.png` (a text file with a `.png` name)
- Create: `tests/test-image-dims.sh`
- Modify: `tests/all.sh` (add `test-image-dims.sh` to the `SUITE` array)

**Interfaces:**
- Produces (sourced API used by Task 3):
  - `img_format <file>` → prints `png` | `jpeg` | `unknown`
  - `png_dims <file>` → prints `W H` (decimal, space-separated) and returns 0, or returns 1 and prints nothing
  - `dims_match_accepted <W> <H>` → returns 0 if `W×H` or `H×W` is an accepted size, else 1
  - `ACCEPTED_SIZES` → newline-separated `W H` constant (portrait)

- [ ] **Step 1: Create the fixture generator `tests/make-png.py`**

```python
#!/usr/bin/env python3
# make-png.py — generate a minimal valid solid-color PNG of exact WxH.
# Used ONCE to produce committed test fixtures; not part of the scanner or test runtime.
import sys, zlib, struct

def make_png(w, h, path):
    def chunk(typ, data):
        body = typ + data
        return struct.pack('>I', len(data)) + body + struct.pack('>I', zlib.crc32(body) & 0xffffffff)
    sig = b'\x89PNG\r\n\x1a\n'
    ihdr = struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)  # 8-bit, colour type 2 (RGB)
    row = b'\x00' + b'\x00\x00\x00' * w                  # filter byte 0 + black pixels
    idat = zlib.compress(row * h, 9)
    with open(path, 'wb') as f:
        f.write(sig + chunk(b'IHDR', ihdr) + chunk(b'IDAT', idat) + chunk(b'IEND', b''))

if __name__ == '__main__':
    make_png(int(sys.argv[1]), int(sys.argv[2]), sys.argv[3])
```

- [ ] **Step 2: Generate the three unit-test fixtures**

Run:
```bash
mkdir -p tests/fixtures/img-dims
python3 tests/make-png.py 1290 2796 tests/fixtures/img-dims/accepted.png
python3 tests/make-png.py 1000 1000 tests/fixtures/img-dims/nonaccepted.png
printf 'this is not a png\n' > tests/fixtures/img-dims/notreally.png
```
Expected: `accepted.png` and `nonaccepted.png` are valid PNGs (`file` reports "PNG image data, 1290 x 2796" / "1000 x 1000"); `notreally.png` is ASCII text.

- [ ] **Step 3: Write the failing unit test `tests/test-image-dims.sh`**

```bash
#!/usr/bin/env bash
# tests/test-image-dims.sh — unit tests for image-dims.sh (format + PNG dims).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/_assert.sh
source "$HERE/_assert.sh"
# shellcheck source=skills/appstore-precheck/scripts/image-dims.sh
source "$HERE/../skills/appstore-precheck/scripts/image-dims.sh"

FX="$HERE/fixtures/img-dims"

section "img_format"
assert_eq "png"     "$(img_format "$FX/accepted.png")"    "PNG magic detected"
assert_eq "png"     "$(img_format "$FX/nonaccepted.png")" "PNG magic detected (non-accepted size)"
assert_eq "unknown" "$(img_format "$FX/notreally.png")"   "text file with .png name is not a PNG"
assert_eq "unknown" "$(img_format "$FX/missing.png")"     "missing file is unknown"

section "png_dims"
assert_eq "1290 2796" "$(png_dims "$FX/accepted.png")"    "IHDR dimensions parsed (accepted)"
assert_eq "1000 1000" "$(png_dims "$FX/nonaccepted.png")" "IHDR dimensions parsed (non-accepted)"
assert_eq ""          "$(png_dims "$FX/notreally.png")"   "non-PNG yields no dims"

section "dims_match_accepted"
dims_match_accepted 1290 2796 && r=yes || r=no
assert_eq "yes" "$r" "1290x2796 is an accepted size"
dims_match_accepted 2796 1290 && r=yes || r=no
assert_eq "yes" "$r" "landscape orientation of an accepted size matches"
dims_match_accepted 1000 1000 && r=yes || r=no
assert_eq "no"  "$r" "1000x1000 is not an accepted size"

echo
if (( fails == 0 )); then echo "[test-image-dims.sh] OK"; else echo "[test-image-dims.sh] $fails FAILED"; fi
exit "$fails"
```

- [ ] **Step 4: Run the test to verify it fails**

Run: `bash tests/test-image-dims.sh`
Expected: FAIL — `image-dims.sh` does not exist yet (source error / functions undefined).

- [ ] **Step 5: Implement `skills/appstore-precheck/scripts/image-dims.sh`**

```bash
#!/usr/bin/env bash
# image-dims.sh — zero-dependency image format + PNG dimension helpers for scan.sh.
# Pure bash + od + awk; bash 3.2 compatible; sourced, no side effects, no output on load.

# img_format <file> -> "png" | "jpeg" | "unknown"
img_format() {
  local f="$1" sig
  [[ -r "$f" ]] || { echo unknown; return; }
  sig="$(od -An -tx1 -N8 "$f" 2>/dev/null | tr -d ' \n')"
  case "$sig" in
    89504e470d0a1a0a*) echo png ;;
    ffd8ff*)           echo jpeg ;;
    *)                 echo unknown ;;
  esac
}

# png_dims <file> -> "W H" (decimal) and return 0, or return 1 with no output.
# IHDR width = big-endian bytes 16-19, height = 20-23 (8-byte signature + 4-byte
# length + "IHDR" tag precede the 8 dimension bytes at offset 16).
png_dims() {
  local f="$1"
  [[ "$(img_format "$f")" == png ]] || return 1
  local b
  b=($(od -An -tu1 -j16 -N8 "$f" 2>/dev/null))
  [[ "${#b[@]}" -ge 8 ]] || return 1
  local w=$(( b[0]*16777216 + b[1]*65536 + b[2]*256 + b[3] ))
  local h=$(( b[4]*16777216 + b[5]*65536 + b[6]*256 + b[7] ))
  printf '%s %s\n' "$w" "$h"
}

# ACCEPTED_SIZES — current Apple App Store screenshot pixel sizes (portrait "W H").
# The matcher tries both orientations. VERIFY against Apple's official page:
# https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications/
ACCEPTED_SIZES="
1320 2868
1290 2796
1284 2778
1242 2688
1179 2556
1170 2532
1242 2208
750 1334
640 1136
2064 2752
2048 2732
1668 2388
1668 2224
1536 2048
"

# dims_match_accepted <W> <H> -> return 0 if W×H or H×W is an accepted size.
dims_match_accepted() {
  local w="$1" h="$2" aw ah
  while read -r aw ah; do
    [[ -z "$aw" ]] && continue
    if { [[ "$w" == "$aw" && "$h" == "$ah" ]]; } || { [[ "$w" == "$ah" && "$h" == "$aw" ]]; }; then
      return 0
    fi
  done <<< "$ACCEPTED_SIZES"
  return 1
}
```

- [ ] **Step 6: Verify the `ACCEPTED_SIZES` table against Apple (maintainer web step)**

Run a `WebFetch` on `https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications/` and confirm each iPhone/iPad portrait pixel size in `ACCEPTED_SIZES`. Correct any value that Apple's page contradicts. (Do NOT trust a single third-party summary; use Apple's page.) Keep `1290 2796` present — it is the size used by the cross-task fixtures. This is a maintainer/CI action; it does not run in the offline scanner.

- [ ] **Step 7: Run the test to verify it passes**

Run: `bash tests/test-image-dims.sh`
Expected: PASS — `[test-image-dims.sh] OK`, exit 0.

- [ ] **Step 8: Register the suite in `tests/all.sh`**

In the `SUITE=(...)` array (after `test-guideline-drift.sh`), add:
```bash
  "test-image-dims.sh" # image-dims.sh PNG magic + IHDR dimension parse + accepted-size match
```

- [ ] **Step 9: Run the full suite + shellcheck**

Run: `bash tests/all.sh && shellcheck skills/appstore-precheck/scripts/image-dims.sh tests/test-image-dims.sh`
Expected: `SUITE PASSED (14 files)`; shellcheck clean.

- [ ] **Step 10: Commit**

```bash
git add skills/appstore-precheck/scripts/image-dims.sh tests/make-png.py tests/fixtures/img-dims tests/test-image-dims.sh tests/all.sh
git commit -m "feat(screenshots): image-dims.sh — zero-dep PNG format + IHDR dimension helpers"
```

---

### Task 2: Refresh placeholder screenshot fixtures to real accepted-size PNGs (byte-identity prep)

**Why:** Existing fixtures use 1–2 byte non-PNG placeholder files named `01.png` (only to satisfy §7's file count). Task 3 adds format validation that would (correctly) WARN on those invalid files, changing 9 fixtures' output. Replacing them with real accepted-size PNGs keeps the file count (so the existing "only 1 image" WARN and PASS lines are unchanged) AND passes Task 3's future format/dimension checks silently — preserving byte-identity. This task is a pure fixture refresh: it changes NO scanner code, so scan output must be unchanged by it alone.

**Files (replace each 1–2 byte `.png` with a real 1290×2796 PNG):**
- Modify: `tests/fixtures/sample-app/ios/fastlane/screenshots/en-US/01.png`
- Modify: `tests/fixtures/root-app/fastlane/screenshots/en-US/01.png`
- Modify: `tests/fixtures/audio-playback-app/ios/fastlane/screenshots/en-US/01.png`
- Modify: `tests/fixtures/review-prompt-app/ios/fastlane/screenshots/en-US/01.png`
- Modify: `tests/fixtures/voice-recorder-app/ios/fastlane/screenshots/en-US/01.png`
- Modify: `tests/fixtures/clean-app/ios/fastlane/screenshots/en-US/01.png`
- Modify: `tests/fixtures/photos-picker-app/ios/fastlane/screenshots/en-US/01.png`
- Modify: `tests/fixtures/camera-capture-app/ios/fastlane/screenshots/en-US/01.png`
- Modify: `tests/fixtures/no-iap-app/ios/fastlane/screenshots/en-US/01.png`

**Interfaces:** none (fixtures only).

- [ ] **Step 1: Capture the pre-change scan output for all fixtures (baseline)**

Run:
```bash
bash tests/run.sh > /tmp/screenshots-baseline.txt 2>&1; echo "exit=$?"
```
Expected: exit 0. Keep `/tmp/screenshots-baseline.txt` for Step 3.

- [ ] **Step 2: Replace every placeholder `.png` with a real 1290×2796 PNG**

Run:
```bash
python3 tests/make-png.py 1290 2796 /tmp/real-shot.png
for p in \
  tests/fixtures/sample-app/ios/fastlane/screenshots/en-US/01.png \
  tests/fixtures/root-app/fastlane/screenshots/en-US/01.png \
  tests/fixtures/audio-playback-app/ios/fastlane/screenshots/en-US/01.png \
  tests/fixtures/review-prompt-app/ios/fastlane/screenshots/en-US/01.png \
  tests/fixtures/voice-recorder-app/ios/fastlane/screenshots/en-US/01.png \
  tests/fixtures/clean-app/ios/fastlane/screenshots/en-US/01.png \
  tests/fixtures/photos-picker-app/ios/fastlane/screenshots/en-US/01.png \
  tests/fixtures/camera-capture-app/ios/fastlane/screenshots/en-US/01.png \
  tests/fixtures/no-iap-app/ios/fastlane/screenshots/en-US/01.png ; do
    cp /tmp/real-shot.png "$p"
done
```
Expected: all nine files are now valid 1290×2796 PNGs.

- [ ] **Step 3: Verify scan output is byte-identical to the baseline**

Run:
```bash
bash tests/run.sh > /tmp/screenshots-after.txt 2>&1; echo "exit=$?"
diff /tmp/screenshots-baseline.txt /tmp/screenshots-after.txt && echo "BYTE-IDENTICAL"
```
Expected: `exit=0`, `diff` prints nothing, `BYTE-IDENTICAL`. (If any check greps binary content and diverges, stop and investigate — do not proceed.)

- [ ] **Step 4: Run the full suite**

Run: `bash tests/all.sh`
Expected: `SUITE PASSED (14 files)`.

- [ ] **Step 5: Commit**

```bash
git add tests/fixtures/*/ios/fastlane/screenshots/en-US/01.png tests/fixtures/root-app/fastlane/screenshots/en-US/01.png
git commit -m "test(fixtures): replace 1-byte screenshot placeholders with real 1290x2796 PNGs (byte-identical scan output)"
```

---

### Task 3: `scan.sh` §7 format + dimension integration + `screenshot-dimensions` rule + end-to-end fixture

**Files:**
- Modify: `skills/appstore-precheck/scripts/scan.sh` (add `source` line after `:17`; add §7b block after the §7 block ending ~`:396`)
- Modify: `skills/appstore-precheck/scripts/findings.sh:8-30` (add `42) screenshot-dimensions` to the `rule_slug` catalog)
- Modify: `tests/test-findings.sh` (assert `rule_slug 42`)
- Create: `tests/fixtures/screenshots-app/` (a project with mixed valid/invalid screenshots)
- Modify: `tests/run.sh` (add a `check_fixture screenshots-app ...` block with assertions)

**Interfaces:**
- Consumes (from Task 1): `img_format`, `png_dims`, `dims_match_accepted` (sourced from `image-dims.sh`).
- Produces: findings under `rule_id == "screenshot-dimensions"`; WARN lines beginning `WARN: 2.3.3 Screenshot ...`.

- [ ] **Step 1: Build the end-to-end fixture `tests/fixtures/screenshots-app/`**

Run:
```bash
mkdir -p tests/fixtures/screenshots-app/ios/fastlane/screenshots/en-US
mkdir -p tests/fixtures/screenshots-app/ios/App
python3 tests/make-png.py 1290 2796 tests/fixtures/screenshots-app/ios/fastlane/screenshots/en-US/01.png
python3 tests/make-png.py 1290 2796 tests/fixtures/screenshots-app/ios/fastlane/screenshots/en-US/02.png
python3 tests/make-png.py 1290 2796 tests/fixtures/screenshots-app/ios/fastlane/screenshots/en-US/03.png
python3 tests/make-png.py 1000 1000 tests/fixtures/screenshots-app/ios/fastlane/screenshots/en-US/04-wrongsize.png
printf 'not a png\n' > tests/fixtures/screenshots-app/ios/fastlane/screenshots/en-US/05-corrupt.png
cat > tests/fixtures/screenshots-app/ios/App/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict></dict></plist>
PLIST
cat > tests/fixtures/screenshots-app/ios/App/ContentView.swift <<'SWIFT'
import SwiftUI
struct ContentView: View { var body: some View { NavigationStack { Text("Hi") } } }
SWIFT
```
Expected: `en-US` has three accepted-size PNGs, one wrong-size PNG, one corrupt `.png`.

- [ ] **Step 2: Write the failing end-to-end assertions in `tests/run.sh`**

Add this block (place it near the other `check_fixture` calls, before the final total):
```bash
check_fixture screenshots-app "screenshot dimension + format checks (§7b)"
assert_has "WARN: 2.3.3 Screenshot" "wrong-size / corrupt screenshots produce a dimension/format WARN"
assert_has "1000x1000"              "the non-accepted size is reported with its dimensions"
assert_has "not a valid PNG"        "the renamed non-PNG is flagged as invalid"
assert_absent "01.png is 1290x2796" "an accepted-size PNG does not produce a size WARN"
finish_fixture
```

- [ ] **Step 3: Run run.sh to verify the new fixture assertions fail**

Run: `bash tests/run.sh 2>&1 | sed -n '/screenshots-app/,/PASSED\|FAILED/p'`
Expected: the `screenshots-app` block FAILS (the §7b checks do not exist yet).

- [ ] **Step 4: Source `image-dims.sh` in `scan.sh`**

After line 17 (`source ".../project-model.sh"`), add:
```bash
source "$(dirname "${BASH_SOURCE[0]}")/image-dims.sh"
```

- [ ] **Step 5: Add the §7b dimension/format block in `scan.sh`**

Immediately after the §7 block (the `fi` closing the `if [[ -n "$SCREEN_DIR" ... ]]` at ~line 396), insert:
```bash
# ===================================================================
# §7b — 2.3.3 Screenshot format + PNG dimensions (deterministic; PNG dims,
# JPEG format only). WARN-only: the accepted-size table can drift, and we
# cannot know which display slot a file targets, so mismatches never FAIL.
# ===================================================================
if [[ -n "$SCREEN_DIR" && -d "$SCREEN_DIR" ]]; then
  set_rule "screenshot-dimensions"
  while IFS= read -r img; do
    [[ -z "$img" ]] && continue
    fmt="$(img_format "$img")"
    case "$img" in
      *.png)
        if [[ "$fmt" != png ]]; then
          warn "2.3.3 Screenshot $img is not a valid PNG (file content does not match .png extension)" "$img"
          continue
        fi
        dims="$(png_dims "$img")"
        if [[ -z "$dims" ]]; then
          warn "2.3.3 Screenshot $img — could not read PNG dimensions (possibly truncated)" "$img"
        else
          w="${dims% *}"; h="${dims#* }"
          if ! dims_match_accepted "$w" "$h"; then
            warn "2.3.3 Screenshot $img is ${w}x${h}, which matches no known App Store screenshot size — verify against the current spec" "$img"
          fi
        fi
        ;;
      *.jpg|*.jpeg)
        if [[ "$fmt" != jpeg ]]; then
          warn "2.3.3 Screenshot $img is not a valid JPEG (file content does not match extension)" "$img"
        fi
        ;;
    esac
  done < <(find "$SCREEN_DIR" -maxdepth 3 -type f \( -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' \) 2>/dev/null | sort)
  set_rule ""
fi
```

- [ ] **Step 6: Add the catalog entry in `findings.sh`**

In `rule_slug()` (findings.sh:8-30), after the `41) echo mdm ;;` entry and before `*) echo "" ;;`, add:
```bash
    42) echo screenshot-dimensions ;;
```

- [ ] **Step 7: Add the catalog assertion in `tests/test-findings.sh`**

After the existing `assert_eq "" "$(rule_slug 999)" ...` line, add:
```bash
assert_eq "screenshot-dimensions" "$(rule_slug 42)" "catalog lookup §42 screenshot-dimensions"
```

- [ ] **Step 8: Run run.sh — new fixture assertions pass**

Run: `bash tests/run.sh 2>&1 | sed -n '/screenshots-app/,/PASSED\|FAILED/p'`
Expected: the `screenshots-app` block PASSES.

- [ ] **Step 9: Verify byte-identity for all pre-existing fixtures (self-contained)**

At this point the scan.sh + findings.sh edits are in the working tree but NOT yet committed. Capture
the baseline by temporarily stashing only those two files, so the comparison is self-contained within
this task (do not rely on any `/tmp` file from an earlier task):
```bash
git stash push -- skills/appstore-precheck/scripts/scan.sh skills/appstore-precheck/scripts/findings.sh
bash tests/run.sh > /tmp/base-precode.txt 2>&1   # pre-§7b (fixtures present, no new code)
git stash pop
bash tests/run.sh > /tmp/after-code.txt 2>&1     # with §7b
# Exclude the new screenshots-app block from BOTH; the rest must be identical.
diff <(sed '/FIXTURE: screenshots-app/,/-> PASSED/d;/FIXTURE: screenshots-app/,/ASSERTION(S) FAILED/d' /tmp/base-precode.txt) \
     <(sed '/FIXTURE: screenshots-app/,/-> PASSED/d;/FIXTURE: screenshots-app/,/ASSERTION(S) FAILED/d' /tmp/after-code.txt) \
  && echo "PRE-EXISTING FIXTURES BYTE-IDENTICAL"
```
Expected: `PRE-EXISTING FIXTURES BYTE-IDENTICAL` (the only new output is the `screenshots-app` block). If the diff is non-empty, stop and investigate before committing.

- [ ] **Step 10: Verify JSON attribution of the new findings**

Run:
```bash
tmp="$(mktemp -d)"; cp -R tests/fixtures/screenshots-app/. "$tmp/"
( cd "$tmp" && APPSTORE_PRECHECK_CONFIG=/nonexistent bash "$PWD/../../skills/appstore-precheck/scripts/scan.sh" --format json 2>/dev/null ) \
  | jq -r '.findings[] | select(.rule_id=="screenshot-dimensions") | "\(.severity) \(.message)"'
rm -rf "$tmp"
```
Expected: at least one line, each `WARN`, with `rule_id == screenshot-dimensions`. (Adjust the scan.sh path to an absolute path if needed.)

- [ ] **Step 11: Run the full suite + shellcheck + scorecard**

Run: `bash tests/all.sh && shellcheck skills/appstore-precheck/scripts/scan.sh && ./scripts/scorecard.sh --check`
Expected: `SUITE PASSED (14 files)`; shellcheck clean; `scorecard: up to date`.

- [ ] **Step 12: Commit**

```bash
git add skills/appstore-precheck/scripts/scan.sh skills/appstore-precheck/scripts/findings.sh tests/test-findings.sh tests/fixtures/screenshots-app tests/run.sh
git commit -m "feat(screenshots): §7 PNG dimension + format validation (WARN-only, rule screenshot-dimensions)"
```

---

### Task 4: Layer 2 — agent-mode structured screenshot vision review

**Files:**
- Create: `skills/appstore-precheck/references/screenshot-vision-review.md`
- Modify: `skills/appstore-precheck/references/pierre-deep-review.md` (check #8 procedure points at the new checklist)
- Modify: `skills/appstore-precheck/SKILL.md` (Phase 4 references the new checklist)

**Interfaces:** documentation only; no code, no tests (agent-mode / host vision model, mirrors how `pierre-deep-review.md` is maintained).

- [ ] **Step 1: Create `references/screenshot-vision-review.md`**

Model the structure on `pierre-deep-review.md` (rules block → checklist table → per-check procedure → output format). Content:

```markdown
# Screenshot vision review (agent-mode, non-blocking)

Deepens Pierre deep-review check #8 (2.3.5) into a dedicated, structured screenshot review.
This is the **vision layer** of the Review Simulator: the host model reads the actual screenshot
images and cross-checks their content against the metadata and the shipped app.

**Identity:** this runs ONLY in agent-skill mode (Claude Code / Codex / …), using the host LLM's
vision capability — exactly like Pierre reads code and the drift phase fetches URLs. It is NOT a
bundled dependency and does NOT run in the offline CLI / npx / GitHub-Action path.

**This phase does not change the GREEN/YELLOW/RED verdict** (verdict comes only from scan
`FAIL:`/`WARN:` counts). It emits `REVIEW-PASS:` / `REVIEW-FINDING: … WARN` lines, like Pierre
deep-review.

## Rules

- Read-only. Never modify project files.
- Evidence-based: cite the screenshot **filename** (and locale) for every finding. If you cannot
  read an image, say so — do not invent findings.
- Read at least one screenshot per primary locale; when several are present, scan them all.
- All five checks, every run: report each as `REVIEW-PASS:` or `REVIEW-FINDING: … WARN`.
- If there are no in-repo screenshots, report each check as
  `REVIEW-PASS: <guideline> — not applicable (no in-repo screenshots; managed in App Store Connect)`.
- Severity is always WARN (advisory). Cautious language ("may trigger review questions").
- Write Pierre's 2–3 sentence explanations in the user's conversation language.

## The 5 checks

| # | Guideline | Question |
|---|-----------|----------|
| S1 | 2.3.3 / 2.3.7 | Placeholder / dev-debug / empty-state content: Lorem ipsum, debug overlays or logs, visible TODO/FIXME, empty lists or skeleton loaders shown as content, simulator status bar with placeholder carrier/time. |
| S2 | 2.3.3 | Text overflow / truncation / clipping: clipped or overlapping labels, cut-off buttons, text running off-screen. |
| S3 | 2.3.5 | Wrong device frame / aspect: an iPad screenshot in an iPhone slot (or vice-versa), letterboxing, obviously stretched/squished aspect. |
| S4 | 2.3.3 / 2.3.10 | Misleading marketing: 2.3.3 "show the app in use" — the shot is a splash/title/logo/pure marketing art, not actual app UI; 2.3.10 — a feature is depicted that the app does not ship. |
| S5 | 2.3.5 | Metadata ↔ screenshot claim mismatch: visible UI text/features contradict the description, keywords, or promo text. |

## Per-check procedure

### S1 — Placeholder / dev-debug / empty-state
1. Open each screenshot; read visible text and UI state.
2. Flag Lorem ipsum, debug HUDs, log text, "TODO"/"FIXME", empty/skeleton content presented as real, or a simulator status bar with placeholder carrier/time.
3. Cite the filename. Not applicable if no screenshots.

### S2 — Text overflow / truncation
1. Inspect labels, buttons, and headings for clipping, overlap, or off-screen text.
2. Flag any truncation that suggests an unfinished or broken layout.

### S3 — Wrong device frame / aspect
1. Compare each screenshot's aspect to its locale/slot (iPhone vs iPad).
2. Flag an iPad-aspect image in an iPhone slot (or vice-versa), letterboxing, or stretched aspect.

### S4 — Misleading marketing
1. Determine whether each screenshot shows the app actually in use (real UI) vs pure title/splash/logo art.
2. Flag shots that are marketing art rather than the app in use (2.3.3), or that depict a feature absent from the build (2.3.10).

### S5 — Metadata ↔ screenshot mismatch
1. Read the visible UI text/features and compare to the description, keywords, and promo text.
2. Flag direct contradictions (a feature/claim in the screenshot not in metadata, or vice-versa).

## Output format

```
REVIEW-PASS: <guideline> — <one-line why it looks OK, with screenshot filename>
```
or
```
REVIEW-FINDING: <guideline> WARN — <one-line concrete issue, with screenshot filename>
Pierre: <2–3 sentences: why Apple cares, what you saw, what to fix or verify>
```
```

- [ ] **Step 2: Point Pierre check #8 at the new checklist**

In `references/pierre-deep-review.md`, in the "### 8 — 2.3.5 Screenshots vs reality" procedure, append a final line:
```markdown
4. For the full structured screenshot vision review (placeholder/empty-state, text overflow,
   wrong device frame, misleading marketing, metadata mismatch), follow
   `references/screenshot-vision-review.md`.
```

- [ ] **Step 3: Reference the checklist from SKILL.md Phase 4**

In `SKILL.md`, in the Phase 4 description (where `references/pierre-deep-review.md` is referenced), add a sentence:
```markdown
When screenshots are present, also run the structured screenshot vision review in
`references/screenshot-vision-review.md` (non-blocking; host vision model; never changes the verdict).
```

- [ ] **Step 4: Verify docs consistency + suite still green**

Run: `bash tests/all.sh && grep -c "screenshot-vision-review" skills/appstore-precheck/SKILL.md skills/appstore-precheck/references/pierre-deep-review.md`
Expected: `SUITE PASSED (14 files)`; each file references the new doc at least once.

- [ ] **Step 5: Commit**

```bash
git add skills/appstore-precheck/references/screenshot-vision-review.md skills/appstore-precheck/references/pierre-deep-review.md skills/appstore-precheck/SKILL.md
git commit -m "feat(screenshots): agent-mode structured vision review (Layer 2, non-blocking) wired into Pierre Phase 4"
```

---

### Task 5: Documentation — methodology + README

**Files:**
- Modify: `skills/appstore-precheck/references/methodology.md` (document §7b + limitations)
- Modify: `README.md` (mention the screenshot dimension/format check where checks are described)

**Interfaces:** documentation only.

- [ ] **Step 1: Add a methodology note**

In `references/methodology.md`, in the section describing §7 / screenshots, add:
```markdown
### Screenshot format + dimensions (§7b, 2.3.3)

The deterministic scanner reads each in-repo screenshot's magic bytes and, for PNGs, its IHDR
dimensions (offset 16–23), with no dependencies beyond `od`/`awk`. It emits a WARN when a `.png`
or `.jpg`/`.jpeg` file's content does not match its extension, when a PNG is truncated, or when a
PNG's dimensions match no known App Store screenshot size (either orientation). These are **WARN
only**: the accepted-size table can drift as Apple revises device specs, and the scanner cannot know
which display slot a given file targets, so a size mismatch never forces a RED verdict. JPEG
dimensions are not parsed in this version (JPEGs are format-validated and counted only). The
accepted-size table lives in `scripts/image-dims.sh` and is verified against Apple's screenshot
specifications page.
```

- [ ] **Step 2: Add a README mention**

In `README.md`, where screenshot checks (2.3.3) are listed, add a short bullet:
```markdown
- **Screenshot format & size (2.3.3):** flags corrupt/mislabelled image files and PNG dimensions that match no known App Store screenshot size (advisory WARN).
```

- [ ] **Step 3: Verify suite + versions still consistent (no bump in-branch)**

Run: `bash tests/all.sh && ./scripts/check-versions.sh`
Expected: `SUITE PASSED (14 files)`; `OK: versions match (1.8.0)` (bump happens at release, not here).

- [ ] **Step 4: Commit**

```bash
git add skills/appstore-precheck/references/methodology.md README.md
git commit -m "docs(screenshots): document §7b dimension/format check + limitations"
```

---

## Self-Review

**Spec coverage:**
- Layer 1 deterministic dimension/format → Tasks 1 + 3. ✓
- New `image-dims.sh` (pure bash + od/awk, zero-dep) → Task 1. ✓
- New rule id `screenshot-dimensions` → Task 3 (findings.sh #42). ✓
- WARN severity, never FAIL → §7b block (Task 3) uses only `warn`. ✓
- Byte-identity for existing fixtures → Task 2 (fixture refresh) + Task 3 Step 9 (diff). ✓
- JPEG dims deferred (format-only) → §7b `*.jpg|*.jpeg` branch checks format only. ✓
- Layer 2 agent-mode structured checklist → Task 4 (new reference + Pierre #8 + SKILL Phase 4). ✓
- Non-blocking / never changes verdict → Layer 2 emits REVIEW-* only. ✓
- Tests registered in all.sh → Task 1 Step 8. ✓
- Docs / methodology / limitations → Task 5. ✓
- No version bump in-branch → Task 5 Step 3 asserts 1.8.0. ✓

**Placeholder scan:** every code/test/doc step contains full content; no TBD/TODO in the plan itself (the "TODO"/"FIXME" strings are screenshot-content examples in the S1 checklist). ✓

**Type/name consistency:** `img_format`, `png_dims`, `dims_match_accepted`, `ACCEPTED_SIZES`, and rule slug `screenshot-dimensions` are used identically in Tasks 1 and 3. Fixture size `1290×2796` is used consistently in Tasks 1–3 and is present in `ACCEPTED_SIZES`. ✓

**Note for executor:** `od -An -tu1 -j16 -N8` field parsing in `png_dims` uses unquoted `b=($(...))` array capture — this is intentional word-splitting of numeric `od` output; shellcheck SC2207 may warn. If shellcheck fails CI, add `# shellcheck disable=SC2207` on that line with a comment, or use `read -r -a b < <(od ...)`.
