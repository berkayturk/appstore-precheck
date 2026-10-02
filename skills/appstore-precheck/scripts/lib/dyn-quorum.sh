#!/usr/bin/env bash
# lib/dyn-quorum.sh — the DECISION RULES of the Phase 6 dynamic tier, as pure
# functions: how four launch signals become one launch verdict, and how N repeated
# verdicts become one transcript line. No simctl, no Maestro, no files: this is the
# part of dynamic-run.sh that CI can pin, so the determinism policy is tested code,
# not prose. Sourced by dynamic-run.sh. Bash 3.2 compatible.
#
# POLICY (from the Phase 2 contract)
#   * N=3 repeats, each on a freshly erased device. A FINDING needs 3/3; mixed or incomplete
#     observations are SKIP, with their counts preserved for human review.
#   * A driver timeout or an unreadable run is a SKIP for that repeat, never a
#     FINDING. If every repeat was a SKIP, the check is a SKIP.
#   * Launch evidence combines four signals: process alive, screenshot not
#     uniform, no crash in the log stream, accessibility tree size. A signal that
#     could not be read is named in the line. A degenerate tree (Flutter / Compose)
#     is never a failure on its own. A flat screenshot alone is not a crash.
#     A clean log alone cannot establish a successful launch.

# dyn_launch_verdict <process> <screenshot> <log> <tree>
#   process:    alive | dead | unread
#   screenshot: varied | uniform | unread
#   log:        clean | crash | unread
#   tree:       <node count> | unread
# -> "<PASS|FINDING|SKIP><TAB><detail>"
dyn_launch_verdict() {
  local proc="${1:-unread}" shot="${2:-unread}" log="${3:-unread}" tree="${4:-unread}"
  local unread="" fail="" ok="" degenerate="" positive=0
  case "$proc" in
    alive) ok="process alive"; positive=1 ;;
    dead)  fail="process gone" ;;
    *)     unread="process state" ;;
  esac
  case "$log" in
    crash) fail="${fail:+$fail, }crash in log stream" ;;
    clean) ok="${ok:+$ok, }no crash in log" ;;
    *)     unread="${unread:+$unread, }log stream" ;;
  esac
  case "$shot" in
    varied)  ok="${ok:+$ok, }screenshot not uniform"; positive=1 ;;
    uniform) unread="${unread:+$unread, }flat screenshot (first-screen review required)" ;;
    *)       unread="${unread:+$unread, }screenshot" ;;
  esac
  case "$tree" in
    unread|"") unread="${unread:+$unread, }accessibility tree" ;;
    *) if [[ ! "$tree" =~ ^[0-9]+$ ]]; then unread="${unread:+$unread, }accessibility tree"
       elif (( tree <= 3 )); then degenerate="accessibility tree has $tree node(s) (degenerate: Flutter/Compose expose no semantics; not a failure on its own)"
       else ok="${ok:+$ok, }accessibility tree $tree nodes"; positive=1; fi ;;
  esac
  local detail=""
  if [[ -n "$fail" ]]; then
    detail="$fail"
    [[ -n "$degenerate" ]] && detail="$detail; $degenerate"
    [[ -n "$unread" ]] && detail="$detail ($unread could not be read)"
    printf 'FINDING\t%s\n' "$detail"; return 0
  fi
  if (( positive == 0 )) || [[ "$shot" == uniform ]]; then
    detail="launch health inconclusive${ok:+; $ok}"
    [[ -n "$degenerate" ]] && detail="$detail; $degenerate"
    [[ -n "$unread" ]] && detail="$detail ($unread could not be read)"
    printf 'SKIP\t%s\n' "$detail"; return 0
  fi
  detail="$ok"
  [[ -n "$degenerate" ]] && detail="$detail; $degenerate"
  [[ -n "$unread" ]] && detail="$detail ($unread could not be read)"
  printf 'PASS\t%s\n' "$detail"
}

# dyn_quorum <pass> <finding> <skip>: conclusions need three observed repeats.
# Mixed evidence and incomplete runs stay SKIP with counts for human review.
dyn_quorum() {
  local pass="${1:-0}" finding="${2:-0}" skip="${3:-0}" n
  n=$((pass + finding + skip))
  if (( n >= 3 && finding == n )); then
    printf 'FINDING\tquorum %d/%d: failed on every launch\n' "$finding" "$n"
  elif (( n >= 3 && pass == n )); then
    printf 'PASS\tquorum %d/%d passed\n' "$pass" "$n"
  else
    printf 'SKIP\tquorum %d/%d failures, %d passed, %d skipped; at least three unanimous observations required\n' "$finding" "$n" "$pass" "$skip"
  fi
}

# Strip control characters from untrusted bundle names, ids and diagnostic text.
dyn_line() {
  local kind="$1" guideline="$2" id="$3" msg="$4"
  case "$kind" in PASS|FINDING|SKIP) ;; *) kind=SKIP ;; esac
  guideline="$(printf '%s' "$guideline" | LC_ALL=C tr '[:cntrl:]' ' ')"
  id="$(printf '%s' "$id" | LC_ALL=C tr '[:cntrl:]' ' ')"
  msg="$(printf '%s' "$msg" | LC_ALL=C tr '[:cntrl:]' ' ')"
  printf 'DYNAMIC-%s: %s [%s] — %s\n' "$kind" "$guideline" "$id" "$msg"
}
