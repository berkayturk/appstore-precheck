"""Status aggregation harvested without obligations/registry dependencies."""
MAX_POINTER = 500
VALID_STATUSES = frozenset({"NOT_RUN", "SKIP", "PASS", "REVIEW_REQUIRED", "WARN", "FINDING"})
DEFECT_RANK = {"REVIEW_REQUIRED": 1, "WARN": 2, "FINDING": 3}

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

def merge_status(previous, status):
    """Order-independent aggregate of results sharing one check id.

    A defect (FINDING > WARN > REVIEW_REQUIRED) dominates. PASS survives only when
    every sibling passed: a PASS next to a SKIP/NOT_RUN sibling means part of the
    check never ran, so the aggregate needs review instead of reading as clean.
    """
    if previous is None or previous == status:
        return status
    worst = max(previous, status, key=lambda value: DEFECT_RANK.get(value, 0))
    if DEFECT_RANK.get(worst, 0):
        return worst
    return "REVIEW_REQUIRED" if "PASS" in (previous, status) else "SKIP"

def merge_result(checks, check_id, status, reason, evidence):
    previous = checks.get(check_id)
    merged = merge_status(previous["status"] if previous else None, status)
    if merged == status:
        record(checks, check_id, status, reason, evidence)
    elif merged != previous["status"]:
        gap = reason if status != "PASS" else previous.get("reason", "")
        record(checks, check_id, merged, "Partial evidence: a sibling check did not run (" +
               single_line(gap, "no reason given") + ")", evidence)

def import_records(checks, rows, evidence):
    errors = []
    if not isinstance(rows, list):
        return ["Optional result collection must be a list"]
    for row in rows:
        if not isinstance(row, dict) or not isinstance(row.get("check_id"), str) or not row["check_id"]:
            errors.append("Malformed optional result ignored")
            continue
        raw_status = row.get("status")
        status = normalize(raw_status) if isinstance(raw_status, str) else None
        if status not in VALID_STATUSES:
            errors.append("Invalid optional result status ignored")
            continue
        merge_result(checks, row["check_id"], status, row.get("reason", ""), evidence + "#" + row["check_id"])
    return errors
