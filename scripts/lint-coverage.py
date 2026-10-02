"""Validate coverage helpers with Python 3.8 grammar and bounded functions."""
import ast
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
names = ['skills/appstore-precheck/scripts/lib/coverage-sections.py',
         'eval/lib/validate_case.py', 'eval/lib/catalog.py', 'tests/eval-catalog-extensions.py', 'scripts/update-coverage-docs.py', 'tests/static-guidelines.py', 'tests/coverage-docs.py', 'tests/coverage-sections.py', 'tests/default-golden.py', 'tests/copyright-boundary.py']
names += [str(path.relative_to(root)) for path in (root / 'skills/appstore-precheck/scripts/lib').glob('*.py') if path.name not in ('png-uniform.py', 'coverage-sections.py')]
names += ['skills/appstore-precheck/scripts/opt-in-review.py', 'skills/appstore-precheck/scripts/augment-json.py']
names += [str(p.relative_to(root)) for p in (root / 'skills/appstore-precheck/scripts/semantic').glob('*.py')]
for name in names:
    path = root / name
    source = path.read_text()
    tree = ast.parse(source, filename=name, feature_version=(3, 8))
    if len(source.splitlines()) > 800:
        raise SystemExit('file exceeds 800 lines: ' + name)
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.end_lineno - node.lineno + 1 > 50:
            raise SystemExit('function exceeds 50 lines: ' + name + ':' + node.name)
for folder in ('tests', 'skills/appstore-precheck/scripts'):
    for path in sorted((root / folder).rglob('*.sh')):
        subprocess.run(['bash', '-n', str(path)], check=True)
print('coverage lint: Python 3.8 grammar, file/function bounds and shell syntax passed')
