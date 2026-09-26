#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -B - <<'PY'
import importlib.util, tempfile, hashlib, datetime
from pathlib import Path
s=importlib.util.spec_from_file_location('contract','skills/appstore-precheck/scripts/verification-contract.py')
m=importlib.util.module_from_spec(s); s.loader.exec_module(m)
assert m.reduce_status('APPLICABLE',['a','b'],['a'],[]) == 'UNRESOLVED'
assert m.reduce_status('UNKNOWN',['a'],['a'],[]) == 'UNRESOLVED'
assert m.reduce_status('NOT_APPLICABLE',['a'],[],[]) == 'UNRESOLVED'
assert m.reduce_status('NOT_APPLICABLE',['a'],[],[],True) == 'NOT_APPLICABLE_VERIFIED'
assert m.reduce_status('APPLICABLE',['a'],['a'],['a']) == 'VERIFIED_FINDING'
assert m.reduce_status('APPLICABLE',['a'],['a'],[],conflict=True) == 'UNRESOLVED'
assert m.reduce_status('APPLICABLE',['a'],['a'],[]) == 'VERIFIED_PASS'
s=m.summarize([{'status':'VERIFIED_FINDING'},{'status':'UNRESOLVED'}])
assert s['decided_percent']==50 and s['verified_pass_percent']==0 and not s['ready']
target={k:'synthetic' for k in m.SCOPE_FIELDS}
target.update(devices=['synthetic phone'],storefronts=['US'],artifact_sha256='a'*64,source_sha256='b'*64,distribution='simulator')
p=m.validate_profile({'schema_version':1,'target':target,'facts':{'ugc':{'value':None}},'reviewed_at':datetime.date.today().isoformat()})
assert m.scope_matches(target,target)
assert not m.scope_matches(dict(target,backend=None),target)
with tempfile.TemporaryDirectory() as d:
 Path(d,'proof').write_bytes(b'synthetic proof')
 e={'id':'e1','kind':'artifact','path':'proof','sha256':hashlib.sha256(b'synthetic proof').hexdigest(),'scope':target,'collector':'fixture','limitations':[],'collected_at':p['reviewed_at']}
 assert not m.evidence_errors(e,p,d)
 assert m.evidence_errors(dict(e,sha256='0'*64),p,d)
 assert m.evidence_errors(dict(e,scope=dict(target,storefronts=['TR'])),p,d)
 assert m.evidence_errors(dict(e,collected_at='2000-01-01'),p,d)
 assert m.evidence_errors(dict(e,path='https://user:secret@example.test'),p,d)
print('verification contract: sufficiency, contradiction, scope, date and hash tests passed')
PY
