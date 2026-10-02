"""Executable v4 advisory gates, including a separate host-vision composition boundary."""
UNKNOWN = {'', 'unknown', 'unverified', 'unspecified', 'missing', 'not supplied'}
# Explicit host-provided kinds require direct visual observation; the local collector cannot supply them.
HOST_INPUT_KINDS = {'screenshots', 'runtime-screenshots', 'icon'}
VISUAL = HOST_INPUT_KINDS
OUTCOMES = {
    'finding': 'The supplied evidence establishes a concrete concern under this bounded question.',
    'no_signal': 'The reviewed evidence contains no concrete concern; this is not a compliance pass.',
    'insufficient_evidence': 'Required inputs, context, applicability, or observations are missing or conflicting.',
}


def is_v4(job):
    check = job.get('context', {}).get('check_definition', {})
    return job.get('workflow') == 'review' and isinstance(check, dict) and 'evidence_inputs' in check


def known(value):
    return value is not None and value is not False and str(value).strip().lower() not in UNKNOWN


def evidence_gaps(job, text_only=True):
    if not is_v4(job):
        return []
    check, context = job['context']['check_definition'], job['context']
    evidence = job.get('evidence', [])
    kinds = {kind for e in evidence if e.get('text', '').strip()
             for kind in e.get('evidence_inputs', [e.get('kind')])}
    gaps = ['missing evidence input: ' + kind for kind in check['evidence_inputs'] if kind not in kinds]
    gaps += ['unknown required context: ' + key for key in check.get('required_context', [])
             if not known(context.get(key))]
    if check['requires_vision']:
        if text_only:
            gaps.append('requires host vision review; Jev is text-only')
        else:
            for kind in set(check['evidence_inputs']) & VISUAL:
                if not any(e.get('kind') == kind and e.get('representation') == 'host visual observation'
                           for e in evidence):
                    gaps.append('missing host visual observation: ' + kind)
    return gaps


def outcome_question(check, boundary):
    instructions = (boundary + check['question'] + ' Required evidence inputs: ' +
                    ', '.join(check['evidence_inputs']) + '. Abstain when: ' +
                    ' '.join(check['abstain_when']) + ' Required context: ' +
                    ', '.join(check.get('required_context', [])) +
                    '. No signal is advisory and never establishes policy compliance.')
    return {'type': 'choice', 'instructions': instructions, 'criteria': OUTCOMES}


def compose_host_review(job, body, text_only=False):
    """Compose explicit host observations; text-only clients must pass text_only=True."""
    check = job['context']['check_definition']
    result = {'id': job['id'], 'workflow': 'review', 'advisory': True, 'check_key': job.get('check_key'),
              'guideline': check['guideline'], 'catalog_version': 4, 'advisory_only': True, 'outcome': 'insufficient_evidence',
              'action': 'pierre_review', 'reason': 'incomplete evidence coverage', 'evidence': [],
              'model_probability': None, 'model_confidence': None}
    gaps = evidence_gaps(job, text_only)
    if gaps or not job['coverage']['complete'] or job['coverage']['missing']:
        result['reason'] = '; '.join(gaps or job['coverage']['missing'] or ['incomplete evidence coverage'])
        return result
    answer = body.get('answers', {}).get('outcome', {})
    choice = answer.get('choice')
    probability = answer.get('probabilities', {}).get(choice, 0)
    confidence = answer.get('confidence', 0)
    result.update(model_probability=probability, model_confidence=confidence)
    if choice not in OUTCOMES or choice == 'insufficient_evidence' or probability < .90 or confidence < .50:
        result['reason'] = 'uncertain or unsupported advisory judgment'
        return result
    citation = body.get('answers', {}).get('evidence', {})
    selected = citation.get('choice')
    if citation.get('probabilities', {}).get(selected, 0) >= .90 and citation.get('confidence', 0) >= .50:
        result['evidence'] = [e for e in job['evidence'] if e['id'] == selected]
    if choice == 'finding' and not result['evidence']:
        result['reason'] = 'concern has no confidently selected evidence span'
        return result
    result.update(outcome=choice, action='advisory_finding' if choice == 'finding' else 'advisory_result',
                  reason='bounded advisory judgment; no scanner verdict or compliance pass',
                  judgments=body.get('answers', {}))
    return result
