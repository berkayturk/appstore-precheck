# Metadata integration notes

- Merge `references/registry/metadata.json` into `check-registry.json` through `scripts/coverage.py --merge`.
- Add `tests/test-metadata-review.sh` to `tests/all.sh`.
- Wire an explicit metadata opt-in in `scan.sh` or the CLI; invoke `metadata-review.sh --repo "$SCAN_ROOT"` and optionally `--asc-app-id`, `--login-required`, `--check-urls`. Parse its JSON records into the run report's `coverage_run` and obligation results. Do not print raw ASC values.
- Candidate obligation routes: age rating declarations (1.3/2.3.6), App Review notes and demo fields (2.1(a)), IAP notes/screenshots (3.1.1, 2.1), localized privacy/support URLs (5.1.1(i), 1.5, 2.3), primary category (2.3), price/storefront (3.x), screenshots (2.3.3). Use `decides: partial` unless the obligation is exactly field presence; content truth, account validity, and regional legality require semantic/attestation evidence.
- The JSON records are intentionally advisory. `SKIP` and `NOT_RUN` must remain visible. No `FAIL:` line or `verdict.sh` change is needed.
