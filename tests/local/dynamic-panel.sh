#!/usr/bin/env bash
# macOS-only, opt-in real build/runtime panel. No existing simulator is erased.
# Usage: bash tests/local/dynamic-panel.sh [--framework name] [--variant clean|broken]
#        [--out directory] [--build-timeout seconds] [--window seconds] [--repeats N]
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CORPUS="$ROOT/corpus/dynamic"
SCRIPTS="$ROOT/skills/appstore-precheck/scripts"
OUT="" FILTER_FW="" FILTER_VARIANT="" BUILD_TIMEOUT=1200 WINDOW=10 REPEATS=3 EXPLORE_SECONDS=90
usage() { echo "dynamic-panel.sh: $1" >&2; exit 64; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --framework) [[ $# -ge 2 ]] || usage "$1 needs a value"; FILTER_FW="$2"; shift 2 ;;
    --variant) [[ $# -ge 2 ]] || usage "$1 needs a value"; FILTER_VARIANT="$2"; shift 2 ;;
    --out) [[ $# -ge 2 ]] || usage "$1 needs a value"; OUT="$2"; shift 2 ;;
    --build-timeout) [[ $# -ge 2 ]] || usage "$1 needs a value"; BUILD_TIMEOUT="$2"; shift 2 ;;
    --window) [[ $# -ge 2 ]] || usage "$1 needs a value"; WINDOW="$2"; shift 2 ;;
    --repeats) [[ $# -ge 2 ]] || usage "$1 needs a value"; REPEATS="$2"; shift 2 ;;
    --explore-seconds) [[ $# -ge 2 ]] || usage "$1 needs a value"; EXPLORE_SECONDS="$2"; shift 2 ;;
    *) usage "unknown option '$1'" ;;
  esac
done
case "$FILTER_FW" in ""|swiftui|rn-bare|expo|flutter|kmp) ;; *) usage "unknown framework '$FILTER_FW'" ;; esac
case "$FILTER_VARIANT" in ""|clean|broken) ;; *) usage "unknown variant '$FILTER_VARIANT'" ;; esac
for n in "$BUILD_TIMEOUT" "$WINDOW" "$REPEATS" "$EXPLORE_SECONDS"; do [[ "$n" =~ ^[0-9]+$ ]] || usage "time and repeat options must be integers"; done
(( BUILD_TIMEOUT >= 1 && REPEATS >= 1 )) || usage "timeout and repeats must be positive"
[[ "$(uname -s)" == Darwin ]] || { echo "SKIP: dynamic panel requires macOS/Xcode"; exit 3; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: Python 3 unavailable"; exit 3; }
command -v xcrun >/dev/null 2>&1 || { echo "SKIP: Xcode command line tools unavailable"; exit 3; }
[[ -n "$OUT" ]] || OUT="$(mktemp -d "${TMPDIR:-/tmp}/precheck-dynamic-panel.XXXXXX")"
mkdir -p "$OUT" || usage "cannot create output directory"
OUT="$(cd "$OUT" && pwd -P)"
echo "dynamic panel artifacts: $OUT"

# One status record per case; the Python summary reads these and the transcript.
for fw in swiftui rn-bare expo flutter kmp; do
  [[ -z "$FILTER_FW" || "$FILTER_FW" == "$fw" ]] || continue
  for variant in clean broken; do
    [[ -z "$FILTER_VARIANT" || "$FILTER_VARIANT" == "$variant" ]] || continue
    case_dir="$OUT/$fw/$variant"
    mkdir -p "$case_dir/artifact" "$case_dir/runtime"
    echo "== $fw/$variant =="
    bash "$CORPUS/$fw/build.sh" "$variant" --out "$case_dir/artifact" --timeout "$BUILD_TIMEOUT" > "$case_dir/build.txt" 2>&1
    build_status=$?
    if [[ "$build_status" -ne 0 ]]; then
      if [[ "$build_status" -eq 3 ]]; then state=SKIP; else state=ERROR; fi
      printf '%s\n' "$state" > "$case_dir/state"
      sed -n '/^SKIP:/p' "$case_dir/build.txt" | tail -1
      continue
    fi
    app="$(sed -n 's/^app_path=//p' "$case_dir/build.txt" | tail -1)"
    if [[ -z "$app" || ! -f "$app/Info.plist" ]]; then
      printf '%s\n' ERROR > "$case_dir/state"
      echo "ERROR: build exported no simulator app"
      continue
    fi
    case "$fw" in swiftui) runtime_fw=native ;; rn-bare|expo) runtime_fw=rn ;; *) runtime_fw="$fw" ;; esac
    extra=()
    if grep -q -- '--explore' "$SCRIPTS/dynamic-run.sh"; then extra+=(--explore --explore-seconds "$EXPLORE_SECONDS"); fi
    bash "$SCRIPTS/dynamic-run.sh" --app "$app" --repo "$CORPUS/$fw/$variant" \
      --framework "$runtime_fw" --out "$case_dir/runtime" --repeats "$REPEATS" \
      --window "$WINDOW" "${extra[@]+"${extra[@]}"}" > "$case_dir/runtime.txt" 2>&1
    runtime_status=$?
    if [[ "$runtime_status" -eq 0 ]]; then
      printf '%s\n' RAN > "$case_dir/state"
      config="$(sed -n 's/^build_config=//p' "$case_dir/build.txt" | tail -1)"
      [[ -n "$config" ]] || config=unknown
      bash "$SCRIPTS/dynamic.sh" --transcript "$case_dir/runtime/transcript.txt" \
        --target simulator --build-config "$config" --format json > "$case_dir/reconciled.json" 2> "$case_dir/reconcile.err" || :
    elif [[ "$runtime_status" -eq 3 || "$runtime_status" -eq 69 ]]; then
      printf '%s\n' SKIP > "$case_dir/state"
    else
      printf '%s\n' ERROR > "$case_dir/state"
    fi
  done
done

python3 - "$CORPUS/manifest.json" "$OUT" <<'PY'
import json, os, re, sys
from pathlib import Path

manifest = json.loads(Path(sys.argv[1]).read_text())
out = Path(sys.argv[2])
rows = []
for case in manifest['cases']:
    d = out / case['framework'] / case['variant']
    if not (d / 'state').exists():
        continue
    state = (d / 'state').read_text().strip()
    transcript = (d / 'runtime/transcript.txt')
    content = transcript.read_text(errors='replace') if transcript.exists() else ''
    matches = re.findall(r'^DYNAMIC-(PASS|FINDING|SKIP):[^\n]*\[dyn-launch\]', content, re.M)
    observed = matches[-1] if matches else 'NOT_RUN'
    expected = case['expected_launch']
    if state == 'RAN' and observed != 'NOT_RUN':
        matched = observed == expected
    else:
        matched = None
    records = []
    for kind, rule in re.findall(r'^DYNAMIC-([A-Z_]+):[^\n]*\[([^]]+)\]', content, re.M):
        records.append({'rule': rule, 'result': kind})
    inventory = d / 'runtime/screen-inventory.json'
    checks = {}
    if inventory.exists():
        try:
            data = json.loads(inventory.read_text())
            checks = {c['check_id']: c.get('status', 'NOT_RUN')
                      for c in data.get('checks', []) if 'check_id' in c}
        except (OSError, ValueError, TypeError):
            pass
    expected_checks = case.get('expected_checks', {})
    observed_checks = {check_id: checks.get(check_id, 'NOT_RUN')
                       for check_id in expected_checks}
    check_matches = {
        check_id: (observed_checks[check_id] == wanted
                   if state == 'RAN' and observed_checks[check_id] != 'NOT_RUN'
                   else None)
        for check_id, wanted in expected_checks.items()
    }
    reason = ''
    if state != 'RAN':
        for log in (d / 'build.txt', d / 'runtime.txt'):
            if log.exists():
                for line in log.read_text(errors='replace').splitlines():
                    if line.startswith(('SKIP:', 'ERROR:')):
                        reason = line[:300]
                        break
            if reason:
                break
    rows.append({'framework': case['framework'], 'variant': case['variant'],
                 'state': state, 'expected_launch': expected,
                 'observed_launch': observed, 'launch_matched': matched,
                 'targeted_defects': case['defects'], 'observations': records,
                 'expected_checks': expected_checks, 'observed_checks': observed_checks,
                 'check_matches': check_matches,
                 'reason': reason})
(out / 'panel.json').write_text(json.dumps({'schema_version': 1, 'cases': rows}, indent=2) + '\n')
with (out / 'panel.tsv').open('w') as f:
    f.write('framework\tvariant\tstate\texpected_launch\tobserved_launch\tlaunch_matched\tcheck_matches\treason\n')
    for r in rows:
        values = [r['framework'], r['variant'], r['state'], r['expected_launch'],
                  r['observed_launch'], str(r['launch_matched']),
                  str(sum(v is True for v in r['check_matches'].values())) + '/' +
                  str(sum(v is not None for v in r['check_matches'].values())) +
                  ' of ' + str(len(r['check_matches'])),
                  r['reason'].replace('\t', ' ')]
        f.write('\t'.join(values) + '\n')
print((out / 'panel.tsv').read_text(), end='')
print('report=' + str(out / 'panel.json'))
PY
