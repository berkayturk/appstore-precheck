"""Evidence bundles, conservative composition, reproducible caches, advisory output."""
import hashlib
import json
import os
import re
import tempfile
import time
from pathlib import Path

from .review_v4 import is_v4, evidence_gaps, compose_host_review
from .client import ServiceError, evaluate, validate_response
from .questions import MODEL, PRICE_PER_MILLION, VERSION, WORKFLOWS, questions_for

THRESHOLDS = {'positive': 0.90, 'negative': 0.10, 'support': 0.95, 'confidence': 0.50}
ID = re.compile(r'^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,100}$')
MAX_REQUEST_BYTES = 160_000


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False,
                                     allow_nan=False).encode()).hexdigest()


def validate_bundle(bundle):
    if not isinstance(bundle, dict) or bundle.get('version') != 1 or not isinstance(bundle.get('jobs'), list):
        raise ValueError('expected bundle version 1 with jobs array')
    if not 1 <= len(bundle['jobs']) <= 128:
        raise ValueError('bundle needs 1..128 jobs')
    seen = set()
    for job in bundle['jobs']:
        if (not isinstance(job, dict) or not isinstance(job.get('id'), str)
                or not ID.fullmatch(job['id']) or job['id'] in seen):
            raise ValueError('job IDs must be unique safe identifiers')
        seen.add(job['id'])
        if job.get('workflow') not in WORKFLOWS or not isinstance(job.get('context'), dict):
            raise ValueError('unknown workflow or missing context')
        missing = [k for k in WORKFLOWS[job['workflow']]['required'] if k not in job['context']]
        if missing:
            raise ValueError('missing context fields: ' + ', '.join(missing))
        if any(job['context'][k] is None for k in WORKFLOWS[job['workflow']]['required']):
            raise ValueError('required context fields cannot be null')
        for key in ('text', 'locale', 'ui_role', 'flow_stage', 'permission_key', 'claim',
                    'comparison_kind', 'source_id', 'evidence_class', 'build_config', 'quote'):
            if key in job['context'] and not isinstance(job['context'][key], str):
                raise ValueError('context.' + key + ' must be text')
        coverage = job.get('coverage', {})
        if (not isinstance(coverage, dict) or type(coverage.get('complete')) is not bool
                or not isinstance(coverage.get('missing'), list)
                or not all(isinstance(x, str) for x in coverage['missing'])):
            raise ValueError('coverage requires complete boolean and missing array')
        evidence = job.get('evidence')
        if not isinstance(evidence, list) or len(evidence) > 64:
            raise ValueError('evidence must be an array of at most 64 spans')
        ids = set()
        for e in evidence:
            if (not isinstance(e, dict) or not isinstance(e.get('id'), str) or not ID.fullmatch(e['id'])
                    or e['id'] in ids or e['id'] == 'none'
                    or not isinstance(e.get('path'), str) or not e['path'].strip()
                    or type(e.get('line')) is not int or e['line'] < 1
                    or not isinstance(e.get('text'), str) or not e['text'].strip()):
                raise ValueError('invalid evidence span')
            ids.add(e['id'])
        validate_workflow_context(job, ids)
    return bundle


def validate_workflow_context(job, ids):
    context = job['context']
    if job['workflow'] == 'rerank':
        candidates = context['candidates']
        if (not isinstance(candidates, list) or not 1 <= len(candidates) <= 32
                or any(not isinstance(c, dict) or not isinstance(c.get('id'), str)
                       or not isinstance(c.get('text'), str) or not c['text'].strip() for c in candidates)
                or len({c['id'] for c in candidates}) != len(candidates)):
            raise ValueError('rerank needs 1..32 unique text candidates')
    if job['workflow'] == 'drift':
        if not isinstance(context['rule_catalog'], list) or len(context['rule_catalog']) > 64:
            raise ValueError('drift rule_catalog must be an array of at most 64 entries')
    if job['workflow'] == 'verify' and context['source_id'] not in ids:
        raise ValueError('verification source_id is not a supplied evidence ID')
    if job['workflow'] == 'disclosure':
        terms = context['product_terms']
        if not isinstance(terms, dict) or type(terms.get('trial')) is not bool:
            raise ValueError('product_terms.trial must be a boolean')


def request_for(job, model=MODEL):
    if not re.fullmatch(r'jev-\d+\.\d+\.\d+', model):
        raise ValueError('pin a versioned Jev model, e.g. jev-1.13.0')
    state = {k: job[k] for k in ('context', 'coverage', 'evidence')}
    request = {'model': model, 'state': state, 'questions': questions_for(job)}
    if len(json.dumps(request, ensure_ascii=False).encode()) > MAX_REQUEST_BYTES:
        raise ValueError('request exceeds 160 KB; split evidence into bounded jobs')
    return request


def fallback(job, reason):
    definition = job['context'].get('check_definition', {})
    return {'id': job['id'], 'workflow': job['workflow'], 'advisory': True,
            'check_key': job.get('check_key'),
            'guideline': definition.get('guideline') if isinstance(definition, dict) else None,
            'catalog_version': 4 if is_v4(job) else job.get('catalog_version'),
            'advisory_only': is_v4(job),
            'outcome': 'insufficient_evidence', 'action': 'pierre_review', 'reason': reason,
            'evidence': [], 'model_probability': None, 'model_confidence': None}


def categorical(answers, result, key):
    answer = answers[key]
    probability = answer['probabilities'][answer['choice']]
    result['model_probability'] = probability
    result['model_confidence'] = answer['confidence']
    return answer['choice'] if probability >= THRESHOLDS['positive'] and answer['confidence'] >= THRESHOLDS['confidence'] else None


def binary(answers, keys, positive=True):
    values = [answers[k]['noul'] for k in keys]
    if positive:
        return 'finding' if any(v >= THRESHOLDS['positive'] for v in values) else (
            'pass' if all(v <= THRESHOLDS['negative'] for v in values) else None)
    return 'finding' if any(v <= THRESHOLDS['negative'] for v in values) else (
        'pass' if all(v >= THRESHOLDS['support'] for v in values) else None)


def disclosure_outcome(job, answers, result):
    keys = ['renewal', 'cancellation']
    if job['context']['product_terms']['trial']:
        keys.append('trial_charge')
    outcome = binary(answers, keys, positive=False)
    if job['context'].get('locale_pair'):
        relation = categorical(answers, result, 'locale_relation')
        if relation in ('omission', 'contradiction'):
            outcome = 'finding'
        elif relation != 'equivalent' and outcome != 'finding':
            outcome = None
    return outcome


def simple_outcome(job, answers, result):
    workflow = job['workflow']
    if workflow == 'review':
        return categorical(answers, result, 'outcome')
    if workflow == 'copy':
        return binary(answers, [k for k in answers if k != 'evidence'])
    if workflow == 'purpose':
        poor = sum(answers['specificity']['probabilities'][str(i)] for i in (0, 1))
        match = answers['feature_match']['noul']
        return 'finding' if poor >= .90 or match <= .10 else ('pass' if poor <= .10 and match >= .95 else None)
    if workflow == 'disclosure':
        return disclosure_outcome(job, answers, result)
    if workflow == 'consistency':
        return {'supported': 'pass', 'contradicted': 'finding'}.get(categorical(answers, result, 'relation'))
    if workflow == 'verify':
        source = next(e for e in job['evidence'] if e['id'] == job['context']['source_id'])
        result['evidence'] = [source]
        supported, over = answers['supported']['noul'], answers['overstatement']['noul']
        return 'finding' if supported <= .10 or over >= .90 else ('pass' if supported >= .95 and over <= .10 else None)
    return None


def descriptive_result(job, answers, result):
    workflow = job['workflow']
    if workflow == 'routing':
        offering = categorical(answers, result, 'offering')
        result['route'] = {'digital': 'digital_purchase_review', 'physical': 'physical_service_review',
                           'mixed': 'combined_purchase_review'}.get(offering, 'pierre_review')
        result['reason'] = 'routing hint only; exemption and account signals never waive a finding'
        result['action'] = result['route']
    elif workflow == 'rerank':
        candidates = job['context']['candidates']
        ranked = [{**c, 'model_score': answers['candidate_%d' % i]['score'],
                   'model_confidence': answers['candidate_%d' % i]['confidence']}
                  for i, c in enumerate(candidates)]
        confident = all(c['model_confidence'] >= THRESHOLDS['confidence'] for c in ranked)
        result['ranking'] = sorted(ranked, key=lambda c: -c['model_score']) if confident else ranked
        result['action'] = 'ranked' if confident else 'original_order'
        result['reason'] = 'ranking only; all candidate sections retained'
    elif workflow == 'drift':
        change = categorical(answers, result, 'change')
        result['affected_rules'] = [r for i, r in enumerate(job['context']['rule_catalog'])
                                    if answers['affected_%d' % i]['noul'] >= .10]
        result['change_type'] = change or 'unclear'
        result['reason'] = 'human reconciliation required; deterministic drift warning retained'
    elif workflow == 'functionality':
        result['functional_completeness_score'] = answers['completeness']['score']
        result['category'] = categorical(answers, result, 'category') or 'unknown'
        result['reason'] = 'functional evidence for Pierre; not a compliance or rejection score'
    else:
        return False
    return True


def compose(job, body):
    """Thresholds are experimental; conclusions never resolve scanner findings."""
    if is_v4(job):
        return compose_host_review(job, body, text_only=True)
    result = fallback(job, 'uncertain judgment')
    answers = body['answers']
    result.update(judgments=answers, model=body['model'], usage=body['usage'])
    if not job['coverage']['complete'] or job['coverage']['missing']:
        result['reason'] = 'incomplete evidence coverage'
        return result
    evidence_answer = answers.get('evidence')
    if evidence_answer and evidence_answer['choice'] != 'none':
        selected = evidence_answer['choice']
        if evidence_answer['probabilities'][selected] >= THRESHOLDS['positive']:
            result['evidence'] = [e for e in job['evidence'] if e['id'] == selected]
    if descriptive_result(job, answers, result):
        return result
    outcome = simple_outcome(job, answers, result)
    if outcome and outcome != 'insufficient_evidence':
        if outcome == 'finding' and not result['evidence']:
            result['reason'] = 'concern has no confidently selected evidence span'
        else:
            result.update(outcome=outcome, action='advisory_finding' if outcome == 'finding' else 'advisory_result',
                          reason='bounded semantic judgment; does not change scanner verdict')
    return result


def atomic_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(dir=str(path.parent), prefix='.typesafe-')
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as stream:
            json.dump(value, stream, ensure_ascii=False, indent=2, allow_nan=False)
            stream.write('\n')
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def preflight_result(job, key):
    gaps = evidence_gaps(job)
    result = None
    if gaps or not job['coverage']['complete'] or job['coverage']['missing']:
        result = fallback(job, '; '.join(gaps) if gaps else 'incomplete evidence coverage; complete the bundle or continue with Pierre')
    context = job['context']
    if result is None and job['workflow'] == 'verify' and context.get('quote'):
        source = next(e for e in job['evidence'] if e['id'] == context['source_id'])
        if ' '.join(context['quote'].split()) not in ' '.join(source['text'].split()):
            result = fallback(job, 'quoted text is absent from the cited source; use original finding template')
            result.update(outcome='finding', action='advisory_finding', evidence=[source])
    if result is not None:
        result.update(cached=False, request_sha256=key, latency_ms=0, estimated_cost_usd=0,
                      billed_input_tokens=0, request_attempted=False, transport_attempts=0,
                      retry_count=0, retry_billing_unknown=False)
    return result


def load_response(path, key, request):
    if path and path.is_file():
        try:
            record = json.loads(path.read_text(encoding='utf-8'))
            if record['request_sha256'] != key or record['request'] != request:
                raise ServiceError('cache request mismatch')
            return validate_response(record['response'], request)
        except (OSError, ValueError, KeyError, ServiceError):
            pass  # Bad cache is never trusted as a result.
    return None


def get_response(request, path, key, live, call, transport, state):
    body = load_response(path, key, request)
    state['cached'] = body is not None
    if body is not None:
        return body
    if not live:
        raise ServiceError('no valid cached result; live inference not enabled')
    if call is evaluate and not os.environ.get('TYPESAFE_API_KEY'):
        raise ServiceError('TYPESAFE_API_KEY is not set')
    state['attempted'] = True
    body = validate_response(call(request, telemetry=transport) if call is evaluate else call(request), request)
    if path:
        try:
            atomic_json(path, {'request_sha256': key, 'request': request, 'response': body})
        except OSError:
            pass  # A cache failure never discards a valid answer.
    return body


def run_job(job, model=MODEL, live=False, cache_dir=None, call=evaluate):
    request = request_for(job, model)
    key = digest({'request': request, 'questions_version': VERSION, 'thresholds': THRESHOLDS})
    path = Path(cache_dir) / (key + '.json') if cache_dir else None
    started = time.monotonic()
    early = preflight_result(job, key)
    if early is not None:
        return early
    transport, state = {'attempts': 0}, {'attempted': False, 'cached': False}
    try:
        body = get_response(request, path, key, live, call, transport, state)
        result = compose(job, body)
        result.update(response=body, cached=state['cached'], request_attempted=state['attempted'])
        result['billed_input_tokens'] = 0 if state['cached'] else body['usage']['input_tokens']
        result['estimated_cost_usd'] = result['billed_input_tokens'] * PRICE_PER_MILLION / 1_000_000
    except ServiceError as exc:
        result = fallback(job, str(exc))
        result.update(cached=False, estimated_cost_usd=None if state['attempted'] else 0,
                      billed_input_tokens=None if state['attempted'] else 0, request_attempted=state['attempted'])
    result['transport_attempts'] = transport['attempts'] if call is evaluate else (1 if result.get('request_attempted') else 0)
    result['retry_count'] = max(0, result['transport_attempts'] - 1)
    result['retry_billing_unknown'] = result['retry_count'] > 0
    result['request_sha256'] = key
    result['latency_ms'] = round((time.monotonic() - started) * 1000, 3)
    return result


def render_text(result):
    # Never echo untrusted source text at column zero: verdict.sh consumes line prefixes.
    pointer = ', '.join('%s:%s' % (e['path'], e['line']) for e in result['evidence'])
    message = ' '.join(('%s — %s %s' % (result['id'], result['reason'], pointer)).split())
    guideline = ' '.join(str(result.get('guideline') or 'semantic/' + result['workflow']).split())
    if result.get('advisory_only') and result['outcome'] in ('insufficient_evidence', 'no_signal'):
        label = 'REVIEW-SKIP' if result['outcome'] == 'insufficient_evidence' else 'REVIEW-NO-SIGNAL'
        return label + ': ' + guideline + ' — ' + message
    if result['outcome'] in ('pass', 'not_applicable'):
        return 'REVIEW-PASS: ' + guideline + ' — ' + message + (' — not applicable' if result['outcome'] == 'not_applicable' else '')
    return 'REVIEW-FINDING: ' + guideline + ' WARN — ' + message
