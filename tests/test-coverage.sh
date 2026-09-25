#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
python3 scripts/coverage.py --output "$tmp/coverage.json" --markdown "$tmp/coverage.md"
python3 - "$tmp/coverage.json" <<'PY'
import json,sys
report=json.load(open(sys.argv[1]))
assert report['total_obligations'] > 0
assert report['obligations_without_route'] >= 0
assert report['routes']['static'] > 0
assert report['routes']['runtime'] > 0
assert report['routes']['semantic'] > 0
PY
python3 - <<'PY'
import importlib.util,json
from pathlib import Path
spec=importlib.util.spec_from_file_location('coverage_tool','scripts/coverage.py')
tool=importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)
catalog=json.loads(Path('skills/appstore-precheck/references/guideline-obligations.json').read_text())
registry=json.loads(Path('skills/appstore-precheck/references/check-registry.json').read_text())
tool.validate(catalog,registry)
first=next(x for x in catalog['obligations'] if x['kind']=='obligation')
old=first['routes']
first['routes']=[{'route':'static','check_id':'nonexistent','decides':'full','evidence_class':'source'}]
try:
    tool.validate(catalog,registry)
except ValueError:
    pass
else:
    raise AssertionError('unknown check must fail validation')
first['routes']=old
tool.validate(catalog,registry)
PY
# Wave 0 deliberately preserves unassigned obligations. The complete gate is
# enabled only after section review and implementation are merged.
if python3 scripts/coverage.py --require-complete --output "$tmp/strict.json" --markdown "$tmp/strict.md" >/dev/null 2>&1; then
  python3 - "$tmp/coverage.json" <<'PY'
import json,sys
assert json.load(open(sys.argv[1]))['obligations_without_route'] == 0
PY
fi
echo 'coverage schema and registry: OK'
