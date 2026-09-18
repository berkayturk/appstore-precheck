"""Stdlib HTTP client with bounded retries and strict typed-response validation."""
import json
import math
import os
import time
import urllib.error
import urllib.request

ENDPOINT = 'https://api.typesafe.ai/v1/systemone'


class ServiceError(Exception):
    """Safe diagnostic: never include headers, server bodies, or the API key."""


def number(value, low=0, high=1):
    return (type(value) in (int, float) and math.isfinite(value) and low <= value <= high)


def validate_response(body, request):
    if not isinstance(body, dict) or body.get('model') != request['model']:
        raise ServiceError('response model does not match pinned model')
    answers = body.get('answers')
    if not isinstance(answers, dict) or set(answers) != set(request['questions']):
        raise ServiceError('missing or unexpected answers')
    for key, question in request['questions'].items():
        answer = answers[key]
        kind = question['type']
        if not isinstance(answer, dict) or answer.get('type') != kind:
            raise ServiceError('answer type mismatch')
        if kind == 'noul':
            if not number(answer.get('noul')):
                raise ServiceError('invalid Noul probability')
            continue
        probabilities = answer.get('probabilities')
        expected = set(question['criteria']) if kind == 'choice' else {str(i) for i in range(len(question['criteria']))}
        if (not isinstance(probabilities, dict) or set(probabilities) != expected
                or not all(number(p) for p in probabilities.values())
                or abs(sum(probabilities.values()) - 1) > 0.001
                or not number(answer.get('confidence'))):
            raise ServiceError('invalid probability distribution')
        if kind == 'choice':
            selected = answer.get('choice')
            if selected not in expected or probabilities[selected] < max(probabilities.values()) - 0.00001:
                raise ServiceError('invalid Choice selection')
        else:
            weighted = sum(int(k) * p for k, p in probabilities.items())
            if (not number(answer.get('score'), 0, len(expected) - 1)
                    or abs(answer['score'] - weighted) > 0.001
                    or not isinstance(answer.get('legend'), dict)
                    or set(answer['legend']) != expected
                    or any(answer['legend'][str(i)] != label for i, label in enumerate(question['criteria']))):
                raise ServiceError('invalid Score value or legend')
    usage = body.get('usage')
    if (not isinstance(usage, dict)
            or any(type(usage.get(k)) is not int or usage[k] < 0 for k in ('input_tokens', 'output_tokens'))):
        raise ServiceError('invalid token usage')
    return body


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None  # Never forward the bearer credential to another endpoint.


def evaluate(request, timeout=15, retries=2, opener=None, sleep=time.sleep):
    key = os.environ.get('TYPESAFE_API_KEY')
    if not key:
        raise ServiceError('TYPESAFE_API_KEY is not set')
    opener = opener or urllib.request.build_opener(NoRedirect()).open
    req = urllib.request.Request(ENDPOINT, data=json.dumps(request, ensure_ascii=False).encode(),
                                 headers={'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json'})
    for attempt in range(retries + 1):
        try:
            with opener(req, timeout=timeout) as response:
                raw = response.read(2_000_001)
                if len(raw) > 2_000_000:
                    raise ServiceError('response exceeds size limit')
                return validate_response(json.loads(raw), request)
        except urllib.error.HTTPError as exc:
            if exc.code not in (429, 500, 502, 503, 504, 529) or attempt == retries:
                raise ServiceError('TypeSafe HTTP %d' % exc.code) from None
            delay = min(2 ** attempt, 4)
            try:
                delay = min(max(float(exc.headers.get('Retry-After', delay)), 0), 5)
            except (TypeError, ValueError):
                pass
            sleep(delay)
        except (urllib.error.URLError, TimeoutError, OSError):
            # A lost response may have been billed; do not blindly retry it.
            raise ServiceError('TypeSafe transport failure') from None
        except (ValueError, UnicodeDecodeError):
            raise ServiceError('TypeSafe returned malformed JSON') from None
