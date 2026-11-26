#!/usr/bin/env bash
# suppress.sh — .precheck-ignore + inline suppression for scan.sh.
# Sourced by scan.sh AFTER findings.sh (needs rule_slug). Bash 3.2: no associative arrays.

_SUPP_RULES=""        # rule-ids suppressed everywhere, one per line
_SUPP_RULE_PATH=""    # "rule<TAB>glob" per line
_SUPP_PATHS=""        # path globs excluded from scanning, one per line (trailing / stripped)
_SUPP_REASON=""       # set by is_suppressed on a hit
_BASE_KEYS=""         # "rule<TAB>file<TAB>message" per line, from --baseline
_BASE_FILE=""

# _is_catalog_rule <token> -> 0 if token is a known rule slug.
# The bound is derived from the catalog itself (rule_slug returns "" past the
# last rule), so a newly added rule can never be silently unsuppressable again.
_is_catalog_rule() {
  local n s
  # Gap records (evidence.sh is_gap_record, ids ending in "-not-audited") are not
  # catalogue rules but are valid .precheck-ignore ids: acknowledging a SKIP by name
  # is the whole reason they have an id. Guarded so suppress.sh still works when
  # sourced alone in tests.
  if command -v is_gap_record >/dev/null 2>&1 && is_gap_record "$1"; then return 0; fi
  n=1
  while s="$(rule_slug "$n")" && [[ -n "$s" ]]; do
    [[ "$s" == "$1" ]] && return 0
    n=$((n + 1))
  done
  return 1
}

# load_precheck_ignore [root]
load_precheck_ignore() {
  local root="${1:-.}" file line t1 t2
  file="$root/.precheck-ignore"
  _SUPP_RULES=""; _SUPP_RULE_PATH=""; _SUPP_PATHS=""
  [[ -f "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"                                   # strip trailing comment
    line="$(printf '%s' "$line" | awk '{$1=$1;print}')"  # trim ends, collapse ws
    [[ -z "$line" ]] && continue
    t1="$(printf '%s' "$line" | awk '{print $1}')"
    t2="$(printf '%s' "$line" | awk '{print $2}')"
    if _is_catalog_rule "$t1"; then
      if [[ -n "$t2" ]]; then
        _SUPP_RULE_PATH="${_SUPP_RULE_PATH}${t1}	${t2%/}
"
      else
        _SUPP_RULES="${_SUPP_RULES}${t1}
"
      fi
    elif [[ "$t1" == */* || "$t1" == *.* || "$t1" == *"*"* ]]; then
      _SUPP_PATHS="${_SUPP_PATHS}${t1%/}
"
    else
      printf 'suppress: unknown rule-id %s in .precheck-ignore (ignored)\n' "$t1" >&2
    fi
  done < "$file"
}

# load_baseline <file> — read a --save-baseline file. Problems are reported on stderr
# and leave the scan untouched: a baseline that cannot be read must never hide anything.
load_baseline() {
  local file="$1" keys
  _BASE_KEYS=""; _BASE_FILE="$file"
  if [[ ! -f "$file" ]]; then printf 'scan.sh: baseline file not found: %s (ignored)\n' "$file" >&2; return 0; fi
  if ! command -v jq >/dev/null 2>&1; then printf 'scan.sh: --baseline needs jq (ignored)\n' >&2; return 0; fi
  # Fields are joined with US (0x1f) and newlines inside a message flattened to spaces, the
  # same normalisation is_suppressed applies to the live message, so the two keys agree.
  keys="$(jq -r '.findings[]? | select(.rule_id != null and .message != null) | [.rule_id, (.file // ""), (.message | gsub("\n"; " "))] | join("\u001f")' "$file" 2>/dev/null)" \
    || { printf 'scan.sh: baseline is not a findings JSON file: %s (ignored)\n' "$file" >&2; return 0; }
  _BASE_KEYS="$keys"
}

# save_baseline <file> — write the live FAIL/WARN findings of this run as a baseline.
# Reads the JSONL findings buffer, so it works in text and json mode alike.
save_baseline() {
  local file="$1"
  if ! command -v jq >/dev/null 2>&1; then printf 'scan.sh: --save-baseline needs jq\n' >&2; return 0; fi
  [[ -s "${FINDINGS_TMP:-}" ]] || printf '' > "${FINDINGS_TMP:-/dev/null}"
  jq -s --arg v "${PRECHECK_VERSION:-dev}" --arg d "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{tool:"appstore-precheck", version:$v, created:$d,
      findings: [ .[] | select(.suppressed == false and (.severity == "FAIL" or .severity == "WARN"))
                       | {rule_id, severity, file, message} ]}' "$FINDINGS_TMP" > "$file" 2>/dev/null \
    || printf 'scan.sh: could not write the baseline %s\n' "$file" >&2
}

# precheck_prune_globs -> one path glob per line (for scan.sh PRUNE/GREP_PRUNE).
precheck_prune_globs() { printf '%s' "$_SUPP_PATHS"; }

# _inline_marker <line-text> <rule> -> 0 if a real comment marker suppresses <rule>.
_inline_marker() {
  local text="$1" rule="$2" spec
  printf '%s' "$text" | grep -qE '(//|#|<!--)[[:space:]]*precheck:ignore' || return 1
  spec="$(printf '%s' "$text" | sed -nE 's/.*precheck:ignore[[:space:]]*([a-z][a-z0-9-]*).*/\1/p')"
  [[ -z "$spec" ]] && return 0        # bare marker suppresses any rule
  [[ "$spec" == "$rule" ]]            # scoped marker must match
}

# is_suppressed <rule> <file> <line> [<message>] -> 0 if suppressed (+ _SUPP_REASON), else 1.
# The message is passed only for FAIL/WARN: a baseline match needs rule + file + text.
is_suppressed() {
  local rule="$1" file="${2:-}" line="${3:-}" msg="${4:-}" r g target
  _SUPP_REASON=""
  if [[ -n "$msg" && -n "$_BASE_KEYS" ]] && printf '%s\n' "$_BASE_KEYS" | grep -qxF "$(printf '%s\037%s\037%s' "$rule" "$file" "${msg//$'\n'/ }")"; then
    _SUPP_REASON="baseline"; return 0
  fi
  if [[ -n "$rule" ]] && printf '%s\n' "$_SUPP_RULES" | grep -qxF "$rule"; then
    _SUPP_REASON="rule:$rule"; return 0
  fi
  if [[ -n "$rule" && -n "$file" && -n "$_SUPP_RULE_PATH" ]]; then
    while IFS='	' read -r r g; do
      [[ -z "$r" ]] && continue
      if [[ "$r" == "$rule" ]]; then
        # shellcheck disable=SC2254
        case "$file" in
          $g|*/$g|$g/*|*/$g/*) _SUPP_REASON="rule-path:$rule:$g"; return 0 ;;
        esac
      fi
    done <<INNER
$_SUPP_RULE_PATH
INNER
  fi
  if [[ -n "$file" && -n "$line" && -f "$file" ]]; then
    target="$(sed -n "${line}p" "$file" 2>/dev/null)"
    if _inline_marker "$target" "$rule"; then _SUPP_REASON="inline"; return 0; fi
    if [[ "$line" -gt 1 ]]; then
      target="$(sed -n "$((line - 1))p" "$file" 2>/dev/null)"
      if _inline_marker "$target" "$rule"; then _SUPP_REASON="inline-above"; return 0; fi
    fi
  fi
  return 1
}
