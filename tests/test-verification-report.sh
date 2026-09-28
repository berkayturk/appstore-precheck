#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -B - <<'PY'
import copy, datetime, hashlib, importlib.util, json, os, subprocess, tempfile
from pathlib import Path
spec=importlib.util.spec_from_file_location('report','skills/appstore-precheck/scripts/verification-report.py')
m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
today=datetime.date.today().isoformat()
target={k:'synthetic' for k in m.contract.SCOPE_FIELDS}
target.update(bundle_id='test.fixture',devices=['phone'],storefronts=['US'],artifact_sha256='a'*64,source_sha256='b'*64,distribution='simulator')
profile={'schema_version':1,'target':target,'reviewed_at':today,'facts':{}}
catalog={'obligations':[{'id':'req-one','kind':'obligation','criterion':'Synthetic two-part requirement','section':'1','exceptions':['exc-one']},{'id':'exc-one','kind':'exception','criterion':'Synthetic exception'}]}
policy={'req-one':{'obligation_id':'req-one','owner':'developer','document_group':'fixture','applicability_evidence':['document'],'applicability_verifiers':['runtime.launch-crash.v1'],'conditions':[{'id':'a','description':'first','evidence_kinds':['runtime-transcript'],'full_positive_verifiers':[],'decisive_finding_verifiers':['runtime.launch-crash.v1'],'review_requirement':'independent evidence review'},{'id':'b','description':'second','evidence_kinds':['document'],'full_positive_verifiers':[],'decisive_finding_verifiers':[],'review_requirement':'independent evidence review'}]}}
with tempfile.TemporaryDirectory() as td:
 base=Path(td); evidence=[]
 def add(ident,kind,payload):
  path=base/(ident+'.json'); path.write_text(json.dumps(payload)); row={'id':ident,'kind':kind,'path':path.name,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'scope':copy.deepcopy(target),'collector':'fixture','limitations':[],'collected_at':today}; evidence.append(row); return ident
 add('document','document',{'description':'Substantive synthetic document with specific observations'})
 runs=[{'environment_id':str(i),'fresh_environment':True,'backend_available':True,'driver_timeout':False,'accessibility_node_count':4,'events':[{'type':'launch_started','bundle_id':'test.fixture'},{'type':'process_exited','bundle_id':'test.fixture','exit_code':9}]} for i in range(3)]
 add('runtime','runtime-transcript',{'schema_version':1,'runs':runs})
 decision={'obligation_id':'req-one','applicability':{'status':'APPLICABLE'},'conditions':[{'condition_id':'a','status':'FINDING','mode':'automatic','verifier':'runtime.launch-crash.v1','evidence_ids':['runtime']}]}
 def report(ds=None,es=None,ps=None,config=None):
  ds=[decision] if ds is None else ds
  if es is None:
   needed=set()
   for d in ds:
    if isinstance(d,dict):
     for claim in d.get('conditions',[])+[d.get('applicability',{})]:
      if isinstance(claim,dict): needed.update(claim.get('evidence_ids',[]))
   for e in evidence:
    if e['id'] in needed and e['kind']=='review-record':
     record=json.loads((base/e['path']).read_text());needed.update(record.get('evidence_ids',[]));needed.update(record.get('authority',{}).get('evidence_ids',[]))
   es=[e for e in evidence if e['id'] in needed]
  return m.build_report(profile,{'schema_version':1,'evidence':es},{'schema_version':1,'decisions':ds},catalog,policy if ps is None else ps,base,config or {})
 def status(r): return r['obligations'][0]['status']
 assert status(report())=='VERIFIED_FINDING'
 assert report()['summary']['decided_percent']==100 and report()['summary']['verified_pass_percent']==0
 bad=copy.deepcopy(decision); bad['conditions'][0]['status']='PASS'
 assert status(report([bad]))=='VERIFIED_FINDING', 'actual contradiction overrides caller PASS'
 for key,value in [('build','other'),('storefronts',['TR']),('bundle_id','test.fixture.extension'),('distribution','distribution')]:
  es=copy.deepcopy(evidence); es[1]['scope'][key]=value; assert status(report(es=es))=='UNRESOLVED'
 for change in [{'collected_at':'2000-01-01'},{'sha256':'0'*64},{'path':'missing'},{'collected_at':'2999-01-01'}]:
  es=copy.deepcopy(evidence); es[1].update(change); assert status(report(es=es))=='UNRESOLVED'
 assert status(report(es=[None]+evidence))=='VERIFIED_FINDING', 'bad evidence row must be isolated'
 assert status(report(ds=[None,decision]))=='VERIFIED_FINDING', 'bad decision row must be isolated'
 for status_alias in ['verified','VERIFIED_PASS','WARN','NEEDS_REVIEW']:
  bad=copy.deepcopy(decision);bad['conditions'][0]['status']=status_alias; assert status(report([bad]))=='VERIFIED_FINDING' and report([bad])['input_errors']
 bad=copy.deepcopy(decision);bad['conditions'][0]['verifier']='unknown-check';assert status(report([bad]))=='VERIFIED_FINDING'
 assert status(report([],config={'attestations':{'req-one':{'answer':'yes','evidence':'document','answered_on':today}}}))=='UNRESOLVED'
 for ap in [{'status':'UNKNOWN'},{'status':'NOT_APPLICABLE'},{'status':'NOT_APPLICABLE','rationale':'Not relevant','evidence_ids':['document'],'reviewer':'owner','source_ids':['exc-one']}]:
  bad=copy.deepcopy(decision);bad['applicability']=ap;bad['conditions']=[];assert status(report([bad]))=='UNRESOLVED'
 bad=copy.deepcopy(decision);bad['conditions'][0].update(status='PASS',mode='reviewed',reviewer='someone',rationale='yes',evidence_ids=['document']);assert status(report([bad]))=='UNRESOLVED'
 # Full labels in policy cannot invent evaluator implementation.
 ps=copy.deepcopy(policy);ps['req-one']['conditions'][0]['full_positive_verifiers']=['invented'];bad['conditions'][0].update(mode='automatic',verifier='invented');assert status(report([bad],ps=ps))=='UNRESOLVED'
 for alteration in ['mixed','timeout','backend','tree','reused','short']:
  mutated=copy.deepcopy(runs)
  if alteration=='mixed': mutated[2]['events'][1]['exit_code']=0
  if alteration=='timeout': mutated[2]['driver_timeout']=True
  if alteration=='backend': mutated[2]['backend_available']=False
  if alteration=='tree': mutated[2]['accessibility_node_count']=0
  if alteration=='reused': mutated[2]['environment_id']='0'
  if alteration=='short': mutated.pop()
  ident='rt-'+alteration;add(ident,'runtime-transcript',{'schema_version':1,'runs':mutated});bad=copy.deepcopy(decision);bad['conditions'][0]['evidence_ids']=[ident];assert status(report([bad]))=='UNRESOLVED',alteration
 # Reviewed positive requires substantive per-condition observations and human authority.
 add('authority','reviewer-authority',{'schema_version':1,'reviewer':'Synthetic reviewer','authorized_by':'Synthetic owner','actor_type':'human','role':'product reviewer','obligation_ids':['req-one'],'identity_check':'owner-confirmed','basis':'Synthetic documented delegation'})
 def review_record(cid,outcome,source_ids=None):
  record={'schema_version':1,'obligation_id':'req-one','condition_id':cid,'outcome':outcome,'reviewer':'Synthetic reviewer','rationale':'Specific observed condition reviewed','scope':target,'reviewed_at':today,'evidence_ids':['document'],'observations':[{'evidence_id':'document','location':'description','observation':'Specific substantive criterion evidence reviewed'}],'authority':{'status':'verified','evidence_ids':['authority']}}
  if source_ids: record.update(source_ids=source_ids,applicability_reason='Synthetic documented exception applies')
  return record
 ps=copy.deepcopy(policy); ps['req-one']['conditions'][0]['evidence_kinds']=['document']
 add('review-a','review-record',review_record('a','PASS'));add('review-b','review-record',review_record('b','PASS'))
 add('review-ap','review-record',review_record('applicability','APPLICABLE',['req-one']))
 good=copy.deepcopy(decision);good['applicability']={'status':'APPLICABLE','rationale':'Scoped criterion applies','source_ids':['req-one'],'reviewer':'Synthetic reviewer','evidence_ids':['review-ap']};good['conditions']=[{'condition_id':c,'status':'PASS','mode':'reviewed','reviewer':'Synthetic reviewer','rationale':'Substantive criterion review','evidence_ids':['review-'+c]} for c in ['a','b']]
 assert status(report([good],ps=ps))=='VERIFIED_PASS'
 mandatory=copy.deepcopy(ps);mandatory['req-one']['conditions'][0]['required_positive_evidence_kinds']=['approval-document']
 mandatory['req-one']['conditions'][0]['evidence_kinds'].append('approval-document')
 assert status(report([good],ps=mandatory))=='UNRESOLVED', 'feature evidence cannot replace a mandatory approval document'
 bare=review_record('a','PASS');bare['rationale']='yes';add('bare-review','review-record',bare)
 bare_claim=copy.deepcopy(good);bare_claim['conditions'][0]['evidence_ids']=['bare-review']
 assert status(report([bare_claim],ps=ps))=='UNRESOLVED', 'a bare answer cannot become a substantive review'
 add('approval-document','approval-document',{'description':'Synthetic study-specific approval fixture, not a real permission'})
 with_doc=review_record('a','PASS');with_doc['evidence_ids'].append('approval-document');with_doc['observations'].append({'evidence_id':'approval-document','location':'description','observation':'Synthetic scope matches this synthetic condition'})
 add('review-a-approved','review-record',with_doc)
 approved=copy.deepcopy(good);approved['conditions'][0]['evidence_ids']=['review-a-approved']
 assert status(report([approved],ps=mandatory))=='VERIFIED_PASS'
 unproven=copy.deepcopy(good);unproven['applicability']={'status':'APPLICABLE'}
 assert status(report([unproven],ps=ps))=='UNRESOLVED', 'applicability needs evidence too'
 assert report([good],ps=ps)['summary']['reviewed_decisions']==1
 manual_app=copy.deepcopy(policy);manual_app['req-one']['applicability_verifiers']=[]
 hybrid=copy.deepcopy(decision);hybrid['applicability']=good['applicability']
 assert report([hybrid],ps=manual_app)['summary']['automatic_decisions']==0
 assert report([hybrid],ps=manual_app)['summary']['reviewed_decisions']==1
 partial=copy.deepcopy(good);partial['conditions'].pop();assert status(report([partial],ps=ps))=='UNRESOLVED'
 assert status(report([good,decision],ps=policy))=='VERIFIED_FINDING'
 assert status(report([good],es=evidence,ps=policy))=='VERIFIED_FINDING', 'contradictory evidence cannot be hidden by omitting its claim'
 add('review-na','review-record',review_record('applicability','NOT_APPLICABLE',['exc-one']))
 na={'obligation_id':'req-one','conditions':[],'applicability':{'status':'NOT_APPLICABLE','rationale':'Exception verified','source_ids':['exc-one'],'reviewer':'Synthetic reviewer','evidence_ids':['review-na']}}
 assert status(report([na]))=='NOT_APPLICABLE_VERIFIED'
 assert report([na])['summary']['verified_not_applicable']==1
 bad=copy.deepcopy(na);bad['applicability']['source_ids']=['unregistered-exception'];assert status(report([bad]))=='NOT_APPLICABLE_VERIFIED' and report([bad])['input_errors'] and not report([bad])['summary']['ready']
 assert status(report([na,decision]))=='VERIFIED_FINDING'
 # Invalid typed rows stay isolated, and errors block readiness even for unrelated rows.
 assert status(report([{'obligation_id':[]},decision]))=='VERIFIED_FINDING'
 malformed=copy.deepcopy(good);malformed['conditions'].append({'condition_id':[]});r=report([malformed],ps=ps);assert status(r)=='VERIFIED_PASS' and not r['summary']['ready']
 assert status(report([good,None],ps=ps))=='VERIFIED_PASS' and not report([good,None],ps=ps)['summary']['ready']
 # All required conditions remain visible; no missing criterion is silently removed.
 assert len(report()['obligations'][0]['conditions'])==2
 assert status(report([],ps={}))=='UNRESOLVED'
 # Duplicate identity is ambiguous and cannot hide a contradictory row.
 assert status(report(es=evidence+[copy.deepcopy(evidence[1])]))=='UNRESOLVED'
 os.environ['PRECHECK_DEMO_PASSWORD']='synthetic-password-private'
 assert 'synthetic-password-private' not in json.dumps(m.redact({'note':'synthetic-password-private','backend':'https://user:pass@example.test?token=hidden'}))
 assert 'user:pass' not in json.dumps(m.redact({'backend':'https://user:pass@example.test'}))
 # Actual CLI: all catalog obligations are emitted, malformed top-level exits 2.
 for name,value in [('profile',profile),('evidence',{'schema_version':1,'evidence':[]}),('decisions',{'schema_version':1,'decisions':[]})]:
  (base/(name+'.json')).write_text(json.dumps(value))
 args=['python3','-B','skills/appstore-precheck/scripts/verification-report.py','--profile',str(base/'profile.json'),'--evidence',str(base/'evidence.json'),'--decisions',str(base/'decisions.json'),'--out',str(base/'report.json'),'--markdown',str(base/'report.md')]
 assert subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.PIPE).returncode==1
 assert subprocess.run(['node','bin/cli.js','verify']+args[3:],stdout=subprocess.PIPE,stderr=subprocess.PIPE).returncode==1
 actual=json.loads((base/'report.json').read_text());cat=json.loads(Path('skills/appstore-precheck/references/guideline-obligations.json').read_text())
 assert actual['summary']['total_obligations']==sum(r['kind']=='obligation' for r in cat['obligations'])
 assert (base/'report.md').is_file()
 (base/'decisions.json').write_text('{}');assert subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.PIPE).returncode==2
 print('verification report: integrity, sufficiency, runtime quorum, isolation and spoofing regressions passed')
PY
