"""Offline catalog, evidence-gate and advisory composition tests; no model-quality claim."""
import copy
import json
import re
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'skills/appstore-precheck/scripts'))
from semantic.questions import questions_for
from semantic.engine import run_job, compose, render_text, request_for
from semantic.collect import collect
from semantic.review_v4 import evidence_gaps, compose_host_review
CATALOG = json.loads((ROOT / 'skills/appstore-precheck/references/review-catalog.json').read_text())
CHECKS = [check for check in CATALOG['checks'] if check['number'] >= 32]
CASES = json.loads((ROOT / 'corpus/synthetic/semantic-v4/cases.json').read_text())['cases']


def make_job(check, case):
    return {'id': check['key'], 'workflow': 'review', 'check_key': check['key'], 'catalog_version': 4,
            'context': {'check_definition': check, **{key: 'Supplied fixture context for '+key for key in check['required_context']}},
            'coverage': {'complete': True, 'missing': []},
            'evidence': [{'id': 'e'+str(i), 'path': 'fixtures/'+kind, 'line': 1, 'text': case['text'],
                          'kind': kind, 'representation': 'host visual observation' if kind in ('screenshots','icon') else 'fixture'}
                         for i,kind in enumerate(check['evidence_inputs'])]}


def body(job, outcome):
    questions = questions_for(job)
    answers = {}
    for key,q in questions.items():
        selected = outcome if key == 'outcome' else 'e0'
        answers[key] = {'choice': selected, 'confidence': 1., 'type': 'choice',
                        'probabilities': {value: float(value == selected) for value in q['criteria']}}
    return {'answers': answers, 'model': 'jev-1.13.0', 'usage': {'input_tokens': 100, 'output_tokens': 10}}


class SemanticV4Tests(unittest.TestCase):
    def test_catalog_and_procedure_contract(self):
        prose=(ROOT/'skills/appstore-precheck/references/pierre-deep-review.md').read_text()
        self.assertEqual(len({case['case_id'] for case in CASES}),75)
        for check in CHECKS:
            self.assertIn(check['tier'],('B','C'))
            self.assertEqual(check['requires_vision'],check['tier']=='C')
            self.assertTrue(check['abstain_when'])
            self.assertTrue(check['question'].endswith('?'))
            self.assertEqual({case['expected'] for case in CASES if case['check_key']==check['key']},
                             {'finding','no_signal','insufficient_evidence'})
            procedure=re.search(r'^### %d — .*?(?=^### |^---$)'%check['number'],prose,re.M|re.S)
            self.assertIsNotNone(procedure)
            self.assertLessEqual(len(procedure[0].strip().splitlines()),8)

    def test_each_rule_prompt_shape_trigger_clean_and_abstain(self):
        self.assertEqual(len(CHECKS),25)
        self.assertEqual([c['number'] for c in CHECKS],list(range(32,57)))
        for check in CHECKS:
            for case in [c for c in CASES if c['check_key']==check['key']]:
                with self.subTest(rule=check['key'],case=case['expected']):
                    job=make_job(check,case); request=request_for(job); q=request['questions']['outcome']
                    self.assertIn(case['text'], [e['text'] for e in request['state']['evidence']])
                    self.assertEqual(request['state']['context']['check_definition']['question'],check['question'])
                    self.assertNotIn('pass',q['criteria']); self.assertIn('no_signal',q['criteria'])
                    self.assertIn(check['question'],q['instructions'])
                    self.assertIn('abstain',q['instructions'].lower())
                    if case['expected']=='insufficient_evidence':
                        job['evidence']=[]
                    result=compose_host_review(job,body(job,case['expected']))
                    self.assertEqual(result['outcome'],case['expected'])
                    self.assertTrue(result['advisory']); self.assertNotIn('REVIEW-PASS:',render_text(result))
                    if case['expected']=='insufficient_evidence':
                        self.assertTrue(render_text(result).startswith('REVIEW-SKIP:'))
                    if case['expected']=='no_signal':
                        self.assertTrue(render_text(result).startswith('REVIEW-NO-SIGNAL:'))

    def test_each_missing_input_or_context_abstains_without_call(self):
        for check in CHECKS:
            clean=next(c for c in CASES if c['check_key']==check['key'] and c['expected']=='no_signal')
            for kind in check['evidence_inputs']:
                with self.subTest(rule=check['key'],missing=kind):
                    job=make_job(check,clean); job['evidence']=[e for e in job['evidence'] if e['kind']!=kind]
                    self.assertTrue(evidence_gaps(job,text_only=False))
                    result=run_job(job,live=True,call=lambda _: self.fail('missing evidence sent to service'))
                    self.assertEqual(result['outcome'],'insufficient_evidence')
            for key in check['required_context']:
                job=make_job(check,clean); job['context'][key]='unknown'
                self.assertTrue(evidence_gaps(job,text_only=False))
                self.assertEqual(compose_host_review(job,body(job,'finding'))['outcome'],'insufficient_evidence')
                result=run_job(job,live=True,call=lambda _: self.fail('missing required context sent to service'))
                self.assertEqual(result['outcome'],'insufficient_evidence')
                self.assertFalse(result['request_attempted'])

    def test_text_only_cannot_claim_vision_and_finding_needs_citation(self):
        for check in CHECKS:
            case=next(c for c in CASES if c['check_key']==check['key'])
            job=make_job(check,case)
            if check['requires_vision']:
                result=run_job(job,live=True,call=lambda _: self.fail('vision sent to text-only service'))
                self.assertEqual(result['outcome'],'insufficient_evidence')
                self.assertEqual(compose(job,body(job,'finding'))['outcome'],'insufficient_evidence')
            answer=body(job,'finding'); answer['answers']['evidence']['choice']='none'
            answer['answers']['evidence']['probabilities']={'none':1.}
            self.assertEqual(compose_host_review(job,answer)['outcome'],'insufficient_evidence')

    def test_b_rules_execute_through_typed_transport_without_pass(self):
        for check in CHECKS:
            if check['requires_vision']:
                continue
            for outcome in ('finding','no_signal'):
                case=next(c for c in CASES if c['check_key']==check['key'] and c['expected']==outcome)
                job=make_job(check,case)
                def transport(request):
                    self.assertIn(case['text'], [e['text'] for e in request['state']['evidence']])
                    self.assertIn(check['question'],request['questions']['outcome']['instructions'])
                    return body(job,outcome)
                result=run_job(job,live=True,call=transport)
                self.assertEqual(result['outcome'],outcome)
                self.assertTrue(result['request_attempted'])
                self.assertNotIn('REVIEW-PASS:',render_text(result))

    def test_old_catalog_checks_preserve_their_renderer(self):
        old=copy.deepcopy(CATALOG['checks'][0])
        job={'id':old['key'],'workflow':'review','catalog_version':4,
             'context':{'check_definition':old},'coverage':{'complete':False,'missing':['missing']},'evidence':[]}
        self.assertTrue(render_text(run_job(job)).startswith('REVIEW-FINDING:'))

    def test_deep53_has_collectible_string_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            (root/'Store.swift').write_text('let purchase = "Camera access"')
            (root/'Store.xcstrings').write_text(json.dumps({'sourceLanguage':'en','strings':{'Camera access':{}}}))
            job=next(job for job in collect(root)['jobs'] if job.get('check_key')=='monetize-builtin-capability')
            self.assertIn('source-strings',job['context']['check_definition']['evidence_inputs'])
            self.assertTrue(any('source-strings' in e['evidence_inputs'] for e in job['evidence']))
            self.assertFalse(any('missing evidence input:' in gap for gap in job['coverage']['missing']))
            self.assertIn('unknown required context: paid_feature',job['coverage']['missing'])

    def test_collector_enforces_types_without_fabricating_metadata(self):
        with tempfile.TemporaryDirectory() as directory, tempfile.TemporaryDirectory() as refs:
            root=Path(directory); (root/'App.swift').write_text('let title = "Local app"')
            ref=Path(refs); ref.joinpath('review-catalog.json').write_text(json.dumps({'version':4,'checks':CHECKS}))
            ref.joinpath('pierre-deep-review.md').write_text('')
            with patch('semantic.collect.REFERENCES',ref): jobs=collect(root)['jobs']
            for job in jobs:
                self.assertFalse(job['coverage']['complete'])
                self.assertTrue(job['coverage']['missing'])
                self.assertFalse(any(e['kind']=='metadata' for e in job['evidence']))


if __name__=='__main__': unittest.main()
