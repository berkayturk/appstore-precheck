#!/usr/bin/env bash
# lib/dyn-device.sh — the throwaway-device lifecycle of the Phase 6 runner, one
# `xcrun simctl` verb per function. Sourced by dynamic-run.sh. Bash 3.2.
#
# DEVICE POLICY (SECURITY.md): this tier only ever boots, erases or deletes a device
# it CREATED in the same run. A user-supplied UDID is used for launching only —
# never erased, never reset, never deleted (see dynamic-run.sh --udid).
#
# DETERMINISM: every repeat starts from an erased device with the same status bar
# (9:41, full battery and bars), all privacy grants reset, and the app freshly
# installed, so a FINDING cannot be an artefact of the previous repeat.
#
# DRY RUN: with DYN_DRY_RUN=1 every simctl call is recorded as "PLAN: <command>" and
# nothing runs; value-returning helpers hand back placeholders. That is what the CI
# test pins (order, repeat count, delete-only-what-we-created) without a simulator.
# Plan lines go to DYN_PLAN_FILE when set (callers redirect stdout/stderr of the real
# commands, which would otherwise swallow them), else to stderr.

: "${DYN_DRY_RUN:=0}"
: "${DYN_PLAN_FILE:=}"

# dyn_plan <text> — record one planned step.
dyn_plan() {
  if [[ -n "$DYN_PLAN_FILE" ]]; then printf 'PLAN: %s\n' "$1" >> "$DYN_PLAN_FILE"; else printf 'PLAN: %s\n' "$1" >&2; fi
}

# dyn_cmd <argv…> — run, or record the plan.
dyn_cmd() {
  if [[ "$DYN_DRY_RUN" == 1 ]]; then dyn_plan "$*"; return 0; fi
  "$@"
}

# Per-step wall-clock caps for teardown and the simulator UI calls. A cap is enforced by
# lib/dyn-process.py (its own process group, up to 15s of TERM grace on top), so the four
# teardown steps of two devices stay inside ~120s (4 x (15s + 15s grace)) even if CoreSimulator wedges.
: "${DYN_TEARDOWN_STEP_TIMEOUT:=15}"
: "${DYN_UI_TIMEOUT:=20}"
DYN_DEVICE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# dyn_cmd_bounded <secs> <argv…> — dyn_cmd with a wall-clock cap (124 on expiry).
dyn_cmd_bounded() {
  local secs="$1"; shift
  if [[ "$DYN_DRY_RUN" == 1 ]]; then dyn_plan "$*"; return 0; fi
  python3 "$DYN_DEVICE_LIB_DIR/dyn-process.py" --timeout "$secs" -- "$@"
}

# dyn_pick_runtime -> the newest available iOS runtime identifier.
dyn_pick_runtime() {
  [[ "$DYN_DRY_RUN" == 1 ]] && { echo "com.apple.CoreSimulator.SimRuntime.iOS-PLAN"; return 0; }
  xcrun simctl list runtimes -j 2>/dev/null \
    | jq -r '[.runtimes[] | select(.platform=="iOS" and .isAvailable)] | sort_by(.version) | last | .identifier // empty'
}

# dyn_pick_device_type iphone|ipad -> the newest numbered iPhone, or the newest 11-inch iPad Pro.
dyn_pick_device_type() {
  local fam="${1:-iphone}"
  [[ "$DYN_DRY_RUN" == 1 ]] && { echo "com.apple.CoreSimulator.SimDeviceType.${fam}-PLAN"; return 0; }
  case "$fam" in
    ipad) xcrun simctl list devicetypes -j 2>/dev/null | jq -r '
            [.devicetypes[] | select(.productFamily=="iPad") | select(.name | test("^iPad Pro 11-inch"))] | last | .identifier // empty' ;;
    *)    xcrun simctl list devicetypes -j 2>/dev/null | jq -r '
            [.devicetypes[] | select(.productFamily=="iPhone") | select(.name | test("^iPhone [0-9]+$"))]
            | sort_by(.name | capture("(?<n>[0-9]+)").n | tonumber) | last | .identifier // empty' ;;
  esac
}

# dyn_device_create <name> <device-type> <runtime> -> udid (stdout), or "" on failure.
dyn_device_create() {
  if [[ "$DYN_DRY_RUN" == 1 ]]; then dyn_plan "xcrun simctl create $1 $2 $3"; echo "UDID-PLAN-${1##*-}"; return 0; fi
  xcrun simctl create "$1" "$2" "$3" 2>/dev/null
}

# dyn_device_boot <udid> — boot and wait until the device is usable.
dyn_device_boot() {
  dyn_cmd xcrun simctl boot "$1" >/dev/null 2>&1 || true   # "already booted" is fine
  dyn_cmd xcrun simctl bootstatus "$1" -b >/dev/null 2>&1
}

# dyn_device_prepare <udid> — deterministic status bar + every privacy grant reset.
dyn_device_prepare() {
  dyn_cmd xcrun simctl status_bar "$1" override --time 9:41 --batteryLevel 100 --batteryState charged --wifiBars 3 --cellularBars 4 >/dev/null 2>&1 || true
  dyn_cmd xcrun simctl privacy "$1" reset all >/dev/null 2>&1 || true
}

# dyn_device_erase <udid> — shut down and wipe (only for a device this run created).
dyn_device_erase() {
  dyn_cmd xcrun simctl shutdown "$1" >/dev/null 2>&1 || true
  dyn_cmd xcrun simctl erase "$1" >/dev/null 2>&1
}

# dyn_device_install <udid> <app-path> -> 0 on success; stderr from simctl is kept for the SKIP line.
dyn_device_install() { dyn_cmd xcrun simctl install "$1" "$2"; }

# dyn_device_container <udid> <bundle-id> -> the installed .app path, or "".
dyn_device_container() {
  if [[ "$DYN_DRY_RUN" == 1 ]]; then dyn_plan "xcrun simctl get_app_container $1 $2 app"; echo ""; return 0; fi
  xcrun simctl get_app_container "$1" "$2" app 2>/dev/null
}

# dyn_device_teardown <udid> — shutdown + delete. ONLY for a device this run created.
# Each step is capped (DYN_TEARDOWN_STEP_TIMEOUT); returns the status of the delete.
dyn_device_teardown() {
  [[ -n "${1:-}" ]] || return 0
  dyn_cmd_bounded "$DYN_TEARDOWN_STEP_TIMEOUT" xcrun simctl shutdown "$1" >/dev/null 2>&1 || true
  dyn_cmd_bounded "$DYN_TEARDOWN_STEP_TIMEOUT" xcrun simctl delete "$1" >/dev/null 2>&1
}

# dyn_ledger_has <file> <line> — exact whole-line membership; a missing file has nothing.
dyn_ledger_has() { [[ -f "$1" ]] && grep -qxF -- "$2" "$1"; }

# dyn_sweep_owned <out-dir> — delete every simulator this run's own ledger still owns.
# A UDID is deleted only when ALL of these hold: it is in <out-dir>/owned-simulators.txt,
# it is not in <out-dir>/deleted-simulators.txt, both ledgers are regular files directly
# inside <out-dir> (a symlinked ledger is never trusted), and `simctl list devices -j`
# currently names that UDID with this tool's own precheck-<timestamp>-<pid>[-ipad] pattern.
# Nothing else is ever deleted. Successes go to deleted-simulators.txt; a device that is
# still present afterwards (or that cannot be verified) goes to cleanup-failures.txt.
# No-op in a dry run.
dyn_sweep_owned() {
  local out="$1" owned deleted failures udid name listing="" pending="" listed=0
  [[ "$DYN_DRY_RUN" == 1 ]] && return 0
  owned="$out/owned-simulators.txt"; deleted="$out/deleted-simulators.txt"; failures="$out/cleanup-failures.txt"
  [[ -f "$owned" && ! -L "$owned" ]] || return 0
  [[ -L "$deleted" ]] && return 0
  [[ ! -e "$deleted" || -f "$deleted" ]] || return 0
  while IFS= read -r udid || [[ -n "$udid" ]]; do
    [[ "$udid" =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]] || continue
    dyn_ledger_has "$deleted" "$udid" && continue
    case " $pending " in *" $udid "*) continue ;; esac
    pending="$pending $udid"
  done < "$owned"
  [[ -n "${pending// /}" ]] || return 0
  if listing="$(xcrun simctl list devices -j 2>/dev/null)" && jq -e . >/dev/null 2>&1 <<<"$listing"; then listed=1; fi
  for udid in $pending; do
    if (( ! listed )); then
      dyn_ledger_has "$failures" "$udid" || printf '%s\n' "$udid" >> "$failures"
      continue
    fi
    name="$(jq -r --arg u "$udid" '[.devices[]?[]? | select(.udid == $u) | .name] | first // empty' <<<"$listing")"
    [[ "$name" =~ ^precheck-[0-9]{14}-[0-9]+(-ipad)?$ ]] || continue
    if dyn_device_teardown "$udid"; then
      printf '%s\n' "$udid" >> "$deleted"
    else
      dyn_ledger_has "$failures" "$udid" || printf '%s\n' "$udid" >> "$failures"
    fi
  done
  return 0
}

# dyn_device_appearance <udid> light|dark ; dyn_device_content_size <udid> <size>
dyn_device_appearance()   { dyn_cmd_bounded "$DYN_UI_TIMEOUT" xcrun simctl ui "$1" appearance "$2" >/dev/null 2>&1 || true; }
dyn_device_content_size() { dyn_cmd_bounded "$DYN_UI_TIMEOUT" xcrun simctl ui "$1" content_size "$2" >/dev/null 2>&1 || true; }

# dyn_device_get_appearance <udid> -> light | dark, or "" when the getter is unavailable or
# answers with anything else. Read-only.
dyn_device_get_appearance() {
  local v
  if [[ "$DYN_DRY_RUN" == 1 ]]; then dyn_plan "xcrun simctl ui $1 appearance   # read the original"; echo light; return 0; fi
  v="$(python3 "$DYN_DEVICE_LIB_DIR/dyn-process.py" --timeout "$DYN_UI_TIMEOUT" -- xcrun simctl ui "$1" appearance 2>/dev/null | head -1 | tr -d '[:space:]')"
  case "$v" in light|dark) echo "$v" ;; *) echo "" ;; esac
}

# dyn_device_get_content_size <udid> -> a restorable content-size category, or "".
dyn_device_get_content_size() {
  local v
  if [[ "$DYN_DRY_RUN" == 1 ]]; then dyn_plan "xcrun simctl ui $1 content_size   # read the original"; echo large; return 0; fi
  v="$(python3 "$DYN_DEVICE_LIB_DIR/dyn-process.py" --timeout "$DYN_UI_TIMEOUT" -- xcrun simctl ui "$1" content_size 2>/dev/null | head -1 | tr -d '[:space:]')"
  case "$v" in
    extra-small|small|medium|large|extra-large|extra-extra-large|extra-extra-extra-large|\
    accessibility-medium|accessibility-large|accessibility-extra-large|accessibility-extra-extra-large|accessibility-extra-extra-extra-large) echo "$v" ;;
    *) echo "" ;;
  esac
}
