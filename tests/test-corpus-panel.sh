#!/usr/bin/env bash
# Local panel summarization stays honest for mixed votes, gaps, and timing.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/precheck-corpus-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
python3 - "$ROOT" "$WORK" <<'PY'
import json, subprocess, sys
from pathlib import Path
root, out = map(Path, sys.argv[1:])
def write(p,data):
 p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(data))
cases=[]
for name,expected,actual,votes in [('clean','PASS','FINDING',{'pass':0,'finding':3,'skip':0}),('mixed','PASS','PASS',{'pass':2,'finding':1,'skip':0}),('gap','FINDING','SKIP',{'pass':0,'finding':0,'skip':3}),('miss','FINDING','PASS',{'pass':3,'finding':0,'skip':0})]:
 cases.append({'framework':'fixture','variant':name,'expected_launch':expected,'defects':[], 'expected_checks':{'dyn-example':'NEEDS_REVIEW'}})
 d=out/'fixture'/name;d.mkdir(parents=True);(d/'state').write_text('RAN')
 (d/'runtime').mkdir();(d/'runtime/transcript.txt').write_text('DYNAMIC-'+actual+': 2.1 [dyn-launch] observed\n')
 write(d/'runtime/run.json',{'launch':votes,'repeats':10,'window_seconds':5,'d1_d2_seconds':[70,71]*5,'device':{'created_by_this_run':True},'timing':{'observation_seconds':[20,21]}})
 write(d/'runtime/screen-inventory.json',{'checks':[{'check_id':'dyn-example','status':'SKIP'}]})
write(out/'manifest.json',{'cases':cases})
subprocess.run(['python3',str(root/'tests/local/dynamic-panel-report.py'),str(out/'manifest.json'),str(out)],check=True,stdout=subprocess.DEVNULL)
r=json.loads((out/'panel.json').read_text()); a,b,c,d=r['cases']
assert a['false_positive'] and r['summary']['false_positives']==1
assert b['mixed'] and b['launch_matched'] is None
assert c['launch_matched'] is None and not c['miss']
assert d['miss'] and r['summary']['misses']==1
assert all(x['check_matches']['dyn-example'] is None for x in r['cases'])
assert a['timing']['legacy_60_second_gate']=='FAIL'
assert a['timing']['lifecycle_median_seconds']==70.5
assert a['timing']['observation_median_seconds']==20.5
assert a['owned_simulator_deleted'] is None
print('PASS: corpus panel preserves misses, mixed votes, gaps and legacy timing')
PY
# Template generators must not receive the user's HOME or demo credentials.
STAGE="$WORK/bootstrap"
mkdir -p "$STAGE/project"
cat > "$STAGE/probe" <<'PROBE'
#!/usr/bin/env python3
import json, os
from pathlib import Path
Path('probe.json').write_text(json.dumps({'home':os.environ['HOME'], 'cwd':os.getcwd(), 'secret_forwarded':'PRECHECK_DEMO_PASSWORD' in os.environ}))
PROBE
chmod +x "$STAGE/probe"
source "$ROOT/corpus/dynamic/bootstrap.sh"
export PRECHECK_DEMO_PASSWORD=synthetic-never-forward
corpus_bootstrap isolation "$STAGE/project" "$STAGE/probe"
python3 - "$STAGE" <<'PY'
import json,sys
from pathlib import Path
stage=Path(sys.argv[1]);r=json.loads((stage/'project/probe.json').read_text())
assert Path(r['home']).resolve()==(stage/'home').resolve()
assert Path(r['cwd']).resolve()==(stage/'project').resolve()
assert not r['secret_forwarded']
print('PASS: corpus bootstrap isolates HOME and excludes demo credentials')
PY
