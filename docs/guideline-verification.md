# Guideline verification

The static verdict, the tool's control capability, and the evidence available for
one submission answer different questions. A GREEN result is not a full guideline
review and does not guarantee Apple approval.

The versioned [verification contract](../skills/appstore-precheck/references/guideline-verification.md)
defines external app profiles, evidence references and condition decisions. Inputs
and reports for a real app belong outside its source tree and outside public Git/npm.
A [blank profile](../skills/appstore-precheck/references/verification-profile.example.json)
starts all target fields and feature facts as unknown; fill them from scoped evidence.

Every catalog obligation remains in the denominator. Verified findings count toward
review completion, but never toward the verified PASS percentage. Verified N/A is
reported separately and needs evidence for the actual exclusion or exception.
Source hints, missing tools, unexecuted routes, owner answers and observed buttons
cannot masquerade as full verification. Independent reviewers must substantiate
content, legal, operational and backend claims with appropriate evidence.

A simulator observation applies to that simulator build. Distribution entitlements,
physical-device behavior, StoreKit transactions and live store declarations require
their own evidence. Changes in source, artifact, backend, storefront or guideline
scope reopen affected decisions. No paid service or private upload is required.

The existing static scanner and upload-token contract remain unchanged. The new
verification report is opt-in, local and separate; it neither creates a token nor
turns a risk acceptance into a passing result.

Run the local verification command with explicit external inputs:

```sh
node bin/cli.js verify --profile /tmp/review/profile.json \
  --evidence /tmp/review/evidence.json --decisions /tmp/review/decisions.json \
  --out /tmp/review/report.json --markdown /tmp/review/report.md
```

`verify --help` lists its inputs. Exit 0 means ready in the supplied scope; 1 means
findings, unresolved evidence or record errors; 2 means invalid top-level inputs or
unreadable files. The report preserves valid records when another record is malformed.
Use schema version 1 with `evidence: []` and `decisions: []` for an initial empty
review: every obligation stays unresolved. `--config` accepts legacy attestations;
a yes answer remains `ATTESTED_YES`.

Applicability labels are requests, not proof. An implemented applicability predicate
or a scoped, authorized substantive review must establish applicability before a
condition can close an obligation. A reviewed applicability decision makes the overall
closure reviewed even when the condition verifier is automatic. The condition policies
and [generated capability report](verification-capability.md) expose positive and
negative directions separately. Regenerate them with
`python3 scripts/verification-policy.py --require-complete`.

For source-only access, `scan.sh --dir /path/to/app --build --metadata --no-runtime
--out /tmp/app-review --format json` builds an isolated copy and inspects it without
launching. A simulator artifact is not signed distribution proof. Runtime navigation
requires an explicit test/sandbox allowlist; see the
[state transition contract](../skills/appstore-precheck/references/runtime-transition-evidence.md).
Demo login additionally requires `--demo-login`, `PRECHECK_DEMO_AUTHORIZED_TEST=1`,
`PRECHECK_DEMO_ENVIRONMENT=test|sandbox`, and credentials/selectors supplied privately
through environment variables. Neither a button nor a successful UI selector proves a
backend transaction, receipt, entitlement or completed account deletion.

[Manual evidence packets](../skills/appstore-precheck/references/manual-evidence-review.md)
group criterion-specific requests by owner and reusable document package. They retain
observed, inferred and attested notes separately from verified results, including
scope-incomplete observations. Where a positive decision needs an actual approval,
license or consent record, generic feature inventory and reviewer authority cannot
replace that document. The packet never supplies a reviewer signature or owner approval.
