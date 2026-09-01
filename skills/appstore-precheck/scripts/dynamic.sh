#!/usr/bin/env bash
# dynamic.sh — turn a Phase 6 transcript into findings, and reconcile them with the
# static scan. Pure text transform: it launches nothing, touches no device, and runs
# anywhere findings.sh runs (ubuntu CI included). Bash 3.2 compatible: no
# associative arrays; the catalogue and the reconciliation table are functions.
#
# WHY THIS EXISTS
# ---------------
# Before Phase 1 the DYNAMIC-PASS / DYNAMIC-FINDING / DYNAMIC-SKIP lines the agent
# printed never reached findings.sh: no rule_id, absent from --format json and
# SARIF, no evidence class, unmeasurable. The tier was a narrative running beside
# the machine-readable pipeline. This script is the bridge, in the same JSONL shape
# scan.sh writes, with two additions that make runtime evidence honest:
#   * every record says where it came from (runtime_target, build_config), and a
#     Debug/unknown build never clears needs_build_verification (evidence.sh);
#   * a runtime observation that contradicts a static finding can RESOLVE it only
#     when the dynamic check is the COMPLETE test of the same proposition — and
#     RESOLVED is structurally inert (see findings.sh), so the verdict arithmetic
#     in verdict.sh / thresholds.sh is untouched.
#
# INPUT GRAMMAR (column 0 only; prose, "Pierre:" lines and indented text are ignored)
#   DYNAMIC-PASS:    <guideline> [<rule-id>] — <message>
#   DYNAMIC-FINDING: <guideline> [<rule-id>] — <message>
#   DYNAMIC-SKIP:    <guideline> [<rule-id>] — <why it could not be driven>
# <rule-id> is one of the D-check ids below, optionally suffixed ":<KEY>" for a
# per-key observation (D4: dyn-permission-prompt:NSCameraUsageDescription). A line
# without a bracketed id is recorded with an empty rule_id and reconciles with
# nothing. A FINDING is recorded as WARN: the tier is advisory in Phase 1, and the
# opt-in blocking channel is Phase 3's job.
#
# USAGE
#   dynamic.sh [--transcript FILE|-] [--findings FILE] [--target simulator|device]
#              [--build-config release|debug|unknown] [--format json|jsonl] [--not-run]
#   --findings   the static side: scan.sh's --format json envelope, or its raw JSONL.
#   --not-run    emit the runtime-not-audited gap record instead of reading a
#                transcript (the tier was not run: no .app / UDID supplied).
#   Exit 64 on a bad argument, 66 on a missing file.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=findings.sh
. "$HERE/findings.sh"
# shellcheck source=evidence.sh
. "$HERE/evidence.sh"

# --- Dynamic-check catalogue ----------------------------------------------------
# dyn_catalogue -> every D-check id, one per line. dyn-install is D0 (setup), the
# rest are observations. Counts derived from this list (the gap record) can never
# disagree with it.
dyn_catalogue() {
  printf '%s\n' dyn-install dyn-launch dyn-first-screen dyn-paywall-visible \
    dyn-restore-tap dyn-permission-prompt dyn-demo-login dyn-screenshot-parity
}
dyn_is_setup() { [[ "${1:-}" == "dyn-install" ]]; }

# dyn_rule_confidence <base-id> -> who acts on it. A person: every D-check is about
# what a reviewer sees in front of them, none is an upload validator. D0 is setup,
# so its PASS is at most a hint that the bundle was installable.
dyn_rule_confidence() {
  case "$1" in
    dyn-launch|dyn-first-screen|dyn-paywall-visible|dyn-restore-tap) echo review-risk ;;
    dyn-permission-prompt|dyn-demo-login|dyn-screenshot-parity) echo review-risk ;;
    dyn-install) echo judgment-call ;;
    *) echo "" ;;
  esac
}

# --- Reconciliation table -------------------------------------------------------
# reconcile_map -> JSON array of {dyn, static, complete, keyed}. "complete" means
# the dynamic check tests the WHOLE proposition the static rule asserts, so a
# runtime contradiction may RESOLVE it; anything less only downgrades (FAIL→WARN)
# and annotates, never to PASS. Rationale per row:
#   demo-account ↔ dyn-demo-login: complete. The static rule asks "are working
#     reviewer credentials declared?"; the dynamic check logs in with them. If the
#     login works, the claim "no working demo path" is false in full.
#   usage-description-crosscheck ↔ dyn-permission-prompt: complete PER KEY only
#     (keyed:true). The static rule finds "API used, NS*UsageDescription missing"
#     per key; a prompt observed for THAT key with the declared text is the whole
#     test. A keyless observation (one permission tried) is partial for every key.
#   subscription-links-restore ↔ dyn-restore-tap: partial. The static rule wants
#     Restore + terms + privacy visible on the paywall; a non-inert Restore tap
#     tests one of three links. Never resolves; FAIL→WARN with the observation.
reconcile_map() {
  cat <<'JSON'
[
  {"dyn":"dyn-demo-login",        "static":"demo-account",                 "complete":true,  "keyed":false},
  {"dyn":"dyn-permission-prompt", "static":"usage-description-crosscheck", "complete":true,  "keyed":true},
  {"dyn":"dyn-restore-tap",       "static":"subscription-links-restore",   "complete":false, "keyed":false}
]
JSON
}

# --- Arguments ------------------------------------------------------------------
TRANSCRIPT="-" STATIC="" TARGET="" CONFIG="unknown" FORMAT="json" NOT_RUN="false"
usage_err() { echo "dynamic.sh: $1" >&2; exit 64; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --transcript)   [[ $# -ge 2 ]] || usage_err "--transcript needs a value"; TRANSCRIPT="$2"; shift 2 ;;
    --findings)     [[ $# -ge 2 ]] || usage_err "--findings needs a value";   STATIC="$2";     shift 2 ;;
    --target)       [[ $# -ge 2 ]] || usage_err "--target needs a value";     TARGET="$2";     shift 2 ;;
    --build-config) [[ $# -ge 2 ]] || usage_err "--build-config needs a value"; CONFIG="$2";   shift 2 ;;
    --format)       [[ $# -ge 2 ]] || usage_err "--format needs a value";     FORMAT="$2";     shift 2 ;;
    --not-run)      NOT_RUN="true"; shift ;;
    *) usage_err "unknown option '$1'" ;;
  esac
done
case "$TARGET" in ""|simulator|device) ;; *) usage_err "--target must be simulator|device" ;; esac
case "$CONFIG" in release|debug|unknown) ;; *) usage_err "--build-config must be release|debug|unknown" ;; esac
case "$FORMAT" in json|jsonl) ;; *) usage_err "--format must be json|jsonl" ;; esac
if [[ -n "$STATIC" && ! -f "$STATIC" ]]; then echo "dynamic.sh: no such file '$STATIC'" >&2; exit 66; fi
if [[ "$NOT_RUN" == "false" && "$TRANSCRIPT" != "-" && ! -f "$TRANSCRIPT" ]]; then
  echo "dynamic.sh: no such file '$TRANSCRIPT'" >&2; exit 66
fi

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
STATIC_JSONL="$WORK/static.jsonl"; DYN_JSONL="$WORK/dyn.jsonl"; OUT_JSONL="$WORK/out.jsonl"
: > "$STATIC_JSONL"; : > "$DYN_JSONL"

# --- Static side: accept the public envelope or raw JSONL -----------------------
if [[ -n "$STATIC" ]]; then
  jq -c 'if (type=="object" and has("findings")) then .findings[] else . end' "$STATIC" > "$STATIC_JSONL" \
    || { echo "dynamic.sh: --findings is not JSON" >&2; exit 65; }
fi

# --- Dynamic side: parse the transcript into records ----------------------------
FINDINGS_TMP="$DYN_JSONL"
set_runtime "$TARGET" "$CONFIG"

# _trim <string> — strip a trailing CR and surrounding blanks (transcripts get pasted
# from editors and terminals that disagree about line endings).
_trim() {
  local v="${1:-}"
  v="${v%$'\r'}"
  while [[ "$v" == *' ' || "$v" == *$'\t' ]]; do v="${v%?}"; done
  while [[ "$v" == ' '* || "$v" == $'\t'* ]]; do v="${v#?}"; done
  printf '%s' "$v"
}

# parse_line <line> — one column-0 DYNAMIC-* line -> one record. Everything else is
# silently not a record. Fields: <guideline> [<id>] — <message>; each optional past
# the guideline, any run of blanks between them.
parse_line() {
  local line kind rest guideline id="" msg sev
  # Column 0 is decided on the raw line: an indented DYNAMIC-* is commentary.
  line="${1%$'\r'}"
  case "$line" in
    DYNAMIC-PASS:*)    kind=PASS ;;
    DYNAMIC-FINDING:*) kind=FINDING ;;
    DYNAMIC-SKIP:*)    kind=SKIP ;;
    *) return 0 ;;
  esac
  rest="$(_trim "${line#DYNAMIC-*:}")"
  if [[ "$rest" == *' '* ]]; then guideline="${rest%% *}"; rest="$(_trim "${rest#* }")"
  else guideline="$rest"; rest=""; fi
  if [[ "$rest" == \[*\]* ]]; then id="${rest%%]*}"; id="${id#[}"; rest="$(_trim "${rest#*]}")"; fi
  msg="${rest#— }"; msg="${msg#- }"; msg="$(_trim "$msg")"
  case "$kind" in PASS) sev=PASS ;; FINDING) sev=WARN ;; SKIP) sev=SKIP ;; esac
  set_rule "$id"
  set_evidence "runtime"
  set_confidence "$(dyn_rule_confidence "${id%%:*}")"
  if [[ -n "$msg" ]]; then _record "$sev" "$guideline $msg"; else _record "$sev" "$guideline"; fi
}

if [[ "$NOT_RUN" == "true" ]]; then
  n=0; while IFS= read -r d; do dyn_is_setup "$d" || n=$((n + 1)); done < <(dyn_catalogue)
  set_runtime "" ""
  set_rule "runtime-not-audited"
  _record SKIP "runtime — the Phase 6 dynamic tier did not run (no built simulator .app or booted UDID + bundle id was supplied): $n dynamic checks were not observed. Supply a simulator .app path (or a booted UDID + bundle id) and ask for the dynamic check to close this gap"
else
  if [[ "$TRANSCRIPT" == "-" ]]; then
    [[ -t 0 ]] && usage_err "no --transcript given and stdin is a terminal (pass --transcript FILE, pipe the transcript in, or use --not-run)"
    src="/dev/stdin"
  else src="$TRANSCRIPT"; fi
  while IFS= read -r line || [[ -n "$line" ]]; do parse_line "$line"; done < "$src"
fi
# Detach the buffer: findings.sh reads FINDINGS_TMP, which the linter cannot see.
# shellcheck disable=SC2034
FINDINGS_TMP=""

# --- Corroborate the caller's build_config against D0 ----------------------------
# --build-config is a caller assertion; the guard it feeds must not rest on a typo.
# D0 records the .app's parent directory in its own line. A "release" claim over a
# transcript whose D0 says Debug-iphonesimulator is degraded to unknown, loudly.
if [[ "$CONFIG" == "release" ]] \
   && jq -e 'select(.rule_id=="dyn-install") | select(.message|test("Debug-iphonesimulator"))' "$DYN_JSONL" >/dev/null 2>&1; then
  echo "dynamic.sh: --build-config release contradicted by the D0 line (Debug-iphonesimulator); treating the run as unknown" >&2
  CONFIG="unknown"
  tmp="$WORK/dyn.cfg.jsonl"
  jq -c 'if .build_config != null then .build_config = "unknown" else . end' "$DYN_JSONL" > "$tmp" && mv "$tmp" "$DYN_JSONL"
fi

# --- Reconcile -----------------------------------------------------------------
# The derivation for a runtime observation stays in evidence.sh: this is the only
# value jq needs, computed once for the run's build_config.
RT_NB="$(needs_build_verification runtime validator-blocking "$CONFIG")"

jq -n -c \
  --slurpfile static "$STATIC_JSONL" --slurpfile dyn "$DYN_JSONL" \
  --argjson map "$(reconcile_map)" --argjson rt_nb "$RT_NB" \
  --arg target "$TARGET" --arg config "$CONFIG" '
  def tgt: ($target | if .=="" then null else . end);
  def runtime_fields: {runtime_target:tgt, build_config:$config};
  def obs_text($d): ($d.message | sub("^[^ ]+ ?"; ""));
  # Every aimed observation is folded into the message — the winner decides the
  # branch, but no observation (or screenshot reference) is ever dropped.
  def fold($a): " · runtime: " + ([$a[] | obs_text(.)] | join("; "));
  # confirm: same severity, evidence runtime. The qualifier can only be CLEARED by
  # a release run, never raised: an already-established claim (manifest evidence)
  # stays established.
  def confirm($c; $a): $c + runtime_fields
      + {evidence:"runtime",
         needs_build_verification:($c.needs_build_verification and $rt_nb),
         message:($c.message + fold($a))};
  # resolve: withdrawn by a complete runtime test; inert downstream.
  def resolve($c; $a): $c + runtime_fields
      + {severity:"RESOLVED", resolved_by:"runtime", evidence:"runtime",
         needs_build_verification:false, message:($c.message + fold($a))};
  # downgrade: FAIL→WARN only, evidence and qualifier untouched, observation appended.
  def downgrade($c; $a; $why): $c + runtime_fields
      + {severity:(if $c.severity=="FAIL" then "WARN" else $c.severity end),
         message:($c.message + fold($a) + $why)};
  # A per-key id is free text an agent typed. Only a well-formed key may aim at a
  # static record: at most one colon, and a plist-key-shaped token (letters, digits,
  # underscore, at least 5 characters). Anything else aims at nothing.
  def key_ok($k): ($k == null) or ($k | test("^[A-Za-z][A-Za-z0-9_]{4,}$"));
  def complete($d): ($d._m.complete and (($d._m.keyed|not) or $d._key!=null));
  # For one static record, the observations aimed at it. A key must match as a whole
  # token of the message, never as a bare substring.
  def aimed($c; $mapped): [$mapped[] | select(._m.static==$c.rule_id)
      | . as $d | select($d._key==null
                         or ($c.message|test("(^|[^A-Za-z0-9_])" + $d._key + "([^A-Za-z0-9_]|$)")))];
  def reconcile_one($c; $mapped):
      aimed($c; $mapped) as $a
      | if ($a|length)==0 then {rec:$c, confirmed:0, resolved:0, used:[]}
        elif ($c.severity!="FAIL" and $c.severity!="WARN") or $c.suppressed then
          {rec:$c, confirmed:0, resolved:0, used:[]}
        elif ([$a[]|select(.severity=="WARN")]|length)>0 then
          {rec:confirm($c; $a), confirmed:1, resolved:0, used:[$a[].id]}
        else ([$a[]|select(.severity=="PASS")][0]) as $d
          | if complete($d) and (($c.needs_build_verification|not) or $config=="release") then
              {rec:resolve($c; $a), confirmed:0, resolved:1, used:[$a[].id]}
            elif complete($d) then
              {rec:downgrade($c; $a; " (observed on a " + $config + " build; does not establish the shipping archive, so not resolved)"),
               confirmed:0, resolved:0, used:[$a[].id]}
            else
              {rec:downgrade($c; $a; " (partial check; the static claim is wider than what was observed)"),
               confirmed:0, resolved:0, used:[$a[].id]}
            end
        end;
  ($dyn | map(. + {_base:(.rule_id|split(":")[0]),
                   _key:(.rule_id|split(":") | if length==2 then .[1] elif length>2 then "" else null end)})) as $dyn
  # Observations that may touch a static record: mapped, non-SKIP, well-formed key.
  | ($dyn | map(select(.severity!="SKIP") | select(key_ok(._key))
               | . as $d | [$map[] | select(.dyn==$d._base)] | select(length>0) | $d + {_m:.[0]})) as $mapped
  | ($static | map(reconcile_one(.; $mapped))) as $r
  # Consumption is tracked per RECORD (its id), so two lines with one rule id are
  # never conflated: each is either folded into a static record or kept standalone.
  | ([$r[].used[]] | unique) as $used
  | ($dyn | map(select((.id as $id | $used | index($id)) | not)) | map(del(._base,._key))) as $standalone
  | {records:([$r[].rec] + $standalone),
     stats:{observed:([$dyn[]|select(.severity!="SKIP")]|length),
            resolved:([$r[].resolved]|add // 0),
            confirmed:([$r[].confirmed]|add // 0)}}
' > "$WORK/reconciled.json" || { echo "dynamic.sh: reconciliation failed" >&2; exit 70; }

jq -c '.records[]' "$WORK/reconciled.json" > "$OUT_JSONL"
STATS="$(jq -c '.stats' "$WORK/reconciled.json")"

if [[ "$FORMAT" == "jsonl" ]]; then cat "$OUT_JSONL"; exit 0; fi
FINDINGS_TMP="$OUT_JSONL" render_json | jq --argjson rt "$STATS" '.summary.runtime = $rt'
