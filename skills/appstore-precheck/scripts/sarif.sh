#!/usr/bin/env bash
# sarif.sh — SARIF 2.1.0 output layer for scan.sh. Sourced; pure jq over the
# findings buffer. No side effects, no output on load. bash 3.2 compatible.

: "${PRECHECK_VERSION:=dev}"

# render_sarif -> prints a SARIF 2.1.0 log built from the FINDINGS_TMP buffer.
# results[] = non-suppressed FAIL/WARN only (PASS + suppressed excluded);
# level: FAIL->error, WARN->warning. rules[] = distinct non-empty ruleIds present.
render_sarif() {
  local buf="${FINDINGS_TMP:-/dev/null}"
  local uri="https://github.com/berkayturk/appstore-precheck"
  local help="https://github.com/berkayturk/appstore-precheck/blob/main/skills/appstore-precheck/references/methodology.md"
  if [[ ! -s "$buf" ]]; then
    jq -nc --arg v "$PRECHECK_VERSION" --arg u "$uri" '
      {"$schema":"https://json.schemastore.org/sarif-2.1.0.json", "version":"2.1.0",
       "runs":[{"tool":{"driver":{"name":"appstore-precheck","version":$v,"informationUri":$u,"rules":[]}},"results":[]}]}'
    return 0
  fi
  jq -s --arg v "$PRECHECK_VERSION" --arg u "$uri" --arg help "$help" '
    (map(select(.suppressed==false and (.severity=="FAIL" or .severity=="WARN")))) as $issues
    | ($issues
        | map({id:.rule_id, text:.guideline})
        | map(select(.id != "" and .id != null))
        | unique_by(.id)
        | map({id:.id, name:.id, shortDescription:{text:.text}, helpUri:$help})) as $rules
    | ($issues | map(
        ( (if (.rule_id // "") == "" then {} else {ruleId:.rule_id} end)
          + {level:(if .severity=="FAIL" then "error" else "warning" end),
             message:{text:.message}}
          + (if .file != null
               then {locations:[{physicalLocation:(
                       {artifactLocation:{uri:.file}}
                       + (if .line != null then {region:{startLine:.line}} else {} end))}]}
               else {locations:[]} end) )
      )) as $results
    | {"$schema":"https://json.schemastore.org/sarif-2.1.0.json", "version":"2.1.0",
       "runs":[{"tool":{"driver":{"name":"appstore-precheck","version":$v,"informationUri":$u,"rules":$rules}},"results":$results}]}
  ' "$buf"
}
