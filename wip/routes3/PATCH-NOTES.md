# Section 3 route integration

Seven opt-in, read-only checks now produce bounded evidence packets from app source,
entitlement files, and local StoreKit test configuration. They add 21 partial
links to Section 3 obligations. All positive signals return `NEEDS_REVIEW`.
No signal returns `SKIP`; missing repositories return `NOT_RUN`. No raw source,
prices, product IDs, URLs, or credentials enter JSON output.

| Check | Evidence | Obligation links |
| --- | --- | ---: |
| `section3-payment-mechanisms` | StoreKit and third-party checkout source signals | 1 |
| `section3-license-unlock` | license and activation based unlock signals | 1 |
| `section3-subscription-offer` | offer wording and price/term facets | 8 |
| `section3-external-entitlement` | external checkout call sites and entitlement presence | 5 |
| `section3-iap-catalog` | local StoreKit product/period signals | 1 |
| `section3-random-item-odds` | paid random item and odds wording | 1 |
| `section3-loan-terms` | loan, APR, fee, repayment wording | 4 |

The local `.storekit` file is simulator test data, not App Store Connect state.
Its short-period marker is a review lead, not a final violation. Source text
cannot determine the actual paywall display, payment eligibility by storefront,
subscription value, gift/refund operations, loan effective APR, or legal approval.
Those obligations retain the generic attestation route. The external purchase
entitlement is also only a presence signal; current contractual terms and
regional availability need independent review.

Integrator: merge this branch, run `python3 scripts/coverage.py --merge`, and add
`tests/test-section3-review.sh` to `tests/all.sh`. The existing
`tests/test-obligations-3.sh` checks against the central registry, so it passes
after the merge step. Wire `section3-review.py --repo <path>` only into an
explicit report/review flow; it is intentionally absent from the default scan.

Verification: fixture test, syntax compilation, and in-memory merged registry
validation pass. On the read-only ControlDopamine source tree the check completed
in under one second after excluding generated `output/` and dependency trees.
