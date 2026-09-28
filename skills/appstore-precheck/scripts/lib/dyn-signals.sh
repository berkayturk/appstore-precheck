#!/usr/bin/env bash
# lib/dyn-signals.sh — one launch repeat of the Phase 6 runner: start the observers,
# launch the app, wait the window, then read the FOUR launch-health signals and hand
# them to dyn_launch_verdict (lib/dyn-quorum.sh). Sourced by dynamic-run.sh. Bash 3.2.
#
#   process alive     kill -0 on the PID `simctl launch` printed (simulator apps are
#                     host processes).
#   screenshot        `simctl io screenshot` + lib/png-uniform.py: a flat frame is a
#                     hung splash or a dead process. Unreadable -> "unread".
#   log stream        `simctl spawn <udid> log stream --style compact` filtered to the
#                     app, started BEFORE launch; a crash / SIGABRT / EXC_BAD_ACCESS /
#                     "Terminating app" line, or a new .ips report for the executable in
#                     ~/Library/Logs/DiagnosticReports, is "crash". No file -> "unread".
#   accessibility     `maestro hierarchy` node count. Maestro missing or timing out ->
#                     "unread" (a driver timeout is never a FINDING). A tiny tree is
#                     reported as its count; dyn_launch_verdict knows it is degenerate.
# The app is launched with SIMCTL_CHILD_CFNETWORK_DIAGNOSTICS=3 so the same log file
# also feeds dyn-hosts-contacted (lib/dyn-hosts.sh).

: "${DYN_DRY_RUN:=0}"
: "${DYN_MAESTRO_TIMEOUT:=45}"
DYN_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# dyn_with_timeout <secs> <argv…> — run with a wall-clock cap (macOS has no
# coreutils timeout). Exit 124 on expiry, else the command's status.
dyn_with_timeout() {
  local secs="$1"; shift
  python3 "$DYN_LIB_DIR/dyn-process.py" --timeout "$secs" -- "$@"
}

DYN_LOG_PID=""
# dyn_log_start <udid> <executable> <bundle-id> <out-file> — background log stream.
dyn_log_start() {
  local udid="$1" exe="$2" bid="$3" out="$4"
  if [[ "$DYN_DRY_RUN" == 1 ]]; then dyn_plan "xcrun simctl spawn $udid log stream --style compact --predicate 'process == \"$exe\" OR eventMessage CONTAINS \"$bid\"' > $out &"; return 0; fi
  xcrun simctl spawn "$udid" log stream --style compact \
    --predicate "process == \"$exe\" OR eventMessage CONTAINS \"$bid\" OR (subsystem == \"com.apple.CFNetwork\" AND process == \"$exe\")" \
    > "$out" 2>/dev/null &
  DYN_LOG_PID=$!
}
dyn_log_stop() {
  [[ -n "$DYN_LOG_PID" ]] && { kill "$DYN_LOG_PID" 2>/dev/null; wait "$DYN_LOG_PID" 2>/dev/null; }
  DYN_LOG_PID=""
  return 0
}

# dyn_launch <udid> <bundle-id> -> PID (stdout) or "" ; always --terminate-running-process.
dyn_launch() {
  local udid="$1" bid="$2" out
  if [[ "$DYN_DRY_RUN" == 1 ]]; then dyn_plan "SIMCTL_CHILD_CFNETWORK_DIAGNOSTICS=3 xcrun simctl launch --terminate-running-process $udid $bid"; echo ""; return 0; fi
  out="$(SIMCTL_CHILD_CFNETWORK_DIAGNOSTICS=3 xcrun simctl launch --terminate-running-process "$udid" "$bid" 2>/dev/null)" || { echo ""; return 1; }
  # "com.example.app: 41231"
  printf '%s' "${out##*: }" | tr -dc '0-9'
}

# dyn_signal_process <pid> -> alive | dead | unread
dyn_signal_process() {
  local pid="${1:-}"
  [[ -n "$pid" ]] || { echo unread; return 0; }
  if kill -0 "$pid" 2>/dev/null; then echo alive; else echo dead; fi
}

# dyn_signal_screenshot <udid> <png-out> -> varied | uniform | unread
dyn_signal_screenshot() {
  local udid="$1" png="$2" r
  if [[ "$DYN_DRY_RUN" == 1 ]]; then dyn_plan "xcrun simctl io $udid screenshot --type=png $png"; echo unread; return 0; fi
  xcrun simctl io "$udid" screenshot --type=png "$png" >/dev/null 2>&1 || { echo unread; return 0; }
  command -v python3 >/dev/null 2>&1 || { echo unread; return 0; }
  r="$(python3 "$DYN_LIB_DIR/png-uniform.py" "$png" 2>/dev/null)" || { echo unread; return 0; }
  case "$r" in uniform) echo uniform ;; varied*) echo varied ;; *) echo unread ;; esac
}

# dyn_signal_log <log-file> <executable> <since-marker-file> -> clean | crash | unread
dyn_signal_log() {
  local log="$1" exe="$2" marker="${3:-}" reports=""
  [[ -s "$log" || -f "$log" ]] || { echo unread; return 0; }
  if grep -qE 'SIGABRT|SIGSEGV|SIGBUS|SIGILL|SIGTRAP|EXC_BAD_ACCESS|EXC_CRASH|EXC_BREAKPOINT|Terminating app due to|Fatal error:|fatalError|crashed' "$log" 2>/dev/null; then
    echo crash; return 0
  fi
  if [[ -n "$marker" && -d "$HOME/Library/Logs/DiagnosticReports" ]]; then
    reports="$(find "$HOME/Library/Logs/DiagnosticReports" -maxdepth 1 -name "${exe}-*.ips" -newer "$marker" 2>/dev/null | head -1)"
    [[ -n "$reports" ]] && { echo crash; return 0; }
  fi
  echo clean
}

# dyn_signal_tree <udid> <json-out> -> <node count> | unread
dyn_signal_tree() {
  local udid="$1" out="$2" n
  if [[ "$DYN_DRY_RUN" == 1 ]]; then dyn_plan "maestro --device $udid hierarchy > $out   # one Maestro invocation, one flow"; echo unread; return 0; fi
  command -v maestro >/dev/null 2>&1 || { echo unread; return 0; }
  dyn_with_timeout "$DYN_MAESTRO_TIMEOUT" sh -c 'maestro --device "$1" hierarchy > "$2" 2>/dev/null' _ "$udid" "$out" || { echo unread; return 0; }
  n="$(jq '[.. | objects | select(has("attributes"))] | length' "$out" 2>/dev/null)" || { echo unread; return 0; }
  [[ "$n" =~ ^[0-9]+$ ]] && echo "$n" || echo unread
}

# dyn_repeat <udid> <bundle-id> <executable> <window-secs> <out-dir> <i>
# -> "<verdict><TAB><detail><TAB><proc>,<shot>,<log>,<tree>" for dyn-launch; files in out-dir.
dyn_repeat() {
  local udid="$1" bid="$2" exe="$3" window="$4" out="$5" i="$6"
  local marker="$out/marker-$i" log="$out/log-$i.txt" png="$out/launch-$i.png" hier="$out/hierarchy-$i.json"
  local pid proc shot lg tree verdict
  : > "$marker"; : > "$log"
  dyn_log_start "$udid" "$exe" "$bid" "$log"
  pid="$(dyn_launch "$udid" "$bid")"
  if [[ "$DYN_DRY_RUN" == 1 ]]; then dyn_plan "sleep $window   # observation window, repeat $i"; else sleep "$window"; fi
  proc="$(dyn_signal_process "$pid")"
  shot="$(dyn_signal_screenshot "$udid" "$png")"
  tree="$(dyn_signal_tree "$udid" "$hier")"
  dyn_log_stop
  lg="$(dyn_signal_log "$log" "$exe" "$marker")"
  [[ "$DYN_DRY_RUN" == 1 ]] && lg=unread
  verdict="$(dyn_launch_verdict "$proc" "$shot" "$lg" "$tree")"
  printf '%s\t%s,%s,%s,%s\n' "$verdict" "$proc" "$shot" "$lg" "$tree"
}
