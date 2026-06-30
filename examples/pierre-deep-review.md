# Example: Phase 4 deep review (REVIEW-FINDING)

Advisory output from Pierre's 22 semantic checks. These lines do **not** change the
GREEN/YELLOW/RED verdict — they flag issues a static grep cannot catch.

## Context

Static scan: **GREEN** (0 FAIL, 2 WARN). Phase 4 still runs all **28** checks (22 Kova A + 6 Kova B v1 †).

## Phase 4 summary

```
Deep review: 28 checks — 25 REVIEW-PASS, 3 REVIEW-FINDING
```

## REVIEW-FINDING lines (excerpt)

```
REVIEW-FINDING: 2.1 WARN — metadata description promises "AI-powered insights" but no ML/AI framework or on-device model found in Swift
Pierre: Guideline 2.1 requires that store listing accurately represent app functionality. Your English description advertises AI analysis, yet the codebase has no Core ML, Vision, or third-party ML SDK imports — reviewers treat this as misleading metadata. Either implement the feature or remove the claim before submission.

REVIEW-FINDING: 5.1.1(i) WARN — privacy policy states "We do not collect precise location" but Info.plist declares NSLocationWhenInUseUsageDescription and LocationManager is used in MapView.swift:18
Pierre: Under 5.1.1(i) Apple compares your privacy policy to actual data practices. The fetched policy denies location collection while MapView.swift requests when-in-use location — a direct contradiction reviewers reject. Update the policy or remove location usage.

REVIEW-FINDING: 3.1.2 WARN — paywall disclosure is a single keyword stub ("subscription_terms") with no readable trial or cancel sentence in SubscriptionView.swift
Pierre: 3.1.2 requires clear auto-renewal and cancellation language users can understand. Your paywall references a string key but the resolved text is not a legible sentence covering trial length, renewal, and how to cancel. Replace with full disclosure copy in every locale before review.
```

## Phase 5 verdict (unchanged by deep review)

```
| State | FAIL | WARN | PASS |
|-------|------|------|------|
| GREEN |  0   |  2   |  39  |

Deep review: 3 advisory findings — review before submit; token still written.

→ .precheck-pass written (valid 60 min). Upload allowed.
```
