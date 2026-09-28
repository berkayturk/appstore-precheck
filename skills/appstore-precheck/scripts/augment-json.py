#!/usr/bin/env python3
"""Add obligation run coverage to a scanner JSON envelope (stdlib only)."""

import argparse
import importlib.util
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REF = HERE.parent / "references"
# NOT_RUN stays the status (no positive evidence exists); a separate "ran, no signal"
# status would be rejected by attestation-report.py's RUN_STATUSES, so only the wording
# is made precise: the rule was evaluated and found nothing to report.
SILENT_STATIC_REASON = ("Static rule was evaluated but emitted no line: no applicable signal "
                        "exists in the project, so no positive evidence was recorded")


def load_attestation_engine():
    spec = importlib.util.spec_from_file_location("attestation_report", HERE / "attestation-report.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def normalize_static(findings, registry):
    """Aggregate scanner lines per routed static rule.

    FINDING and WARN dominate. PASS is kept only when every line of the rule passed:
    a PASS next to a SKIP means part of the rule never ran, so it needs review.
    """
    seen = {}
    for row in findings:
        check_id = row.get("rule_id")
        if not check_id or registry.get("checks", {}).get(check_id, {}).get("route") != "static":
            continue
        if row.get("suppressed"):
            continue
        severity = row.get("severity")
        status = "FINDING" if severity == "FAIL" else severity
        if status not in {"FINDING", "WARN", "PASS", "SKIP"}:
            continue
        seen.setdefault(check_id, []).append((status, "finding:" + str(row.get("id") or check_id)))
    normalized = {}
    for check_id, rows in seen.items():
        statuses = {status for status, _ in rows}
        for status in ("FINDING", "WARN"):
            if status in statuses:
                normalized[check_id] = {"status": status,
                                        "evidence": next(ptr for st, ptr in rows if st == status)}
                break
        else:
            if statuses == {"PASS", "SKIP"}:
                normalized[check_id] = {"status": "REVIEW_REQUIRED",
                                        "reason": "Partial static coverage: a sibling check of this rule was skipped"}
            elif statuses == {"SKIP"}:
                normalized[check_id] = {"status": "SKIP", "reason": "Static scanner did not complete this check"}
            else:
                normalized[check_id] = {"status": "PASS", "evidence": rows[0][1]}
    return normalized


def static_rule_catalogue():
    """Rule slugs the default scanner always evaluates (findings.sh rule_slug)."""
    text = (HERE / "findings.sh").read_text(errors="replace")
    return set(re.findall(r"[0-9]+\)\s+echo\s+([a-z0-9-]+)\s*;;", text))


def mark_silent_static(checks, registry):
    """Routed static rules that ran but wrote no line are not 'never invoked'."""
    marked = dict(checks)
    for check_id in static_rule_catalogue():
        entry = registry.get("checks", {}).get(check_id)
        if entry and entry.get("route") == "static" and check_id not in marked:
            marked[check_id] = {"status": "NOT_RUN", "reason": SILENT_STATIC_REASON}
    return marked


def accept_run_results(raw, registry, engine, errors):
    """Validate each observed check on its own so one bad record cannot erase the tier."""
    accepted = {}
    for check_id, result in raw.items():
        try:
            accepted.update(engine.validate_run_results({"checks": {check_id: result}}, registry))
        except (ValueError, KeyError, TypeError) as exc:
            errors.append("Optional check result dropped: " + str(exc))
    return accepted


def route_run_counts(report):
    counts = {}
    for row in report["obligations"]:
        for route in row["routes"]:
            bucket = counts.setdefault(route["route"], {"ran": 0, "skipped": 0, "not_run": 0})
            status = route["run_status"]
            if status == "SKIP":
                bucket["skipped"] += 1
            elif status in {"NOT_RUN", "ATTESTATION_REQUIRED"}:
                bucket["not_run"] += 1
            else:
                bucket["ran"] += 1
    return counts


def augment(envelope, args):
    """Return (augmented copy of envelope, errors). Raises only on a broken skill install."""
    catalog = json.loads((REF / "guideline-obligations.json").read_text())
    registry = json.loads((REF / "check-registry.json").read_text())
    engine = load_attestation_engine()
    errors = []
    try:
        config = engine.read_object(args.config) if args.config and args.config.is_file() else {}
    except (OSError, ValueError, json.JSONDecodeError):
        config = {}
        errors.append("Attestation config could not be read; answers were not applied")
    checks = mark_silent_static(normalize_static(envelope.get("findings", []), registry), registry)
    if args.run_results and args.run_results.is_file():
        try:
            observed = engine.read_object(args.run_results).get("checks", {})
            if not isinstance(observed, dict):
                raise ValueError("run results checks must be an object")
            checks.update(accept_run_results(observed, registry, engine, errors))
        except (OSError, ValueError, json.JSONDecodeError):
            errors.append("Optional check results could not be read")
    try:
        report = engine.build_report(catalog, registry, config, {"checks": checks})
    except (ValueError, KeyError, TypeError) as exc:
        # A malformed user answer cannot erase the scanner's own JSON result.
        errors.append("Coverage inputs were invalid: " + str(exc))
        report = engine.build_report(catalog, registry, {}, {"checks": normalize_static(envelope.get("findings", []), registry)})
    result = dict(envelope)
    # Units differ on purpose: coverage_run counts ROUTE ENTRIES by run outcome (an
    # obligation with two static routes adds two), while coverage_summary.route_counts
    # counts OBLIGATIONS that declare a route kind (each at most once per kind).
    result["coverage_run"] = route_run_counts(report)
    result["coverage_summary"] = report["summary"]
    result["obligations"] = report["obligations"]
    if args.opt_summary and args.opt_summary.is_file():
        try:
            opt = json.loads(args.opt_summary.read_text())
            if not isinstance(opt, dict):
                raise ValueError("opt-in summary must be an object")
            result["opt_in"] = {"tiers": opt.get("tiers", {}),
                                "blocking": opt.get("blocking", []),
                                "input_errors": opt.get("input_errors", []),
                                "run_results": opt.get("run_results"),
                                "report_dir": str(args.opt_summary.parent)}
        except (OSError, ValueError):
            errors.append("Opt-in summary could not be read")
    if errors:
        result["coverage_errors"] = errors
    return result


def emit(envelope):
    json.dump(envelope, sys.stdout, ensure_ascii=False, separators=(",", ":"))
    sys.stdout.write("\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path)
    parser.add_argument("--run-results", type=Path)
    parser.add_argument("--opt-summary", type=Path)
    args = parser.parse_args()
    data = sys.stdin.buffer.read()
    try:
        envelope = json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, ValueError):
        envelope = None
    if not isinstance(envelope, dict):
        # Not a scanner envelope: hand it back untouched so nothing is ever lost.
        sys.stdout.buffer.write(data)
        sys.stdout.buffer.flush()
        return 0
    try:
        result = augment(envelope, args)
    except Exception as exc:  # the scanner's own JSON must always survive
        print("augment-json: " + type(exc).__name__ + ": " + str(exc), file=sys.stderr)
        emit(dict(envelope, coverage_errors=["Coverage could not be computed: " + type(exc).__name__]))
        return 0
    emit(result)
    return 0


if __name__ == "__main__":
    sys.exit(main())
