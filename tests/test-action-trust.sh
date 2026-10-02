#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
# shellcheck source=tests/_assert.sh
source tests/_assert.sh
calls="$(grep -E 'bash "\$scan"' action.yml)"
assert_eq "$(printf '%s\n' "$calls" | grep -c 'env -u APPSTORE_PRECHECK_TRUST_CONFIG')" 3 'all action scan invocations drop config trust'
assert_contains "$(cat SECURITY.md)" 'Release build scripts can access the network' 'build script network effects are documented'
exit "$fails"
