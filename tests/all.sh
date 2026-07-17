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
  "test-rag-ingest.sh" # eval/rag/ingest.sh full-corpus extraction (RAG eval, no network)
  "test-rag-embed.sh" # eval/rag/embed.py SQL generation (RAG eval, no network)
  "test-rag-retrieve.sh" # eval/rag/retrieve.py similarity-query generation (RAG eval, no network)
  "test-image-dims.sh" # image-dims.sh PNG magic + IHDR dimension parse + accepted-size match
  "test-sarif.sh"     # sarif.sh render_sarif SARIF 2.1.0 output
  "test-action-sarif.sh" # action.yml opt-in SARIF/annotation inputs default off
  "test-pack.sh"      # npm tarball self-containment (files array regression guard)
  "test-eval-parse.sh" # eval parse_verdict.py + build_request.py (LLM eval, no network)
  "test-rag-build-request.sh" # eval/lib/build_request.py --retrieved flag (RAG eval, no network)
  "test-eval-score.sh" # eval/score.py metric math on a fixed synthetic run (no network)
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
