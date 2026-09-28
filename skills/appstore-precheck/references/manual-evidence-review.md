# Manual and semantic evidence packet

The offline packet generator assembles every catalog obligation from the installed
criterion policies. It re-runs the verification evaluator against external inputs;
it does not trust a supplied report's result labels. It makes no network, model,
build or runtime calls, and never grants a review approval. Packet creation returning
exit 0 means files were produced, **not** that the application is ready.

```sh
python3 skills/appstore-precheck/scripts/manual-review-packet.py \
  --source-root /path/to/read-only-app \
  --profile /tmp/app-review/profile.json \
  --evidence /tmp/app-review/evidence.json \
  --decisions /tmp/app-review/decisions.json \
  --out /tmp/app-review/manual-packet
```

`--profile` uses the [verification contract](guideline-verification.md). All target
fields may initially be null; unknown facts create gaps, not exclusions.
`--evidence` and `--decisions` are optional: omitted files mean empty evidence and
claims. `--config` accepts external legacy attestations; yes remains ATTESTED_YES.
`--source-root` is required to guard output isolation. `--out` must be a new directory
outside that root, including through symlinks. The directory is private (0700), files
are 0600, and existing output is never overwritten. Errors return exit 2 with a
payload-free diagnostic. Use private external paths; do not commit application packets.

The three output files are:

- `manual-review-packet.json`: every obligation, owner, exact condition IDs,
  applicability and exception context, review requirements, evaluator results,
  evidence pointers, gaps and limitations. Counts are derived at runtime.
- `developer-input-backlog.json`: pending requests grouped by owner and document
  group, with exact obligation/condition mappings and a shared evidence-kind index.
  Provide a reusable document once and identify the relevant locations for each
  mapped condition. Kinds are permitted alternatives subject to the complete review
  requirement; the index is not a demand to supply every alternative. Policies may
  additionally specify `required_positive_evidence_kinds`; these are necessary for a positive PASS decision and appear
  separately in requests and in the shared index's `mandatory_positive_for` mappings.
  They do not require a missing license/approval to be supplied before a violation
  can be established, and their presence does not guarantee authenticity.
- `manual-review-packet.md`: the grouped questions and evidence requirements for
  reviewers. The JSON remains the complete condition/result record.

Every attestation-only obligation remains in the packet. A missing installed policy
is explicitly counted as a policy gap and retains a criterion review request. It
cannot be hidden by a smaller denominator. New section policies are picked up on the
next run; policy and catalog hashes bind the packet to the rules used. Re-generate
when the rules, target scope, source, listing, backend, or evidence changes.

## Observations and interpretation

Optional `--observations` accepts version 1 analyst notes. The following identifiers
are synthetic; use actual obligation/condition IDs from the generated packet and
actual evidence IDs from the manifest:

```json
{
  "schema_version": 1,
  "observations": [{
    "obligation_id": "synthetic-obligation",
    "condition_id": "content-inventory",
    "basis": "observed",
    "summary": "The supplied capture shows one localized content state.",
    "location": "capture-01, screen 1",
    "evidence_ids": ["capture-01"],
    "limitations": ["Other locales, remote content and feature states were not observed."]
  }]
}
```

`observed` means a cited local observation; `inferred` means an interpretation that
still needs confirmation; `attested` means a supplied assertion. These annotations
never close a condition. A caller-supplied `verified` basis is rejected. Verified
status comes only from the trusted evaluator and its sufficient scoped evidence.
Malformed notes are isolated, allowing other valid notes to survive.

Evidence candidates rejected for incomplete scope, age, hash or identity remain
visible in `observation_evidence_candidates` with validation errors. A note citing
such a candidate is explicitly marked as having incomplete or invalid evidence
binding; it cannot establish scoped closure. Missing/invalid records do not become
valid because their file is listed. Accepted evaluator evidence is kept separately.
Sensitive environment values and credential URL patterns are redacted, but private
source, documents and outputs must still stay local.

## What the owner and reviewer must supply

Each request copies the exact criterion policy's evidence types and review scope.
For content, cover bundled, remote, user and third-party material, supported locales,
feature states and ongoing controls. For minimum functionality, use the complete
product flow and supported platforms. For metadata, compare the actual selected
listing to the shipped artifact and observed behavior. For privacy and consent,
trace actual data use and recipients against consent, SDK configuration and declared
practices. For licenses and regulated activity, identify the relevant rights, holder,
territory, term and authorized use. For UGC operations, inspect operational processes
and credible records as well as UI entry points. These are review scope examples;
the installed policy supplies each exact requirement.

One screenshot, a clean sample, the presence of a document, or a source keyword cannot
prove complete compliance. A snapshot does not guarantee future remote content or
backend operations. Simulator evidence cannot establish distribution signatures,
entitlement approval or physical-device behavior. Missing runtime authorization or
test backend remains NOT_RUN, not an application violation.

Reviewed closure additionally requires the verification contract's substantive
`review-record` observations and a supplied `reviewer-authority` record identifying
a human reviewer, role, authorizing owner, basis and exact authorized obligation IDs.
The packet leaves reviewer identity empty and requests this input; it never generates
an authority record, signature, owner confirmation or legal/institutional approval.
The evaluator's integrity checks do not establish document authenticity. An analyst
must not invent authority or turn a supplied yes answer into a verified conclusion.
Keep unverified authenticity, institutional permission and operational claims open.
A risk acceptance cannot change a verified violation into PASS.
