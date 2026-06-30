# Example: RED (submission blocked)

A run with at least one FAIL. No token is written; the upload guard blocks `fastlane deliver`
until the issues are fixed.

## scan.sh output (excerpt)

```
PASS: layout — ios='./ios/MyApp' metadata='./ios/fastlane/metadata' xcstrings='./ios/MyApp/Localizable.xcstrings' locales=8
FAIL: 5.1.1 Required Reason API — 'FileTimestamp' used in code (e.g. ./ios/MyApp/Cache.swift) but not declared in PrivacyInfo.xcprivacy
FAIL: 2.3.10 Other-platform mention — banned reference in metadata:
      ./ios/fastlane/metadata/en-US/description.txt:5:Also on Android and Google Play
FAIL: 3.1.2 Restore Purchases — not found in ./ios/MyApp/SubscriptionView.swift (required by Apple)
PASS: 4.2 Minimum functionality — 9 navigation hub(s) found
---END-OF-SCAN---
```

## Pierre commentary (Phase 3, excerpt)

```
FAIL: 5.1.1 Required Reason API — 'FileTimestamp' used in code (e.g. ./ios/MyApp/Cache.swift) but not declared in PrivacyInfo.xcprivacy
Pierre: Apple requires every Required Reason API your app uses to be declared in PrivacyInfo.xcprivacy with an approved reason code. Cache.swift reads file timestamps but the manifest does not declare FileTimestamp — reviewers reject this under 5.1.1. Add the category and a matching reason to PrivacyInfo.xcprivacy.

FAIL: 2.3.10 Other-platform mention — banned reference in metadata:
      ./ios/fastlane/metadata/en-US/description.txt:5:Also on Android and Google Play
Pierre: Store metadata must not promote other app stores. Line 5 of your English description names Android and Google Play, which is a standard 2.3.10 rejection. Delete every other-platform reference from metadata before resubmitting.

FAIL: 3.1.2 Restore Purchases — not found in ./ios/MyApp/SubscriptionView.swift (required by Apple)
Pierre: Subscription apps must offer Restore Purchases on the paywall so users can recover purchases. SubscriptionView.swift has no restore control — Guideline 3.1.2 blocks submission until you add one wired to StoreKit.
```

## Verdict

```
| State | FAIL | WARN | PASS |
|-------|------|------|------|
|  RED  |  3   |  0   |   2  |

Most critical fix: add Restore Purchases + Terms + Privacy to SubscriptionView.swift.

→ No .precheck-pass. Submission BLOCKED until the 3 FAILs are resolved.
```
