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
 cases.append({'framework':'fixture','variant':name,'expected_launch':expected,'defects':[], 'expected_checks':{'dyn-example':'NEEDS_REVIEW'},'expected_runtime_labels':['Runtime seed']})
 d=out/'fixture'/name;d.mkdir(parents=True);(d/'state').write_text('RAN')
 (d/'runtime').mkdir();(d/'runtime/transcript.txt').write_text('DYNAMIC-'+actual+': 2.1 [dyn-launch] observed\n')
 write(d/'runtime/run.json',{'launch':votes,'repeats':sum(votes.values()),'window_seconds':5,'dry_run':False,'d1_d2_seconds':[70,71]*5,'device':{'created_by_this_run':True},'timing':{'observation_seconds':[20,21]}})
 write(d/'runtime/hierarchy-1.json',{'children':[{'attributes':{'text':'Runtime seed'}}]})
 write(d/'runtime/screen-inventory.json',{'checks':[{'check_id':'dyn-example','status':'SKIP'}]})
write(out/'manifest.json',{'cases':cases})
subprocess.run(['python3',str(root/'tests/local/dynamic-panel-report.py'),str(out/'manifest.json'),str(out)],check=True,stdout=subprocess.DEVNULL)
r=json.loads((out/'panel.json').read_text()); a,b,c,d=r['cases']
assert a['false_positive'] and r['summary']['false_positives']==1
assert b['mixed'] and b['launch_matched'] is None
assert c['launch_matched'] is None and not c['miss']
assert d['miss'] and r['summary']['misses']==1
assert all(x['check_matches']['dyn-example'] is None for x in r['cases'])
assert all(x['runtime_seed_matches']['Runtime seed'] is True for x in r['cases'])
assert a['timing']['legacy_60_second_gate']=='NOT_EVALUATED'
assert a['timing']['lifecycle_median_seconds']==70.5
assert a['timing']['observation_median_seconds']==20.5
assert a['owned_simulator_deleted'] is None
# Independently reproduced false-success regressions.
d = out/'fixture'/'partial-finding'
d.mkdir(parents=True);(d/'state').write_text('RAN');(d/'runtime').mkdir()
(d/'runtime/transcript.txt').write_text('DYNAMIC-FINDING: 2.1 [dyn-launch] one failure two skips\n')
write(d/'runtime/run.json',{'launch':{'pass':0,'finding':1,'skip':2},'repeats':3,'dry_run':False})
cases.append({'framework':'fixture','variant':'partial-finding','expected_launch':'FINDING','defects':[]})
d=out/'fixture'/'stale';d.mkdir(parents=True);(d/'state').write_text('SKIP');(d/'runtime').mkdir()
(d/'runtime/transcript.txt').write_text('DYNAMIC-PASS: 2.1 [dyn-launch] stale result\n')
write(d/'runtime/run.json',{'launch':{'pass':3,'finding':0,'skip':0},'repeats':3,'dry_run':False})
cases.append({'framework':'fixture','variant':'stale','expected_launch':'FINDING','defects':[]})
d=out/'swiftui'/'clean';d.mkdir(parents=True);(d/'state').write_text('RAN');(d/'runtime').mkdir()
(d/'runtime/transcript.txt').write_text('DYNAMIC-PASS: 2.1 [dyn-launch] dry run\n')
write(d/'runtime/run.json',{'launch':{'pass':10,'finding':0,'skip':0},'repeats':10,'window_seconds':5,'dry_run':True,'d1_d2_seconds':[0]*10,'device':{'created_by_this_run':True}})
cases.append({'framework':'swiftui','variant':'clean','expected_launch':'PASS','defects':[]})
write(out/'integrity.json',{'unchanged':True})
write(out/'manifest.json',{'cases':cases})
subprocess.run(['python3',str(root/'tests/local/dynamic-panel-report.py'),str(out/'manifest.json'),str(out)],check=True,stdout=subprocess.DEVNULL)
r=json.loads((out/'panel.json').read_text()); partial,stale,dry=r['cases'][-3:]
assert partial['mixed'] and partial['launch_matched'] is None, partial
assert stale['observed_launch']=='NOT_RUN' and not stale['miss'], stale
assert dry['timing']['legacy_60_second_gate']=='NOT_EVALUATED', dry
# A global snapshot cannot bind a historical case.
run=json.loads((d/'runtime/run.json').read_text());run['dry_run']=False;write(d/'runtime/run.json',run)
subprocess.run(['python3',str(root/'tests/local/dynamic-panel-report.py'),str(out/'manifest.json'),str(out)],check=True,stdout=subprocess.DEVNULL)
assert json.loads((out/'panel.json').read_text())['cases'][-1]['timing']['legacy_60_second_gate']=='NOT_EVALUATED'
write(d/'integrity.json',{'unchanged':True})
subprocess.run(['python3',str(root/'tests/local/dynamic-panel-report.py'),str(out/'manifest.json'),str(out)],check=True,stdout=subprocess.DEVNULL)
assert json.loads((out/'panel.json').read_text())['cases'][-1]['timing']['legacy_60_second_gate']=='NOT_EVALUATED'
write(d/'integrity.json',{'unchanged':True,'before':{'sha256':'a'*64,'stable_read':True},'after':{'sha256':'a'*64,'stable_read':True}})
# A real clean10 benchmark keeps the old lifecycle definition and checks all owned devices.
run={'launch':{'pass':10,'finding':0,'skip':0},'repeats':10,'window_seconds':5,'dry_run':False,'d1_d2_seconds':[70,71]*5,'timing':{'observation_seconds':[20,21]*5},'device':{'created_by_this_run':True,'udid':'owned-phone'}}
write(d/'runtime/run.json',run)
(d/'runtime/owned-simulators.txt').write_text('owned-phone\nowned-ipad\n')
(d/'runtime/deleted-simulators.txt').write_text('owned-phone\n')
write(out/'simulators-after.json',{'devices':{'runtime':[{'udid':'owned-ipad'}]}})
subprocess.run(['python3',str(root/'tests/local/dynamic-panel-report.py'),str(out/'manifest.json'),str(out)],check=True,stdout=subprocess.DEVNULL)
speed=json.loads((out/'panel.json').read_text())['cases'][-1]
assert speed['timing']['legacy_60_second_gate']=='FAIL' and speed['timing']['lifecycle_median_seconds']==70.5
assert speed['timing']['observation_median_seconds']==20.5
assert speed['owned_simulator_deleted'] is False
(d/'runtime/deleted-simulators.txt').write_text('owned-phone\nowned-ipad\n')
write(out/'simulators-after.json',{'devices':{'runtime':[]}})
run['d1_d2_seconds']=[60]*10
write(d/'runtime/run.json',run)
subprocess.run(['python3',str(root/'tests/local/dynamic-panel-report.py'),str(out/'manifest.json'),str(out)],check=True,stdout=subprocess.DEVNULL)
speed=json.loads((out/'panel.json').read_text())['cases'][-1]
assert speed['owned_simulator_deleted'] is True and speed['timing']['legacy_60_second_gate']=='PASS'
write(out/'simulators-after.json',{'devices':{'runtime':'unreadable group'}})
subprocess.run(['python3',str(root/'tests/local/dynamic-panel-report.py'),str(out/'manifest.json'),str(out)],check=True,stdout=subprocess.DEVNULL)
assert json.loads((out/'panel.json').read_text())['cases'][-1]['owned_simulator_deleted'] is None
write(d/'integrity.json',{'unchanged':False})
subprocess.run(['python3',str(root/'tests/local/dynamic-panel-report.py'),str(out/'manifest.json'),str(out)],check=True,stdout=subprocess.DEVNULL)
assert json.loads((out/'panel.json').read_text())['cases'][-1]['timing']['legacy_60_second_gate']=='NOT_EVALUATED'
print('PASS: partial findings, stale files and dry runs cannot pass corpus gates')
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
# Refuse a reused case directory before any build/simulator action.
mkdir -p "$WORK/guard/swiftui/clean" "$WORK/shims"
printf 'old evidence\n' > "$WORK/guard/swiftui/clean/transcript.txt"
printf '#!/bin/sh\nprintf "Darwin\\n"\n' > "$WORK/shims/uname"
printf '#!/bin/sh\nexit 99\n' > "$WORK/shims/xcrun"
chmod +x "$WORK/shims/uname" "$WORK/shims/xcrun"
if PATH="$WORK/shims:$PATH" bash "$ROOT/tests/local/dynamic-panel.sh" --framework swiftui --variant clean --out "$WORK/guard" > "$WORK/guard.log" 2>&1; then
  echo 'FAIL: nonempty case output accepted' >&2
  exit 1
else
  status=$?
fi
[[ "$status" == 64 ]]
[[ "$(cat "$WORK/guard/swiftui/clean/transcript.txt")" == 'old evidence' ]]
grep -q 'choose a fresh --out' "$WORK/guard.log"
echo 'PASS: stale case output is refused without erasing evidence'
