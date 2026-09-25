# Attestation integration notes

This branch owns only the generic attestation/reporting engine, registry fragment, focused test, and reference documentation.

## Registry and obligation wiring

`references/registry/attestation.json` defines `attestation-generic`. Merge it with `python3 scripts/coverage.py --merge`. Add this route to every obligation that cannot receive a full automatic or semantic decision in the final reviewed catalog:

```json
{
  "route": "attestation",
  "check_id": "attestation-generic",
  "decides": "full",
  "evidence_class": "developer-attestation"
}
```

Keep any existing partial routes. Set `primary_route` to `attestation` when it is currently null; otherwise preserve the meaningful primary route. Update the per-section fragment, then regenerate the central catalog. Do not add this route to `informational`, `definition`, or `exception` rows. The generated question comes from each reviewed, public `criterion`, so reviewer changes to those criteria affect questions without embedding Apple text.

## Run API

```sh
python3 skills/appstore-precheck/scripts/attestation-report.py \
  --catalog skills/appstore-precheck/references/guideline-obligations.json \
  --registry skills/appstore-precheck/references/check-registry.json \
  --config /path/to/app/.appstore-precheck.json \
  --run-results /path/to/normalized-check-results.json \
  --out /path/to/obligation-report.json \
  --markdown /path/to/obligation-report.md
```

`--config` and `--run-results` can be omitted; the report then records unanswered attestations and NOT_RUN checks. The `--run-results` file is `{ "checks": { "check-id": { "status": "PASS|FINDING|WARN|SKIP|NOT_RUN|REVIEW_REQUIRED", "evidence": "pointer", "reason": "..." } } }`. PASS/FINDING require evidence; SKIP/NOT_RUN/REVIEW_REQUIRED require reason. An omitted check is NOT_RUN. The integrator should normalize existing scanner/artifact/runtime/metadata outputs into this map only for checks actually invoked; never synthesize PASS from silence. The script writes JSON to `--out` (or stdout when omitted) and Markdown to `--markdown` when requested. `summary`, `sections`, and `obligations` are stable top-level JSON keys. `summary.route_counts` counts possible routes per obligation; `summary.routes_run` counts attempted routes; `summary.automatically_decided` counts only full automatic PASS/FINDING in this run. The output may be included as `coverage_run` in the opt-in scan JSON envelope, or distributed as a companion artifact. Keep the existing default text output byte-identical.

`tests/test-attestation-report.sh` provides yes/no/unknown/missing/invalid attestation fixtures; automatic PASS/FINDING, semantic PASS, partial-result abstention, NOT_RUN, invalid check result, CLI JSON/Markdown, and registry-fragment validation. Add it to `tests/all.sh` in the integrator branch.

The config shape is `attestations:{obligation_id:{answer,evidence,answered_on}}`. Answers must be lowercase `yes`, `no`, or `unknown`; evidence is a nonempty, single-line pointer; date is ISO `YYYY-MM-DD` and cannot be future. Self-reported answers are `ATTESTED_YES` or `ATTESTED_NO`, never a verified PASS/FINDING. Unknown and invalid answers remain unresolved.
