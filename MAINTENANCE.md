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

Walk the 41 vectors in the methodology table and confirm each still matches how Apple reviews
today. Pay special attention to the signal lists that go stale fastest:

- The tracking / ad SDK list in §16 (`scan.sh`: `tracking_sdk`). New ad and attribution SDKs
  appear often; add them as they gain adoption.
- The analytics SDK list in §19 (`scan.sh`: `analytics_sdk`).
- The third-party payment SDK list in §21 (`scan.sh`: `payment_sdk`) and the UGC / chat SDK
  signals in §22 (`ugc_signal`); both grow as new SDKs gain adoption.
- The hot-patch frameworks in §32 (`hotcode`), the crypto SDKs in §34 (`crypto_sdk`), the
  remote-desktop SDKs in §36 (`remote_desktop`), and the MDM signals in §41 (`mdm_sig`); these
  vendor lists go stale the same way the ad/analytics lists do.
- The Required Reason API categories in §1 and the sensitive frameworks in §2.
- The banned / deprecated API list in §11.
- The account-deletion rule in §38 (5.1.1(v)) and the 4.2.3 web-wrapper heuristic threshold in
  §35; both are policy-sensitive and worth re-checking after a guidelines update.

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

- **Versions:** `plugin.json`, `package.json`, and `SKILL.md` must share one version. The guard
  is `npm run check-versions`; CI runs it on every push.
- **Vector count:** the count appears in the README intro and table, `SKILL.md`, `plugin.json`,
  the methodology table, and the changelog. When you add or remove a check, update all of them.
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
- `claude plugin validate .` passes.
- The changelog has an entry and the version is bumped in lockstep.
- The manual pre-submit checklist at the end of the methodology reference still reflects what the
  scanner cannot verify.
