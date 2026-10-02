#!/usr/bin/env bash
# Bash entry point retained for build-plan consumers; never chooses the first candidate.
build_project() {
  python3 - "$1" "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" <<'PY'
import importlib.util, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location('build_plan', Path(sys.argv[2]) / 'build-plan.py')
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
found = module.projects(Path(sys.argv[1]))
if len(found) != 1:
    print('SKIP: ambiguous build candidates: ' + ', '.join(found), file=sys.stderr)
    raise SystemExit(3)
print(found[0])
PY
}
