#!/usr/bin/env bash
# tests/all.sh — run the whole test suite. Each test file is independently runnable
# and exits non-zero on failure; this aggregator runs them all and fails if any do.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The suite: fixture scan tests + focused unit tests. Add new test files here.
SUITE=(
  "run.sh"            # scan.sh against fixtures
  "test-verdict.sh"   # verdict.sh thresholds, token actions, exit codes
  "test-guard.sh"     # fastlane-guard.sh token gating + exit codes
  "test-config.sh"    # .appstore-precheck.json override honoring
  "test-install.sh"   # install.sh per-host vendoring
  "test-phase2.sh"    # Phase 2 fastlane-precheck wrapper (secret-free dry-run)
  "test-cli.sh"       # npx CLI wrapper (bin/cli.js) verdict + exit codes
  "test-findings.sh"  # findings.sh structured-findings helper
  "test-format-json.sh" # scan.sh --format json envelope + text-mode parity
  "test-suppress.sh"  # suppress.sh + emit-time .precheck-ignore wiring
  "test-scorecard.sh" # scorecard.sh metric math + --check staleness gate
  "test-scorecard-outcomes.sh" # scorecard-outcomes.sh tally + honesty floor
  "test-project-model.sh" # project-model.sh pbxproj parser + resolver
  "test-guideline-drift.sh" # guideline-drift.sh parse/diff + coverage↔fingerprint consistency
  "test-evidence.sh"  # evidence.sh per-rule evidence class + confidence + derived build-verification
  "test-guideline-cite.sh" # guideline-cite.sh offline pinned-quote citation lookup
  "test-skip.sh"      # SKIP (not-audited) line class: emission, counting, json/sarif
  "test-saturated.sh" # §54 saturated-category (4.3(b)) field scoping + word boundaries
  "test-ipv4-literal.sh" # §55 ipv4-literal (2.5.5): IPv4-only socket APIs + literals, exclusions, labels
  "test-design-40.sh" # guideline 4.0: baseline N.0 sections, pinned quote, deep-review check 31
  "test-phase6-doc.sh" # Phase 6 reference contract: D0 install step, D3 StoreKit SKIP, device lifecycle, rule ids, D3b, four launch signals
  "test-dynamic-reconcile.sh" # dynamic.sh transcript -> runtime records, reconciliation table, Debug guard, RESOLVED inertness
  "test-framework-detect.sh" # framework-detect.sh (rn/flutter/kmp/native from file presence) + scan.sh framework-not-audited gap record
  "test-app-discover.sh" # app-discover.sh: DerivedData/.app candidates, config from dir name, newest recommended, never builds
  "test-dynamic-libs.sh" # lib/dyn-*: launch-signal verdict, N=3 quorum, png-uniform, geometry heuristics, hosts parity, installed-bundle readers
  "test-dynamic-run.sh" # dynamic-run.sh against a shimmed xcrun/maestro: lifecycle order, erase between repeats, delete-only-created, Metro guard, dry-run plan
  "test-rag-ingest.sh" # eval/rag/ingest.sh full-corpus extraction (RAG eval, no network)
  "test-rag-embed.sh" # eval/rag/embed.py SQL generation (RAG eval, no network)
  "test-rag-gemini-client.sh" # eval/rag/gemini_client.py retry-delay parsing + 429 backoff (RAG eval, no network)
  "test-rag-retrieve.sh" # eval/rag/retrieve.py similarity-query generation (RAG eval, no network)
  "test-sdk-signals.sh" # per-SDK coverage for the tracking (§16) + analytics (§19) signal lists
  "test-image-dims.sh" # image-dims.sh PNG magic + IHDR dimension parse + accepted-size match
  "test-sarif.sh"     # sarif.sh render_sarif SARIF 2.1.0 output
  "test-action-sarif.sh" # action.yml opt-in SARIF/annotation inputs default off
  "test-pack.sh"      # npm tarball self-containment (files array regression guard)
  "test-eval-parse.sh" # eval parse_verdict.py + build_request.py (LLM eval, no network)
  "test-rag-build-request.sh" # eval/lib/build_request.py --retrieved flag (RAG eval, no network)
  "test-rag-run-guard.sh" # eval/run.sh --rag mismatch guard (RAG eval, no network)
  "test-eval-score.sh" # eval/score.py metric math on a fixed synthetic run (no network)
  "test-typesafe.sh"   # optional typed semantic review, transport/cache failures, gate isolation
  "test-coverage.sh"   # obligation schema, registry, and route coverage
  "test-copyright-boundary.sh" # source-text and npm package boundary
  "test-default-golden.sh" # default scan text pinned to main baseline
  "test-build-run.sh" # isolated opt-in build plans and source immutability
  "test-obligations-1.sh" # Safety section atomic classification
  "test-obligations-2.sh" # Performance section atomic classification
  "test-obligations-3.sh" # Business section atomic classification
  "test-obligations-4.sh" # Design section atomic classification
  "test-obligations-5.sh" # Legal section atomic classification
  "test-obligations-intro.sh" # Submission process atomic classification
  "test-artifact-review.sh" # compiled bundle inspection and evidence gaps
  "test-attestation-report.sh" # developer answers and obligation-level run report
  "test-metadata-review.sh" # local and opt-in ASC listing evidence
  "test-coverage-json.sh" # actual-run route states in the JSON envelope
  "test-section1-review.sh" # Safety evidence routes and explicit abstention
  "test-section2-review.sh" # Performance evidence routes and explicit abstention
  "test-section3-review.sh" # Commerce evidence routes and explicit abstention
  "test-section4-review.sh" # Design evidence routes and explicit abstention
  "test-section5-review.sh" # Privacy and legal evidence routes and explicit abstention
  "test-section6-review.sh" # Intro and submission evidence routes and explicit abstention
  "test-runtime-review.sh" # bounded screen discovery and opt-in blocking
  "test-opt-in-review.sh" # temporary build orchestration and CLI opt-in
)

failed=()
for t in "${SUITE[@]}"; do
  echo "################################################################"
  echo "# $t"
  echo "################################################################"
  if bash "$DIR/$t"; then
    echo "[$t] OK"
  else
    echo "[$t] FAILED"
    failed+=("$t")
  fi
  echo
done

echo "================================================================"
if (( ${#failed[@]} == 0 )); then
  echo "SUITE PASSED (${#SUITE[@]} files)"
else
  echo "SUITE FAILED: ${failed[*]}"
  exit 1
fi
