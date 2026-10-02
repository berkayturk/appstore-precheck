"""Allowlisted opt-in escalation from three fresh, observed runtime failures."""
import json
from pathlib import Path
import re


def blocking(out):
    try:
        report = json.loads((Path(out) / 'run.json').read_text())
        transcript = (Path(out) / 'transcript.txt').read_text().splitlines()
    except (OSError, ValueError):
        return []
    if (report.get('dry_run') is not False or report.get('fresh_erases') != 3 or report.get('repeats') != 3
            or not report.get('device', {}).get('created_by_this_run')):
        return []
    result = []
    for rule, field, evidence, message in (
        ('dyn-launch', 'launch', r'process gone|app crash in log', 'App crashed on three fresh simulator launches'),
        ('dyn-demo-login', 'demo_login', r'explicit login rejection', 'Demo login was rejected on three fresh attempts'),
    ):
        if report.get(field) != {'pass': 0, 'finding': 3, 'skip': 0}:
            continue
        pattern = r'^DYNAMIC-FINDING: 2\.1 \[' + rule + r'\] — quorum 3/3: .*fresh erase verified'
        if any(re.search(pattern, line) and re.search(evidence, line) for line in transcript):
            result.append('2.1 [' + rule + '] ' + message + '; opt-in dynamic blocking')
    return result
