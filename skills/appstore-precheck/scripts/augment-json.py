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
SILENT_STATIC_REASON = ("Static rule ran in this scan; it emits no line when no applicable signal "
                        "exists in the project")


def load_attestation_engine():
    spec = importlib.util.spec_from_file_location("attestation_report", HERE / "attestation-report.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def normalize_static(findings, registry):
    rank = {"FINDING": 4, "WARN": 3, "PASS": 2, "SKIP": 1}
    normalized = {}
    for row in findings:
        check_id = row.get("rule_id")
        if not check_id or registry.get("checks", {}).get(check_id, {}).get("route") != "static":
            continue
        if row.get("suppressed"):
            continue
        severity = row.get("severity")
        status = "FINDING" if severity == "FAIL" else severity
        if status not in rank:
            continue
        previous = normalized.get(check_id)
        if previous and rank[previous["status"]] >= rank[status]:
            continue
        if status == "SKIP":
            result = {"status": status, "reason": "Static scanner did not complete this check"}
        else:
            pointer = "finding:" + str(row.get("id") or check_id)
            result = {"status": status, "evidence": pointer}
        normalized[check_id] = result
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path)
    parser.add_argument("--run-results", type=Path)
    parser.add_argument("--opt-summary", type=Path)
    args = parser.parse_args()
    try:
        envelope = json.load(sys.stdin)
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
        envelope["coverage_run"] = route_run_counts(report)
        envelope["coverage_summary"] = report["summary"]
        envelope["obligations"] = report["obligations"]
        if args.opt_summary and args.opt_summary.is_file():
            opt = json.loads(args.opt_summary.read_text())
            envelope["opt_in"] = {"tiers": opt.get("tiers", {}),
                                  "blocking": opt.get("blocking", []),
                                  "input_errors": opt.get("input_errors", []),
                                  "run_results": opt.get("run_results"),
                                  "report_dir": str(args.opt_summary.parent)}
        if errors:
            envelope["coverage_errors"] = errors
        json.dump(envelope, sys.stdout, ensure_ascii=False, separators=(",", ":"))
        sys.stdout.write("\n")
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as exc:
        print("augment-json: " + str(exc), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
