# Guideline coverage and developer attestations

The public obligation catalog records each app obligation, its source reference, and possible check routes. `coverage.json` counts these routes. A route means a check is implemented; it does not mean that check ran or passed for a particular app. The run report records that distinction for every obligation.

Run an obligation report with a results file from the checks you invoked:

```sh
python3 skills/appstore-precheck/scripts/attestation-report.py \
  --config /path/to/app/.appstore-precheck.json \
  --run-results /path/to/check-results.json \
  --out /path/to/obligation-report.json \
  --markdown /path/to/obligation-report.md
```

The config may contain developer answers under `attestations`. Use each public catalog obligation ID as a key:

```json
{
  "attestations": {
    "atom-example-id": {
      "answer": "yes",
      "evidence": "docs/review-notes.md#content-rights",
      "answered_on": "2026-09-25"
    }
  }
}
```

The example ID is a placeholder; use an ID from `guideline-obligations.json`. Answers are exactly `yes`, `no`, or `unknown`. Evidence is a nonempty, single-line pointer to a document, screenshot, test result, or review note; use a date in `YYYY-MM-DD` form. Do not put credentials or private content in the evidence pointer. A missing or invalid answer is `ATTESTATION_REQUIRED`. `unknown` stays `ATTESTATION_UNKNOWN`. A `yes` becomes `ATTESTED_YES`, which remains a developer statement and never becomes an observed PASS. A `no` becomes `ATTESTED_NO` for manual review.

The `--run-results` file is a JSON object whose `checks` field maps registered check IDs to results. A decisive result needs an evidence pointer. A skipped or unavailable result needs a reason:

```json
{
  "checks": {
    "registered-check-id": {
      "status": "SKIP",
      "reason": "Required input was unavailable"
    }
  }
}
```

Accepted run statuses are `PASS`, `FINDING`, `WARN`, `SKIP`, `NOT_RUN`, and `REVIEW_REQUIRED`. A check missing from that file is `NOT_RUN`. Only a `full` route with an actual `PASS` or `FINDING` decides an obligation. Partial routes remain evidence but do not close the decision. The report's automatic decision rate counts only `static`, `artifact`, `runtime`, or `metadata` routes that made such a decision in this run. Semantic decisions and developer answers have their own status. The summary distinguishes available route counts from routes actually run. The report includes every obligation's routes, outcome, evidence pointer, section summary, required questions, and NOT_RUN/SKIP reasons.

This is a local review aid. It does not change the existing scanner verdict or submission token. Keep generated run reports outside the app repository when their evidence pointers are sensitive.
