# Field tests: dogfooding on real App Store apps

To validate the scanner beyond its own fixtures, it was run against three large,
open-source iOS apps that ship via fastlane with real subscriptions and privacy
manifests. The goal was not to judge those apps, but to find **scanner** bugs:
false positives, false negatives, and auto-detection failures. Two real detection
bugs (plus a portability bug) were found and fixed; the remaining findings are either
genuine observations or documented heuristic limits with a config/manual remedy.

| Repo | Resolved iOS dir | Locales | Verdict (counts) | What it exercised |
|------|------------------|---------|------------------|-------------------|
| [duckduckgo/iOS](https://github.com/duckduckgo/iOS) | `./DuckDuckGo` | 22 | RED (8 FAIL / 1 WARN / 11 PASS) | Subscriptions, 22-locale metadata, multi-manifest privacy |
| [Automattic/pocket-casts-ios](https://github.com/Automattic/pocket-casts-ios) | `./podcasts` | 12 | RED (21 FAIL / 2 WARN / 9 PASS) | Watch app + main app, centralized purchase/legal UI |
| [wikimedia/wikipedia-ios](https://github.com/wikimedia/wikipedia-ios) | `./Wikipedia/Code` | 0 | RED (3 FAIL / 2 WARN / 6 PASS) | Framework-heavy, no in-repo ASC metadata, no IAP |

All three were shallow-cloned and scanned read-only. Verdict counts are post-fix.

## Bugs found and fixed

### 1. iOS source dir resolved to the wrong target (false negative + false positive)

Detection keyed the iOS source dir purely on **Info.plist location** (the dir with the
most Swift files). Modern Xcode apps often have **no checked-in Info.plist** for the main
target (it is auto-generated), so detection landed on whichever target *did* ship one:

- **pocket-casts** → picked `./Pocket Casts Watch App`. StoreKit lives in `./podcasts`,
  so IAP went undetected and the entire 3.1.2 paywall section was wrongly **skipped**
  (false negative, the worst kind for this tool).
- **wikipedia** → picked `./WMF Framework`. A framework imports `CoreLocation` but
  legitimately carries no `NSLocationWhenInUseUsageDescription` (that belongs to the app),
  producing a **spurious 5.1.1 purpose-string FAIL** (false positive).

**Fix** (`fix(detect): find the app target via entry point + paywall cluster`): candidate
dirs now also include **app-entry-point** dirs (`@main` / `AppDelegate`), scored by Swift
count with non-app targets (Watch / Extension / Widget / Intents / Clip / Notification /
Share / Sticker / Tests / Framework) deprioritized so they only win when nothing app-like
exists. After the fix: pocket-casts → `./podcasts` (IAP detected), wikipedia →
`./Wikipedia/Code` (CoreLocation false positive gone, now an honest "Info.plist not found"
WARN). DuckDuckGo was already correct (`./DuckDuckGo`) and stayed correct. A regression
fixture (`tests/fixtures/watch-app`) locks this in.

Two sub-bugs surfaced alongside it:
- The `find`-style prune list was being passed to `grep` (invalid), so the entry-point
  search silently matched nothing. Added a grep-native `GREP_PRUNE` (`--exclude-dir`).
- The required-links check grepped a single auto-picked file and FAILed when it landed on a
  `*ViewModel*` or a manage/cancel screen. It now excludes `*ViewModel*` and greps the whole
  **paywall cluster**; a link in any paywall view satisfies the requirement.

### 2. Empty array unbound under `set -u` (portability)

The `watch-app` regression fixture (0 locales + IAP) immediately exposed a second bug on the
CI runner's bash: a `declare -a` array that is never populated makes `${#arr[@]}` an
unbound-variable error under `set -u`, aborting the scan before the verdict. Fixed by
initializing arrays with `=()` (and keeping the `${arr[@]+…}` idiom for bash 3.2 empty-array
*expansion*, which macOS still ships). This compounded an earlier macOS-only crash fixed in
`fix: guard empty LOCALES/PAYWALL_GLOBS expansion under bash 3.2 set -u`.

## Remaining findings: real, or documented heuristic limits

These are **not** bugs to fix in the scanner; they are either true observations or known
limits of static analysis, each with a remedy.

- **3.1.2 links not in the paywall *view* (pocket-casts).** Restore lives in
  `InAppPurchases/IAPHelper.swift` and Terms/Privacy in `LegalAndMoreView.swift` /
  `AccountViewController`, architecturally separate from the paywall view files. The
  cluster grep still FAILs because the links aren't *in the paywall UI*, which is itself a
  legitimate 3.1.2 angle (Apple expects them on/near the purchase screen). Confirmed remedy:
  pointing `paywallGlobs` at the real files (`*IAPHelper*`, `*LegalAndMore*`, …) turns all
  three into PASS. Takeaway: on apps that centralize purchase/legal UI, set `paywallGlobs`.
- **5.1.1 SystemBootTime flags `CACurrentMediaTime()` (duckduckgo, pocket-casts).** The
  hits are in animation code (`Confetti.swift`, `WMFWelcomeAnimation…`), where a Required
  Reason declaration is likely unnecessary. Apple's stance on `CACurrentMediaTime()` (built
  on `mach_absolute_time`) is genuinely gray, so the check flags it for **manual review**
  rather than risk a false negative by ignoring it. Treat a used-but-undeclared 5.1.1 Required
  Reason API line as "verify," not gospel, especially in multi-manifest apps, where the symbol may be
  declared in a different target's `PrivacyInfo.xcprivacy` than the one the scanner reads.
- **2.3.7 metadata gaps (duckduckgo keywords, pocket-casts name/subtitle).** Real
  observations: several locales have empty/absent `keywords.txt` (DuckDuckGo) or `name.txt`
  (pocket-casts manages those centrally rather than per-locale in-repo). Whether these are
  defects depends on the project's delivery setup; the scanner correctly reports the
  in-repo state.
- **2.5.1 private API (wikipedia).** One banned-identifier match; worth a manual look, the
  kind of signal the check exists to raise.

## Conclusion

≥3 real, large third-party repos validated the scanner end-to-end. Dogfooding caught and
fixed two real auto-detection bugs (wrong target → IAP false-negative + framework
purpose-string false-positive) and a `set -u` portability crash, with a regression fixture
added. The residual FAILs are real findings or architecture-dependent heuristic limits, each
with a `paywallGlobs` / manual-verification remedy. None are silent scanner errors.

## Earlier coverage groundwork field run (2026-10-02)

ControlDopamine was scanned with the default scanner on macOS with Bash 3.2.
That earlier snapshot added coverage accounting and launch-evidence corrections,
before the new static vectors were integrated. The existing source-only findings remain advisory.

| Check | Result | Evidence / interpretation |
|---|---|---|
| Default static scan | GREEN: 0 FAIL, 3 WARN, 26 PASS, 0 SKIP | `scan.sh --dir ../controldopamine`; no token applied |
| New-vector WARN review | Not applicable: zero new static vectors | No new WARN is attributed to this change; this does not validate the planned §56–§71 checks |
| Source preservation | Before/after `git status --porcelain` identical | Empty status diff; source content hash was not measured |
| Existing built app discovery | SKIP: zero candidates, exit 3 | `app-discover.sh --repo ../controldopamine --json` |
| Live dynamic review | NOT_RUN: no existing simulator `.app` found | No build or simulator launch performed; the new launch rules are covered by offline shims only |

The section inventory is separate from the run: optional semantic, vision and dynamic
routes do not become observed merely because they appear in the baseline.


## Guideline expansion field run (2026-10-02)

ControlDopamine was scanned read-only on macOS with Bash 3.2.57, using its existing
configuration and suppression file. No build, installation, launch, network review,
or `verdict.sh --apply` was performed. Before/after `git status --porcelain` was
byte-identical; source content hashes were not measured.

| Command / observation | Result | Scope |
|---|---|---|
| `scan.sh --dir ../controldopamine --format json` | Exit 0; 0 FAIL, 3 WARN, 40 PASS, 1 suppressed record | Existing findings remain; none of the new vectors warns after the fix below |
| Default text scan piped to `verdict.sh` without `--apply` | GREEN; fail=0 warn=3 pass=41 skip=0 | Text also counts the unstructured layout PASS; no token was written |
| `coverage_sections` | 26/102 sections touched; 2 SKIP records; 9 human-only | Static run only; deep/dynamic/vision remain unexecuted |
| New §56–§71 results | 15 PASS observations, 1 rule SKIP; additional icon-visual SKIP | PASS means no matched heuristic signal, not policy verification |
| §63 extension parity | SKIP | Main bundle identifier is build-setting-derived; a resolved archive is required |
| §69 icon pixels | SKIP | Apple emoji artwork requires visual review; metadata text was checked |
| `app-discover.sh --repo ../controldopamine --json` | Exit 3, `candidates: []`, `launched: false` | No existing simulator bundle was found; device archives do not qualify |
| Live dynamic D1–D17 review | NOT_RUN | No simulator `.app`; no build attempted. D9 already covers 2.4.1, so six new checks end at D17 |

### Manual decisions for every new WARN

| Vector | Initial observation | Manual decision and final result |
|---|---|---|
| §57 / 2.4.4 `device-restart-instructions` | `ios/ControlDopamineTests/MonotonicClockTests.swift` contains a reboot-related Swift Testing test description | **False positive, narrowed.** It describes a unit test, not user-facing instructions. Files importing Swift Testing/XCTest are excluded from this check. A red then green regression test covers both imports; the real rerun emits PASS. |

No other new-vector WARN appeared. The retained unsuppressed warnings concern
permission priming copy, trial-first paywall wording and the existing Xcode upgrade
heuristic; they are outside this expansion. The suppressed privacy-manifest finding
remains recorded with its existing suppression.

The first integration run also exposed two evidence-reader limits. Compiled
`.app`/`.xcarchive` resources were being read as source: those bundles are now pruned,
with a regression fixture. The 5,588,422-byte String Catalog exceeded the generic
2 MiB read limit: localization resources now have a separate bounded 8 MiB limit,
with readable-large and too-large abstention tests. Source/manifest limits remain
2 MiB, and incomplete inputs still produce SKIP rather than absence claims.

Runtime fixtures are synthetic and tool shims, not recordings of this application.
Capture and MusicKit checks only verify positive observations; missing-indicator and
missing-authorization defect detection is not implemented. Location review reports
observed request timing; WhenInUse/Always scope comparison is not implemented.
See `tests/local/guideline-runtime-notes.md` for exact runtime limits.


## Review round 1 field rerun (2026-10-02)

Run from this repository with `--dir ../controldopamine`. Default JSON and text scans
returned exit 0: 0 FAIL, 3 WARN, 40 structured PASS, 1 suppressed finding. The text
renderer also includes the existing unstructured layout PASS. The three unsuppressed
warnings remain permission-priming copy, trial-first paywall copy and the Xcode upgrade
heuristic; no §56–§71 WARN was produced, so no additional new-vector warning required
a manual disposition. The earlier reboot-test false positive remains fixed.

Run coverage now counts issue-bearing sections only: **3/102**, with **2 unique skipped
sections** and **2 unaudited check records** (extension bundle resolution and icon pixels).
PASS absence observations are excluded. The repository inventory is **93 touched,
2 positive-only**; it does not describe this application's verified compliance.

The review's emoji check inspects artwork asset names, not metadata characters. The
document-access check accepts system document pickers and reviews custom browser signals.
Discovery again returned exit 3 with no simulator app candidates. Live dynamic checks
remain NOT_RUN; no build or simulator session was started.

Read-only preservation was checked by SHA-256 before/after for 6,646 regular files:
zero changes. The snapshot excludes .git, dependencies, caches, symlinks and compiled
bundles. Git status was not rerun under this review's no-Git instruction. Evidence lives
in `.planning/guideline-91-evidence/review-section6-field-*.log` and
`review-field-preservation.json` in the review checkout.
