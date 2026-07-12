#!/usr/bin/env python3
"""build_request.py — assemble one Anthropic Messages API request body for an eval case.

Reads the target check's table row and per-check procedure from
skills/appstore-precheck/references/pierre-deep-review.md (single source of
truth — no duplicated prompt text), plus the case's fixture files, and prints
the full JSON request body to stdout.

The system prompt is byte-identical across cases (rules + output format), so
repeated calls share the Anthropic prompt-cache prefix.

Usage: build_request.py <case.json> <model> <max_tokens>
"""
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
PIERRE_MD = REPO / "skills" / "appstore-precheck" / "references" / "pierre-deep-review.md"
DATASET = REPO / "eval" / "dataset"

FIXTURE_EXCLUDE = {".DS_Store"}


def extract_section(text, heading):
    """Return the body of a '## <heading>' section (up to the next ## or ---)."""
    pattern = rf"^## {re.escape(heading)}\n(.*?)(?=^## |^---$)"
    match = re.search(pattern, text, re.MULTILINE | re.DOTALL)
    if not match:
        raise SystemExit(f"build_request: section '## {heading}' not found in {PIERRE_MD}")
    return match.group(1).strip()


def extract_check_row(text, check_id):
    """Return the markdown table row for check <check_id> from the 28-check table."""
    for line in text.splitlines():
        if re.match(rf"^\|\s*{check_id}\s*\|", line):
            return line.strip()
    raise SystemExit(f"build_request: table row for check {check_id} not found")


def extract_procedure(text, check_id):
    """Return the '### <check_id> — ...' per-check procedure block."""
    pattern = rf"^### {check_id} — .*?(?=^### |^---$)"
    match = re.search(pattern, text, re.MULTILINE | re.DOTALL)
    if not match:
        raise SystemExit(f"build_request: procedure '### {check_id} —' not found")
    return match.group(0).strip()


def fixture_files(fixture_dir):
    """Yield (relative_path, content) for every fixture file, sorted for determinism."""
    paths = sorted(p for p in fixture_dir.rglob("*")
                   if p.is_file() and p.name not in FIXTURE_EXCLUDE)
    for path in paths:
        yield path.relative_to(fixture_dir).as_posix(), path.read_text(encoding="utf-8")


def build_system(pierre_text):
    rules = extract_section(pierre_text, "Rules")
    output_format = extract_section(pierre_text, "Output format")
    return (
        "You are Pierre, the review-simulator of appstore-precheck, running ONE check "
        "of the Phase 4 deep review (28 semantic checks) on an iOS project.\n\n"
        "The full project relevant to this check is provided verbatim in the user "
        "message. You cannot fetch URLs; when a check needs fetched URL content, it "
        "is supplied pre-fetched in the user message (treat it as the fetch result).\n\n"
        "## Rules\n\n" + rules + "\n\n"
        "## Output format\n\n" + output_format + "\n\n"
        "Report ONLY the single target check named in the user message: output exactly "
        "one REVIEW-PASS: or REVIEW-FINDING: line for it (plus the Pierre: explanation "
        "block when it is a REVIEW-FINDING). Do not report any other check. Write the "
        "Pierre explanation in English."
    )


def build_user(case, pierre_text):
    check_id = case["check_id"]
    parts = [
        f"# Target check: {check_id} (guideline {case['guideline']})",
        "Table row from the 28-check catalog:",
        extract_check_row(pierre_text, check_id),
        "## Procedure",
        extract_procedure(pierre_text, check_id),
        "## Project files",
    ]
    fixture_dir = DATASET / case["fixture"]
    for rel, content in fixture_files(fixture_dir):
        parts.append(f"### {rel}\n```\n{content.rstrip()}\n```")
    fetched = case.get("fetched_urls") or {}
    if fetched:
        parts.append("## Pre-fetched URL contents")
        for kind in sorted(fetched):
            parts.append(f"### {kind}\n```\n{fetched[kind].rstrip()}\n```")
    parts.append(
        f"Run check {check_id} now and output its single REVIEW-PASS: or "
        "REVIEW-FINDING: line."
    )
    return "\n\n".join(parts)


def thinking_always_on(model):
    """Fable/Mythos-tier models have always-on thinking: the `thinking` field
    must be omitted entirely (any explicit configuration is rejected with 400)."""
    return model.startswith(("claude-fable", "claude-mythos"))


def main(argv):
    if len(argv) != 4:
        print("usage: build_request.py <case.json> <model> <max_tokens>", file=sys.stderr)
        return 64
    case = json.loads(Path(argv[1]).read_text(encoding="utf-8"))
    pierre_text = PIERRE_MD.read_text(encoding="utf-8")
    model = argv[2]
    body = {
        "model": model,
        "max_tokens": int(argv[3]),
        "output_config": {"effort": "low"},
        "system": [{
            "type": "text",
            "text": build_system(pierre_text),
            "cache_control": {"type": "ephemeral"},
        }],
        "messages": [{"role": "user", "content": build_user(case, pierre_text)}],
    }
    if not thinking_always_on(model):
        body["thinking"] = {"type": "disabled"}
    json.dump(body, sys.stdout, ensure_ascii=False)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
