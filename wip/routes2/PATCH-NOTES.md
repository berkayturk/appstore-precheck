# Section 2 route patch

## Implemented

- Added three opt-in, read-only checks in `scripts/lib/section2-review.py`: source signals for visible placeholders or unfinished code; source signals for reviewer login or remote-service dependence; and a local fastlane screenshot inventory for visual comparison.
- Each check emits `NEEDS_REVIEW` for a matching signal, `SKIP` when it has no suitable evidence, and `NOT_RUN` when the repository is missing. It never emits `PASS` or `FINDING`. Output contains only relative paths, line numbers, signal labels, and image counts; no source lines, URLs, screenshots, or credentials.
- Added `references/registry/section2.json` with three implemented check IDs and `tests/test-section2-review.sh` with triggering, clean, and unavailable fixtures.
- Added 28 partial route edges across 19 Section 2 obligations: 8 edges for the new checks and 20 edges to existing metadata and artifact checks. Existing attestation routes remain. No new route is labeled `full`.

## Integration requests

1. Merge the fragment with `python3 scripts/coverage.py --merge`; do not copy this worker's central catalogs. Add `bash tests/test-section2-review.sh` to `tests/all.sh`.
2. Run `section2-review.py --repo "$PROJECT_ROOT"` only in the explicitly requested Section 2 deep review. Record its per-check `NEEDS_REVIEW`, `SKIP`, or `NOT_RUN` status in the obligation run report. Default `scan.sh` output must remain unchanged.
3. If an opt-in ASC read is available, run the existing metadata checks for Section 2 review notes, demo account fields, screenshots, category, age rating, and selected URLs. Their `PASS` means a field or image exists, not that its content is accurate or a service works.
4. If a built artifact is available, run the existing artifact checks for debug residue, direct private API linkage, executable loading, entitlements, and SDK age. An unsigned simulator app can yield `SKIP` for entitlements.

## Verification

- `bash tests/test-section2-review.sh` passed.
- Temporary `coverage.py --merge` passed: 585/585 routed and 133 registered checks in this worktree snapshot.
- `bash tests/test-copyright-boundary.sh` passed package boundary; source-overlap test skipped because the private cache is absent in this worktree.
- `python3 -m py_compile` and `git diff --check` passed.
- `npm run lint`, `bash scripts/check-versions.sh`, `claude plugin validate .`, and `grok plugin validate .` passed (Claude reports an existing ignored `interface` field warning).
- `npm test` reached the complete suite but failed two catalog tests in this unmerged worktree: `test-obligations-2.sh` reads the central registry before this fragment is merged, and `test-obligations-1.sh` rejects the reviewed Section 1 root ref `1`. The integrator must rerun after merging fragments and fix the latter assertion.

## Limits

Source hints do not prove that the submitted release is complete or that a backend remains available. Screenshot filenames do not prove that an image depicts app operation. URL field checks establish syntax and optional HEAD reachability only. Demo credential presence does not prove successful sign-in; the runtime quorum check remains responsible for that observation. Apple review-period continuity remains an attestation.
