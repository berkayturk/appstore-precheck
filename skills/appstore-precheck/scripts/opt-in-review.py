#!/usr/bin/env python3
"""Coordinate explicitly requested build, artifact, runtime, and metadata tiers."""

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ARTIFACT_IDS = (
    "artifact-entitlements", "artifact-reason-api", "artifact-private-api",
    "artifact-url-schemes", "artifact-ats", "artifact-sdk",
    "artifact-embedded-sdk", "artifact-executable-loading", "artifact-debug",
)
DYNAMIC = re.compile(r"^DYNAMIC-(PASS|FINDING|SKIP): \S+ \[([^]]+)\] — (.*)$")


def run(command, timeout):
    try:
        return subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              text=True, timeout=timeout, check=False)
    except (OSError, subprocess.TimeoutExpired):
        return None


def skip_reason(process, fallback):
    if process:
        for line in process.stdout.splitlines():
            if line.startswith("SKIP:"):
                return line[:300]
    return fallback


MAX_POINTER = 500


def single_line(value, fallback):
    """Collapse a free-text reason to one line within the report pointer limit."""
    text = " ".join(str(value or "").split())
    return (text or fallback)[:MAX_POINTER]


def record(checks, check_id, status, reason="", evidence=""):
    result = {"status": status}
    if status in {"PASS", "FINDING", "WARN"}:
        result["evidence"] = single_line(evidence, "review:" + check_id)
    elif status in {"SKIP", "NOT_RUN", "REVIEW_REQUIRED"}:
        result["reason"] = single_line(reason, "Evidence was insufficient")
    checks[check_id] = result


def normalize(status):
    return {"NEEDS_REVIEW": "REVIEW_REQUIRED"}.get(status, status)


def import_records(checks, rows, evidence):
    for row in rows:
        check_id = row.get("check_id")
        if not check_id:
            continue
        status = normalize(row.get("status"))
        if status not in {"PASS", "FINDING", "WARN", "SKIP", "NOT_RUN", "REVIEW_REQUIRED"}:
            continue
        record(checks, check_id, status, row.get("reason", ""), evidence + "#" + check_id)


def import_dynamic(checks, content, evidence):
    # Bundle subchecks include a plist key suffix. Aggregate under the registered
    # parent ID, retaining an advisory defect over a later bundle summary PASS.
    rank = {"SKIP": 0, "PASS": 1, "WARN": 2, "FINDING": 3}
    for line in content.splitlines():
        match = DYNAMIC.match(line)
        if not match:
            continue
        state, raw_id, reason = match.groups()
        check_id = raw_id.split(":", 1)[0]
        if state == "FINDING" and "quorum 3/3" not in reason:
            state = "WARN"
        previous = checks.get(check_id)
        if previous and rank.get(previous["status"], -1) > rank[state]:
            continue
        record(checks, check_id, state, reason, evidence + "#" + raw_id)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True, type=Path)
    parser.add_argument("--out-dir", required=True, type=Path)
    parser.add_argument("--build", action="store_true")
    parser.add_argument("--app", type=Path)
    parser.add_argument("--metadata", action="store_true")
    parser.add_argument("--asc-app-id")
    parser.add_argument("--check-urls", action="store_true")
    parser.add_argument("--dynamic-blocking", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    if args.build and args.app:
        parser.error("choose --build or --app")
    if args.dynamic_blocking and not (args.build or args.app):
        parser.error("--dynamic-blocking requires --build or --app")
    if (args.asc_app_id or args.check_urls) and not args.metadata:
        parser.error("ASC and URL checks require --metadata")
    repo = args.repo.resolve()
    if not repo.is_dir():
        parser.error("--repo must be a directory")
    out = args.out_dir.resolve()
    if out == repo or repo in out.parents:
        parser.error("--out-dir must be outside the user project")
    out.mkdir(parents=True, exist_ok=True)
    checks, tiers, blocking = {}, {}, []
    app = args.app.resolve() if args.app else None

    for section in range(1, 7):
        script = HERE / "lib" / ("section{}-review.py".format(section))
        if not script.is_file():
            continue
        process = run([sys.executable, str(script), "--repo", str(repo)], 120)
        label = "section{}".format(section)
        if process and process.returncode == 0:
            try:
                payload = json.loads(process.stdout)
                output = out / (label + ".json")
                output.write_text(json.dumps(payload, indent=2) + "\n")
                import_records(checks, payload.get("checks", []), str(output))
                tiers[label] = "RAN"
            except (ValueError, TypeError):
                tiers[label] = "SKIP: unreadable source review results"
        else:
            tiers[label] = "SKIP: source review unavailable"

    if args.build:
        cmd = ["bash", str(HERE / "build-run.sh"), "--repo", str(repo),
               "--out", str(out / "artifact")]
        if args.dry_run:
            cmd.append("--dry-run")
        process = run(cmd, 1250)
        if process is None:
            tiers["build"] = "SKIP: tool or deadline unavailable"
        elif process.returncode == 0:
            tiers["build"] = "PLAN" if args.dry_run else "RAN"
            for line in process.stdout.splitlines():
                if line.startswith("app_path=") and not args.dry_run:
                    app = Path(line.split("=", 1)[1])
        else:
            tiers["build"] = skip_reason(process, "SKIP: isolated simulator build unavailable; use --app with a built simulator bundle")

    artifact_cmd = ["bash", str(HERE / "artifact-review.sh"), "--format", "json"]
    if app and not args.dry_run:
        artifact_cmd += ["--app", str(app)]
    process = run(artifact_cmd, 120)
    if process and process.returncode == 0:
        try:
            payload = json.loads(process.stdout)
            artifact_output = out / "artifact-review.json"
            artifact_output.write_text(json.dumps(payload, indent=2) + "\n")
            import_records(checks, payload.get("checks", []), str(artifact_output))
            tiers["artifact"] = "RAN" if app and not args.dry_run else "NOT_RUN"
        except (ValueError, TypeError):
            tiers["artifact"] = "SKIP: unreadable artifact results"
    else:
        tiers["artifact"] = "SKIP: artifact inspection unavailable"
    for check_id in ARTIFACT_IDS:
        checks.setdefault(check_id, {"status": "NOT_RUN", "reason": "No inspectable app artifact"})

    if app and not args.dry_run:
        cmd = ["bash", str(HERE / "dynamic-run.sh"), "--app", str(app),
               "--repo", str(repo), "--repeats", "3", "--explore",
               "--out", str(out / "runtime")]
        if args.dynamic_blocking:
            cmd.append("--dynamic-blocking")
        process = run(cmd, 900)
        if process is None:
            tiers["runtime"] = "SKIP: simulator driver or deadline unavailable"
        else:
            tiers["runtime"] = "RAN" if process.returncode == 0 else "SKIP: simulator setup unavailable"
            import_dynamic(checks, process.stdout, str(out / "runtime" / "transcript.txt"))
            for line in process.stdout.splitlines():
                if line.startswith("FAIL: ") and args.dynamic_blocking:
                    blocking.append(line)
            inventory = out / "runtime" / "screen-inventory.json"
            if inventory.is_file():
                try:
                    import_records(checks, json.loads(inventory.read_text()).get("checks", []), str(inventory))
                except (OSError, ValueError, TypeError):
                    tiers["explore"] = "SKIP: screen inventory unreadable"
    else:
        tiers["runtime"] = "NOT_RUN"

    if args.metadata:
        cmd = ["bash", str(HERE / "metadata-review.sh"), "--repo", str(repo)]
        if args.asc_app_id:
            cmd += ["--asc-app-id", args.asc_app_id]
        if args.check_urls:
            cmd.append("--check-urls")
        process = run(cmd, 120)
        if process and process.returncode == 0:
            try:
                payload = json.loads(process.stdout)
                metadata_output = out / "metadata-review.json"
                metadata_output.write_text(json.dumps(payload, indent=2) + "\n")
                import_records(checks, payload.get("results", []), str(metadata_output))
                tiers["metadata"] = "RAN"
            except (ValueError, TypeError):
                tiers["metadata"] = "SKIP: unreadable metadata results"
        else:
            tiers["metadata"] = "SKIP: metadata inspection unavailable"
    else:
        tiers["metadata"] = "NOT_RUN"

    (out / "run-results.json").write_text(json.dumps({"checks": checks}, indent=2) + "\n")
    summary = {"schema_version": 1, "tiers": tiers, "blocking": blocking,
               "run_results": str(out / "run-results.json")}
    (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    json.dump(summary, sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
