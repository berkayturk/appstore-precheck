#!/usr/bin/env python3
"""Bind a local panel to corpus inputs and runner code; no source writes."""
import hashlib
import importlib.util
import json
import sys
from pathlib import Path

root, target, mode = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
spec = importlib.util.spec_from_file_location('source_snapshot', root / 'skills/appstore-precheck/scripts/source-snapshot.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
parts = {name: module.snapshot(root / name) for name in
         ('corpus/dynamic', 'skills/appstore-precheck/scripts', 'tests/local')}
digest = hashlib.sha256(json.dumps(parts, sort_keys=True).encode()).hexdigest()
record = {'sha256': digest, 'stable_read': all(p['stable_read'] for p in parts.values()),
          'parts': parts}
if mode == 'before':
    target.write_text(json.dumps({'before': record}, indent=2) + '\n')
else:
    prior = json.loads(target.read_text())
    prior['after'] = record
    prior['unchanged'] = (prior['before']['stable_read'] and record['stable_read'] and
                          prior['before']['sha256'] == digest)
    target.write_text(json.dumps(prior, indent=2) + '\n')
