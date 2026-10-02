"""Offline behavioral tests: typed judgments, abstentions, transport, caches, packaging."""
import copy
import io
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
import urllib.error
from pathlib import Path
from unittest.mock import patch
from contextlib import redirect_stdout, redirect_stderr

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'skills/appstore-precheck/scripts'))
sys.path.insert(0, str(ROOT / 'eval/lib'))
sys.path.insert(0, str(ROOT / 'eval'))
from semantic.client import ServiceError, evaluate, validate_response
from semantic.engine import compose, request_for, run_job, validate_bundle, render_text
from semantic.collect import collect
from semantic.questions import WORKFLOWS
from catalog import CATALOG, BY_KEY, resolve, procedure_path, fingerprint
from build_request import build_system
from parse_verdict import parse_verdict
import score

EXAMPLE = json.loads((ROOT / 'skills/appstore-precheck/references/typesafe-example.json').read_text())


def job(workflow):
    return copy.deepcopy(next(j for j in EXAMPLE['jobs'] if j['workflow'] == workflow))


def response(request, choices=None, probabilities=None):
    """Synthetic API responses: never presented as a model-quality measurement."""
    choices, probabilities = choices or {}, probabilities or {}
    answers = {}
    for name, q in request['questions'].items():
        if q['type'] == 'noul':
            answers[name] = {'type': 'noul', 'noul': probabilities.get(name, .99)}
        elif q['type'] == 'choice':
            selected = choices.get(name, next(iter(q['criteria'])))
            values = {k: float(k == selected) for k in q['criteria']}
            answers[name] = {'type': 'choice', 'choice': selected, 'confidence': 1., 'probabilities': values}
        else:
            index = choices.get(name, len(q['criteria']) - 1)
            answers[name] = {'type': 'score', 'score': float(index), 'confidence': 1.,
                             'probabilities': {str(i): float(i == index) for i in range(len(q['criteria']))},
                             'legend': {str(i): s for i, s in enumerate(q['criteria'])}}
    return {'model': request['model'], 'answers': answers, 'usage': {'input_tokens': 1000, 'output_tokens': 20}}


class TypeSafeTests(unittest.TestCase):
    def test_every_workflow_executes_and_preserves_distributions(self):
        validate_bundle(EXAMPLE)
        self.assertEqual(set(WORKFLOWS), {j['workflow'] for j in EXAMPLE['jobs']})
        for j in EXAMPLE['jobs']:
            with self.subTest(workflow=j['workflow']):
                req = request_for(j)
                body = response(req)
                validate_response(body, req)
                result = run_job(j, live=True, call=lambda _: body)
                self.assertTrue(result['advisory'])
                self.assertEqual(result['judgments'], body['answers'])
                self.assertAlmostEqual(result['estimated_cost_usd'], .000042)

    def test_typed_review_and_missing_evidence(self):
        j = job('review'); req = request_for(j)
        body = response(req, {'outcome': 'finding'})
        self.assertEqual(compose(j, body)['outcome'], 'finding')
        body = response(req, {'outcome': 'pass'})
        self.assertEqual(compose(j, body)['outcome'], 'pass')
        j['coverage']['missing'] = ['unknown shipping target']
        self.assertEqual(compose(j, body)['outcome'], 'insufficient_evidence')
        self.assertEqual(run_job(j, live=True, call=lambda _: self.fail('must not call'))['billed_input_tokens'], 0)

    def test_uncertain_distribution_abstains(self):
        j = job('review'); req = request_for(j); body = response(req)
        a = body['answers']['outcome']
        a.update(confidence=.1, probabilities={'finding': .4, 'pass': .3, 'not_applicable': .1, 'insufficient_evidence': .2})
        validate_response(body, req)
        self.assertEqual(compose(j, body)['action'], 'pierre_review')

    def test_finding_requires_source_selection(self):
        j = job('review'); body = response(request_for(j), {'evidence': 'none'})
        self.assertEqual(compose(j, body)['outcome'], 'insufficient_evidence')

    def test_unused_trial_and_locale_questions_do_not_force_escalation(self):
        j = job('disclosure'); j['context']['product_terms']['trial'] = False
        j['context'].pop('locale_pair')
        body = response(request_for(j), {'locale_relation': 'unresolved'}, {'trial_charge': .5})
        self.assertEqual(compose(j, body)['outcome'], 'pass')
        body['answers']['cancellation']['noul'] = .01
        self.assertEqual(compose(j, body)['outcome'], 'finding')

    def test_reranking_preserves_all_and_falls_back(self):
        j = job('rerank'); body = response(request_for(j), {'candidate_0': 0, 'candidate_1': 3})
        result = compose(j, body)
        self.assertEqual([c['id'] for c in result['ranking']], ['screenshots', 'privacy'])
        body['answers']['candidate_0']['confidence'] = .1
        self.assertEqual([c['id'] for c in compose(j, body)['ranking']], ['privacy', 'screenshots'])

    def test_routing_and_drift_never_clear_findings(self):
        for workflow in ('routing', 'drift', 'functionality'):
            j = job(workflow); result = compose(j, response(request_for(j)))
            self.assertEqual(result['outcome'], 'insufficient_evidence')
            self.assertTrue(result['advisory'])
        j = job('routing'); result = compose(j, response(request_for(j), {'offering': 'physical'}))
        self.assertEqual(result['route'], 'physical_service_review')

    def test_quote_mismatch_does_not_need_model(self):
        j = job('verify'); j['context']['quote'] = 'fabricated quotation'
        result = run_job(j, live=True, call=lambda _: self.fail('must not call'))
        self.assertEqual(result['outcome'], 'finding')
        self.assertEqual(result['estimated_cost_usd'], 0)
        self.assertIsNone(result['model_confidence'])

    def test_corrupt_responses_never_pass(self):
        for corrupt in ('missing', 'nan', 'unknown', 'sum', 'model', 'negative_usage', 'choice'):
            j = job('review'); req = request_for(j); body = response(req)
            if corrupt == 'missing': body['answers'].pop('outcome')
            if corrupt == 'nan': body['answers']['outcome']['confidence'] = float('nan')
            if corrupt == 'unknown': body['answers']['outcome']['probabilities']['invented'] = 0
            if corrupt == 'sum': body['answers']['outcome']['probabilities']['pass'] = .4
            if corrupt == 'model': body['model'] = 'jev-latest'
            if corrupt == 'negative_usage': body['usage']['input_tokens'] = -1
            if corrupt == 'choice': body['answers']['outcome']['choice'] = 'pass'
            with self.subTest(corrupt=corrupt):
                with self.assertRaises(ServiceError): validate_response(body, req)
                self.assertEqual(run_job(j, live=True, call=lambda _: body)['action'], 'pierre_review')
        j = job('purpose'); req = request_for(j); body = response(req)
        body['answers']['specificity']['score'] = 1.5
        with self.assertRaises(ServiceError): validate_response(body, req)

    def test_cache_is_bound_to_evidence_model_and_questions(self):
        j = job('review'); calls = []
        def api(req): calls.append(req); return response(req)
        with tempfile.TemporaryDirectory() as directory:
            first = run_job(j, live=True, cache_dir=directory, call=api)
            second = run_job(j, cache_dir=directory, call=api)
            self.assertEqual(len(calls), 1)
            self.assertTrue(second['cached'])
            self.assertEqual(second['billed_input_tokens'], 0)
            self.assertEqual(first['outcome'], second['outcome'])
            cache = next(Path(directory).glob('*.json'))
            self.assertEqual(cache.stat().st_mode & 0o777, 0o600)
            j['evidence'][0]['text'] += ' Changed.'
            self.assertEqual(run_job(j, cache_dir=directory)['action'], 'pierre_review')
            j = job('review'); cache.write_text('{broken')
            self.assertEqual(run_job(j, cache_dir=directory)['action'], 'pierre_review')

    @patch.dict(os.environ, {'TYPESAFE_API_KEY': 'never-print-this-key'})
    def test_http_contract_bounded_retries_and_secret_safe_errors(self):
        request = request_for(job('review')); calls, delays = [], []
        def open_mock(req, timeout):
            calls.append(req)
            self.assertEqual(req.full_url, 'https://api.typesafe.ai/v1/systemone')
            self.assertEqual(req.headers['Authorization'], 'Bearer never-print-this-key')
            if len(calls) < 3:
                raise urllib.error.HTTPError(req.full_url, 429, 'secret body', {'Retry-After': '600'}, None)
            return io.BytesIO(json.dumps(response(request)).encode())
        transport = {}
        evaluate(request, opener=open_mock, sleep=delays.append, telemetry=transport)
        self.assertEqual(transport['attempts'], 3)
        self.assertEqual(delays, [5, 5])
        def unauthorized(req, timeout):
            raise urllib.error.HTTPError(req.full_url, 401, 'never-print-this-key', {}, None)
        with self.assertRaisesRegex(ServiceError, '^TypeSafe HTTP 401$'):
            evaluate(request, opener=unauthorized)

    @patch.dict(os.environ, {'TYPESAFE_API_KEY': 'synthetic-test-only'})
    def test_retry_telemetry_success_failure_and_cache(self):
        j = job('review'); request = request_for(j)
        class Opener:
            def __init__(self, always_fail=False):
                self.calls = 0
                self.always_fail = always_fail
            def open(self, req, timeout):
                self.calls += 1
                if self.always_fail or self.calls == 1:
                    raise urllib.error.HTTPError(req.full_url, 429, 'retry', {'Retry-After': '0'}, None)
                return io.BytesIO(json.dumps(response(request)).encode())
        with tempfile.TemporaryDirectory() as directory:
            transport = Opener()
            with patch('semantic.client.urllib.request.build_opener', return_value=transport):
                result = run_job(j, live=True, cache_dir=directory)
            self.assertEqual(result['transport_attempts'], 2)
            self.assertEqual(result['retry_count'], 1)
            self.assertTrue(result['retry_billing_unknown'])
            self.assertEqual(result['billed_input_tokens'], 1000)
            cached = run_job(j, cache_dir=directory)
            self.assertTrue(cached['cached'])
            self.assertEqual(cached['transport_attempts'], 0)
            self.assertFalse(cached['retry_billing_unknown'])
        with patch('semantic.client.urllib.request.build_opener', return_value=Opener(True)):
            failed = run_job(j, live=True)
        self.assertEqual(failed['transport_attempts'], 3)
        self.assertEqual(failed['retry_count'], 2)
        self.assertIsNone(failed['estimated_cost_usd'])
        self.assertTrue(failed['retry_billing_unknown'])
        self.assertEqual(failed['action'], 'pierre_review')

    def test_no_request_paths_have_zero_transport_attempts(self):
        incomplete = job('review'); incomplete['coverage']['complete'] = False
        mismatch = job('verify'); mismatch['context']['quote'] = 'absent fabricated quote'
        with patch.dict(os.environ, {}, clear=True):
            results = [run_job(incomplete, live=True), run_job(mismatch, live=True),
                       run_job(job('review')), run_job(job('review'), live=True)]
        for result in results:
            self.assertEqual(result['transport_attempts'], 0)
            self.assertEqual(result['retry_count'], 0)
            self.assertFalse(result['retry_billing_unknown'])
            self.assertFalse(result['request_attempted'])

    def test_catalog_versions_preserve_historical_guidelines_and_procedures(self):
        historical = {'check_id': 6, 'catalog_version': 2}
        current = {'check_id': 6, 'catalog_version': 3}
        self.assertEqual(resolve(historical)['guideline'], '2.3.2')
        self.assertEqual(resolve({'check_id': 6})['guideline'], '2.3.2')
        self.assertEqual(resolve(current)['guideline'], '2.3.5')
        self.assertIn('### 6 — 2.3.2 Category fit', procedure_path(historical).read_text())
        self.assertIn('### 6 — 2.3.5 Category fit', procedure_path(current).read_text())
        self.assertIn('### 8 — 2.3.5 Screenshots', procedure_path(historical).read_text())
        self.assertIn('### 8 — 2.3.3 Screenshots', procedure_path(current).read_text())
        for version in (1, CATALOG['version'] + 1, '3', True, 3.0, None):
            with self.assertRaises(ValueError):
                resolve({'check_id': 6, 'catalog_version': version})
        with tempfile.TemporaryDirectory() as directory:
            reviews = [j for j in collect(Path(directory))['jobs'] if j['workflow'] == 'review']
        self.assertEqual(len(reviews), len(CATALOG['checks']))
        self.assertTrue(all(j['catalog_version'] == CATALOG['version'] for j in reviews))

    def test_collector_limits_and_skips_credentials_and_symlinks(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'App.swift').write_text('let api_key = "secret-value"\n// password: secret-password\n')
            (root / '.env').write_text('SECRET=not-readable')
            (root / 'outside.swift').symlink_to('/etc/passwd')
            (root / 'Huge.swift').write_text('x' * 70_000)
            bundle = collect(root); validate_bundle(bundle)
            self.assertGreaterEqual(len(bundle['jobs']), 31)
            serialized = json.dumps(bundle)
            self.assertNotIn('secret-value', serialized)
            self.assertNotIn('secret-password', serialized)
            self.assertNotIn('not-readable', serialized)
            self.assertNotIn('root:', serialized)
            self.assertFalse(bundle['jobs'][0]['coverage']['complete'])

    def test_stable_catalog_and_historical_labels(self):
        self.assertEqual(BY_KEY['rating-manipulation']['number'], 29)
        case = json.loads((ROOT / 'eval/dataset/cases/check28-clean-system-prompt.json').read_text())
        self.assertEqual(resolve(case)['key'], 'rating-manipulation')
        legacy = json.loads((ROOT / 'eval/baseline/cases-v1.json').read_text())
        self.assertEqual(next(c for c in legacy if c['id'] == case['id'])['check_id'], 28)
        self.assertEqual(len(BY_KEY), len(CATALOG['checks']))

    def test_v3_statuses_are_abstentions_and_explicit_nonapplicability(self):
        for status in ('NEEDS-REVIEW', 'UNSUPPORTED', 'NOT-RUN'):
            raw = {'content': [{'type': 'text', 'text': 'REVIEW-' + status + ': 2.3 — evidence unavailable'}]}
            self.assertEqual(parse_verdict(raw)['verdict'], 'insufficient_evidence')
        raw = {'content': [{'type': 'text', 'text': 'REVIEW-NOT-APPLICABLE: 1.2 — verified scope excludes UGC'}]}
        self.assertEqual(parse_verdict(raw)['verdict'], 'not-applicable')
        current = procedure_path({'check_id': 6, 'catalog_version': 3}).read_text()
        prompt = build_system(current, 3)
        self.assertIn('REVIEW-NEEDS-REVIEW', prompt)
        self.assertNotIn('exactly one REVIEW-PASS: or REVIEW-FINDING:', prompt)
        before = fingerprint()
        original = Path.read_text
        def changed(path, *args, **kwargs):
            text = original(path, *args, **kwargs)
            return text + ' changed' if path.name == 'pierre-deep-review-v2.md' else text
        with patch.object(Path, 'read_text', changed):
            self.assertNotEqual(fingerprint(), before)

    def test_abstentions_are_not_true_negatives_and_count_in_coverage(self):
        samples = [{'predicted': 'insufficient_evidence', 'expected': 'pass'},
                   {'predicted': 'unparseable', 'expected': 'finding'},
                   {'predicted': 'pass', 'expected': 'pass'}]
        self.assertEqual(score.confusion(samples), (0, 0, 0, 1))
        self.assertEqual(parse_verdict({'provider': 'typesafe', 'result': {'outcome': 'insufficient_evidence'}})['verdict'], 'insufficient_evidence')
        self.assertEqual(score.majority(['finding', 'finding', 'pass', 'not-applicable', 'unparseable']), ('no-majority', False))

    @patch.dict(os.environ, {'TYPESAFE_API_KEY': 'synthetic-test-only'})
    def test_eval_runner_repeats_resume_telemetry_and_failure_recovery(self):
        spec = importlib.util.spec_from_file_location('typesafe_eval_runner', ROOT / 'eval/typesafe/run.py')
        runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)
        calls = []
        def api(req):
            calls.append(req)
            return response(req, {'outcome': 'pass'})
        def invoke(j, model, live):
            return run_job(j, model, live, call=api)
        with tempfile.TemporaryDirectory() as directory, redirect_stdout(io.StringIO()):
            args = ['--out', directory, '--cases', 'check18-specific-purpose-strings', '--repeat', '3']
            with patch.object(runner, 'run_job', side_effect=invoke):
                self.assertEqual(runner.main(args), 0)
                self.assertEqual(len(calls), 3)
                self.assertEqual(runner.main(args), 0)
                self.assertEqual(len(calls), 3)  # resume, not a fake fresh consistency measurement
                result_path = Path(directory) / 'check18-specific-purpose-strings/rep2.json'
                result_path.write_text(json.dumps({'provider': 'typesafe', 'result': {'outcome': 'insufficient_evidence'}}))
                self.assertEqual(runner.main(args), 0)
                self.assertEqual(len(calls), 4)
            stats = score.run_stats(Path(directory), score.DEFAULT_DATASET)
            self.assertEqual(len(stats['scored']), 1)  # case snapshot, not the whole current dataset
            self.assertEqual(stats['coverage'], 1)
            telemetry = '\n'.join(score.telemetry(Path(directory), stats['results']))
            self.assertIn('Brier score: 0.0000', telemetry)
            self.assertIn('$0.000126', telemetry)
            with redirect_stderr(io.StringIO()):
                self.assertEqual(runner.main(args[:-1] + ['1']), 1)

    def test_malformed_bundle_returns_usage_error_without_traceback(self):
        cli = [sys.executable, '-B', str(ROOT / 'skills/appstore-precheck/scripts/semantic-review.py')]
        with tempfile.TemporaryDirectory() as directory:
            bad = Path(directory) / 'bad.json'
            malformed = job('purpose'); malformed['id'] = None
            bad.write_text(json.dumps({'version': 1, 'jobs': [malformed]}))
            result = subprocess.run(cli + ['--bundle', str(bad), '--live'], capture_output=True, text=True)
            self.assertEqual(result.returncode, 64)
            self.assertNotIn('Traceback', result.stderr)

    def test_cli_dry_run_and_gate_isolation(self):
        cli = [sys.executable, '-B', str(ROOT / 'skills/appstore-precheck/scripts/semantic-review.py')]
        result = subprocess.run(cli + ['--bundle', str(ROOT / 'skills/appstore-precheck/references/typesafe-example.json'), '--dry-run'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(json.loads(result.stdout)['requests']), 10)
        j = job('review'); r = compose(j, response(request_for(j)))
        r['evidence'][0]['path'] = 'x\nFAIL: injected'
        line = render_text(r)
        self.assertEqual(len(line.splitlines()), 1)
        verdict = subprocess.run(['bash', str(ROOT / 'skills/appstore-precheck/scripts/verdict.sh')], input=line, capture_output=True, text=True)
        self.assertIn('VERDICT: GREEN', verdict.stdout)


if __name__ == '__main__':
    unittest.main()
