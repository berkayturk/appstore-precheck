#!/usr/bin/env python3
"""validate_case.py — validate every eval dataset case against eval/schema/case.schema.json.

Stdlib-only (no jsonschema dependency): the constraints in the schema file are
enforced here directly, plus cross-field checks the schema cannot express:
  - id must equal the case filename (without .json)
  - tier must match check_id (Tier B = checks 4, 5, 7, 10, 15, 28)
  - fixture directory must exist and contain at least one file

Exit 0 if all cases pass, 1 otherwise. Usage: validate_case.py <eval-dir>
"""
import json
import re
import sys
from pathlib import Path

TIER_B_CHECKS = frozenset({4, 5, 7, 10, 15, 28})
REQUIRED = ("id", "check_id", "tier", "guideline", "expected", "rationale",
            "label_confirmed", "fixture")
ALLOWED = frozenset(REQUIRED) | {"fetched_urls", "notes"}
EXPECTED_VALUES = ("finding", "pass", "not-applicable")
ID_RE = re.compile(r"^check[0-9]{2}-[a-z0-9-]+$")
FIXTURE_RE = re.compile(r"^fixtures/[a-z0-9-]+/$")


def check_case(path, dataset_dir):
    """Return a new list of error strings for one case file (empty = valid)."""
    errors = []
    try:
        case = json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        return [f"invalid JSON: {exc}"]
    if not isinstance(case, dict):
        return ["top-level value must be an object"]

    for key in REQUIRED:
        if key not in case:
            errors.append(f"missing required field '{key}'")
    for key in case:
        if key not in ALLOWED:
            errors.append(f"unknown field '{key}'")
    if errors:
        return errors

    if not (isinstance(case["id"], str) and ID_RE.match(case["id"])):
        errors.append(f"id {case['id']!r} does not match ^check[0-9]{{2}}-[a-z0-9-]+$")
    if case["id"] != path.stem:
        errors.append(f"id {case['id']!r} != filename stem {path.stem!r}")

    if not (isinstance(case["check_id"], int) and 1 <= case["check_id"] <= 28):
        errors.append(f"check_id {case['check_id']!r} must be an integer in 1..28")
    else:
        want_tier = "B" if case["check_id"] in TIER_B_CHECKS else "A"
        if case["tier"] != want_tier:
            errors.append(f"tier {case['tier']!r} inconsistent with check_id "
                          f"{case['check_id']} (expected {want_tier!r})")

    if not (isinstance(case["guideline"], str) and case["guideline"]):
        errors.append("guideline must be a non-empty string")
    if case["expected"] not in EXPECTED_VALUES:
        errors.append(f"expected {case['expected']!r} not in {EXPECTED_VALUES}")
    if not (isinstance(case["rationale"], str) and len(case["rationale"]) >= 10):
        errors.append("rationale must be a string of at least 10 characters")
    if not isinstance(case["label_confirmed"], bool):
        errors.append("label_confirmed must be a boolean")

    fixture = case["fixture"]
    if not (isinstance(fixture, str) and FIXTURE_RE.match(fixture)):
        errors.append(f"fixture {fixture!r} does not match ^fixtures/[a-z0-9-]+/$")
    else:
        fixture_dir = dataset_dir / fixture
        files = [p for p in fixture_dir.rglob("*") if p.is_file()] if fixture_dir.is_dir() else []
        if not files:
            errors.append(f"fixture dir {fixture!r} missing or empty")

    fetched = case.get("fetched_urls")
    if fetched is not None:
        if not isinstance(fetched, dict) or any(
                not isinstance(v, str) for v in fetched.values()):
            errors.append("fetched_urls must be an object of string values")
    notes = case.get("notes")
    if notes is not None and not isinstance(notes, str):
        errors.append("notes must be a string")
    return errors


def main(argv):
    if len(argv) != 2:
        print("usage: validate_case.py <eval-dir>", file=sys.stderr)
        return 64
    eval_dir = Path(argv[1])
    dataset_dir = eval_dir / "dataset"
    case_files = sorted((dataset_dir / "cases").glob("*.json"))
    if not case_files:
        print(f"validate: no case files under {dataset_dir / 'cases'}", file=sys.stderr)
        return 1

    failures = 0
    for path in case_files:
        errors = check_case(path, dataset_dir)
        if errors:
            failures += 1
            for err in errors:
                print(f"FAIL {path.name}: {err}", file=sys.stderr)
        else:
            print(f"ok   {path.name}")
    if failures:
        print(f"validate: {failures}/{len(case_files)} case(s) invalid", file=sys.stderr)
        return 1
    print(f"validate: {len(case_files)} case(s) valid")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
