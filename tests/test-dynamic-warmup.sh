#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/_assert.sh
source "$ROOT/tests/_assert.sh"
L="$ROOT/skills/appstore-precheck/scripts/lib"
# shellcheck source=skills/appstore-precheck/scripts/lib/dyn-device.sh
source "$L/dyn-device.sh"
# shellcheck source=skills/appstore-precheck/scripts/lib/dyn-signals.sh
source "$L/dyn-signals.sh"
# shellcheck source=skills/appstore-precheck/scripts/lib/dyn-geometry.sh
source "$L/dyn-geometry.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir "$T/bin"
export WARM_COUNT="$T/count" WARM_TREE="$ROOT/tests/fixtures/dynamic-hierarchies/clean.json" WARM_MODE=fail
cat > "$T/bin/maestro" <<'SHIM'
#!/bin/sh
n=0; test ! -f "$WARM_COUNT" || n=$(cat "$WARM_COUNT")
n=$((n+1)); echo "$n" > "$WARM_COUNT"
if test "$WARM_MODE" = always; then exit 1; fi
if test "$n" = 1; then
  if test "$WARM_MODE" = sleep; then sleep 10; fi
  exit 1
fi
cat "$WARM_TREE"
SHIM
chmod +x "$T/bin/maestro"
export PATH="$T/bin:$PATH"
note() { printf '# %s\n' "$1"; }
DYN_MAESTRO_TIMEOUT=2
DYN_MAESTRO_WARMUP_TIMEOUT=0.05
for WARM_MODE in fail sleep; do
  rm -f "$WARM_COUNT"
  line="$(dyn_maestro_warmup OWNED)"
  assert_contains "$line" 'NOTE: [dyn-maestro-warmup]' 'warm-up emits a note'
  assert_absent "$line" DYNAMIC-PASS 'warm-up is not evidence'
  assert_absent "$line" DYNAMIC-FINDING 'warm-up cannot report a finding'
  nodes="$(dyn_signal_tree_retry OWNED "$T/tree.json")"
  assert_gt "$nodes" 3 'read after warm-up is usable'
  assert_eq "$(cat "$WARM_COUNT")" 2 'exactly one discarded warm-up'
  line="$(dyn_geometry_line "$(dyn_geometry_report "$T/tree.json" 0 0)" 4.0 dyn-dark-mode dark)"
  assert_contains "$line" 'DYNAMIC-PASS: 4.0 [dyn-dark-mode]' 'D7 passes on the observed clean tree'
done
rm -f "$WARM_COUNT"; DYN_MAESTRO_WARMUP_TIMEOUT=0; WARM_MODE=fail
dyn_maestro_warmup OWNED >/dev/null
assert_path_absent "$WARM_COUNT" 'disabled warm-up makes no call'
assert_eq "$(dyn_signal_tree OWNED "$T/tree.json")" unread 'without warm-up first read retains old failure'
rm -f "$WARM_COUNT"
assert_gt "$(dyn_signal_tree_retry OWNED "$T/tree.json")" 3 'unread geometry retries once'
assert_eq "$(cat "$WARM_COUNT")" 2 'one retry only'
rm -f "$WARM_COUNT"; WARM_MODE=always
assert_eq "$(dyn_signal_tree_retry OWNED "$T/tree.json")" unread 'persistent failure remains unread'
assert_eq "$(cat "$WARM_COUNT")" 2 'persistent failure is bounded'
exit "$fails"
