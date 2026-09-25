# Section 4 route implementation handoff

The Section 4 fragment still contains 246 records, including 104 obligations. No IDs,
source fingerprints, criteria, or generic attestation routes changed.

## Added routes

- Five new read-only static checks in `scripts/lib/section4-review.py`, all with
  triggering and clean fixtures in `tests/test-section4-review.sh`:
  - `section4-extension-commerce`: two partial routes for advertising and in-app
    purchase API references scoped to a declared extension source tree.
  - `section4-keyboard-navigation`: one partial route for a declared keyboard
    extension and a source hint for its keyboard-switch control.
  - `section4-safari-access`: one partial route for a declared Safari extension
    and broad manifest host permissions.
  - `section4-apple-branding`: one partial route for an Apple brand term in an
    app display name. Authorization remains a human question.
  - `section4-placeholder-copy`: two partial routes for explicit placeholder
    literals in app source. Absence produces SKIP, never PASS.
- Existing `dyn-siwa-parity` is linked once to the 4.8 primary-login obligation.
- Existing semantic `brand-use` is linked to two 4.1(c) name/brand obligations.

All new checks return NEEDS_REVIEW, SKIP, or NOT_RUN. They never decide the
complete guideline duty, so the attestation routes remain. The existing
`dyn-placeholder` check returns PASS from marker absence; it was deliberately
not linked to 4.2 because that does not establish app completeness.

## Integration

1. Merge this branch into `feat/guideline-coverage-100`.
2. Run `python3 scripts/coverage.py --merge` to add the fragment routes and five
   registry entries to the central files.
3. Add `tests/test-section4-review.sh` to `tests/all.sh`.
4. The opt-in route runner can call
   `python3 skills/appstore-precheck/scripts/lib/section4-review.py --repo "$project"`
   and record each JSON check status; no default-scan invocation is requested.
5. Run `tests/test-obligations-4.sh` after the central registry merge. Before
   that merge, it cannot resolve the new fragment check IDs by design.

## Verification

- `bash tests/test-section4-review.sh`: passed.
- A temporary union of all obligation and registry fragments validated with
  `scripts/coverage.py`: 585/585 obligations routed, 148 checks registered.
- Section 4 files passed the private source eight-word overlap check.
- `npm run lint` passed with `PYTHONPYCACHEPREFIX=/private/tmp/appstore-pycache`.
- The full copyright test with the private source available currently reports
  an overlap in `scripts/scan.sh`; this branch does not edit that file.
