#!/usr/bin/env bash
# lib/dyn-quorum.sh — the DECISION RULES of the Phase 6 dynamic tier, as pure
# functions: how four launch signals become one launch verdict, and how N repeated
# verdicts become one transcript line. No simctl, no Maestro, no files: this is the
# part of dynamic-run.sh that CI can pin, so the determinism policy is tested code,
# not prose. Sourced by dynamic-run.sh. Bash 3.2 compatible.
#
# POLICY (from the Phase 2 contract)
#   * N=3 repeats, each on a freshly erased device. A FINDING needs 3/3; a mixed
#     result is a FINDING line carrying its ratio ("crashed on 2 of 3 launches") —
#     recorded as WARN by dynamic.sh like every FINDING, and never eligible for the
#     Phase 3 blocking channel, which reads the ratio.
#   * A driver timeout or an unreadable run is a SKIP for that repeat, never a
#     FINDING. If every repeat was a SKIP, the check is a SKIP.
#   * Launch health combines process, screenshot, crash log and accessibility tree.
#     A PASS needs at least one positive app signal, with no failure signal; a
#     readable log containing no crash does not itself prove a successful launch.
#     A signal that
#     could not be read is named in the line. A degenerate tree (Flutter / Compose)
#     is never a failure on its own.

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
    uniform) fail="${fail:+$fail, }screenshot is a single flat colour" ;;
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
  if (( positive == 0 )); then
    detail="no positive app launch signal${ok:+; $ok}"
    [[ -n "$degenerate" ]] && detail="$detail; $degenerate"
    [[ -n "$unread" ]] && detail="$detail ($unread could not be read)"
    printf 'SKIP\t%s\n' "$detail"; return 0
  fi
  detail="$ok"
  [[ -n "$degenerate" ]] && detail="$detail; $degenerate"
  [[ -n "$unread" ]] && detail="$detail ($unread could not be read)"
  printf 'PASS\t%s\n' "$detail"
}

# dyn_quorum <pass> <finding> <skip> — fold N repeat verdicts into one.
# -> "<PASS|FINDING|SKIP><TAB><detail>". FINDING only when every readable repeat
# failed AND at least the full N failed; a mixed result is a FINDING with its ratio
# (advisory, non-unanimous); all-SKIP is a SKIP.
dyn_quorum() {
  local pass="${1:-0}" finding="${2:-0}" skip="${3:-0}" n
  n=$((pass + finding + skip))
  if (( n == 0 )) || (( skip == n )); then
    printf 'SKIP\tno repeat could be driven (%d of %d skipped)\n' "$skip" "$n"; return 0
  fi
  if (( finding == n )); then
    printf 'FINDING\tquorum %d/%d: failed on every launch\n' "$finding" "$n"; return 0
  fi
  if (( finding > 0 )); then
    printf 'FINDING\tquorum %d/%d: failed on %d of %d launches (not unanimous; advisory, never blocking)%s\n' \
      "$finding" "$n" "$finding" "$n" "$( (( skip > 0 )) && printf '; %d could not be driven' "$skip")"; return 0
  fi
  printf 'PASS\tquorum %d/%d passed%s\n' "$pass" "$n" "$( (( skip > 0 )) && printf ' (%d of %d could not be driven)' "$skip" "$n")"
}

# dyn_line <PASS|FINDING|SKIP> <guideline> <rule-id> <message> -> one transcript line
# in the grammar dynamic.sh parses (column 0, id in brackets, em-dash separator).
dyn_line() {
  local kind="$1" guideline="$2" id="$3" msg="$4"
  case "$kind" in PASS|FINDING|SKIP) ;; *) kind=SKIP ;; esac
  printf 'DYNAMIC-%s: %s [%s] — %s\n' "$kind" "$guideline" "$id" "$msg"
}
