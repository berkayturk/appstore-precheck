#!/usr/bin/env bash
# dynamic-run.sh — the Phase 6 runner: a throwaway simulator, N deterministic launch
# repeats, the observation-based D-checks, and a transcript dynamic.sh can reconcile.
# macOS + Xcode only (xcrun). Bash 3.2 compatible. It NEVER builds: the .app must
# already exist (app-discover.sh finds one; the user confirms it).
#
# WHAT IT OBSERVES (each line carries its rule id; see simulator-dynamic-review.md)
#   D0  dyn-install         create → boot → status bar → privacy reset → install
#   D1  dyn-launch          N repeats, each on an erased device; four signals per repeat
#                           (process, screenshot, log stream, accessibility tree);
#                           FINDING only when every repeat failed, mixed carries its ratio
#   D2  dyn-first-screen    a non-blank first screen (screenshot + process)
#   D7  dyn-dark-mode       geometry heuristics under `simctl ui appearance dark`
#   D8  dyn-dynamic-type    the same at accessibility-extra-extra-extra-large
#   D9  dyn-ipad-layout     (--ipad) the same on an iPad simulator this run creates
#   D10 dyn-shipped-*       the INSTALLED bundle: Info.plist keys vs the repo plist,
#                           DTXcode (SDK floor), otool -L — nothing executed
#   D11 dyn-hosts-contacted hosts from CFNetwork diagnostics (opt-in --pktap adds DNS)
# The selector-based checks (D3 paywall, D3b Restore tap, D4 prompts, D5 demo login,
# D6 screenshot parity) stay with the agent + Maestro MCP; on Flutter / KMP they are
# recorded as unexecuted here; measured accessibility may still support exploration.
#
# WHAT IT NEVER DOES: xcodebuild / flutter / gradle; touch a device it did not create
# (a --udid device is launched on, never erased, reset or deleted; D7/D8 read its
# appearance and content size first, restore them exactly, and are SKIPped when the
# originals cannot be read); write under the repo (an --out inside --repo is exit 64).
#
# CLEANUP: the EXIT trap deletes this run's own simulators (each simctl step capped),
# then sweeps <out>/owned-simulators.txt minus deleted-simulators.txt (only precheck-*
# devices, only ledgers inside --out). A watchdog starts the wind-down min(120s, 1/4) of
# PRECHECK_RUNTIME_DEADLINE_SECONDS before the supervisor's deadline so teardown finishes.
#
# USAGE
#   dynamic-run.sh --app <path.app> [--repo DIR] [--framework rn|flutter|kmp|native]
#                  [--repo-plist Info.plist] [--repeats 3] [--window 10]
#                  [--device-type ID] [--runtime ID] [--ipad] [--pktap] [--out DIR]
#                  [--explore] [--demo-login] [--dynamic-blocking] [--dry-run]
#   dynamic-run.sh --udid <UDID> --bundle-id <id> [same options]
#   Output: the transcript on stdout (also <out>/transcript.txt) + <out>/run.json.
#   Then: dynamic.sh --transcript <out>/transcript.txt --findings <scan.json> \
#                    --target simulator --build-config <from run.json>
#   Exit 0 ran; 3 setup failed (every check SKIP); 64 usage; 66 missing file; 69 no xcrun.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# A process-group supervisor gives traps time to remove this run's devices on
# cancellation/deadline. No caller-owned simulator is ever deleted.
if [[ "${PRECHECK_RUNTIME_SUPERVISED:-0}" != 1 ]]; then
  export PRECHECK_RUNTIME_SUPERVISED=1
  exec python3 "$HERE/lib/dyn-process.py" --timeout "${PRECHECK_RUNTIME_DEADLINE_SECONDS:-1800}" -- bash "$0" "$@"
fi
# shellcheck source=framework-detect.sh
. "$HERE/framework-detect.sh"
# shellcheck source=lib/dyn-quorum.sh
. "$HERE/lib/dyn-quorum.sh"
# shellcheck source=lib/dyn-device.sh
. "$HERE/lib/dyn-device.sh"
# shellcheck source=lib/dyn-signals.sh
. "$HERE/lib/dyn-signals.sh"
# shellcheck source=lib/dyn-geometry.sh
. "$HERE/lib/dyn-geometry.sh"
# shellcheck source=lib/dyn-hosts.sh
. "$HERE/lib/dyn-hosts.sh"
# shellcheck source=lib/dyn-bundle.sh
. "$HERE/lib/dyn-bundle.sh"

# --- Arguments --------------------------------------------------------------------
APP="" UDID="" BID="" REPO="" FRAMEWORK="" REPO_PLIST="" REPEATS=3 WINDOW=10
DEVTYPE="" RUNTIME="" IPAD=0 PKTAP=0 OUT="" DYN_DRY_RUN=0 EXPLORE=0 EXPLORE_SECONDS=360 EXPLORE_SCREENS=25 DYN_BLOCKING=0 DYN_DEMO=0 NAVIGATION_AUTH=""
usage_err() { echo "dynamic-run.sh: $1" >&2; exit 64; }
need() { [[ $# -ge 2 ]] || usage_err "$1 needs a value"; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)         need "$@"; APP="$2"; shift 2 ;;
    --udid)        need "$@"; UDID="$2"; shift 2 ;;
    --bundle-id)   need "$@"; BID="$2"; shift 2 ;;
    --repo)        need "$@"; REPO="$2"; shift 2 ;;
    --framework)   need "$@"; FRAMEWORK="$2"; shift 2 ;;
    --repo-plist)  need "$@"; REPO_PLIST="$2"; shift 2 ;;
    --repeats)     need "$@"; REPEATS="$2"; shift 2 ;;
    --window)      need "$@"; WINDOW="$2"; shift 2 ;;
    --device-type) need "$@"; DEVTYPE="$2"; shift 2 ;;
    --runtime)     need "$@"; RUNTIME="$2"; shift 2 ;;
    --out)         need "$@"; OUT="$2"; shift 2 ;;
    --ipad)        IPAD=1; shift ;;
    --pktap)       PKTAP=1; shift ;;
    --dry-run)     DYN_DRY_RUN=1; shift ;;
    --explore)     EXPLORE=1; shift ;;
    --explore-seconds) need "$@"; EXPLORE_SECONDS="$2"; shift 2 ;;
    --explore-screens) need "$@"; EXPLORE_SCREENS="$2"; shift 2 ;;
    --authorized-navigation) need "$@"; NAVIGATION_AUTH="$2"; shift 2 ;;
    --demo-login)  DYN_DEMO=1; shift ;;
    --dynamic-blocking) DYN_BLOCKING=1; shift ;;
    *) usage_err "unknown option '$1'" ;;
  esac
done
export DYN_DRY_RUN
[[ "$EXPLORE_SECONDS" =~ ^[0-9]+$ ]] && (( EXPLORE_SECONDS >= 1 && EXPLORE_SECONDS <= 360 )) || usage_err "--explore-seconds must be 1..360"
[[ "$EXPLORE_SCREENS" =~ ^[0-9]+$ ]] && (( EXPLORE_SCREENS >= 1 && EXPLORE_SCREENS <= 25 )) || usage_err "--explore-screens must be 1..25"
if [[ -n "$APP" && -n "$UDID" ]]; then usage_err "give --app OR --udid, not both"; fi
if [[ -z "$APP" && -z "$UDID" ]]; then usage_err "one of --app <path.app> or --udid <UDID> --bundle-id <id> is required"; fi
if [[ -n "$UDID" && -z "$BID" ]]; then usage_err "--udid needs --bundle-id"; fi
[[ "$REPEATS" =~ ^[0-9]+$ ]] && (( REPEATS >= 1 )) || usage_err "--repeats must be a positive integer"
[[ "$WINDOW" =~ ^[0-9]+$ ]] || usage_err "--window must be an integer number of seconds"
if (( DYN_BLOCKING )) && [[ -n "$UDID" || "$REPEATS" != 3 ]]; then
  usage_err "--dynamic-blocking requires --app and exactly three fresh repeats"
fi
if (( DYN_DEMO )) && [[ -n "$UDID" || "$REPEATS" != 3 ]]; then
  usage_err "--demo-login requires --app and exactly three fresh repeats"
fi
case "$FRAMEWORK" in ""|rn|flutter|kmp|native) ;; *) usage_err "--framework must be rn|flutter|kmp|native" ;; esac
if [[ -n "$APP" ]]; then
  [[ -d "$APP" ]] || { echo "dynamic-run.sh: no such .app: $APP" >&2; exit 66; }
  [[ -f "$APP/Info.plist" ]] || { echo "dynamic-run.sh: $APP has no Info.plist (not an installable bundle)" >&2; exit 66; }
fi
[[ -n "$REPO" && ! -d "$REPO" ]] && { echo "dynamic-run.sh: --repo is not a directory: $REPO" >&2; exit 66; }
command -v xcrun >/dev/null 2>&1 || { echo "dynamic-run.sh: xcrun not found — this tier needs macOS with Xcode (it is permanently local-only)" >&2; exit 69; }
[[ -z "$FRAMEWORK" ]] && { if [[ -n "$REPO" ]]; then FRAMEWORK="$(detect_framework "$REPO")"; else FRAMEWORK=native; fi; }
OUT_GENERATED=0
if [[ -z "$OUT" ]]; then OUT="$(mktemp -d "${TMPDIR:-/tmp}/precheck-dynamic.XXXXXX")"; OUT_GENERATED=1; fi
# The header promises nothing is ever written under the repo: refuse an --out that resolves
# inside --repo (symlinks resolved, path need not exist yet) BEFORE anything is created.
# Fail closed: anything but a definite "outside" answer stops the run.
if [[ -n "$REPO" ]]; then
  python3 "$HERE/lib/dyn-paths.py" inside "$OUT" "$REPO"; out_rc=$?
  case "$out_rc" in
    0) (( OUT_GENERATED )) && rmdir "$OUT" 2>/dev/null; usage_err "--out must not be inside --repo (the runner never writes under the repo): $OUT" ;;
    1) ;;
    *) (( OUT_GENERATED )) && rmdir "$OUT" 2>/dev/null; usage_err "cannot verify that --out is outside --repo (dyn-paths.py failed)" ;;
  esac
fi
mkdir -p "$OUT" || { echo "dynamic-run.sh: cannot create --out $OUT" >&2; exit 66; }
TRANSCRIPT="$OUT/transcript.txt"; : > "$TRANSCRIPT"
DYN_PLAN_FILE="$OUT/plan.txt"; : > "$DYN_PLAN_FILE"; export DYN_PLAN_FILE

# --- Transcript helpers -------------------------------------------------------------
emit() { printf '%s\n' "$1" | tee -a "$TRANSCRIPT"; }
note() { printf '# %s\n' "$1" | tee -a "$TRANSCRIPT"; }
skip_all() { # skip_all <reason> — every observation this runner owns, as SKIP with one cause.
  local id g
  for id in dyn-launch dyn-first-screen dyn-dark-mode dyn-dynamic-type dyn-ipad-layout \
            dyn-shipped-bundle dyn-shipped-sdk dyn-shipped-links dyn-hosts-contacted; do
    case "$id" in dyn-launch|dyn-first-screen) g=2.1 ;; dyn-dark-mode|dyn-dynamic-type) g=4.0 ;; dyn-ipad-layout) g=2.4.1 ;;
                  dyn-shipped-sdk) g=2.1 ;; dyn-shipped-links) g=2.5.1 ;; dyn-hosts-contacted) g=5.1.2 ;; *) g=5.1.1 ;; esac
    emit "$(dyn_line SKIP "$g" "$id" "$1")"
  done
}

# --- Identity of the app under test ---------------------------------------------------
BUILD_CONFIG="unknown" EXE="" APP_LABEL=""
if [[ -n "$APP" ]]; then
  BID="$(dyn_plist_string "$APP/Info.plist" CFBundleIdentifier)"
  EXE="$(dyn_plist_string "$APP/Info.plist" CFBundleExecutable)"
  BUILD_CONFIG="$(dyn_config_from_dir "$APP")"
  APP_LABEL="$(basename "$(dirname "$APP")")/$(basename "$APP")"
  [[ -n "$BID" ]] || { emit "$(dyn_line SKIP setup dyn-install "$APP_LABEL has no CFBundleIdentifier in Info.plist; not installable")"; skip_all "setup failed: no bundle id"; exit 3; }
fi
[[ -n "$EXE" ]] || EXE="${BID##*.}"

# Metro precondition (React Native): a Debug .app without an embedded main.jsbundle
# loads its JS from Metro on port 8081. Without Metro EVERY RN app "crashes on launch",
# which would be a false FINDING, so the launch checks are SKIPped instead.
METRO_SKIP=0
if [[ "$FRAMEWORK" == rn && -n "$APP" && ! -f "$APP/main.jsbundle" ]]; then
  if ! (exec 3<>/dev/tcp/127.0.0.1/8081) 2>/dev/null; then METRO_SKIP=1; fi
fi

# --- Teardown, always -------------------------------------------------------------------
CREATED_UDID="" CREATED_IPAD="" PKTAP_PID="" WATCHDOG_PID="" CLEANING=0
# A --udid device is never erased or deleted, but D7/D8 change its UI settings; the
# originals are recorded here so cleanup restores them exactly, even on cancellation.
UI_RESTORE_UDID="" UI_RESTORE_APPEARANCE="" UI_RESTORE_CONTENT=""
cleanup() {
  # Re-entrancy: a second signal during teardown only sets a flag (a handler, not SIG_IGN,
  # which children would inherit and then ignore TERM from the step timeouts).
  trap 'CLEANING=2' TERM INT USR1
  [[ -n "$WATCHDOG_PID" ]] && { kill "$WATCHDOG_PID" 2>/dev/null; wait "$WATCHDOG_PID" 2>/dev/null; WATCHDOG_PID=""; }
  dyn_log_stop
  [[ -n "$PKTAP_PID" ]] && { sudo kill "$PKTAP_PID" 2>/dev/null || kill "$PKTAP_PID" 2>/dev/null; PKTAP_PID=""; }
  if [[ -n "$UI_RESTORE_UDID" ]]; then
    [[ -z "$UI_RESTORE_APPEARANCE" ]] || dyn_device_appearance "$UI_RESTORE_UDID" "$UI_RESTORE_APPEARANCE"
    [[ -z "$UI_RESTORE_CONTENT" ]] || dyn_device_content_size "$UI_RESTORE_UDID" "$UI_RESTORE_CONTENT"
    UI_RESTORE_UDID=""
  fi
  local owned
  for owned in "$CREATED_UDID" "$CREATED_IPAD"; do
    [[ -n "$owned" ]] || continue
    # A failed delete is not recorded here: the sweep below retries it once and only
    # a device that is STILL present lands in cleanup-failures.txt.
    dyn_device_teardown "$owned" && printf '%s\n' "$owned" >> "$OUT/deleted-simulators.txt"
  done
  CREATED_UDID="" CREATED_IPAD=""
  dyn_sweep_owned "$OUT"
  # The normal path calls cleanup mid-script; make cancellation effective again.
  trap 'exit 143' TERM; trap 'exit 130' INT; trap 'exit 124' USR1
  return 0
}
trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT
# Deadline watchdog. The supervisor (lib/dyn-process.py, PRECHECK_RUNTIME_DEADLINE_SECONDS)
# TERMs this process group at the deadline and only waits a short grace before SIGKILL, so
# the runner starts winding down a quarter of the deadline (at most 120s) EARLIER: the
# watchdog signals USR1 here and TERMs the step in flight, the trap exits 124, and the
# bounded teardown runs to completion before the supervisor's deadline.
trap 'note "deadline watchdog fired: stopping the run and tearing down its own simulators"; exit 124' USR1
if [[ "$DYN_DRY_RUN" != 1 ]]; then
  wd_deadline="${PRECHECK_RUNTIME_DEADLINE_SECONDS:-1800}"
  if [[ "$wd_deadline" =~ ^[0-9]+$ ]] && (( wd_deadline >= 4 )); then
    wd_reserve=$(( wd_deadline / 4 )); (( wd_reserve > 120 )) && wd_reserve=120
    python3 "$HERE/lib/dyn-watchdog.py" --pid "$$" --after "$(( wd_deadline - wd_reserve ))" >/dev/null 2>&1 & WATCHDOG_PID=$!
  fi
  # Startup sweep: a previous run killed before teardown finished (same --out) may have
  # left ledgered precheck-* devices behind; only those, only when they still exist.
  dyn_sweep_owned "$OUT"
fi

# --- D0: device + install -------------------------------------------------------------------
[[ -n "$RUNTIME" ]] || RUNTIME="$(dyn_pick_runtime)"
[[ -n "$DEVTYPE" ]] || DEVTYPE="$(dyn_pick_device_type iphone)"
DEV_NAME="precheck-$(date +%Y%m%d%H%M%S)-$$"
if [[ -n "$APP" ]]; then
  [[ -n "$RUNTIME" && -n "$DEVTYPE" ]] || { emit "$(dyn_line SKIP setup dyn-install "no available iOS runtime / iPhone device type to create a simulator from")"; skip_all "setup failed: no runtime"; exit 3; }
  CREATED_UDID="$(dyn_device_create "$DEV_NAME" "$DEVTYPE" "$RUNTIME")"
  [[ -n "$CREATED_UDID" ]] || { emit "$(dyn_line SKIP setup dyn-install "simctl create failed for $DEVTYPE on $RUNTIME")"; skip_all "setup failed: simctl create"; exit 3; }
  printf '%s\n' "$CREATED_UDID" >> "$OUT/owned-simulators.txt"
  UDID="$CREATED_UDID"
  dyn_device_boot "$UDID"
  dyn_device_prepare "$UDID"
  if ! inst_err="$(dyn_device_install "$UDID" "$APP" 2>&1 >/dev/null)"; then
    emit "$(dyn_line SKIP setup dyn-install "simctl install failed for $APP_LABEL: ${inst_err:-non-zero exit} (wrong architecture, a device build, or a corrupt bundle)")"
    skip_all "setup failed: simctl install"; exit 3
  fi
  emit "$(dyn_line PASS setup dyn-install "installed $BID from $APP_LABEL on $DEV_NAME ($UDID, created by this run; erased before each repeat, deleted after; build config $BUILD_CONFIG from the directory name)")"
else
  emit "$(dyn_line PASS setup dyn-install "using user-supplied device $UDID for $BID (not created by this run: never erased, reset or deleted; repeats relaunch without a fresh erase, so they are less deterministic; build config unknown)")"
fi
INSTALLED="$(dyn_device_container "$UDID" "$BID")"
[[ -n "$INSTALLED" && -d "$INSTALLED" ]] || INSTALLED="$APP"

# --- D10: the installed bundle (nothing executed) -----------------------------------------------
if [[ -n "$INSTALLED" && -f "$INSTALLED/Info.plist" ]]; then
  if [[ -z "$REPO_PLIST" && -n "$REPO" ]]; then
    while IFS= read -r p; do
      [[ "$(dyn_plist_string "$p" CFBundleIdentifier)" == "$BID" ]] && { REPO_PLIST="$p"; break; }
    done < <(find "$REPO" -name Info.plist -not -path '*/build/*' -not -path '*/DerivedData/*' -not -path '*/Pods/*' -not -path '*/node_modules/*' 2>/dev/null)
  fi
  while IFS= read -r l; do emit "$l"; done < <(dyn_bundle_plist_lines "$INSTALLED/Info.plist" "$REPO_PLIST")
  emit "$(dyn_bundle_sdk_line "$INSTALLED/Info.plist")"
  emit "$(dyn_bundle_links_line "$INSTALLED")"
else
  emit "$(dyn_line SKIP 5.1.1 dyn-shipped-bundle "installed bundle path could not be resolved (simctl get_app_container)")"
  emit "$(dyn_line SKIP 2.1 dyn-shipped-sdk "installed bundle path could not be resolved")"
  emit "$(dyn_line SKIP 2.5.1 dyn-shipped-links "installed bundle path could not be resolved")"
fi

# --- pktap (opt-in, sudo) ---------------------------------------------------------------------------
if (( PKTAP )) && [[ "$DYN_DRY_RUN" != 1 ]]; then
  sudo -n tcpdump -i pktap,en0 -k P -w "$OUT/capture.pcap" >/dev/null 2>&1 & PKTAP_PID=$!
  sleep 1; kill -0 "$PKTAP_PID" 2>/dev/null || { PKTAP_PID=""; note "pktap capture could not start (sudo -n tcpdump); hosts come from CFNetwork diagnostics only"; }
elif (( PKTAP )); then
  dyn_plan "sudo tcpdump -i pktap,en0 -k P -w $OUT/capture.pcap &"
fi

# --- D1 / D2: N launch repeats ----------------------------------------------------------------------
L_PASS=0 L_FIND=0 L_SKIP=0 S_PASS=0 S_FIND=0 S_SKIP=0 D_PASS=0 D_FIND=0 D_SKIP=0 D1_D2_SECONDS="" OBSERVATION_SECONDS=""
LAST_DETAIL="" LAST_SIGNALS="" LAUNCH_KIND="SKIP" FRESH=1 TREE_MAX=-1
if (( METRO_SKIP )); then
  emit "$(dyn_line SKIP 2.1 dyn-launch "Metro bundler not running on 127.0.0.1:8081 and $APP_LABEL embeds no main.jsbundle; a React Native Debug build cannot load its JavaScript, so a launch would fail for a reason that is not the app's — start Metro or supply a release bundle")"
  emit "$(dyn_line SKIP 2.1 dyn-first-screen "launch skipped (Metro not running)")"
else
  i=1
  while (( i <= REPEATS )); do
    repeat_started=$SECONDS
    if (( i > 1 || DYN_BLOCKING || DYN_DEMO )) && [[ -n "$CREATED_UDID" ]]; then
      dyn_device_erase "$UDID" || FRESH=0
      dyn_device_boot "$UDID"; dyn_device_prepare "$UDID"
      dyn_device_install "$UDID" "$APP" >/dev/null 2>&1 || FRESH=0
    fi
    observation_started=$SECONDS
    r="$(dyn_repeat "$UDID" "$BID" "$EXE" "$WINDOW" "$OUT" "$i")"
    OBSERVATION_SECONDS="${OBSERVATION_SECONDS}${OBSERVATION_SECONDS:+,}$((SECONDS-observation_started))"
    kind="$(cut -f1 <<<"$r")"; LAST_DETAIL="$(cut -f2 <<<"$r")"; LAST_SIGNALS="$(cut -f3 <<<"$r")"
    tree_nodes="${LAST_SIGNALS##*,}"
    if [[ "$tree_nodes" =~ ^[0-9]+$ ]] && (( tree_nodes > TREE_MAX )); then TREE_MAX="$tree_nodes"; fi
    case "$kind" in PASS) L_PASS=$((L_PASS+1)) ;; FINDING) L_FIND=$((L_FIND+1)) ;; *) L_SKIP=$((L_SKIP+1)) ;; esac
    if (( DYN_DEMO )) && [[ "$DYN_DRY_RUN" != 1 ]]; then
      demo="$(python3 "$HERE/lib/dyn-demo-login.py" "$UDID" "$BID")"
      demo_kind="$(cut -f1 <<<"$demo")"
      case "$demo_kind" in PASS) D_PASS=$((D_PASS+1)) ;; FINDING) D_FIND=$((D_FIND+1)) ;; *) D_SKIP=$((D_SKIP+1)) ;; esac
    fi
    # D2 from the same repeat: a varied screenshot with a live process is a real first screen.
    proc="${LAST_SIGNALS%%,*}"; rest="${LAST_SIGNALS#*,}"; shot="${rest%%,*}"
    if [[ "$shot" == varied && "$proc" == alive ]]; then S_PASS=$((S_PASS+1))
    elif [[ "$shot" == uniform || "$proc" == dead ]]; then S_FIND=$((S_FIND+1))
    else S_SKIP=$((S_SKIP+1)); fi
    D1_D2_SECONDS="${D1_D2_SECONDS}${D1_D2_SECONDS:+,}$((SECONDS-repeat_started))"
    i=$((i+1))
  done
  q="$(dyn_quorum "$L_PASS" "$L_FIND" "$L_SKIP")"; LAUNCH_KIND="$(cut -f1 <<<"$q")"
  fresh_note=""
  if (( DYN_BLOCKING )) && [[ "$CREATED_UDID" != "" && "$DYN_DRY_RUN" != 1 && "$FRESH" == 1 && "$REPEATS" == 3 ]]; then
    fresh_note="; fresh erase verified"
  fi
  emit "$(dyn_line "$LAUNCH_KIND" 2.1 dyn-launch "$(cut -f2 <<<"$q"); last repeat: $LAST_DETAIL; window ${WINDOW}s; screenshots $OUT/launch-*.png$fresh_note")"
  q="$(dyn_quorum "$S_PASS" "$S_FIND" "$S_SKIP")"
  emit "$(dyn_line "$(cut -f1 <<<"$q")" 2.1 dyn-first-screen "$(cut -f2 <<<"$q") (a non-blank screenshot with the process alive after ${WINDOW}s; a splash stuck as a flat frame counts as failed)")"
fi
if (( DYN_DEMO )); then
  if [[ "$DYN_DRY_RUN" == 1 ]]; then
    emit "$(dyn_line SKIP 2.1 dyn-demo-login "dry run: no credentials entered")"
  elif (( D_FIND == 3 && D_PASS == 0 && D_SKIP == 0 )); then
    if [[ "$FRESH" == 1 ]]; then
      emit "$(dyn_line FINDING 2.1 dyn-demo-login "quorum 3/3: explicit login rejection on every attempt; fresh erase verified")"
    else
      emit "$(dyn_line SKIP 2.1 dyn-demo-login "all attempts rejected but fresh erase could not be verified")"
    fi
  elif (( D_PASS == 3 )); then
    emit "$(dyn_line PASS 2.1 dyn-demo-login "quorum 3/3: demo success selector observed on every attempt")"
  else
    emit "$(dyn_line SKIP 2.1 dyn-demo-login "mixed or unreadable login attempts: pass $D_PASS, rejected $D_FIND, skipped $D_SKIP of 3; backend or selector evidence insufficient")"
  fi
fi

# --- D7 / D8: dark mode and Dynamic Type geometry ------------------------------------------------------
geometry_pass() { # geometry_pass <rule-id> <guideline> <label> <tag>
  local id="$1" g="$2" label="$3" tag="$4" tree png hier
  png="$OUT/$tag.png"; hier="$OUT/$tag.json"
  [[ "$DYN_DRY_RUN" == 1 ]] || sleep 2
  dyn_signal_screenshot "$UDID" "$png" >/dev/null
  tree="$(dyn_signal_tree "$UDID" "$hier")"
  if [[ "$DYN_DRY_RUN" == 1 ]]; then emit "$(dyn_line SKIP "$g" "$id" "dry run: $label not observed")"; return 0; fi
  [[ "$tree" == unread ]] && { emit "$(dyn_line SKIP "$g" "$id" "$label: accessibility tree could not be read (Maestro missing or timed out); screenshot $png for a human eye")"; return 0; }
  emit "$(dyn_geometry_line "$(dyn_geometry_report "$hier" 0 0)" "$g" "$id" "$label" "$png")"
}
if (( DYN_DEMO )); then
  emit "$(dyn_line SKIP 4.0 dyn-dark-mode "demo credentials entered; persistent screenshots suppressed")"
  emit "$(dyn_line SKIP 4.0 dyn-dynamic-type "demo credentials entered; persistent screenshots suppressed")"
elif (( METRO_SKIP )) || [[ "$LAUNCH_KIND" != PASS && "$L_PASS" -eq 0 ]]; then
  emit "$(dyn_line SKIP 4.0 dyn-dark-mode "app did not stay up on any launch; layout not judged")"
  emit "$(dyn_line SKIP 4.0 dyn-dynamic-type "app did not stay up on any launch; layout not judged")"
else
  # A device this run created starts from factory settings (light / large). A user-supplied
  # --udid device keeps whatever its owner set: read the originals first, restore them
  # exactly afterwards, and SKIP a check whose original cannot be read (never guess).
  if [[ -n "$CREATED_UDID" ]]; then ORIG_APPEARANCE=light ORIG_CONTENT=large
  else ORIG_APPEARANCE="$(dyn_device_get_appearance "$UDID")"; ORIG_CONTENT="$(dyn_device_get_content_size "$UDID")"; fi
  if [[ -z "$ORIG_APPEARANCE" ]]; then
    emit "$(dyn_line SKIP 4.0 dyn-dark-mode "not judged: the original appearance of user-supplied device $UDID could not be read (simctl ui appearance getter unavailable), so it cannot be restored; the device was left unchanged")"
  else
    [[ -n "$CREATED_UDID" ]] || { UI_RESTORE_UDID="$UDID" UI_RESTORE_APPEARANCE="$ORIG_APPEARANCE" UI_RESTORE_CONTENT="${ORIG_CONTENT:-}"; }
    dyn_device_appearance "$UDID" dark
    geometry_pass dyn-dark-mode 4.0 "dark appearance" dark
    dyn_device_appearance "$UDID" "$ORIG_APPEARANCE"
    UI_RESTORE_UDID=""
  fi
  if [[ -z "$ORIG_CONTENT" ]]; then
    emit "$(dyn_line SKIP 4.0 dyn-dynamic-type "not judged: the original content size of user-supplied device $UDID could not be read (simctl ui content_size getter unavailable), so it cannot be restored; the device was left unchanged")"
  else
    [[ -n "$CREATED_UDID" ]] || { UI_RESTORE_UDID="$UDID" UI_RESTORE_APPEARANCE="${ORIG_APPEARANCE:-}" UI_RESTORE_CONTENT="$ORIG_CONTENT"; }
    dyn_device_content_size "$UDID" accessibility-extra-extra-extra-large
    geometry_pass dyn-dynamic-type 4.0 "Dynamic Type accessibility-extra-extra-extra-large" dynamic-type
    dyn_device_content_size "$UDID" "$ORIG_CONTENT"
    UI_RESTORE_UDID=""
  fi
fi

# --- D9: iPad (opt-in) --------------------------------------------------------------------------------
if (( IPAD )); then
  if [[ -n "$INSTALLED" && -f "$INSTALLED/Info.plist" ]] && ! dyn_plist_supports_ipad "$INSTALLED/Info.plist"; then
    emit "$(dyn_line SKIP 2.4.1 dyn-ipad-layout "not applicable: UIDeviceFamily has no iPad entry (an iPhone-only app runs in compatibility mode)")"
  elif (( METRO_SKIP )); then
    emit "$(dyn_line SKIP 2.4.1 dyn-ipad-layout "launch skipped (Metro not running)")"
  else
    IPAD_TYPE="$(dyn_pick_device_type ipad)"
    CREATED_IPAD="$(dyn_device_create "${DEV_NAME}-ipad" "$IPAD_TYPE" "$RUNTIME")"
    if [[ -z "$CREATED_IPAD" ]]; then
      emit "$(dyn_line SKIP 2.4.1 dyn-ipad-layout "simctl create failed for $IPAD_TYPE")"
    else
      printf '%s\n' "$CREATED_IPAD" >> "$OUT/owned-simulators.txt"
      dyn_device_boot "$CREATED_IPAD"; dyn_device_prepare "$CREATED_IPAD"
      if dyn_device_install "$CREATED_IPAD" "${APP:-}" >/dev/null 2>&1; then
        saved="$UDID"; UDID="$CREATED_IPAD"
        r="$(dyn_repeat "$UDID" "$BID" "$EXE" "$WINDOW" "$OUT" ipad)"
        if [[ "$DYN_DRY_RUN" == 1 ]]; then emit "$(dyn_line SKIP 2.4.1 dyn-ipad-layout "dry run: iPad layout not observed")"
        elif [[ "$(cut -f1 <<<"$r")" == PASS ]]; then geometry_pass dyn-ipad-layout 2.4.1 "iPad layout ($IPAD_TYPE)" ipad-layout
        else emit "$(dyn_line SKIP 2.4.1 dyn-ipad-layout "app did not stay up on the iPad simulator: $(cut -f2 <<<"$r")")"; fi
        UDID="$saved"
      else
        emit "$(dyn_line SKIP 2.4.1 dyn-ipad-layout "simctl install failed on the iPad simulator")"
      fi
    fi
  fi
fi

# --- D11: hosts contacted -----------------------------------------------------------------------------
HOSTS="$OUT/hosts.txt"; : > "$HOSTS"
cat "$OUT"/log-*.txt 2>/dev/null > "$OUT/log-all.txt" || : > "$OUT/log-all.txt"
dyn_hosts_from_log "$OUT/log-all.txt" >> "$HOSTS"
if [[ -n "$PKTAP_PID" ]]; then
  sudo kill "$PKTAP_PID" 2>/dev/null || kill "$PKTAP_PID" 2>/dev/null; PKTAP_PID=""; sleep 1
  tcpdump -nn -r "$OUT/capture.pcap" 'udp port 53' > "$OUT/dns.txt" 2>/dev/null || true
  dyn_hosts_from_tcpdump_text "$OUT/dns.txt" >> "$HOSTS"
fi
sort -u -o "$HOSTS" "$HOSTS"
HOST_NOTE=""
if (( METRO_SKIP )); then HOST_NOTE="launch skipped (Metro not running)"
elif [[ "$DYN_DRY_RUN" == 1 ]]; then HOST_NOTE="dry run"
elif [[ ! -s "$HOSTS" && "$FRAMEWORK" == flutter ]]; then HOST_NOTE="Flutter's Dart HttpClient bypasses CFNetwork, so the log-based capture cannot see it; re-run with --pktap (sudo tcpdump) to read DNS for every process"
elif [[ ! -s "$HOSTS" ]]; then HOST_NOTE="CFNetwork diagnostics saw no request in a ${WINDOW}s window across $REPEATS repeat(s); a networking stack that bypasses CFNetwork would also be invisible here (--pktap)"
elif [[ -n "$PKTAP_PID" || -s "$OUT/dns.txt" ]]; then HOST_NOTE="CFNetwork diagnostics + DNS (pktap)"
else HOST_NOTE="CFNetwork diagnostics only; a stack that bypasses CFNetwork is invisible here"; fi
PRIV=""; [[ -n "$INSTALLED" && -f "$INSTALLED/PrivacyInfo.xcprivacy" ]] && PRIV="$INSTALLED/PrivacyInfo.xcprivacy"
emit "$(dyn_hosts_line "$(dyn_hosts_parity "$HOSTS" "$PRIV")" "$HOST_NOTE")"

# Optional bounded navigation on the same throwaway simulator. The inventory is
# independent of the D-check transcript and cannot change the legacy verdict.
if (( EXPLORE )); then
  if [[ "$DYN_DRY_RUN" == 1 ]]; then
    note "explore dry run: no screens observed"
  elif (( DYN_DEMO )); then
    note "explore SKIP: demo credentials entered; persistent screen capture suppressed"
  elif [[ "$LAUNCH_KIND" != PASS || -z "$CREATED_UDID" ]]; then
    note "explore SKIP: requires a successful launch on this run's created simulator"
  elif ! command -v maestro >/dev/null 2>&1; then
    note "explore SKIP: Maestro unavailable (install Maestro to capture accessibility screens)"
  else
    navigation_args=()
    [[ -z "$NAVIGATION_AUTH" ]] || navigation_args=(--authorized-navigation "$NAVIGATION_AUTH")
    [[ -z "$REPO" ]] || navigation_args=(${navigation_args[@]+"${navigation_args[@]}"} --repo "$REPO")
    python3 "$HERE/lib/dyn-explore.py" --udid "$UDID" --bundle-id "$BID" --out "$OUT" \
      --seconds "$EXPLORE_SECONDS" --max-screens "$EXPLORE_SCREENS" ${navigation_args[@]+"${navigation_args[@]}"} \
      ${HOSTS:+--hosts "$HOSTS"} ${PRIV:+--privacy-manifest "$PRIV"} \
      ${INSTALLED:+--installed-bundle "$INSTALLED"} ${APP:+--source-bundle "$APP"} \
      > "$OUT/explore.json" || note "explore SKIP: Maestro exploration failed or timed out"
  fi
fi

# --- Dedicated selector checks: report what ran and measured accessibility scope ----------------
case "$FRAMEWORK" in
  flutter|kmp)
    why="$(dyn_selector_scope "$FRAMEWORK" "$TREE_MAX")"
    emit "$(dyn_line SKIP 3.1.2 dyn-restore-tap "$why")"
    (( DYN_DEMO )) || emit "$(dyn_line SKIP 2.1 dyn-demo-login "$why")"
    emit "$(dyn_line SKIP '5.1.1(ii)' dyn-permission-prompt "$why (trigger half); the OS prompt itself is native and visible in a screenshot")"
    note "agent: D3 paywall, D6 screenshot parity remain observation-based and can still be judged from screenshots" ;;
  *)
    note "agent: selector-based checks left for Maestro MCP — D3 dyn-paywall-visible, D3b dyn-restore-tap, D4 dyn-permission-prompt:<KEY>, D5 dyn-demo-login, D6 dyn-screenshot-parity; one flow per maestro invocation; labels are in accessibilityText" ;;
esac

# --- Run metadata ------------------------------------------------------------------------------------------
jq -n --arg app "${APP:-}" --arg bid "$BID" --arg cfg "$BUILD_CONFIG" --arg fw "$FRAMEWORK" \
      --arg udid "$UDID" --arg name "$DEV_NAME" --arg type "$DEVTYPE" --arg rt "$RUNTIME" \
      --argjson n "$REPEATS" --argjson w "$WINDOW" --arg out "$OUT" \
      --argjson created "$([[ -n "$CREATED_UDID" ]] && echo true || echo false)" \
      --argjson metro "$([[ "$METRO_SKIP" == 1 ]] && echo true || echo false)" \
      --argjson dry "$([[ "$DYN_DRY_RUN" == 1 ]] && echo true || echo false)" \
      --argjson lp "$L_PASS" --argjson lf "$L_FIND" --argjson ls "$L_SKIP" \
      --arg durations "$D1_D2_SECONDS" --arg observations "$OBSERVATION_SECONDS" '
  {app:(if $app=="" then null else $app end), bundle_id:$bid, build_config:$cfg, framework:$fw,
   device:{udid:$udid, name:$name, type:$type, runtime:$rt, created_by_this_run:$created},
   repeats:$n, window_seconds:$w, launch:{pass:$lp, finding:$lf, skip:$ls},
   d1_d2_seconds:($durations | if . == "" then [] else split(",") | map(tonumber) end), metro_skipped:$metro,
   timing:{legacy_d1_d2_definition:"per repeat reset/boot/install when performed plus D1+D2; unchanged",
           observation_definition:"launch and full observation window plus four signal collection, excluding lifecycle and demo",
           observation_seconds:($observations | if . == "" then [] else split(",") | map(tonumber) end)},
   dry_run:$dry, out:$out, transcript:($out + "/transcript.txt"),
   next:("dynamic.sh --transcript " + $out + "/transcript.txt --findings <scan.json> --target simulator --build-config " + $cfg)}' > "$OUT/run.json"
# Teardown now (the EXIT trap becomes a no-op) so the transcript and the plan are complete.
cleanup
if [[ "$DYN_DRY_RUN" == 1 ]]; then
  echo "# dry run — the plan (nothing above was executed):"
  cat "$DYN_PLAN_FILE"
fi
echo "dynamic-run: transcript $TRANSCRIPT · run.json $OUT/run.json · build config $BUILD_CONFIG (pass it to dynamic.sh --build-config)" >&2
if (( DYN_BLOCKING )) && [[ "$DYN_DRY_RUN" != 1 ]]; then
  bash "$HERE/runtime-review.sh" --dynamic-blocking --transcript "$TRANSCRIPT" | tee -a "$TRANSCRIPT"
fi
exit 0
