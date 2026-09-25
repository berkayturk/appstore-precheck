#!/usr/bin/env python3
"""Add obligation run coverage to a scanner JSON envelope (stdlib only)."""

import argparse
import importlib.util
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REF = HERE.parent / "references"


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
        checks = normalize_static(envelope.get("findings", []), registry)
        if args.run_results and args.run_results.is_file():
            try:
                checks.update(engine.read_object(args.run_results).get("checks", {}))
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
