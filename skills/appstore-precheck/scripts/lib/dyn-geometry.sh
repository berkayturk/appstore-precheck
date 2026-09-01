#!/usr/bin/env bash
# lib/dyn-geometry.sh — layout heuristics over a Maestro view hierarchy (JSON), for
# the dark-mode, Dynamic Type and iPad observations (dyn-dark-mode, dyn-dynamic-type,
# dyn-ipad-layout; guidelines 4.0 / 2.4.1). Pure jq over a file: testable on CI with
# recorded hierarchies, no device needed. Sourced by dynamic-run.sh. Bash 3.2.
#
# The hierarchy is what `maestro hierarchy` prints: a tree of {attributes:{text,
# accessibilityText, bounds:"[x1,y1][x2,y2]", …}, children:[…]}. The label a control
# exposes lives in `accessibilityText`, not `text` — matchers read both.
#
# Three heuristics, all judgment-call (a clipped frame is a hint, not a rejection):
#   clipped    a labelled node whose bounds leave the screen rectangle
#   zero_size  a labelled node with an empty rectangle (text that cannot be seen)
#   overlap    two labelled LEAF nodes whose rectangles overlap by more than half of
#              the smaller one (a price row drawn over another at XXXL text size)
# A degenerate tree (<= 3 nodes) is SKIP: Flutter and Compose Multiplatform expose no
# semantics to Maestro on a perfectly healthy screen, so nothing can be judged.

# dyn_geometry_report <hierarchy.json> <screen_w> <screen_h> -> JSON
#   {nodes, degenerate, clipped:[label…], zero_size:[label…], overlap:[[a,b]…]}
dyn_geometry_report() {
  local file="$1" w="${2:-0}" h="${3:-0}"
  [[ -f "$file" ]] || { echo '{"nodes":0,"degenerate":true,"clipped":[],"zero_size":[],"overlap":[],"error":"no hierarchy file"}'; return 0; }
  jq -c --argjson W "$w" --argjson H "$h" '
    def lbl: ((.attributes.accessibilityText // "") as $a | (.attributes.text // "") as $t
                | if $a != "" then $a else $t end);
    def rect: (.attributes.bounds // "" | capture("\\[(?<x1>-?[0-9]+),(?<y1>-?[0-9]+)\\]\\[(?<x2>-?[0-9]+),(?<y2>-?[0-9]+)\\]")?
               | {x1:(.x1|tonumber), y1:(.y1|tonumber), x2:(.x2|tonumber), y2:(.y2|tonumber)});
    def leaf: ((.children // []) | length) == 0;
    [.. | objects | select(has("attributes"))] as $nodes
    | ($nodes | length) as $n
    | [$nodes[] | select(lbl != "") | select(rect != null) | {label: lbl, r: rect, leaf: leaf}] as $labelled
    # Screen rectangle: the size given by the caller, else the bounds of the root node (the Maestro root
    # is the full screen), else no clipping judgement at all.
    | (if ($W > 0 and $H > 0) then {w:$W, h:$H}
       else (($nodes[0] // {}) | rect) as $root | (if $root == null then null else {w:$root.x2, h:$root.y2} end) end) as $scr
    | ($scr != null and $scr.w > 0 and $scr.h > 0) as $screen
    | {nodes: $n,
       degenerate: ($n <= 3),
       clipped: [$labelled[] | select($screen) | select(.r.x1 < -1 or .r.y1 < -1 or .r.x2 > $scr.w + 1 or .r.y2 > $scr.h + 1) | .label],
       zero_size: [$labelled[] | select(.r.x2 - .r.x1 <= 0 or .r.y2 - .r.y1 <= 0) | .label],
       overlap: ([$labelled[] | select(.leaf) | select(.r.x2 - .r.x1 > 0 and .r.y2 - .r.y1 > 0)] as $L
                 | [range(0; $L|length) as $i | range($i + 1; $L|length) as $j
                    | $L[$i] as $a | $L[$j] as $b
                    | (([$a.r.x2, $b.r.x2] | min) - ([$a.r.x1, $b.r.x1] | max)) as $iw
                    | (([$a.r.y2, $b.r.y2] | min) - ([$a.r.y1, $b.r.y1] | max)) as $ih
                    | select($iw > 0 and $ih > 0)
                    | (($a.r.x2 - $a.r.x1) * ($a.r.y2 - $a.r.y1)) as $aa
                    | (($b.r.x2 - $b.r.x1) * ($b.r.y2 - $b.r.y1)) as $ab
                    | select(($iw * $ih) > 0.5 * ([$aa, $ab] | min))
                    | [$a.label, $b.label]])}
  ' "$file" 2>/dev/null || echo '{"nodes":0,"degenerate":true,"clipped":[],"zero_size":[],"overlap":[],"error":"hierarchy is not JSON"}'
}

# dyn_geometry_line <report-json> <guideline> <rule-id> <context> [<screenshot>]
# -> one transcript line. Degenerate -> SKIP; any heuristic hit -> FINDING; else PASS.
dyn_geometry_line() {
  local rep="$1" guideline="$2" id="$3" ctx="$4" shot="${5:-}"
  local n c z o first
  n="$(jq -r .nodes <<<"$rep")"
  if [[ "$(jq -r .degenerate <<<"$rep")" == "true" ]]; then
    printf 'DYNAMIC-SKIP: %s [%s] — %s: accessibility tree has %s node(s) (degenerate: Flutter/Compose expose no semantics to Maestro); layout cannot be judged from the tree%s\n' \
      "$guideline" "$id" "$ctx" "$n" "${shot:+ — judge the screenshot by eye: $shot}"
    return 0
  fi
  c="$(jq -r '.clipped|length' <<<"$rep")"; z="$(jq -r '.zero_size|length' <<<"$rep")"; o="$(jq -r '.overlap|length' <<<"$rep")"
  if (( c + z + o > 0 )); then
    first="$(jq -r '[(.clipped[]? | "clipped: \(.)"), (.zero_size[]? | "zero-size: \(.)"), (.overlap[]? | "overlap: \(.[0]) / \(.[1])")] | .[0:3] | join("; ")' <<<"$rep")"
    printf 'DYNAMIC-FINDING: %s [%s] — %s: %s clipped, %s zero-size, %s overlapping labelled frame(s) in a %s-node tree (%s)%s\n' \
      "$guideline" "$id" "$ctx" "$c" "$z" "$o" "$n" "$first" "${shot:+; screenshot $shot}"
    return 0
  fi
  printf 'DYNAMIC-PASS: %s [%s] — %s: no clipped, zero-size or overlapping labelled frame in a %s-node tree%s\n' \
    "$guideline" "$id" "$ctx" "$n" "${shot:+; screenshot $shot}"
}
