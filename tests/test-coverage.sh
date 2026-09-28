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
assert report['obligations_without_route'] == 0
assert report['routed_obligations'] == report['total_obligations']
assert report['routes']['static'] > 0
assert report['routes']['runtime'] > 0
assert report['routes']['semantic'] > 0
assert report['unrouted_checks'] == [], report['unrouted_checks']
# The routed headline includes the generic attestation route; the narrower rows are derived.
assert 0 < report['automated_route'] <= report['non_attestation_route'] < report['routed_obligations']
assert report['non_attestation_route'] + report['attestation_only'] <= report['total_obligations']
assert isinstance(report['full_positive_automatic'], int)
assert report['full_positive_automatic'] <= report['automated_route']
PY
grep -q '| Routed (including developer attestation) |' "$tmp/coverage.md"
grep -q '| Full positive automatic decision capability |' "$tmp/coverage.md"
grep -q 'does not certify App Store compliance' "$tmp/coverage.md"
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
# an exceptions[] link must point at an exception-kind record
bad=next(x for x in catalog['obligations'] if x['kind']=='obligation' and x['id']!=first['id'])
first['exceptions']=[bad['id']]
try:
    tool.validate(catalog,registry)
except ValueError:
    pass
else:
    raise AssertionError('exception link to an obligation must fail validation')
first['exceptions']=[]
# a non-obligation record must carry a justified route
info=next(x for x in catalog['obligations'] if x['kind']!='obligation')
saved=info['routes']
info['routes']=[]
try:
    tool.validate(catalog,registry)
except ValueError:
    pass
else:
    raise AssertionError('non-obligation without a route must fail validation')
info['routes']=saved
tool.validate(catalog,registry)
# a registered check that no obligation routes to is reported and fails --require-complete
registry['checks']['orphan-check']=dict(registry['checks']['att-usage'])
summary=tool.report(catalog,tool.validate(catalog,registry))
assert summary['unrouted_checks']==['orphan-check'], summary['unrouted_checks']
del registry['checks']['orphan-check']
PY
python3 scripts/coverage.py --require-complete --output "$tmp/strict.json" --markdown "$tmp/strict.md" >/dev/null
echo 'coverage schema and registry: OK'
