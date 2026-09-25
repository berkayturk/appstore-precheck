# Section 1 route patch

This patch registers three opt-in, read-only evidence checks for ten Section 1 obligations. Each added route is partial; generic attestation remains available for every mapped obligation.

| Check | Route | Obligations | Output boundary |
|---|---|---:|---|
| `section1-ugc-controls` | static | 3 | UGC source signal and separate prepublication filter, report, and block hints; actual workflow remains `NEEDS_REVIEW`. |
| `section1-kids-dependencies` | static | 2 | Requires confirmed `--kids-category yes`; scans source and dependency manifests for third-party ad/analytics SDK signals; presence and absence both require review. |
| `section1-safety-signals` | semantic | 5 | Categorized source-text hints for weapons commerce, medical measurement, substance commerce, and anonymous calling; interpretation and behavior require review. |

Run: `python3 skills/appstore-precheck/scripts/lib/section1-review.py --repo APP_PATH [--kids-category yes]`.
The JSON packet never includes matching source text; it contains a relative file, line number, and signal category. `SKIP` means the limited pattern set did not apply or did not find a hint, not compliance. No check emits `PASS` or `FINDING`.

Integration: merge `references/registry/section1.json` with `scripts/coverage.py --merge`, add `tests/test-section1-review.sh` to `tests/all.sh`, and invoke the new checker only in the explicit review path. Do not infer Kids Category from child-oriented marketing text alone. The scanner's existing `ugc-no-moderation` PASS remains a weaker hint and should not override the new packet's review status.

Verified: fixture test, Python compile, temporary catalog/registry merge and validation, copyright/package boundary test, diff whitespace check.
