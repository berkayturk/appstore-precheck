#!/usr/bin/env python3
"""validate_case.py — validate every eval dataset case against eval/schema/case.schema.json.

Stdlib-only (no jsonschema dependency): the constraints in the schema file are
enforced here directly, plus cross-field checks the schema cannot express:
  - id must equal the case filename (without .json)
  - tier and stable check_key must match the current versioned catalog
  - fixture directory must exist and contain at least one file

Exit 0 if all cases pass, 1 otherwise. Usage: validate_case.py <eval-dir>
"""
import json
import re
import sys
from pathlib import Path
from catalog import BY_NUMBER, resolve

TIER_B_CHECKS = frozenset(n for n, c in BY_NUMBER.items() if c['tier'] == 'B')
REQUIRED = ("id", "check_id", "tier", "guideline", "expected", "rationale",
            "label_confirmed", "fixture")
ALLOWED = frozenset(REQUIRED) | {"fetched_urls", "notes", "check_key", "catalog_version"}
EXPECTED_VALUES = ("finding", "pass", "not-applicable", "insufficient_evidence")
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

    if not (type(case["check_id"]) is int and case["check_id"] in BY_NUMBER):
        errors.append(f"check_id {case['check_id']!r} must be an integer in 1..31")
    else:
        want_tier = "B" if case["check_id"] in TIER_B_CHECKS else "A"
        if case["tier"] != want_tier:
            errors.append(f"tier {case['tier']!r} inconsistent with check_id "
                          f"{case['check_id']} (expected {want_tier!r})")
        try:
            resolve(case)
        except ValueError as exc:
            errors.append(str(exc))

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
