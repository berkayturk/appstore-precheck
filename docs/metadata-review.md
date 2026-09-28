# Metadata and App Store Connect review

`metadata-review.sh` reads a project's `fastlane/metadata/` and screenshots. App Store Connect (ASC) access is opt-in, read-only, and uses GET requests. It does not run `fastlane deliver`, submit an app, or change store data.

```sh
bash skills/appstore-precheck/scripts/metadata-review.sh --repo /path/to/app
ASC_KEY_ID=... ASC_ISSUER_ID=... ASC_KEY_PATH=/path/to/AuthKey.p8 \
  bash skills/appstore-precheck/scripts/metadata-review.sh --repo /path/to/app \
  --asc-app-id 1234567890 --login-required --out /tmp/metadata-review.json
```

`--asc-app-id` selects ASC mode. `--asc-version-id` and `--asc-info-id` resolve ambiguity when an app has multiple resources. Without a version ID, the reviewer chooses the newest iOS editable version by `createdDate`, or the newest iOS version if none are editable. Without an info ID, it uses the first app info returned. Review the selected resource in ASC before relying on its status.

The token uses `ASC_KEY_ID`, `ASC_ISSUER_ID`, and `ASC_KEY_PATH`. Python creates a ten-minute ES256 JWT and signs with `openssl`. The private key is read from its existing path; neither the key nor JWT is saved. `ASC_P8_PATH` used by the older Phase 2 wrapper is intentionally separate. Missing keys, OpenSSL, network, authorization, or an ASC resource produce `SKIP` for affected checks. No credentials or raw metadata values are emitted.

`--check-urls` separately opts in to HEAD requests for privacy and support URLs. Without it, those checks verify only URL presence and syntax and explicitly say reachability was not checked. The HEAD implementation accepts public HTTP(S) destinations only, including redirects. A failed HEAD request needs review because some sites reject HEAD even when GET works.

The JSON result has one stable record for each of eleven `meta-*` checks: `check_id`, `status`, `evidence_class`, `reason`, and sanitized `evidence`. `NOT_RUN` means the route was not selected or no local source exists; `SKIP` means applicable evidence could not be obtained. `PASS` confirms only the stated presence/configuration condition. Missing information yields `NEEDS_REVIEW`; this module does not create a blocking `FAIL:` line. Demo credentials are checked as required only when ASC says `demoAccountRequired` or the caller passes `--login-required`. No conclusion is drawn about whether a demo account can actually log in or remains valid through review.

## Sources used

| Check | Local fastlane source | ASC GET resource |
| --- | --- | --- |
| `meta-age-rating` | — | `/v1/apps/{id}/appInfos`, then `/v1/appInfos/{id}/ageRatingDeclaration` |
| `meta-review-notes` | `metadata/review_information/notes.txt` | `/v1/appStoreVersions/{id}/appStoreReviewDetail` |
| `meta-demo-account` | `metadata/review_information/demo_user.txt`, `demo_password.txt` | Same review detail, presence only |
| `meta-iap-review-notes` | — | `/v1/apps/{id}/inAppPurchasesV2`; `/v1/apps/{id}/subscriptionGroups` and group subscriptions |
| `meta-iap-screenshot` | — | `/v2/inAppPurchases/{id}/appStoreReviewScreenshot`; `/v1/subscriptions/{id}/appStoreReviewScreenshot` |
| `meta-privacy-url` | `metadata/{locale}/privacy_url.txt` | `/v1/appInfos/{id}/appInfoLocalizations` |
| `meta-support-url` | `metadata/{locale}/support_url.txt` | `/v1/appStoreVersions/{id}/appStoreVersionLocalizations` |
| `meta-category` | `metadata/primary_category.txt` | Primary category relationship on app info |
| `meta-price` | — | `/v1/apps/{id}/appPriceSchedule`, base territory and manual price relationship |
| `meta-storefront` | — | `/v1/apps/{id}/appAvailabilityV2`, then `/v2/appAvailabilities/{id}/territoryAvailabilities` |
| `meta-screenshots` | `fastlane/screenshots/{locale}/*.{png,jpg,jpeg}` | Version localizations, screenshot sets, and screenshots |

Local fastlane review information may contain credentials. The report records only whether both fields are populated. ASC IAP and subscription checks inspect resources returned by these endpoints; versions or products omitted by ASC permissions remain a coverage gap. A screenshot's presence does not establish its truthfulness or compliance. Storefront and price presence does not validate regional legal or commercial terms.

The endpoint and field choices follow [Apple's App Store Connect API documentation](https://developer.apple.com/documentation/appstoreconnectapi/) and the [fastlane deliver metadata layout](https://docs.fastlane.tools/actions/deliver/). The offline test uses `--asc-fixture` with `APPSTORE_PRECHECK_TEST_MODE=1` to inject mock GET responses without credentials or network access. The output identifies fixture mode so it cannot be mistaken for a live ASC check.
