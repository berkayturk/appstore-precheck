# Section 6 route integration

- Merge this branch after the other section fragments. Only `obligations/intro.json`, `registry/section6.json`, `section6-review.py`, this note, and its fixture test were changed.
- Run `python3 scripts/coverage.py --merge` from the integrated branch to bring the new routes into the public catalog and central registry. Then run `bash tests/test-section6-review.sh` and add that test to `tests/all.sh`.
- The optional source hint runner is `python3 skills/appstore-precheck/scripts/lib/section6-review.py --repo <project>`. It emits `{schema_version: 1, checks: [...]}` using the same result shape as section 1/4. Add it to the opt-in review orchestration, if section runners are invoked there; absent invocation, report `NOT_RUN` honestly.
- The two new checks identify dependency manifests and hardware API references. They produce `NEEDS_REVIEW`, never a compliance `PASS` or blocking finding. They do not emit dependency names or source lines, only file/line/signal evidence.
- Existing metadata checks `meta-demo-account`, `meta-review-notes`, `meta-iap-review-notes` and existing semantic/runtime checks are linked as partial evidence where appropriate. The post-submission expedite and bug-fix procedures remain attestation only.
- Keep the generic attestation route on each obligation. A launch observation or filled review note cannot prove the full, ongoing, or conditional obligation.
