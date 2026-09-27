#!/usr/bin/env python3
"""Bind a local panel to corpus inputs and runner code; no source writes."""
import hashlib
import json
import sys
from pathlib import Path

root, target, mode = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
files = {}
for base in (root / 'corpus/dynamic', root / 'skills/appstore-precheck/scripts', root / 'tests/local'):
    for path in sorted(base.rglob('*')):
        if path.is_file() and '__pycache__' not in path.parts:
            files[str(path.relative_to(root))] = hashlib.sha256(path.read_bytes()).hexdigest()
digest = hashlib.sha256(json.dumps(files, sort_keys=True).encode()).hexdigest()
record = {'sha256': digest, 'files': files}
if mode == 'before':
    target.write_text(json.dumps({'before': record}, indent=2) + '\n')
else:
    prior = json.loads(target.read_text())
    prior['after'] = record
    prior['unchanged'] = prior['before']['sha256'] == digest
    target.write_text(json.dumps(prior, indent=2) + '\n')
