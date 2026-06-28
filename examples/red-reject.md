# Example: RED (submission blocked)

A run with at least one FAIL. No token is written; the upload guard blocks `fastlane deliver`
until the issues are fixed.

## scan.sh output (excerpt)

```
PASS: layout — ios='./ios/MyApp' metadata='./ios/fastlane/metadata' xcstrings='./ios/MyApp/Localizable.xcstrings' locales=8
FAIL: 5.1.1(v) Required Reason API — 'FileTimestamp' used in code (e.g. ./ios/MyApp/Cache.swift) but not declared in PrivacyInfo.xcprivacy
FAIL: 2.3.10 Other-platform mention — banned reference in metadata:
      ./ios/fastlane/metadata/en-US/description.txt:5:Also on Android and Google Play
FAIL: 3.1.2 Restore Purchases — not found in ./ios/MyApp/SubscriptionView.swift (required by Apple)
PASS: 4.0 Minimum functionality — 9 navigation hub(s) found
---END-OF-SCAN---
```

## Adversarial review (Phase 3, excerpt)

```
Guideline 3.1.2 - Business - Payments - Subscriptions
Risk: REJECT-CERTAIN

We noticed that your auto-renewable subscription does not include a functional
"Restore Purchases" control on the paywall (SubscriptionView.swift). 

Next Steps: Add a Restore Purchases action and link to your Terms of Use (EULA)
and Privacy Policy adjacent to the purchase controls.
```

## Verdict

```
| State | FAIL | WARN | PASS |
|-------|------|------|------|
|  RED  |  3   |  0   |   2  |

Most critical fix: add Restore Purchases + Terms + Privacy to SubscriptionView.swift.

→ No .precheck-pass. Submission BLOCKED until the 3 FAILs are resolved.
```
