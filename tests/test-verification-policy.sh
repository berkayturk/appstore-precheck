#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -B - <<'PY'
import copy,importlib.util,json,tempfile
from pathlib import Path
s=importlib.util.spec_from_file_location('policy','scripts/verification-policy.py');m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
catalog={'source':{},'obligations':[{'id':'synthetic','kind':'obligation','section':'1','criterion':'Synthetic criterion','apple_ref':'1.0','routes':[{'route':'static','decides':'full'}],'exceptions':[],'applicability':{}}]}
base=m.report(catalog,{},{});assert base['summary']['full_positive_capability']==0
cap={'bounded':{'positive':True,'finding':True}}
c={'id':'criterion','description':'Inspect all required conditions','evidence_kinds':['artifact'],'review_requirement':'Retain bounded scope','full_positive_verifiers':['bounded'],'decisive_finding_verifiers':['bounded']}
p={'schema_version':1,'section':'1','obligations':[{'obligation_id':'synthetic','owner':'reviewer','document_group':'synthetic','applicability_evidence':['app profile'],'conditions':[c]}]}
with tempfile.TemporaryDirectory() as d:
 f=Path(d)/'1.json';f.write_text(json.dumps(p));pol=m.load_policies(d,catalog,cap)
 r=m.report(catalog,pol,cap);assert r['summary']['full_positive_capability']==1
 p['obligations'][0]['conditions'].append(dict(c,id='second',full_positive_verifiers=[],decisive_finding_verifiers=[]));f.write_text(json.dumps(p))
 r=m.report(catalog,m.load_policies(d,catalog,cap),cap);assert r['summary']['full_positive_capability']==0 and r['summary']['decisive_finding_capability']==1
 p['obligations'][0]['conditions'][0]['full_positive_verifiers']=['invented'];f.write_text(json.dumps(p))
 try:m.load_policies(d,catalog,cap)
 except ValueError:pass
 else:raise AssertionError('unimplemented verifier accepted')
 p['obligations'][0]['conditions'][0]['full_positive_verifiers']=['bounded']
 for invalid in (['invented-kind'], ['artifact', 'artifact'], 'artifact'):
  p['obligations'][0]['conditions'][0]['required_positive_evidence_kinds']=invalid;f.write_text(json.dumps(p))
  try:m.load_policies(d,catalog,cap)
  except ValueError:pass
  else:raise AssertionError('invalid mandatory evidence kinds accepted')
 p['obligations'][0]['conditions'][0]['required_positive_evidence_kinds']=['artifact'];f.write_text(json.dumps(p))
 assert m.load_policies(d,catalog,cap)['synthetic']['conditions'][0]['required_positive_evidence_kinds']==['artifact']
 for invalid in ([[]], [['invented']], [['artifact','artifact']], ['artifact'], 'artifact'):
  p['obligations'][0]['conditions'][0]['required_positive_evidence_groups']=invalid;f.write_text(json.dumps(p))
  try:m.load_policies(d,catalog,cap)
  except ValueError:pass
  else:raise AssertionError('invalid positive alternatives accepted')
 p['obligations'][0]['conditions'][0]['required_positive_evidence_groups']=[['artifact']];f.write_text(json.dumps(p))
 assert m.load_policies(d,catalog,cap)['synthetic']['conditions'][0]['required_positive_evidence_groups']==[['artifact']]
installed=m.load_policies(m.REF/'verification',json.loads((m.REF/'guideline-obligations.json').read_text()),m.verifier_capabilities())
def condition(ident,cid):return next(c for c in installed[ident]['conditions'] if c['id']==cid)
for ident,cid,kind in [
 ('atom-c568f26de7444ff59dfb492fdb9ce4d5','criterion','rights-record'),
 ('atom-0c62e14c97974eaf95c413cb93cf16db','criterion','certification-record'),
 ('atom-13f97b3592d642d7acaa569ec9b7e0b9','carrier-media-approval','apple-bundle-approval'),
 ('atom-e591af4341824863947c5635c09b12e4','derivatives-local-licenses','regulatory-permissions')]:
 assert kind in condition(ident,cid)['required_positive_evidence_kinds']
assert condition('atom-a7348ccb4c63425ca0384e3ee4c9e339','qualified-dose-origin-or-approval')['required_positive_evidence_groups']==[['institutional-authorization','regulatory-approval']]
assert condition('atom-564c86e5c2b44721aacf6d633eec6024','pass-signature')['required_positive_evidence_groups']==[['issued-pass-artifact','pass-signature-verification']]
# A prior approval does not replace the separate carrier purchase requirement.
assert not condition('atom-0a55d4fab71c4f72a3d6fb6921722d2d','carrier-iap-availability').get('required_positive_evidence_kinds')
print('policy capability: full routes cannot promote verification; missing conditions, unknown verifiers and missing qualifying documents rejected')
PY
