#!/usr/bin/env bash
# scorecard-real.sh — clone the pinned real-app panel, scan each, join with human TP/FP labels.
# Network + slow; run via `scorecard.sh --real`, non-blocking in CI.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCAN="$ROOT/skills/appstore-precheck/scripts/scan.sh"
MAN="$ROOT/corpus/real/manifest.json"
LAB="$ROOT/corpus/real/labels.json"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

tp=0; fp=0; unlabeled=0
count="$(jq '.apps|length' "$MAN")"
i=0
while [[ $i -lt $count ]]; do
  name="$(jq -r ".apps[$i].name" "$MAN")"
  repo="$(jq -r ".apps[$i].repo" "$MAN")"
  commit="$(jq -r ".apps[$i].commit" "$MAN")"
  i=$((i+1))
  dir="$WORK/$name"
  git clone --quiet --filter=blob:none "$repo" "$dir" 2>/dev/null || { echo "clone failed: $name" >&2; continue; }
  git -C "$dir" checkout --quiet "$commit" 2>/dev/null || { echo "checkout failed: $name@$commit" >&2; continue; }
  findings="$(cd "$dir" && PRECHECK_VERSION=scorecard bash "$SCAN" --format json 2>/dev/null \
              | jq -c --arg app "$name" '.findings[]|select(.severity!="PASS" and .suppressed==false)|{app:$app, rule_id, file, line}')"
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    key="$(printf '%s' "$f" | jq -r '"\(.app)|\(.rule_id)|\(.file)|\(.line)|'"$commit"'"')"
    label="$(jq -r --arg k "$key" '.[$k] // "UNLABELED"' "$LAB")"
    case "$label" in
      TP) tp=$((tp+1)) ;;
      FP) fp=$((fp+1)) ;;
      *)  unlabeled=$((unlabeled+1)) ;;
    esac
  done <<< "$findings"
done

echo "real-panel: tp=$tp fp=$fp unlabeled=$unlabeled"
awk -v tp="$tp" -v fp="$fp" 'BEGIN{ p=(tp+fp>0)?tp/(tp+fp):1; printf "real-panel precision (FP rate basis): %.2f\n", p }'
[[ $unlabeled -gt 0 ]] && echo "note: $unlabeled finding(s) UNLABELED — run the human labelling pass (see corpus/real/README)."
exit 0
