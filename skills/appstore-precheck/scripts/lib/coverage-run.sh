#!/usr/bin/env bash
# Append static run coverage; optional tier summaries are reported separately.
coverage_run_json() {
  jq --argjson gaps "${COVERAGE_GAPS_JSON:-[]}" --slurpfile baseline "$SCRIPT_DIR/../guidelines-baseline.json" '
    ($baseline[0]) as $b
    | ($b.all_sections | map(. as $s
        | select(any($b.all_sections[]; startswith($s + ".")) | not)
        | select($b.not_counted[.] == null))) as $leaves
    | ([.findings[] | select(.severity == "WARN" or .severity == "FAIL") | .guideline
        | split("(")[0] | select(. as $s | $leaves | index($s))] | unique) as $touched
    | ([.findings[] | select(.severity == "SKIP" and .rule_id != "modular-checks-not-audited")] | length) as $legacy
    | ([$gaps[].guideline, (.findings[] | select(.severity == "SKIP") | .guideline)]
        | map(split("(")[0]) | map(select(. as $s | $leaves | index($s))) | unique) as $skipped
    | .summary.not_audited = ($legacy + ($gaps | length))
    | . + {coverage_sections: {
        denominator: ($leaves | length), touched: ($touched | length),
        touched_sections: $touched, skip: ($skipped | length), skipped_sections: $skipped,
        legacy_skip: $legacy, gaps: $gaps,
        human_only: ($b.human_only | length), human_only_sections: $b.human_only,
        not_run_routes: ["deep", "dynamic", "vision"],
        scope: "Static issue sections only (PASS excluded); SKIP counts unique leaf sections. Input-gap records remain separately visible."
      }}'
}
