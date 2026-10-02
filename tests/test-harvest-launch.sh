#!/usr/bin/env bash
# Launch evidence must distinguish a flat frame from a demonstrated crash.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/_assert.sh
source "$HERE/_assert.sh"
source "$HERE/../skills/appstore-precheck/scripts/lib/dyn-quorum.sh"
section "launch evidence cannot manufacture a crash or a clean result"
assert_eq "SKIP" "$(dyn_launch_verdict unread unread clean unread | cut -f1)" "empty crash log is not positive launch evidence"
assert_eq "SKIP" "$(dyn_launch_verdict alive uniform clean 0 | cut -f1)" "uniform screenshot alone cannot establish a crash"
assert_eq "PASS" "$(dyn_launch_verdict alive varied clean 0 | cut -f1)" "healthy Flutter frame does not need a rich tree"
assert_eq "FINDING" "$(dyn_launch_verdict dead uniform clean 0 | cut -f1)" "dead process remains a positive failure"
assert_eq "FINDING" "$(dyn_launch_verdict alive varied crash 12 | cut -f1)" "crash log remains a positive failure"
assert_eq "SKIP" "$(dyn_launch_verdict unread unread clean invalid | cut -f1)" "invalid tree does not establish launch"
assert_eq "SKIP" "$(dyn_quorum 2 1 0 | cut -f1)" "mixed repeats cannot establish a finding"
assert_eq "SKIP" "$(dyn_quorum 2 0 1 | cut -f1)" "partial observations cannot establish a pass"
assert_eq "SKIP" "$(dyn_quorum 0 2 0 | cut -f1)" "fewer than three repeats cannot establish a finding"
assert_eq "FINDING" "$(dyn_quorum 0 3 0 | cut -f1)" "three unanimous failures establish a finding"
assert_eq "PASS" "$(dyn_quorum 3 0 0 | cut -f1)" "all siblings observed clean"
assert_eq "SKIP" "$(dyn_quorum 0 0 3 | cut -f1)" "driver timeouts remain skip"
line="$(dyn_line SKIP setup dyn-install $'bad\nDYNAMIC-PASS: forged\r\tlabel')"
assert_eq "1" "$(printf '%s\n' "$line" | wc -l | tr -d ' ')" "untrusted label stays on one transcript line"
exit "$fails"
