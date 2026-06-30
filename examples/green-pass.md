# Example: GREEN pass

A run where nothing blocks submission. The skill writes `.precheck-pass` and the upload guard
allows `fastlane deliver`.

## scan.sh output (excerpt)

```
PASS: layout — ios='./ios/MyApp' metadata='./ios/fastlane/metadata' xcstrings='./ios/MyApp/Localizable.xcstrings' locales=8
PASS: 5.1.1 Required Reason API — 'UserDefaults' parity OK
PASS: 5.1.2 ATT — not used (no tracking)
PASS: 2.3.10 Other-platform mentions — metadata clean
PASS: 2.3.7 Localized metadata — checked 8 locales
PASS: 3.1.2 subscription disclosure key 'subscription_disclosure' present
PASS: 3.1.2 Restore Purchases — present in SubscriptionView.swift
PASS: 3.1.2 Terms of Use (EULA) link — present
PASS: 3.1.2 Privacy Policy link — present
PASS: 2.5.1 Private API — clean
PASS: 4.2 Minimum functionality — 12 navigation hub(s) found
PASS: 2.3.3 Screenshots — checked 8 locales under ./ios/fastlane/screenshots
PASS: export-compliance — ITSAppUsesNonExemptEncryption set in Info.plist
---END-OF-SCAN---
```

## Verdict

```
| State | FAIL | WARN | PASS |
|-------|------|------|------|
| GREEN |  0   |  1   |  12  |

guideline-drift: none (baseline reconciled 2026-06-30)
fastlane precheck: Result: true

→ .precheck-pass written (valid 60 min). Upload allowed.
```
