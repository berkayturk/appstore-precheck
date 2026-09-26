#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -B - <<'PY'
import contextlib,importlib.util,io,json,sys,tempfile,types
from pathlib import Path
from unittest import mock
s=importlib.util.spec_from_file_location('runner','skills/appstore-precheck/scripts/opt-in-review.py');m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
checks={}
errors=m.import_records(checks,[None,{'check_id':'x','status':{}},{'check_id':'x','status':'FINDING'},{'check_id':'x','status':'PASS'}],'synthetic')
assert len(errors)==2 and checks['x']['status']=='FINDING'
with tempfile.TemporaryDirectory() as d:
 root=Path(d);repo=root/'source';repo.mkdir();app=root/'Sample.app';app.mkdir()
 def call(flags):
  calls=[]
  def run(argv,timeout):
   calls.append(argv)
   if argv[1].endswith('dynamic-run.sh'):return types.SimpleNamespace(returncode=0,stdout='')
   return types.SimpleNamespace(returncode=0,stdout=json.dumps({'checks':[],'results':[]}))
  with mock.patch.object(m,'run',run),mock.patch.object(sys,'argv',['runner','--repo',str(repo),'--out-dir',str(root/'report'),'--app',str(app)]+flags),contextlib.redirect_stdout(io.StringIO()):
   assert m.main()==0
  return calls,json.loads((root/'report/summary.json').read_text())
 calls,out=call(['--no-runtime','--metadata']);assert out['tiers']['runtime']=='NOT_RUN'
 assert not any('dynamic-run.sh' in ' '.join(a) for a in calls)
 calls,out=call(['--demo-login']);assert any(a[1].endswith('dynamic-run.sh') and '--demo-login' in a for a in calls)
 calls,out=call(['--no-runtime','--metadata','--asc-app-id','123','--asc-version-id','v1','--asc-info-id','i1'])
 cmd=next(a for a in calls if a[1].endswith('metadata-review.sh'));assert cmd[cmd.index('--asc-version-id')+1]=='v1' and cmd[cmd.index('--asc-info-id')+1]=='i1'
 assert list(repo.iterdir())==[]
print('orchestration: no-runtime never launches, explicit demo and ASC selectors forwarded, source untouched')
PY
node bin/cli.js --help | grep -q -- '--no-runtime'
if node bin/cli.js --demo-login --no-runtime >/dev/null 2>&1; then
  echo 'conflicting runtime options accepted'; exit 1
fi
