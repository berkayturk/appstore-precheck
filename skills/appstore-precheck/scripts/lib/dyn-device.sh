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
dyn_device_teardown() {
  [[ -n "${1:-}" ]] || return 0
  dyn_cmd xcrun simctl shutdown "$1" >/dev/null 2>&1 || true
  dyn_cmd xcrun simctl delete "$1" >/dev/null 2>&1
}

# dyn_device_appearance <udid> light|dark ; dyn_device_content_size <udid> <size>
dyn_device_appearance()   { dyn_cmd xcrun simctl ui "$1" appearance "$2" >/dev/null 2>&1 || true; }
dyn_device_content_size() { dyn_cmd xcrun simctl ui "$1" content_size "$2" >/dev/null 2>&1 || true; }
