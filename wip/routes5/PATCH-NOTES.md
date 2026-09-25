# Section 5 route implementation

This branch adds four read-only source evidence checks and links eight Section 5 obligations to partial evidence routes. Every obligation retains its generic developer attestation. No source signal is treated as a compliance decision, and missing signals are SKIP.

## New checks

- `section5-contact-select-all`: a Contacts picker and a Select All UI control occur in one source file. Review the live recipient selection flow.
- `section5-contact-preselect`: a Contacts picker and an assignment of all contacts to the selected set occur in one source file. Review the initial selection state.
- `section5-safari-obscure`: a SafariViewController and a covering or hidden view operation occur in one source file. Review the rendered presentation.
- `section5-privacy-entry`: a privacy policy or notice UI label is present. Review whether the current policy is reachable and easy to find.

The evidence packet includes only relative source paths, line numbers, and signal names. It excludes source text, URLs, and credential values. The scanner excludes dependency, build, test, and symlinked directories and has file/size/line bounds.

## Existing checks linked

- `meta-privacy-url`: privacy policy metadata field presence, partial evidence for the App Store listing requirement.
- `dyn-permission-prompt`: a runtime permission prompt is partial evidence for location notice and permission timing.
- `dyn-hosts-contacted`: a host inventory is partial evidence for reviewing third-party data destinations; it does not reveal what data was sent.

## Integrator requests

1. Merge `references/registry/section5.json` with `scripts/coverage.py --merge` after this branch merges.
2. Add `tests/test-section5-review.sh` to `tests/all.sh`.
3. Invoke the new scanner only in the optional expanded review path, for example `python3 skills/appstore-precheck/scripts/lib/section5-review.py --repo <source-root>`, and merge its four records into the normalized run results. Keep the default scan text unchanged.
4. Keep all four new routes partial; do not count a source hint as a full automatic decision.
