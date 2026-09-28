#!/usr/bin/env bash
# Optional runtime screen inventory or Phase 3 blocking projection.
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "${1:-}" == "--dynamic-blocking" ]]; then
  shift
  [[ "${1:-}" == "--transcript" && $# -eq 2 ]] || {
    echo 'runtime-review.sh: --dynamic-blocking --transcript FILE' >&2; exit 64;
  }
  [[ -f "$2" ]] || { echo "runtime-review.sh: transcript missing: $2" >&2; exit 66; }
  python3 - "$2" <<'PY'
import pathlib, re, sys
lines = pathlib.Path(sys.argv[1]).read_text(errors="replace").splitlines()
for check_id, guideline, message in (
    ("dyn-launch", "2.1", "App crashed on all three fresh simulator launches"),
    ("dyn-demo-login", "2.1", "Demo login failed on all three fresh simulator attempts"),
):
    # Exact 3/3 and proof of three fresh erases required. A mixed-repeat
    # or two-repeat finding can never become a blocking FAIL.
    rx = re.compile(r"^DYNAMIC-FINDING: \S+ \[" + re.escape(check_id) +
                    r"\] — quorum 3/3: .*\bfresh erase verified\b")
    if any(rx.search(line) for line in lines):
        print("FAIL: " + guideline + " [" + check_id + "] " + message +
              "; bypass by rerunning without --dynamic-blocking")
PY
  exit 0
fi
command -v python3 >/dev/null 2>&1 || {
  echo 'runtime-review: Python 3.8+ is required' >&2; exit 69;
}
if [[ "${1:-}" == "--transitions" ]]; then
  exec python3 "$HERE/lib/dyn-transitions.py" "$@"
fi
exec python3 "$HERE/lib/dyn-explore.py" "$@"
