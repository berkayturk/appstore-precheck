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
