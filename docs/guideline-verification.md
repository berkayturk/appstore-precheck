# Guideline verification

The static verdict, the tool's control capability, and the evidence available for
one submission answer different questions. A GREEN result is not a full guideline
review and does not guarantee Apple approval.

The versioned [verification contract](../skills/appstore-precheck/references/guideline-verification.md)
defines external app profiles, evidence references and condition decisions. Inputs
and reports for a real app belong outside its source tree and outside public Git/npm.
A [blank profile](../skills/appstore-precheck/references/verification-profile.example.json)
starts all target fields and feature facts as unknown; fill them from scoped evidence.

Every catalog obligation remains in the denominator. Verified findings count toward
review completion, but never toward the verified PASS percentage. Verified N/A is
reported separately and needs evidence for the actual exclusion or exception.
Source hints, missing tools, unexecuted routes, owner answers and observed buttons
cannot masquerade as full verification. Independent reviewers must substantiate
content, legal, operational and backend claims with appropriate evidence.

A simulator observation applies to that simulator build. Distribution entitlements,
physical-device behavior, StoreKit transactions and live store declarations require
their own evidence. Changes in source, artifact, backend, storefront or guideline
scope reopen affected decisions. No paid service or private upload is required.

The existing static scanner and upload-token contract remain unchanged. The new
verification report is opt-in, local and separate; it neither creates a token nor
turns a risk acceptance into a passing result.
