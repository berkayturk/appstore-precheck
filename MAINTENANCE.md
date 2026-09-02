# Maintenance

This scanner encodes Apple's App Store Review Guidelines, a moving target. The checks are static
and hand maintained, so they drift out of date unless someone reconciles them on a schedule. This
file is that schedule. None of it is automated on purpose: drift detection that silently fixes
itself would hide the very gap it is meant to surface.

## Cadence

### Monthly: guideline drift check

Run Phase 0 (the live guideline drift check) against the tracked baseline and act on the result.

- The mechanics and the two-pass fetch technique live in
  [`references/methodology.md`](skills/appstore-precheck/references/methodology.md#phase-0-guideline-drift-check).
- The baseline is [`skills/appstore-precheck/guidelines-baseline.json`](skills/appstore-precheck/guidelines-baseline.json).
- If the check reports NEW or REMOVED section numbers, review the live page, decide whether the
  change deserves a new scan check, then reconcile the baseline by hand and set `reconciled_on`
  to the date you did it. Never let a script update the baseline.

### Quarterly: vector and pattern review

Walk the 55 vectors in the methodology table and confirm each still matches how Apple reviews
today. Also spot-check the 31 Pierre deep-review checks in
[`references/pierre-deep-review.md`](skills/appstore-precheck/references/pierre-deep-review.md)
after major guideline updates. Pay special attention to the signal lists that go stale fastest:

- The tracking / ad SDK list in §16 (`scan.sh`: `tracking_sdk`). New ad and attribution SDKs
  appear often; add them as they gain adoption. Every signal in the list has a named case in
  [`tests/test-sdk-signals.sh`](tests/test-sdk-signals.sh) — add one there with the SDK's real
  module/entry-point symbol, plus a negative case if the symbol is a common English word.
- The analytics SDK list in §19 (`scan.sh`: `analytics_sdk`), covered by the same test file.
- The third-party payment SDK list in §21 (`scan.sh`: `payment_sdk`) and the UGC / chat SDK
  signals in §22 (`ugc_signal`); both grow as new SDKs gain adoption.
- The hot-patch frameworks in §32 (`hotcode`), the crypto SDKs in §34 (`crypto_sdk`), the
  remote-desktop SDKs in §36 (`remote_desktop`), and the MDM signals in §41 (`mdm_sig`); these
  vendor lists go stale the same way the ad/analytics lists do.
- The Required Reason API categories in §1 and the sensitive frameworks in §2.
- The banned / deprecated API list in §11.
- The account-deletion rule in §38 (5.1.1(v)) and the 4.2.3 web-wrapper heuristic threshold in
  §35; both are policy-sensitive and worth re-checking after a guidelines update.
- The IPv4 exclusion heuristics in §55 (`ipv4-literal`): loopback / `0.0.0.0` / `255.x` / CIDR /
  version-looking values / comments. A false WARN here is cheap to add an exclusion for; a missed
  literal is what the reviewer's NAT64 network finds.
- The ad / attribution **vendor → domain** catalogue in
  `skills/appstore-precheck/scripts/lib/dyn-hosts.sh` (`dyn_tracking_domain_catalogue`), which the
  dynamic tier's `dyn-hosts-contacted` compares against `NSPrivacyTrackingDomains`. It mirrors the
  §16 SDK list and goes stale the same way: when an SDK is added to §16, add its endpoint domains
  here. `tests/test-dynamic-libs.sh` pins the row shape (`vendor<TAB>domain`).
- The framework detection rules in `framework-detect.sh` (`package.json` react-native dependency,
  `pubspec.yaml` + `ios/Runner.xcodeproj`, Gradle/`.kt` + `iosApp/`) and the Metro precondition
  (port 8081, `main.jsbundle`) in `dynamic-run.sh`; toolchains move their layouts.

A pattern that is missing a popular new SDK is a silent false negative, so this review matters
more than it looks.

### After every WWDC (mandatory)

WWDC is when Apple ships the largest batch of policy and privacy-manifest changes. Treat the next
reconciliation as required, not optional:

- Reconcile `guidelines-baseline.json` against the updated guidelines.
- Check for new Required Reason APIs and privacy-manifest rules, and update §1 and the
  `PrivacyInfo.xcprivacy` expectations.
- Re-read the export-compliance, ATT, and account-deletion rules; these shift between releases.
- Bump `fastlane` so Phase 2 (`fastlane precheck`) carries Apple's latest rule engine.

## Keeping the pieces in lockstep

- **Versions:** `.claude-plugin/plugin.json`, `.cursor-plugin/plugin.json`,
  `.grok-plugin/plugin.json`, `.grok-plugin/marketplace.json` (`plugins[0].version`),
  `package.json`, and `SKILL.md` must share one version. The guard
  is `npm run check-versions`; CI runs it on every push.
- **Grok marketplace `sha` (optional, post-merge):** the `.grok-plugin/marketplace.json` entry
  points at this repo by URL and is unpinned, so the marketplace flow installs GitHub `main` and
  deployments with `require_sha` refuse it. To pin a release, once the release commit is on `main`
  set `plugins[0].source.sha` to its full sha and push that as a follow-up commit. Unpinned is the
  supported default; see [`docs/publishing-plugins.md`](docs/publishing-plugins.md).
- **Hook envelopes:** every plugin manifest wires the same `hooks/hooks.json`, and the hosts
  disagree on the payload shape: `.tool_input.command` (Claude Code), `.toolInput.command`
  (Grok Build, camelCase throughout), `.command` (Cursor `beforeShellExecution`). Reading only one
  shape fails **open** on the others. The guard reads all three and `tests/test-guard.sh` covers
  each. On a block it writes Pierre's reason to **both** stderr (Claude Code shows stderr on
  exit 2) and stdout as JSON (`decision: deny` plus `hookSpecificOutput.permissionDecision`),
  because Grok documents stderr feedback only for `Stop`/`SubagentStop`. When adding a host, add
  its envelope to the jq chain and a test case, or the guard silently stops guarding.
- **Homebrew formula:** the tap ([`berkayturk/homebrew-tap`](https://github.com/berkayturk/homebrew-tap))
  pins the npm tarball of one exact version, so every npm release MUST be followed by
  `bash scripts/update-brew-formula.sh` (fetches the published tarball, rewrites the formula's
  `url` + `sha256`, pushes the tap). The guard is the weekly `brew-sync` workflow, which fails
  when the tap drifts from npm latest.
- **Vector count:** the count appears in the README intro and table, `SKILL.md`,
  the methodology table, and the changelog. When you add or remove a check, update all of them.
  The deep-review count (31) lives in the same places plus `pierre-deep-review.md`; the Tier B
  item list (4, 5, 7, 10, 15, 29, 30, 31) is repeated in SKILL.md, the reference and the README.
  The **dynamic-check catalogue** is `dyn_catalogue` in `scripts/dynamic.sh`; the reference
  `simulator-dynamic-review.md` must name every id in it (`tests/test-phase6-doc.sh` enforces this),
  and the `runtime-not-audited` count is derived from it, never typed.
- **Output format:** tests assert on the exact `FAIL:` / `WARN:` / `PASS: <topic> — <detail>`
  shape. The em-dash in those output lines is machine format and stays. Prose everywhere else
  stays human, with no em-dashes.

## Adding a check

Follow [`docs/adding-a-check.md`](docs/adding-a-check.md). In short: add the check to `scan.sh`
behind its signal gate, add a fixture that trips it plus an `assert_absent` guard on a clean
fixture so it cannot false-fire, then bump the count across every surface above. Uncertain or
exemption-prone checks are WARN, never FAIL.

## Before each release

- `npm test`, `npm run lint`, and `shellcheck -x --severity=warning` on the changed scripts are
  green.
- `claude plugin validate .` and `grok plugin validate .` pass.
- `bash tests/local/run-dynamic.sh` (macOS only; boots a throwaway simulator and **executes** a
  built app you confirm — never part of `tests/all.sh`). The shimmed CI counterpart is
  `tests/test-dynamic-run.sh`; this one proves the real `simctl` / Maestro path still works on the
  current Xcode.
- The changelog has an entry and the version is bumped in lockstep.
- The manual pre-submit checklist at the end of the methodology reference still reflects what the
  scanner cannot verify.
- **After `npm publish`:** run `bash scripts/update-brew-formula.sh` so the Homebrew tap ships the
  new version. Not optional — brew users stay on the old release until this runs, and the weekly
  `brew-sync` CI check goes red on drift.
