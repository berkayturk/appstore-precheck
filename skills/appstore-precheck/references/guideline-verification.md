# Evidence-bound verification contract (version 1)

Verification is an explicit, offline, read-only workflow, separate from the legacy
GREEN/YELLOW/RED verdict and `.precheck-pass`. Route availability, review completion,
and compliance are different measurements. It cannot guarantee Apple approval.

## Inputs

All inputs are external JSON files; never write them into the application. Every
file has `schema_version: 1`. Unknown facts stay `null`, not `false`.

* Profile: `target` contains `bundle_id`, `version`, `build`, `artifact_sha256`,
  `source_sha256`, `platform`, `os`, `devices`, `storefronts`, `backend`, and
  `distribution` (simulator/distribution/physical). `reviewed_at` is an ISO date.
  `facts` maps names to `{value, evidence_ids, scope, observed_at}`. Unknown target
  fields are permitted for a gap report, but cannot support verified closure.
* Evidence manifest: `evidence` is a list of `{id, kind, path, sha256,
  collected_at, scope, collector, limitations}`. Paths are local, relative to the
  manifest or absolute; no remote fetch, credential URLs, embedded secrets or
  executable content. Hashes must match bytes read. Scope binds the target fields;
  no implicit wildcard or simulator-to-distribution promotion. Dates in the future,
  expired evidence, missing files and wrong hashes leave affected claims open.
* Decisions: `decisions` is a list of `{obligation_id, applicability, conditions}`.
  Applicability is `{status, rationale, evidence_ids, reviewer, source_ids}` with
  APPLICABLE / NOT_APPLICABLE / UNKNOWN. Only evidence-reviewed and justified
  non-applicability can close an item. `source_ids` names the applicable criterion
  or exception. Conditions are `{condition_id, status, evidence_ids, mode,
  verifier, reviewer, rationale}`. `mode` is `automatic` or `reviewed`;
  `status` is PASS / FINDING / UNKNOWN. Reviewed decisions need an identified
  reviewer and rationale as well as evidence; an unverified supplied answer is
  still an attestation. Never invent an owner signature or legal authority.
* Optional legacy config: `attestations` keeps `answer/evidence/answered_on`.
  `yes` remains ATTESTED_YES; it never supplies verified conditions.

## Trusted policy and sufficiency

Versioned policy fragments live in `references/verification/`. Each section file
contains `{schema_version: 1, section, obligations: [...]}`. Each policy row names
`obligation_id`, `conditions`, `applicability_evidence`, `owner`, and `document_group`.
Each condition has `id`, `description`, `evidence_kinds`, `full_positive_verifiers`,
`decisive_finding_verifiers`, and `review_requirement`. These separate the scope of
positive proof from the narrower proof of a decisive violation. An absent policy
falls back to one `criterion` condition requiring independent evidence review;
route `decides: full` alone never grants new verification capability.

The evaluator must not accept caller-defined conditions or verifier capabilities.
Automatic verifiers must inspect hashed evidence content and bind their result to
that obligation and condition. Merely setting a verifier name, `verified: true`,
or a PASS/FINDING status in a manifest is not proof. A keyword scan is a lead.

Full PASS requires APPLICABLE and sufficient evidence for every required condition.
One proven necessary-condition violation is a VERIFIED_FINDING even if other
conditions remain open. Contradiction takes precedence over PASS and N/A. A newer
failure cannot be hidden by an older PASS. Partial observations remain unresolved.
Runtime violations require three independent fresh-environment failures; mixed
results, driver deadlines, backend outages and degenerate accessibility trees do
not establish an app violation. Restore needs entitlement/receipt confirmation;
account deletion needs authorized test-backend confirmation.

Output includes all catalog obligations, verified N/A separately, unresolved
requirements, owner, scope, evidence IDs and limitations. Unknown applicability
stays in the denominator. Completion includes verified findings; compliance counts
only VERIFIED_PASS. Automatic and reviewed decisions have separate counts.
Readiness requires every item VERIFIED_PASS or NOT_APPLICABLE_VERIFIED, with no
conflicts or invalid required evidence. Errors in one record must not erase others.

Changing build, source, backend, platform, storefront, policy or evidence invalidates
relevant closure. A risk acceptance is not compliance. Evidence file integrity is
not document authenticity or institutional approval; record that owner review gap.
