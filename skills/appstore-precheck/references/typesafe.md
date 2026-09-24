# Optional TypeSafe / Jev semantic review

TypeSafe is an opt-in, text-only advisory layer. The default Bash scanner, JSON/SARIF
formats, FAIL/WARN counts, evidence labels, runtime reconciliation, and upload token
are unchanged. Every result has `advisory: true`; the report has `mode: shadow`.
Experimental probability thresholds are not a claim of measured App Store accuracy.

## Run it

Python 3.8+ with the standard library is sufficient; no pip or npm dependency is added.
The `review` command is included in the npm package and the skill installation.

```sh
# Collect locally; no network, build, or device access. Redirect to a private location.
npx appstore-precheck review --repo /path/to/app --prepare > /tmp/review-bundle.json

# Inspect and enrich the bundle, then inspect the exact API requests (still offline).
npx appstore-precheck review --bundle /tmp/review-bundle.json --dry-run

# TYPESAFE_API_KEY must already be set in your environment; never put it in the bundle.
# --live explicitly sends the bundle's source/copy/policy evidence to TypeSafe.
npx appstore-precheck review --bundle /tmp/review-bundle.json --live \
  --cache-dir /tmp/app-typesafe-cache > /tmp/review-result.json

# Replay exact cached requests, without a key or network access.
npx appstore-precheck review --bundle /tmp/review-bundle.json \
  --cache-dir /tmp/app-typesafe-cache --format text
```

When installed as a skill, run `python3 -B <skill-dir>/scripts/semantic-review.py`
with the same arguments. `--workflows` prints every question and required context field.
Without `--live`, requests never reach the network. `--repo` defaults to preparation;
`--bundle` defaults to cache-only review. Missing credentials/cache, malformed answers,
timeouts, or unknown evidence become `insufficient_evidence`, never PASS.

The collector excludes dependency/build/test trees, hidden directories, credentials
files, and symlinks. It redacts recognizable secret assignments and private keys.
Redaction is best-effort: inspect collected source before sending it. App Review
password files are never collected. Represent credentials only as locally established
presence/placeholder facts; do not submit passwords or App Store Connect keys.

Collection is deliberately bounded: 48 evidence files, 5,000 characters per file,
70,000 collected characters, and at most 128 jobs. Truncation/unreadable files set
coverage gaps; they are never silently treated as absence. Parsed plist/String Catalog
values use file-level line 1 pointers explicitly marked as representations. Host agents
should replace them with exact source spans when available. Source coverage never proves
shipping-binary behavior. URL contents and visual observations require host inspection.

## Bundle contract

The complete executable example is [typesafe-example.json](typesafe-example.json).
It contains synthetic evidence for all ten workflows, not labeled accuracy results.

```json
{
  "version": 1,
  "jobs": [{
    "id": "camera-purpose",
    "workflow": "purpose",
    "context": {
      "permission_key": "NSCameraUsageDescription",
      "text": "Scan QR codes to open your saved tickets.",
      "locale": "en",
      "feature_description": "The ticket screen scans QR codes."
    },
    "coverage": {"complete": true, "missing": []},
    "evidence": [{
      "id": "purpose",
      "path": "App/Info.plist",
      "line": 24,
      "text": "Scan QR codes to open your saved tickets."
    }, {
      "id": "feature",
      "path": "App/TicketScanner.swift",
      "line": 18,
      "text": "metadataOutput.metadataObjectTypes = [.qr]"
    }]
  }]
}
```

`context` holds facts, comparisons, and policy text. Questions live in the versioned
registry, not user data. `evidence` contains verbatim source spans, unique IDs and real
pointers (or explicitly marked parsed representations). `coverage.complete` is the
host's assertion that evidence is sufficient for this *bounded question*, not a model
prediction. Keep it false until missing inputs are actually supplied. Incomplete jobs
return a Pierre handoff without spending API tokens. Do not set it true just to run Jev.

## Workflows and host integration

| Workflow | Primitive | Required context / use |
|---|---|---|
| `review` | Choice | `check_definition`; one catalog check, outcome plus evidence selection |
| `copy` | Noul | `text`, `locale`, `ui_role`, `flow_stage`; attach handler/flow evidence for consent or rating gates |
| `purpose` | Score + Noul | `permission_key`, `text`, `locale`, `feature_description`; specificity and feature agreement |
| `disclosure` | Noul + Choice | `copy`, `product_terms` (including boolean `trial`), `locale`, `policy_excerpt`; optional `locale_pair` |
| `consistency` | Choice | `claim`, `comparison_kind`; compare marketing, code, privacy, or locale evidence |
| `routing` | Choice + Noul | `offering`, `flow`, `policy_excerpt`; add storefront, exemption and account-dependency evidence |
| `rerank` | Score per candidate | `query`, `candidates` with unique `id` and `text`; original order is fallback |
| `verify` | Noul | `claim`, `source_id`, `evidence_class`, `build_config`; optional exact `quote` |
| `drift` | Choice + Noul | `old_text`, `new_text`, `publication_date`, `rule_catalog`; each rule evaluated independently |
| `functionality` | Score + Choice | `app_purpose`, `reachable_flows`, `coverage_notes`; observed task completion, not compliance |

All questions within a job share state and are independent. The runner processes jobs
sequentially to bound load. A later request is needed when routing discovers new evidence
requirements. Unknown/mixed offerings retain a broader review route. Exemption signals
never clear scanner warnings. Disclosures ignore trial answers when no trial exists and
ignore locale comparison answers when no locale pair was supplied.

For Phase 3, submit each explanation claim with its real cited source to `verify`.
An exact-quote mismatch is caught locally before inference. When verification fails,
retain the original scanner line and evidence pointer, revise the explanation or use
a factual template; never modify the scanner finding.

For Phase 4, prepare all 31 checks using `review-catalog.json` stable keys. Add narrow
copy, purpose, disclosure, comparison, and routing jobs as evidence becomes available.
Keep full Pierre review during the experimental rollout. Supplementary workflow jobs
are a separate shadow-results block, not extra checks in the "31 checks" denominator.
`action: pierre_review` means
the host agent continues the original checklist procedure; the standalone CLI does not
launch an agent or bill a second model. Emit the existing advisory `REVIEW-*` report.
Screenshots, previews, layout, and actual simulator actions remain with the host tools.
Do not present text-only Jev judgments as image inspection or runtime verification.

For Phase 0, provide the fetched old/new policy text and affected rule definitions to
`drift`. Filter announcement dates deterministically before creating jobs. Retain every
original drift warning regardless of the model's change classification. Reconciliation
remains a deliberate human action; this tool never updates fingerprints or baseline files.

For retrieval, the existing eval RAG helper supports:

```sh
python3 eval/rag/retrieve.py --case eval/dataset/cases/check18-specific-purpose-strings.json \
  --top-k 10 --rerank-typesafe
```

This explicitly adds a paid Jev reranking call after Gemini retrieval. Uncertain ranks
and service failures preserve the original ordering. All candidates are retained;
exact section references must not be discarded because of semantic ranking.

## Uncertainty, provenance, and fallback

- Choice: selected probability at least 0.90 and distribution confidence at least 0.50.
- Noul: concern at least 0.90; absence at most 0.10; verified support at least 0.95.
- Score: preserve levels and probabilities; purpose quality uses probability mass on
  the two weakest levels. Functionality scores only prioritize review.
- One serious concern cannot be averaged away by unrelated positive signals.
- Findings need a confidently selected supplied evidence span. Unknown evidence IDs,
  missing questions, invalid probabilities, NaN, model mismatch and invalid usage fail
  validation. Noul has no invented confidence field.
- Existing `confidence` enforcement labels remain unchanged. Jev values use
  `model_probability`, `model_confidence`, and the raw `judgments` object. Probability
  is not the likelihood Apple rejects the submission.
- An incomplete review renders an advisory handoff, never a clean pass. Text output
  has no `FAIL:`/`WARN:` lines that could enter verdict arithmetic.

## Cost, caching, and evaluation

The default is pinned `jev-1.13.0`. Reviewed documentation on 2026-09-18 lists $0.042
per million input tokens and free output tokens. `estimated_cost_usd` uses actual
returned input usage; it is an estimate, not an invoice. Transport failures can have
unknown cost. Host/Pierre calls are not included. Replayed results report zero new
billed tokens; API latency and cache latency remain distinguishable through `cached`.

The documented ~100 ms typical query latency is not a measured repo guarantee. Reports
record measured request latency. HTTP requests time out after 15 seconds, with at most
two retries for retryable HTTP statuses and backoff capped at 5 seconds. Lost transport
responses are not automatically retried. Redirects cannot forward the API key.

Caches are opt-in. Files are written atomically with mode 0600 and include exact requests,
responses, model, evidence, question-version and threshold fingerprints. Keep caches
outside version control. Invalid or mismatched entries are never trusted. A changed
model, evidence bundle, question, or threshold requires a new result.

```sh
bash eval/validate.sh
bash eval/run.sh --provider typesafe --cases 'check18-*' --dry-run
# Paid evaluation; requires TYPESAFE_API_KEY. Every repeat is a fresh request.
bash eval/run.sh --provider typesafe --repeat 3 --out eval/runs/jev-pilot
python3 eval/score.py --run eval/runs/jev-pilot
```

Current cases have stable `check_key` values; display numbers are catalog-versioned.
New runs snapshot cases. Historical results retain their original labels and numbering
through `eval/baseline/cases-v1.json`; old response files are never relabeled or rewritten.
The scorer separates abstentions from true negatives, reports decision coverage,
latency percentiles, estimated cost, probability bands and binary Brier score when
TypeSafe data exists. A 95% decision-coverage floor on answerable cases accompanies
the existing Tier-A F1 gate; expected abstentions are measured separately.
New candidate fixtures remain `label_confirmed: false` until a human independently
reviews them. Offline mocked tests are protocol/behavior checks, not quality evidence.

Before promoting any workflow, evaluate false negatives and false positives by check
and language, measure handoff rate, calibrate thresholds on held-out human labels, and
compare *total* cost including host escalation. Preserve shadow mode until that evidence
supports a narrower deployment. No TypeSafe judgment issues or removes an upload token.

Sources: [API](https://docs.typesafe.ai/api), [models/pricing](https://docs.typesafe.ai/models),
[confidence](https://docs.typesafe.ai/confidence), [state](https://docs.typesafe.ai/concepts/state),
[reranking](https://docs.typesafe.ai/cookbooks/rerank_typesafe),
[citation verification](https://docs.typesafe.ai/cookbooks/citation_check).

## Request-attempt telemetry

JSON results include `transport_attempts`, `retry_count` and
`retry_billing_unknown`. Cache hits, offline fallbacks and evidence guards use
zero attempts. The built-in client counts each HTTP attempt, including failed
ones. Injected test/custom clients count one invocation; their internal retries
are not observable.

When a retry occurs, usage and estimated cost from the final response do not
account for unknown billing of earlier attempts. Treat `retry_billing_unknown`
as an incomplete billing record, not a zero-cost retry. Failed requests without
usage keep billing unknown. These local fields do not alter the API contract or
authorize live calls. See the [TypeSafe API reference](https://docs.typesafe.ai/api)
for the current transport contract.
