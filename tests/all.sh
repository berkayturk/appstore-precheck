#!/usr/bin/env bash
# tests/all.sh — run the whole test suite. Each test file is independently runnable
# and exits non-zero on failure; this aggregator runs them all and fails if any do.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The suite: fixture scan tests + focused unit tests. Add new test files here.
SUITE=(
  "test-review-round1.sh"
  "test-review-runtime-security.sh"
  "test-guideline-quote-bound.sh"
  "test-build-run.sh"
  "test-opt-in-review.sh"
  "test-metadata-review.sh"
  "test-artifact-review.sh"
  "test-dyn-explore.sh"
  "test-dyn-demo-login.sh"
  "test-runtime-harvest.sh"
  "test-optin-scan.sh"
  "test-action-trust.sh"
  "test-local-corpus.sh"
  "test-augment-json.sh"
  "test-eval-catalog-extensions.sh"
  "test-catalog-provenance.sh"
  "test-static-guidelines.sh"
  "test-static-guideline-shell.sh"
  "test-coverage-docs.sh"
  "test-coverage-sections.sh"
  "test-coverage-run.sh"
  "test-default-golden.sh"
  "test-copyright-boundary.sh"
  "test-harvest-launch.sh"
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
  "test-guideline-routes.sh"
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
  "test-dynamic-guidelines.sh"
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
  "test-semantic-v4.sh"
  "test-typesafe.sh"   # optional typed semantic review, transport/cache failures, gate isolation
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
