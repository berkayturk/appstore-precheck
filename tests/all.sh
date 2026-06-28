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
