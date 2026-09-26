#!/usr/bin/env python3
"""Syntax-check maintained scripts, including optional tiers, without bytecode."""
import ast
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
count = 0
for base in ('skills/appstore-precheck/scripts', 'scripts', 'tests', 'corpus/dynamic'):
    for path in sorted((ROOT / base).rglob('*')):
        if not path.is_file() or any(p in {'node_modules', '.venv', '__pycache__'} for p in path.parts):
            continue
        if path.suffix == '.py':
            ast.parse(path.read_text(), filename=str(path), feature_version=(3, 8))
            count += 1
        elif path.suffix == '.sh':
            subprocess.run(['bash', '-n', str(path)], check=True)
            count += 1
print('Syntax checked {} Bash/Python files (Python 3.8 grammar)'.format(count))
