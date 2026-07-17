#!/usr/bin/env bash
# test-rag-gemini-client.sh — eval/rag/gemini_client.py retry-delay parsing,
# 429 retry/backoff, and MRL truncate/normalize, no real network or real sleep
# (urlopen/time.sleep stubbed).
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
# shellcheck source=tests/_assert.sh
source "$DIR/_assert.sh"

section "gemini_client.truncate_and_normalize"

trunc_result="$(cd "$ROOT/eval/rag" && python3 -c "
import gemini_client as gc

# A fake 3072-dim vector (Gemini's native output size when outputDimensionality
# is ignored) -> must be cut down to OUTPUT_DIMENSIONALITY (1024) and re-normalized.
native = [1.0] * 3072
result = gc.truncate_and_normalize(native)
print(len(result))
norm_sq = sum(x * x for x in result)
print(round(norm_sq, 6))

# Zero vector edge case: must not divide by zero.
zero_result = gc.truncate_and_normalize([0.0] * 3072)
print(len(zero_result))
print(all(x == 0.0 for x in zero_result))
")"
assert_eq "$(echo "$trunc_result" | sed -n '1p')" "1024" "3072-dim vector truncated to OUTPUT_DIMENSIONALITY (1024)"
assert_eq "$(echo "$trunc_result" | sed -n '2p')" "1.0" "truncated vector is L2-normalized (sum of squares == 1)"
assert_eq "$(echo "$trunc_result" | sed -n '3p')" "1024" "zero vector still truncated to the right length"
assert_eq "$(echo "$trunc_result" | sed -n '4p')" "True" "zero vector does not raise a divide-by-zero error"

section "gemini_client.parse_retry_delay"

parsed="$(cd "$ROOT/eval/rag" && python3 -c "
import gemini_client as gc

# Real error body shape from a Gemini 429 response (RetryInfo present).
body = '{\"error\":{\"code\":429,\"details\":[{\"@type\":\"type.googleapis.com/google.rpc.RetryInfo\",\"retryDelay\":\"26s\"}]}}'
print(gc.parse_retry_delay(body))

# No RetryInfo detail -> falls back to the module default.
print(gc.parse_retry_delay('{\"error\":{\"code\":500}}'))

# Malformed body -> falls back to the module default, does not raise.
print(gc.parse_retry_delay('not json'))
")"
default_delay="$(cd "$ROOT/eval/rag" && python3 -c 'import gemini_client as gc; print(gc.DEFAULT_RETRY_DELAY)')"
assert_eq "$(echo "$parsed" | sed -n '1p')" "26.0" "retryDelay '26s' parsed as 26.0 seconds"
assert_eq "$(echo "$parsed" | sed -n '2p')" "$default_delay" "missing RetryInfo falls back to DEFAULT_RETRY_DELAY"
assert_eq "$(echo "$parsed" | sed -n '3p')" "$default_delay" "malformed body falls back to DEFAULT_RETRY_DELAY, no exception"

section "gemini_client.post_json retry-on-429 (urlopen + time.sleep stubbed)"

retry_result="$(cd "$ROOT/eval/rag" && python3 -c "
import io
import urllib.error
import gemini_client as gc

calls = []
sleeps = []
gc.time.sleep = lambda s: sleeps.append(s)

def fake_urlopen(req, timeout=60):
    calls.append(1)
    if len(calls) == 1:
        raise urllib.error.HTTPError(
            req.full_url, 429, 'rate limited', {},
            io.BytesIO(b'{\"error\":{\"details\":[{\"@type\":\"type.googleapis.com/google.rpc.RetryInfo\",\"retryDelay\":\"2s\"}]}}'),
        )
    class Resp:
        def read(self):
            return b'{\"embeddings\":[{\"values\":[1,2,3]}]}'
        def __enter__(self):
            return self
        def __exit__(self, *a):
            return False
    return Resp()

gc.urllib.request.urlopen = fake_urlopen
result = gc.post_json('http://example.invalid', {'x': 1}, 'fake-key', 'test')
print(len(calls))
print(len(sleeps))
print(sleeps[0] if sleeps else 'none')
print(result)
")"
assert_eq "$(echo "$retry_result" | sed -n '1p')" "2" "one 429 then success -> exactly 2 urlopen calls"
assert_eq "$(echo "$retry_result" | sed -n '2p')" "1" "exactly one sleep between the failed and successful call"
assert_eq "$(echo "$retry_result" | sed -n '3p')" "3.0" "sleep duration is the API's retryDelay (2s) plus the 1s buffer"
assert_contains "$(echo "$retry_result" | sed -n '4p')" "[1, 2, 3]" "post_json returns the successful response body"

section "gemini_client.post_json non-429 failure (no retry)"

immediate_fail="$(cd "$ROOT/eval/rag" && python3 -c "
import io
import urllib.error
import gemini_client as gc

calls = []
gc.time.sleep = lambda s: (_ for _ in ()).throw(AssertionError('should never sleep on a non-429 error'))

def fake_urlopen(req, timeout=60):
    calls.append(1)
    raise urllib.error.HTTPError(
        req.full_url, 403, 'forbidden', {}, io.BytesIO(b'{\"error\":{\"message\":\"bad key\"}}'),
    )

gc.urllib.request.urlopen = fake_urlopen
try:
    gc.post_json('http://example.invalid', {'x': 1}, 'fake-key', 'test')
    print('NO_EXCEPTION_RAISED')
except SystemExit as exc:
    print(len(calls))
    print(str(exc))
")"
assert_eq "$(echo "$immediate_fail" | sed -n '1p')" "1" "non-429 error fails on the first attempt, no retry"
assert_contains "$(echo "$immediate_fail" | sed -n '2p')" "Gemini API error 403" "SystemExit message includes the HTTP status and detail"

exit "$fails"
