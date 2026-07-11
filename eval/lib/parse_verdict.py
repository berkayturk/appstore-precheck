#!/usr/bin/env python3
"""parse_verdict.py — extract Pierre's verdict from a raw Messages API response.

Importable (used by score.py) and runnable as a CLI for tests:
    parse_verdict.py <response.json>   -> prints {"verdict": ..., "line": ...}

Verdict values:
    finding        — a REVIEW-FINDING: line is present
    pass           — a REVIEW-PASS: line without 'not applicable'
    not-applicable — a REVIEW-PASS: line containing 'not applicable'
    unparseable    — no REVIEW line found (includes refusals / truncation)
"""
import json
import re
import sys

REVIEW_RE = re.compile(r"^\s*(REVIEW-(?:FINDING|PASS)):\s*(.*)$", re.MULTILINE)


def response_text(response):
    """Concatenate all text blocks of a Messages API response object."""
    blocks = response.get("content") or []
    return "\n".join(b.get("text", "") for b in blocks
                     if isinstance(b, dict) and b.get("type") == "text")


def parse_verdict(response):
    """Return {"verdict": <str>, "line": <str|None>} for one raw API response."""
    if response.get("stop_reason") == "refusal":
        return {"verdict": "unparseable", "line": None}
    match = REVIEW_RE.search(response_text(response))
    if not match:
        return {"verdict": "unparseable", "line": None}
    kind, rest = match.group(1), match.group(2)
    line = f"{kind}: {rest}".strip()
    if kind == "REVIEW-FINDING":
        return {"verdict": "finding", "line": line}
    if "not applicable" in rest.lower():
        return {"verdict": "not-applicable", "line": line}
    return {"verdict": "pass", "line": line}


def main(argv):
    if len(argv) != 2:
        print("usage: parse_verdict.py <response.json>", file=sys.stderr)
        return 64
    with open(argv[1], encoding="utf-8") as fh:
        response = json.load(fh)
    json.dump(parse_verdict(response), sys.stdout, ensure_ascii=False)
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
