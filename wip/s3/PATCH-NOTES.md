# Section 3 integration notes

Source reviewed: [Apple App Review Guidelines, section 3](https://developer.apple.com/app-store/review/guidelines/#3), checked 2026-09-25. Apple's page reports a June 8, 2026 update, matching the private v31 catalog. No source paragraphs are copied here.

## Inventory and lineage

- `references/obligations/3.json` covers every 3.x requirement fragment in the private catalog: 127 source records and their 117 stable candidate atom IDs. No candidate atom was retired or renamed. Heading-only and intentionally omitted clauses have no requirement-fragment ID and therefore no artificial obligation record.
- Source fragments that are explanatory, examples, permissions, consequences, or decomposed parents are retained as informational or exception context. The 117 child atoms contain 94 obligations and 23 exceptions. The source-level `related` fields link each parent to its atoms; atom-level `related` fields point back to the parent. Broad IAP rules cite specific qualifying exceptions in `exceptions`.
- The `kind`, criterion, applicability, platform, and route assignments were independently checked against the live section. In particular, external purchase links retain the US storefront carve-out, regional entitlement scope, and iOS/iPadOS limitation; reader, enterprise, individual service, physical goods, hardware, and charitable fundraising permissions are conditional rather than universal IAP waivers.

## Route implementation requests

Each atom has a proposed full route with `check_id: null` and a temporary `proposed_check_id`. These are **not implemented checks**. Replace the placeholders with registered and fixture-tested check IDs, or consolidate related atoms under a truthful broader check. Current check IDs are attached only as `partial`. Counts below describe proposals, not automatic coverage:

| Proposed primary route | Atoms | Work needed |
| --- | ---: | --- |
| attestation | 63 | Request documentary evidence for rights, approvals, territorial licenses, purchase/refund operations, charity status, and payment arrangements; unknown stays pending. |
| semantic | 28 | Review offer content, trial terms, marketing, collections, deceptive mechanics, and payment UX with cited screenshots and reviewer judgment. |
| runtime | 11 | Observe restore, entitlements after purchase, tier changes, paywalls, and action gates with the dynamic-run API; failed exploration must remain SKIP. |
| metadata | 8 | Inspect App Store Connect products, pricing, loan/offer disclosures, and review notes through the optional read-only metadata route. |
| static | 7 | Scan identifiable payment mechanisms, entitlement and StoreKit configuration, wallet/mining code, and binary-option indicators as leads, never final business-policy conclusions without context. |

Existing checks contribute only partial evidence for 27 atoms (38 partial links). Notably `dyn-restore-tap` proves a visible tap, not an actual restoration; `thirdparty-payment-sdk` detects code, not the applicable storefront or product; `crypto-wallet-mining` cannot establish off-device processing; loan and financial compliance require developer evidence. No current check was marked `full`.

## Merge and review points

- Merge the section file into `guideline-obligations.json` by stable ID. Preserve the section's richer criteria and contextual links. The current skeleton's 3.x placeholders should be replaced, not appended.
- The future coverage validator should treat null `check_id` on non-context routes as a gap until an implementation and test are registered. `proposed_check_id` is a planning hint, not evidence of coverage.
- Review 3.1.1(a) against current entitlement contracts and storefront list at run time; those regions can change while the guideline text stays constant. A storefront-unavailable run is `NEEDS_REVIEW` or `NOT_RUN`, not `PASS`.
- Review 3.1.2(c)'s referenced Schedule 2 terms separately. This section file records that incorporation by reference, but cannot reproduce or validate contractual text from the guideline alone.
- Regulatory claims in 3.1.5 and 3.2.1–3.2.2 need territory-specific evidence; an observed app screen cannot establish a license or legal compliance.
- Apple combines loan APR, fees, and repayment deadline in 3.2.2(ix); retain distinct atoms because each can fail independently.

## Verification

`PRIVATE_CATALOG_PATH=/Users/bt/claude/appstore-precheck/.planning/opus-work/skills/appstore-precheck/references/requirement-catalog.json bash tests/test-obligations-3.sh` passes. The test checks source and atom ID completeness, links and routes, and eight-word source overlap without printing source content. In CI without the private file, it still validates the public schema and explicitly skips the source comparison.
